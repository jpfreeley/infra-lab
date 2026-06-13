# EC2 Spot + NICE DCV Desktop Instance
# Epic: E13 - AWS WorkSpaces Account
# Cost-optimized: spot instance (~70% savings) + persistent EBS for data

###############################################################################
# Official AWS DCV AMI (pre-installed DCV + MATE desktop)
###############################################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["DCV-AmazonLinux2-x86_64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

###############################################################################
# IAM Role for DCV Instance (SSM access + DCV license)
###############################################################################

module "dcv_instance_role" {
  source = "../../modules/iam_role"

  role_name   = "${local.name_prefix}-dcv-instance"
  description = "IAM role for DCV desktop instance (SSM + DCV licensing)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  attach_policy_arns = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.common_tags
}

# Scoped policy for DCV license bucket access
resource "aws_iam_role_policy" "dcv_license" {
  name = "${local.name_prefix}-dcv-license"
  role = module.dcv_instance_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "arn:aws:s3:::dcv-license.${var.aws_region}/*"
      },
      {
        Sid    = "SelfStop"
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" = "infra-lab"
          }
        }
      },
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:infra-lab/desktop/*"
      },
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/infra-lab/desktop/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "dcv" {
  name = "${local.name_prefix}-dcv-instance"
  role = module.dcv_instance_role.role_name

  tags = local.common_tags
}

###############################################################################
# Persistent Data Volume (survives spot interruptions)
# Stores: git repos, Docker volumes, Supabase data, user home
###############################################################################

resource "aws_ebs_volume" "data" {
  availability_zone = "us-east-1a"
  size              = 50
  type              = "gp3"
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data"
  })

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################################
# DCV Desktop Instance (Spot)
###############################################################################

resource "aws_spot_instance_request" "dcv_desktop" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = module.workspaces_vpc.public_subnet_ids[0]
  vpc_security_group_ids = [module.dcv_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.dcv.name

  associate_public_ip_address = true

  # Spot configuration
  spot_type                      = "persistent"
  instance_interruption_behavior = "stop"
  wait_for_fulfillment           = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -x
    exec > /var/log/user-data.log 2>&1

    ###########################################################################
    # PHASE 1: Mount persistent data volume
    ###########################################################################
    DATA_DEVICE="/dev/xvdf"
    MOUNT_POINT="/data"

    # Wait for the volume to be attached (can take a few seconds after boot)
    for i in $(seq 1 30); do
      [ -e $DATA_DEVICE ] && break
      echo "Waiting for data volume ($i/30)..."
      sleep 2
    done

    # Format if new (no filesystem detected)
    if ! blkid $DATA_DEVICE; then
      mkfs.xfs $DATA_DEVICE
    fi

    mkdir -p $MOUNT_POINT
    mount $DATA_DEVICE $MOUNT_POINT

    # Add to fstab for auto-mount on reboot
    grep -q "$MOUNT_POINT" /etc/fstab || \
      echo "$DATA_DEVICE $MOUNT_POINT xfs defaults,nofail 0 2" >> /etc/fstab

    ###########################################################################
    # PHASE 2: Install tools (idempotent — safe to re-run)
    ###########################################################################

    # Git
    yum install -y git

    # Docker
    if ! command -v docker &>/dev/null; then
      amazon-linux-extras install -y docker
      systemctl enable docker
    fi

    # Configure Docker to use persistent volume for data
    mkdir -p $MOUNT_POINT/docker/data /etc/docker
    cat > /etc/docker/daemon.json << 'DOCKER'
    {
      "data-root": "/data/docker/data"
    }
    DOCKER
    systemctl start docker

    # Docker Compose v2
    if [ ! -f /usr/local/lib/docker/cli-plugins/docker-compose ]; then
      mkdir -p /usr/local/lib/docker/cli-plugins
      curl -SL -o /usr/local/lib/docker/cli-plugins/docker-compose \
        https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64
      chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi

    # Docker Buildx
    if [ ! -f /usr/local/lib/docker/cli-plugins/docker-buildx ]; then
      curl -SL -o /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v0.21.2/buildx-v0.21.2.linux-amd64"
      chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
    fi

    # Supabase CLI (two co-located binaries: supabase + supabase-go)
    if [ ! -f /usr/local/share/supabase/supabase ]; then
      mkdir -p /usr/local/share/supabase
      curl -sL https://github.com/supabase/cli/releases/latest/download/supabase_linux_amd64.tar.gz \
        | tar xz -C /usr/local/share/supabase
      ln -sf /usr/local/share/supabase/supabase /usr/local/bin/supabase
    fi

    ###########################################################################
    # PHASE 3: Setup dcvuser
    ###########################################################################
    useradd -m dcvuser 2>/dev/null || true
    echo "dcvuser:ChangeMeOnFirstLogin!" | chpasswd
    usermod -aG docker dcvuser

    # Symlink development directory to persistent volume
    mkdir -p $MOUNT_POINT/home/dcvuser/development
    chown -R dcvuser:dcvuser $MOUNT_POINT/home/dcvuser
    ln -sfn $MOUNT_POINT/home/dcvuser/development /home/dcvuser/development
    chown -h dcvuser:dcvuser /home/dcvuser/development

    ###########################################################################
    # PHASE 4: Start DCV
    ###########################################################################
    systemctl enable dcvserver
    systemctl start dcvserver
    sleep 5
    dcv create-session --owner dcvuser --type virtual console 2>/dev/null || true

    ###########################################################################
    # PHASE 5: Auto-start services for returning users
    ###########################################################################
    if [ -f $MOUNT_POINT/home/dcvuser/development/docker-compose.yml ]; then
      cd $MOUNT_POINT/home/dcvuser/development
      sg docker -c "docker compose up -d" || true
    fi

    if [ -d $MOUNT_POINT/home/dcvuser/development/supabase ]; then
      cd $MOUNT_POINT/home/dcvuser/development
      sg docker -c "supabase start" || true
    fi

    ###########################################################################
    # PHASE 6: Idle auto-stop (30 min no DCV/code-server connections → stop instance)
    ###########################################################################
    cat > /usr/local/bin/idle-check.sh << 'IDLE'
    #!/bin/bash
    IDLE_THRESHOLD_MINUTES=30
    STATE_FILE="/var/run/last-dcv-activity"
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

    # Check DCV connections
    DCV_CONN=$(dcv list-sessions -j 2>/dev/null | grep -o '"num-of-connections" : [0-9]*' | awk -F: '{sum += $2} END {print sum+0}')

    # Check code-server connections (established TCP on port 8080)
    CS_CONN=$(ss -tn state established 2>/dev/null | grep -c ':8080' || echo 0)

    # If either has active connections, mark active
    if [ "$DCV_CONN" -gt 0 ] || [ "$CS_CONN" -gt 0 ]; then
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
      logger -t idle-check "No connections for $${IDLE_MINUTES}min. Stopping."
      aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
    fi
    IDLE
    chmod +x /usr/local/bin/idle-check.sh
    # Initialize activity state (boot counts as activity)
    date +%s > /var/run/last-dcv-activity
    # Run every 5 minutes
    echo "*/5 * * * * root /usr/local/bin/idle-check.sh" > /etc/cron.d/idle-check

    echo "=== User data complete at $(date) ==="
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-dcv-desktop"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

###############################################################################
# Attach persistent data volume to the spot instance
###############################################################################

resource "aws_volume_attachment" "data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_spot_instance_request.dcv_desktop.spot_instance_id

  # Don't force detach — let the instance handle it
  force_detach = false

  # Stop instance before detaching on destroy
  stop_instance_before_detaching = true
}
