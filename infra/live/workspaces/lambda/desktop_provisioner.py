"""
Desktop Provisioner Lambda
Handles self-service dev desktop provisioning via API Gateway.

Endpoints:
  POST /desktops - Launch/start a desktop for a user
  GET  /desktops - Get status of user's desktop

Auth: X-API-Key header (shared secret)
Rate limit: 1 request per IP per 3 minutes
"""

import json
import os
import time
import boto3
from botocore.exceptions import ClientError

# Configuration from environment
AMI_ID = os.environ["AMI_ID"]
INSTANCE_TYPE = os.environ.get("INSTANCE_TYPE", "t3.large")
SUBNET_ID = os.environ["SUBNET_ID"]
SECURITY_GROUP_ID = os.environ["SECURITY_GROUP_ID"]
INSTANCE_PROFILE_ARN = os.environ["INSTANCE_PROFILE_ARN"]
API_SECRET = os.environ["API_SECRET"]
TABLE_NAME = os.environ["TABLE_NAME"]
RATE_LIMIT_SECONDS = int(os.environ.get("RATE_LIMIT_SECONDS", "180"))
OLLAMA_INSTANCE_ID = os.environ.get("OLLAMA_INSTANCE_ID", "")

ec2 = boto3.client("ec2")
ssm = boto3.client("ssm")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

# Port map for response
ENDPOINTS = {
    "dcv_desktop": {"port": 8443, "protocol": "https"},
    "code_server": {"port": 8080, "protocol": "http"},
    "frontend": {"port": 5173, "protocol": "http"},
    "backend": {"port": 5000, "protocol": "http"},
    "supabase_studio": {"port": 54323, "protocol": "http"},
    "supabase_api": {"port": 54321, "protocol": "http"},
}


def build_endpoints(public_ip):
    """Build endpoint URLs from public IP."""
    return {
        name: f"{info['protocol']}://{public_ip}:{info['port']}"
        for name, info in ENDPOINTS.items()
    }


def get_ollama_status():
    """Check Ollama instance state and ensure it's running."""
    if not OLLAMA_INSTANCE_ID:
        return {"status": "not_configured"}
    try:
        result = ec2.describe_instances(InstanceIds=[OLLAMA_INSTANCE_ID])
        state = result["Reservations"][0]["Instances"][0]["State"]["Name"]
        if state == "stopped":
            # Auto-start Ollama
            ec2.start_instances(InstanceIds=[OLLAMA_INSTANCE_ID])
            return {"status": "starting"}
        return {"status": state}
    except Exception:
        return {"status": "unknown"}


def get_ollama_ip():
    """Get Ollama private IP from SSM."""
    try:
        result = ssm.get_parameter(Name="/infra-lab/desktop/ollama-ip")
        return result["Parameter"]["Value"]
    except Exception:
        return "10.0.96.100"  # fallback to fixed IP


def response(status_code, body):
    """Build API Gateway response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-API-Key",
            "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
        },
        "body": json.dumps(body),
    }


def check_rate_limit(source_ip):
    """Check if source IP has made a request in the last RATE_LIMIT_SECONDS."""
    try:
        result = table.get_item(Key={"pk": f"RATELIMIT#{source_ip}"})
        if "Item" in result:
            last_request = float(result["Item"].get("timestamp", 0))
            if time.time() - last_request < RATE_LIMIT_SECONDS:
                return False
    except ClientError:
        pass
    return True


def record_rate_limit(source_ip):
    """Record a request for rate limiting."""
    table.put_item(
        Item={
            "pk": f"RATELIMIT#{source_ip}",
            "timestamp": int(time.time()),
            "ttl": int(time.time()) + RATE_LIMIT_SECONDS * 2,
        }
    )


def update_security_group(source_ip):
    """Add source IP to security group ingress (idempotent)."""
    cidr = f"{source_ip}/32"
    description = f"Auto-provisioned for {source_ip}"

    # Get current rules
    sg = ec2.describe_security_groups(GroupIds=[SECURITY_GROUP_ID])
    existing_cidrs = set()
    for rule in sg["SecurityGroups"][0].get("IpPermissions", []):
        for ip_range in rule.get("IpRanges", []):
            existing_cidrs.add(ip_range.get("CidrIp"))

    if cidr in existing_cidrs:
        return  # Already allowed

    # Add rules for all ports
    ports = [22, 5000, 5173, 8080, 8443, 54321, 54323]
    ip_permissions = []
    for port in ports:
        ip_permissions.append(
            {
                "IpProtocol": "tcp",
                "FromPort": port,
                "ToPort": port,
                "IpRanges": [{"CidrIp": cidr, "Description": description}],
            }
        )
    # DCV UDP
    ip_permissions.append(
        {
            "IpProtocol": "udp",
            "FromPort": 8443,
            "ToPort": 8443,
            "IpRanges": [{"CidrIp": cidr, "Description": description}],
        }
    )

    ec2.authorize_security_group_ingress(
        GroupId=SECURITY_GROUP_ID, IpPermissions=ip_permissions
    )


def get_instance_state(instance_id):
    """Get instance state and public IP."""
    try:
        result = ec2.describe_instances(InstanceIds=[instance_id])
        instance = result["Reservations"][0]["Instances"][0]
        return {
            "state": instance["State"]["Name"],
            "public_ip": instance.get("PublicIpAddress"),
        }
    except (ClientError, IndexError, KeyError):
        return None


def start_instance(instance_id):
    """Start a stopped instance."""
    ec2.start_instances(InstanceIds=[instance_id])


def wait_for_ip(instance_id, max_wait=60):
    """Wait for instance to get a public IP."""
    for _ in range(max_wait // 5):
        info = get_instance_state(instance_id)
        if info and info.get("public_ip"):
            return info["public_ip"]
        time.sleep(5)
    return None


def launch_new_instance(username):
    """Launch a new desktop instance from AMI."""
    user_data = """#!/bin/bash
