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


def response(status_code, body):
    """Build API Gateway response."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
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
    user_data = f"""#!/bin/bash
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
{{"data-root": "/data/docker/data"}}
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

systemctl enable dcvserver
systemctl start dcvserver
sleep 5
dcv create-session --owner dcvuser --type virtual console 2>/dev/null || true
"""

    import base64

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
                    "note": "New desktop provisioning — fully ready in ~5 minutes",
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
