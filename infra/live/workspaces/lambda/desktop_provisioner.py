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

ec2 = boto3.client("ec2")
ssm = boto3.client("ssm")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

# Port map for response
ENDPOINTS = {
    "dcv_desktop": {"port": 8443, "protocol": "https"},
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


def store_claude_api_key(username, claude_api_key):
    """Store user's Claude API key in SSM Parameter Store (SecureString)."""
    if not claude_api_key:
        return
    param_name = f"/infra-lab/desktop/{username}/claude-api-key"
    try:
        # Try to create new parameter with tags
        ssm.put_parameter(
            Name=param_name,
            Value=claude_api_key,
            Type="SecureString",
            Description=f"Claude API key for {username} (BYO key for Continue extension)",
            Tags=[
                {"Key": "Project", "Value": "infra-lab"},
                {"Key": "Owner", "Value": username},
            ],
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ParameterAlreadyExists":
            # Parameter exists — update without tags
            ssm.put_parameter(
                Name=param_name,
                Value=claude_api_key,
                Type="SecureString",
                Overwrite=True,
                Description=f"Claude API key for {username} (BYO key for Continue extension)",
            )
        else:
            raise


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
    image: gitpod/openvscode-server:latest
    network_mode: host
    user: "1000:1000"
    volumes:
      - .:/home/workspace/workspace
      - code-server-config:/home/workspace/.openvscode-server
    environment:
      - HOME=/home/workspace
    entrypoint: /bin/bash
    command:
      - -c
      - |
        export OPENVSCODE_SERVER_ROOT=/home/.openvscode-server
        mkdir -p $$HOME/.openvscode-server/extensions
        chown -R 1000:1000 $$HOME/.openvscode-server 2>/dev/null || true
        $$OPENVSCODE_SERVER_ROOT/bin/openvscode-server --install-extension Continue.continue 2>/dev/null || true
        exec $$OPENVSCODE_SERVER_ROOT/bin/openvscode-server --host 0.0.0.0 --port 8080 --without-connection-token $$HOME/workspace
    restart: unless-stopped

volumes:
  frontend-node-modules:
  code-server-config:
COMPOSE

    # Replace Ollama IP placeholder in docker-compose
    # (Ollama integration disabled — bring your own API key for LLM features)

    # Create backend .env
    cat > MagNet-Agents-Backend/.env << ENVFILE
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU
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
VITE_SUPABASE_URL=http://$INSTANCE_IP:54321
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
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

  # Seed the database with test data (idempotent)
  if [ -f magnet-app-front/seeds/seed.sql ]; then
    SUPABASE_DB=$(sg docker -c "docker ps -q --filter 'name=supabase_db'" | head -1)
    if [ -z "$SUPABASE_DB" ]; then
      SUPABASE_DB=$(sg docker -c "docker ps -q --filter 'ancestor=public.ecr.aws/supabase/postgres'" | head -1)
    fi
    if [ -n "$SUPABASE_DB" ]; then
      sg docker -c "docker cp magnet-app-front/seeds/ $SUPABASE_DB:/tmp/ && docker exec -w /tmp $SUPABASE_DB psql -U postgres -d postgres -f /tmp/seeds/seed.sql" || true
      # Restart PostgREST to reload schema cache after seed creates tables
      sg docker -c "docker restart \$(docker ps -q --filter 'ancestor=public.ecr.aws/supabase/postgrest')" || true
    fi
  fi

  # Pull images + start backend/frontend
  sg docker -c "docker compose pull" || true
  sg docker -c "docker compose up -d" || true
fi

# Install VS Code 1.85 (last version compatible with AL2 glibc 2.26)
if ! command -v code &> /dev/null; then
  cd /tmp && curl -L -o code-1.85.2.rpm 'https://update.code.visualstudio.com/1.85.2/linux-rpm-x64/stable' 2>/dev/null
  yum install -y /tmp/code-1.85.2.rpm 2>/dev/null
  rm -f /tmp/code-1.85.2.rpm
fi

# Install Continue extension in VS Code for dcvuser (pinned — 1.2.24+ breaks on VS Code 1.85)
sudo -u dcvuser code --install-extension Continue.continue@1.2.0 2>/dev/null || true

# Install MemPalace (persistent AI memory — MCP server for Continue)
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  cp /root/.local/bin/uv /usr/local/bin/uv
  cp /root/.local/bin/uvx /usr/local/bin/uvx
fi
sudo -u dcvuser uv tool install mempalace 2>/dev/null || true
mkdir -p $MOUNT_POINT/home/dcvuser/.mempalace
ln -sfn $MOUNT_POINT/home/dcvuser/.mempalace /home/dcvuser/.mempalace
chown -R dcvuser:dcvuser $MOUNT_POINT/home/dcvuser/.mempalace /home/dcvuser/.mempalace

# Write default Continue config (user brings their own Claude API key)
mkdir -p /home/dcvuser/.continue
IMDS_TOKEN2=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
REGION2=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN2" http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_TAGS=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN2" http://169.254.169.254/latest/meta-data/instance-id)" "Name=key,Values=Owner" --query 'Tags[0].Value' --output text --region $REGION2 2>/dev/null)
CLAUDE_KEY=$(aws ssm get-parameter --name "/infra-lab/desktop/$INSTANCE_TAGS/claude-api-key" --with-decryption --query 'Parameter.Value' --output text --region $REGION2 2>/dev/null || echo "")

cat > /home/dcvuser/.continue/config.yaml << CONTINUECONF
name: Local Config
version: 1.0.0
schema: v1
models:
  - name: Claude Sonnet 4.5
    provider: anthropic
    model: claude-sonnet-4-5
    apiKey: $CLAUDE_KEY
    roles:
      - chat
      - edit
      - apply
mcpServers:
  - name: MemPalace
    type: stdio
    command: /home/dcvuser/.local/bin/mempalace-mcp
CONTINUECONF

# If no Claude key was provided, remove the apiKey line so Continue prompts for it
if [ -z "$CLAUDE_KEY" ]; then
  sed -i '/apiKey:/d' /home/dcvuser/.continue/config.yaml
fi

chown -R dcvuser:dcvuser /home/dcvuser/.continue

# Idle auto-stop: stop instance after 30 min of no DCV/code-server connections
# Find aws CLI (v1 at /usr/bin/aws on DCV AMI, v2 at /usr/local/bin/aws if installed)
AWS_BIN=$(command -v aws || echo /usr/bin/aws)
cat > /usr/local/bin/idle-check.sh << IDLE
#!/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
IDLE_THRESHOLD_MINUTES=30
STATE_FILE="/var/run/last-dcv-activity"
IMDS_TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=\$(curl -s -H "X-aws-ec2-metadata-token: \$IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
REGION=\$(curl -s -H "X-aws-ec2-metadata-token: \$IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
# Count DCV connections (any session)
CONNECTIONS=\$(dcv list-sessions -j 2>/dev/null | grep -o '"num-of-connections" : [0-9]*' | awk -F: '{sum += \$2} END {print sum+0}')
# Count established TCP connections on code-server port 8080 (exclude header line)
CODE_SERVER=\$(ss -tn state established '( dport = :8080 or sport = :8080 )' 2>/dev/null | tail -n +2 | wc -l)
if [ "\$CONNECTIONS" -gt 0 ] || [ "\$CODE_SERVER" -gt 0 ]; then
  date +%s > "\$STATE_FILE"
  exit 0
fi
if [ ! -f "\$STATE_FILE" ]; then
  date +%s > "\$STATE_FILE"
  exit 0
fi
LAST_ACTIVITY=\$(cat "\$STATE_FILE")
NOW=\$(date +%s)
IDLE_MINUTES=\$(( (NOW - LAST_ACTIVITY) / 60 ))
if [ "\$IDLE_MINUTES" -ge "\$IDLE_THRESHOLD_MINUTES" ]; then
  logger -t idle-check "No DCV or code-server connections for \${IDLE_MINUTES}min. Stopping."
  aws ec2 stop-instances --instance-ids "\$INSTANCE_ID" --region "\$REGION"
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
        InstanceMarketOptions={
            "MarketType": "spot",
            "SpotOptions": {
                "SpotInstanceType": "one-time",
            },
        },
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
        # Validate input
        if not username or not username.isalnum():
            return response(400, {"error": "username required (alphanumeric only)"})

        # Store Claude API key in SSM if provided
        claude_api_key = body.get("claude_api_key", "").strip()
        if claude_api_key:
            store_claude_api_key(username, claude_api_key)

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