set -x
exec > /var/log/user-data.log 2>&1

DATA_DEVICE="/dev/xvdf"
MOUNT_POINT="/data"

for i in $(seq 1 30); do
  [ -e $DATA_DEVICE ] && break
  sleep 2
done

if ! blkid $DATA_DEVICE; then
  mkfs.xfs $DATA_DEVICE
fi

mkdir -p $MOUNT_POINT
mount $DATA_DEVICE $MOUNT_POINT
grep -q "$MOUNT_POINT" /etc/fstab || echo "$DATA_DEVICE $MOUNT_POINT xfs defaults,nofail 0 2" >> /etc/fstab

yum install -y git

if ! command -v docker &>/dev/null; then
  amazon-linux-extras install -y docker
  systemctl enable docker
fi

mkdir -p $MOUNT_POINT/docker/data /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{"data-root": "/data/docker/data"}
EOF
systemctl start docker

if [ ! -f /usr/local/lib/docker/cli-plugins/docker-compose ]; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -SL -o /usr/local/lib/docker/cli-plugins/docker-compose https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

if [ ! -f /usr/local/lib/docker/cli-plugins/docker-buildx ]; then
  curl -SL -o /usr/local/lib/docker/cli-plugins/docker-buildx "https://github.com/docker/buildx/releases/download/v0.21.2/buildx-v0.21.2.linux-amd64"
  chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
fi

if [ ! -f /usr/local/share/supabase/supabase ]; then
  mkdir -p /usr/local/share/supabase
  curl -sL https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.tar.gz | tar xz -C /usr/local/share/supabase
  ln -sf /usr/local/share/supabase/supabase /usr/local/bin/supabase
fi

useradd -m dcvuser 2>/dev/null || true
echo "dcvuser:ChangeMeOnFirstLogin!" | chpasswd
usermod -aG docker dcvuser

mkdir -p $MOUNT_POINT/home/dcvuser/development
chown -R dcvuser:dcvuser $MOUNT_POINT/home/dcvuser
ln -sfn $MOUNT_POINT/home/dcvuser/development /home/dcvuser/development
chown -h dcvuser:dcvuser /home/dcvuser/development

# First-boot: clone repos and set up dev environment if not already done
if [ ! -f $MOUNT_POINT/home/dcvuser/development/docker-compose.yml ]; then
  IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
  REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
  GH_PAT=$(aws secretsmanager get-secret-value --secret-id "infra-lab/desktop/github-pat" --query SecretString --output text --region $REGION 2>/dev/null | tr -d "\\n")
  OLLAMA_IP_SSM=$(aws ssm get-parameter --name "/infra-lab/desktop/ollama-ip" --query "Parameter.Value" --output text --region $REGION 2>/dev/null | tr -d "\\n")
  if [ -z "$OLLAMA_IP_SSM" ]; then OLLAMA_IP_SSM="10.0.96.100"; fi

  if [ -n "$GH_PAT" ]; then
    cd $MOUNT_POINT/home/dcvuser/development

    # Fetch API keys from Secrets Manager
    OPENAI_KEY=$(aws secretsmanager get-secret-value --secret-id "infra-lab/desktop/openai-key" --query SecretString --output text --region $REGION 2>/dev/null | tr -d "\\n")
    TAVILY_KEY=$(aws secretsmanager get-secret-value --secret-id "infra-lab/desktop/tavily-key" --query SecretString --output text --region $REGION 2>/dev/null | tr -d "\\n")
    APIFY_TOKEN=$(aws secretsmanager get-secret-value --secret-id "infra-lab/desktop/apify-token" --query SecretString --output text --region $REGION 2>/dev/null | tr -d "\\n")

    # Clone repos via HTTPS + PAT
    if [ ! -d "MagNet-Agents-Backend" ]; then
      git clone https://x-access-token:$GH_PAT@github.com/avinair108/MagNet-Agents-Backend.git
    fi
    if [ ! -d "magnet-app-front" ]; then
      git clone https://x-access-token:$GH_PAT@github.com/avinair108/magnet-app-front.git
    fi

    # Create docker-compose.yml
    cat > docker-compose.yml << 'COMPOSE'
services:
  backend:
    image: python:3.11-slim
    working_dir: /app
    volumes:
      - ./MagNet-Agents-Backend:/app
    env_file:
      - ./MagNet-Agents-Backend/.env
    network_mode: host
    command: bash -c "pip install -r requirements.txt && python app.py"
    restart: unless-stopped

  frontend:
    image: node:20-slim
    working_dir: /app
    volumes:
      - ./magnet-app-front:/app
      - frontend-node-modules:/app/node_modules
    network_mode: host
    env_file:
      - ./magnet-app-front/.env
    command: bash -c "npm install --legacy-peer-deps && npm run dev -- --host 0.0.0.0"
    restart: unless-stopped

  code-server:
    image: codercom/code-server:latest
    network_mode: host
    volumes:
      - .:/home/coder/workspace
      - code-server-config:/home/coder/.local
      - /data/home/dcvuser/.hermes:/home/coder/.hermes
    environment:
      - PASSWORD=magnet123
      - OLLAMA_HOST=http://OLLAMA_IP_PLACEHOLDER:11434
    entrypoint: /bin/bash
    command:
      - -c
      - |
        sudo chown -R coder:coder /home/coder/.local 2>/dev/null
        sudo apt-get update -qq && sudo apt-get install -y -qq pipx python3-venv >/dev/null 2>&1
        pipx install 'hermes-agent[acp]' 2>/dev/null
        pipx ensurepath 2>/dev/null
        export PATH=$$PATH:/home/coder/.local/bin
        mkdir -p /home/coder/.local/share/code-server/extensions
        [ ! -f /home/coder/.local/share/code-server/extensions/extensions.json ] && echo '[]' > /home/coder/.local/share/code-server/extensions/extensions.json
        code-server --install-extension vampozo.hermes-ai-agent-vampozo 2>/dev/null
        code-server --install-extension Continue.continue 2>/dev/null
        mkdir -p /home/coder/.continue
        printf '{"models":[{"title":"Qwen 2.5 Coder 14B","provider":"ollama","model":"qwen2.5-coder:14b","apiBase":"%s"}],"tabAutocompleteModel":{"title":"Qwen Autocomplete","provider":"ollama","model":"qwen2.5-coder:14b","apiBase":"%s"}}' "$$OLLAMA_HOST" "$$OLLAMA_HOST" > /home/coder/.continue/config.json
        exec code-server --auth password --bind-addr 0.0.0.0:8080 /home/coder/workspace
    restart: unless-stopped

volumes:
  frontend-node-modules:
  code-server-config:
COMPOSE

    # Replace Ollama IP placeholder in docker-compose
    sed -i "s|OLLAMA_IP_PLACEHOLDER|$OLLAMA_IP_SSM|g" docker-compose.yml

    # Create backend .env
    cat > MagNet-Agents-Backend/.env << ENVFILE
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_KEY=REPLACE_AFTER_SUPABASE_START
SUPABASE_JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long
OPENAI_API_KEY=$OPENAI_KEY
TAVILY_API_KEY=$TAVILY_KEY
APIFY_API_TOKEN=$APIFY_TOKEN
DEBUG=True
FLASK_DEBUG=1
ENVFILE

    # Create frontend .env
    INSTANCE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
    cat > magnet-app-front/.env << ENVFILE
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=REPLACE_AFTER_SUPABASE_START
VITE_MICROSOFT_CLIENT_ID=REPLACE_ME
VITE_MICROSOFT_TENANT_ID=common
VITE_MICROSOFT_REDIRECT_URI=http://$INSTANCE_IP:5173/contact
VITE_APOLLO_CLIENT_ID=
VITE_APOLLO_CLIENT_SECRET=
VITE_API_BASE_URL=http://$INSTANCE_IP:5000
ENVFILE

    # Fix ownership
    chown -R dcvuser:dcvuser $MOUNT_POINT/home/dcvuser/development
  fi
fi

systemctl enable dcvserver
systemctl start dcvserver
sleep 5
dcv create-session --owner dcvuser --type virtual console 2>/dev/null || true

# Auto-start services (both first boot and returning users)
if [ -f $MOUNT_POINT/home/dcvuser/development/docker-compose.yml ]; then
  cd $MOUNT_POINT/home/dcvuser/development

  # Start Supabase
  sg docker -c "/usr/local/bin/supabase start" || true

  # Pull images + start backend/frontend
  sg docker -c "docker compose pull" || true
  sg docker -c "docker compose up -d" || true
fi

# Install Hermes Agent (via pipx in a container, exposed as host script)
if [ ! -f /usr/local/bin/hermes ]; then
  # Create a wrapper that runs hermes inside a Python 3.11 container
  cat > /usr/local/bin/hermes << 'HERMES'
#!/bin/bash
OLLAMA_IP=$(cat /home/dcvuser/.hermes/.env 2>/dev/null | grep OLLAMA_HOST | cut -d/ -f3 | cut -d: -f1)
[ -z "$OLLAMA_IP" ] && OLLAMA_IP="10.0.96.100"
exec docker run --rm -it \
  --network host \
  -v "$HOME:/root" \
  -v "$(pwd):/workspace" \
  -w /workspace \
  -e OLLAMA_HOST=http://$OLLAMA_IP:11434 \
  -e OLLAMA_BASE_URL=http://$OLLAMA_IP:11434 \
  -e MEMPALACE_DIR=/root/.mempalace \
  python:3.11 bash -c "pip install -q hermes-agent mempalace 2>/dev/null && hermes \"\\$@\""
HERMES
  chmod +x /usr/local/bin/hermes
fi

# Install MemPalace on persistent volume
if [ ! -d $MOUNT_POINT/home/dcvuser/.mempalace ]; then
  mkdir -p $MOUNT_POINT/home/dcvuser/.mempalace
fi
ln -sfn $MOUNT_POINT/home/dcvuser/.mempalace /home/dcvuser/.mempalace 2>/dev/null
chown -h dcvuser:dcvuser /home/dcvuser/.mempalace

# Write Hermes config with Ollama IP from SSM
OLLAMA_IP_SSM=$(aws ssm get-parameter --name "/infra-lab/desktop/ollama-ip" --query "Parameter.Value" --output text --region $REGION 2>/dev/null | tr -d "\\n")
if [ -z "$OLLAMA_IP_SSM" ]; then OLLAMA_IP_SSM="10.0.96.100"; fi
mkdir -p $MOUNT_POINT/home/dcvuser/.hermes
cat > $MOUNT_POINT/home/dcvuser/.hermes/.env << HERMESENV
OLLAMA_HOST=http://$OLLAMA_IP_SSM:11434
HERMES_PROVIDER=ollama
HERMES_MODEL=qwen2.5-coder:14b
HERMESENV
cat > $MOUNT_POINT/home/dcvuser/.hermes/config.yaml << HERMESCONFIG
model:
  provider: ollama
  default: qwen2.5-coder:14b
  base_url: http://$OLLAMA_IP_SSM:11434

terminal:
  backend: local
HERMESCONFIG
ln -sfn $MOUNT_POINT/home/dcvuser/.hermes /home/dcvuser/.hermes 2>/dev/null
chown -R dcvuser:dcvuser $MOUNT_POINT/home/dcvuser/.hermes
chmod -R 777 $MOUNT_POINT/home/dcvuser/.hermes
chown -h dcvuser:dcvuser /home/dcvuser/.hermes

# Set OLLAMA_HOST for dcvuser (all shells)
grep -q OLLAMA_HOST /home/dcvuser/.bashrc 2>/dev/null || cat >> /home/dcvuser/.bashrc << BASHRC
export OLLAMA_HOST="http://$OLLAMA_IP_SSM:11434"
export OLLAMA_BASE_URL="http://$OLLAMA_IP_SSM:11434"
BASHRC

# Idle auto-stop: stop instance after 30 min of no DCV connections
cat > /usr/local/bin/idle-check.sh << 'IDLE'
#!/bin/bash
IDLE_THRESHOLD_MINUTES=30
STATE_FILE="/var/run/last-dcv-activity"
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
CONNECTIONS=$(dcv list-sessions -j 2>/dev/null | grep -o '"num-of-connections" : [0-9]*' | awk -F: '{sum += $2} END {print sum+0}')
if [ "$CONNECTIONS" -gt 0 ]; then
  date +%s > "$STATE_FILE"
  exit 0
fi
if [ ! -f "$STATE_FILE" ]; then
  date +%s > "$STATE_FILE"
  exit 0
fi
LAST_ACTIVITY=$(cat "$STATE_FILE")
NOW=$(date +%s)
IDLE_MINUTES=$(( (NOW - LAST_ACTIVITY) / 60 ))
if [ "$IDLE_MINUTES" -ge "$IDLE_THRESHOLD_MINUTES" ]; then
  logger -t idle-check "No DCV connections for ${IDLE_MINUTES}min. Stopping."
  aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
fi
IDLE
chmod +x /usr/local/bin/idle-check.sh
date +%s > /var/run/last-dcv-activity
echo "*/5 * * * * root /usr/local/bin/idle-check.sh" > /etc/cron.d/idle-check
"""

    result = ec2.run_instances(
        ImageId=AMI_ID,
        InstanceType=INSTANCE_TYPE,
        MinCount=1,
        MaxCount=1,
        UserData=user_data,
        IamInstanceProfile={"Arn": INSTANCE_PROFILE_ARN},
        NetworkInterfaces=[
            {
                "DeviceIndex": 0,
                "SubnetId": SUBNET_ID,
                "Groups": [SECURITY_GROUP_ID],
                "AssociatePublicIpAddress": True,
            }
        ],
        TagSpecifications=[
            {
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "Name", "Value": f"dev-desktop-{username}"},
                    {"Key": "Environment", "Value": "sandbox"},
                    {"Key": "Project", "Value": "infra-lab"},
                    {"Key": "ManagedBy", "Value": "terraform"},
                    {"Key": "Owner", "Value": username},
                ],
            }
        ],
    )

    instance_id = result["Instances"][0]["InstanceId"]

    # Create and attach data volume
    vol = ec2.create_volume(
        AvailabilityZone="us-east-1a",
        Size=50,
        VolumeType="gp3",
        Encrypted=True,
        TagSpecifications=[
            {
                "ResourceType": "volume",
                "Tags": [
                    {"Key": "Name", "Value": f"dev-desktop-{username}-data"},
                    {"Key": "Owner", "Value": username},
                    {"Key": "Environment", "Value": "sandbox"},
                    {"Key": "Project", "Value": "infra-lab"},
                    {"Key": "ManagedBy", "Value": "terraform"},
                ],
            }
        ],
    )

    # Wait for instance to be running before attaching
    ec2.get_waiter("instance_running").wait(InstanceIds=[instance_id])

    ec2.attach_volume(
        VolumeId=vol["VolumeId"],
        InstanceId=instance_id,
        Device="/dev/xvdf",
    )

    return instance_id, vol["VolumeId"]


def handler(event, context):
    """Main Lambda handler."""
    # Auth check
    headers = event.get("headers", {})
    api_key = headers.get("x-api-key") or headers.get("X-API-Key") or ""
    if api_key != API_SECRET:
        return response(401, {"error": "Unauthorized"})

    # Get source IP
    source_ip = event.get("requestContext", {}).get(
        "identity", {}).get("sourceIp")
    if not source_ip:
        source_ip = headers.get(
            "X-Forwarded-For", "unknown").split(",")[0].strip()

    http_method = event.get("httpMethod", "GET")
    body = json.loads(event.get("body") or "{}")
    username = body.get("username", "").strip().lower()

    if http_method == "POST":
        # Auto-start Ollama if stopped
        ollama_info = get_ollama_status()

        # Validate input
        if not username or not username.isalnum():
            return response(400, {"error": "username required (alphanumeric only)"})

        # Rate limit check
        if not check_rate_limit(source_ip):
            return response(
                429,
                {
                    "error": f"Rate limited. Try again in {RATE_LIMIT_SECONDS} seconds.",
                },
            )

        # Record this request for rate limiting
        record_rate_limit(source_ip)

        # Check for existing instance
        try:
            result = table.get_item(Key={"pk": f"USER#{username}"})
        except ClientError:
            result = {}

        if "Item" in result:
            instance_id = result["Item"]["instance_id"]
            volume_id = result["Item"].get("volume_id")
            info = get_instance_state(instance_id)

            if info is None:
                # Instance no longer exists — clean up record
                table.delete_item(Key={"pk": f"USER#{username}"})
            elif info["state"] == "running":
                # Already running — update SG and return
                update_security_group(source_ip)
                public_ip = info["public_ip"]
                return response(
                    200,
                    {
                        "status": "running",
                        "username": username,
                        "instance_id": instance_id,
                        "public_ip": public_ip,
                        "endpoints": build_endpoints(public_ip),
                        "ollama": ollama_info,
                        "credentials": {
                            "dcv_user": "dcvuser",
                            "dcv_password": "(set by user)",
                            "code_server_password": "magnet123",
                        },
                    },
                )
            elif info["state"] == "stopped":
                # Start the stopped instance
                start_instance(instance_id)
                update_security_group(source_ip)
                public_ip = wait_for_ip(instance_id)
                if public_ip:
                    # Update record with new IP
                    table.update_item(
                        Key={"pk": f"USER#{username}"},
                        UpdateExpression="SET public_ip = :ip, last_started = :ts",
                        ExpressionAttributeValues={
                            ":ip": public_ip,
                            ":ts": int(time.time()),
                        },
                    )
                    return response(
                        200,
                        {
                            "status": "starting",
                            "username": username,
                            "instance_id": instance_id,
                            "public_ip": public_ip,
                            "endpoints": build_endpoints(public_ip),
                            "ollama": ollama_info,
                            "credentials": {
                                "dcv_user": "dcvuser",
                                "dcv_password": "(set by user)",
                                "code_server_password": "magnet123",
                            },
                            "note": "Instance starting — DCV available in ~2 minutes",
                        },
                    )
                return response(
                    202,
                    {
                        "status": "starting",
                        "instance_id": instance_id,
                        "note": "Instance starting. Poll GET /desktops for IP.",
                    },
                )
            elif info["state"] in ("stopping", "pending"):
                return response(
                    202,
                    {
                        "status": info["state"],
                        "instance_id": instance_id,
                        "note": "Instance is transitioning. Try again in 30 seconds.",
                    },
                )

        # No existing instance — launch new
        instance_id, volume_id = launch_new_instance(username)
        update_security_group(source_ip)
        public_ip = wait_for_ip(instance_id)

        # Store in DynamoDB
        table.put_item(
            Item={
                "pk": f"USER#{username}",
                "username": username,
                "instance_id": instance_id,
                "volume_id": volume_id,
                "public_ip": public_ip or "pending",
                "created_at": int(time.time()),
                "last_started": int(time.time()),
                "source_ip": source_ip,
            }
        )

        if public_ip:
            return response(
                201,
                {
                    "status": "provisioning",
                    "username": username,
                    "instance_id": instance_id,
                    "public_ip": public_ip,
                    "endpoints": build_endpoints(public_ip),
                    "ollama": ollama_info,
                    "credentials": {
                        "dcv_user": "dcvuser",
                        "dcv_password": "ChangeMeOnFirstLogin!",
                        "code_server_password": "magnet123",
                    },
                    "note": "New desktop provisioning — fully ready in ~10 minutes",
                },
            )
        return response(
            202,
            {
                "status": "provisioning",
                "instance_id": instance_id,
                "note": "Desktop launching. Poll GET /desktops for status.",
            },
        )

    elif http_method == "GET":
        # Get status for a username
        username = event.get("queryStringParameters", {}).get("username", "")
        if not username:
            return response(400, {"error": "username query param required"})

        try:
            result = table.get_item(Key={"pk": f"USER#{username}"})
        except ClientError:
            return response(500, {"error": "Database error"})

        if "Item" not in result:
            return response(404, {"error": f"No desktop found for {username}"})

        item = result["Item"]
        instance_id = item["instance_id"]
        info = get_instance_state(instance_id)

        if info is None:
            return response(404, {"error": "Instance no longer exists"})

        public_ip = info.get("public_ip")
        resp_body = {
            "status": info["state"],
            "username": username,
            "instance_id": instance_id,
            "public_ip": public_ip,
        }
        if public_ip and info["state"] == "running":
            resp_body["endpoints"] = build_endpoints(public_ip)
            resp_body["credentials"] = {
                "dcv_user": "dcvuser",
                "code_server_password": "magnet123",
            }

        return response(200, resp_body)

    return response(405, {"error": "Method not allowed"})
