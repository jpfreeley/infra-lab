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
      }
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

    # Mount persistent data volume
    DATA_DEVICE="/dev/xvdf"
    MOUNT_POINT="/data"

    # Wait for the volume to be attached
    while [ ! -e $DATA_DEVICE ]; do
      echo "Waiting for data volume..."
      sleep 2
    done

    # Format if new (no filesystem)
    if ! blkid $DATA_DEVICE; then
      mkfs.xfs $DATA_DEVICE
    fi

    mkdir -p $MOUNT_POINT
    mount $DATA_DEVICE $MOUNT_POINT

    # Add to fstab for remounts
    grep -q "$MOUNT_POINT" /etc/fstab || echo "$DATA_DEVICE $MOUNT_POINT xfs defaults,nofail 0 2" >> /etc/fstab

    # Create directory structure on data volume
    mkdir -p $MOUNT_POINT/home/dcvuser
    mkdir -p $MOUNT_POINT/docker

    # Setup dcvuser
    useradd -m dcvuser 2>/dev/null || true
    echo "dcvuser:ChangeMeOnFirstLogin!" | chpasswd

    # Bind mount dcvuser home to persistent volume
    if [ ! -L /home/dcvuser/development ]; then
      mkdir -p $MOUNT_POINT/home/dcvuser/development
      ln -sfn $MOUNT_POINT/home/dcvuser/development /home/dcvuser/development
      chown -R dcvuser:dcvuser $MOUNT_POINT/home/dcvuser
      chown -h dcvuser:dcvuser /home/dcvuser/development
    fi

    # Point Docker data to persistent volume
    if [ ! -d $MOUNT_POINT/docker/data ]; then
      mkdir -p $MOUNT_POINT/docker/data
    fi
    if [ ! -f /etc/docker/daemon.json ] || ! grep -q "$MOUNT_POINT/docker/data" /etc/docker/daemon.json; then
      mkdir -p /etc/docker
      cat > /etc/docker/daemon.json << 'DOCKER'
    {
      "data-root": "/data/docker/data"
    }
    DOCKER
      systemctl restart docker 2>/dev/null || true
    fi

    # Ensure DCV server is running
    systemctl enable dcvserver
    systemctl start dcvserver

    # Wait for DCV server to be ready
    sleep 5

    # Create a virtual session for dcvuser
    dcv create-session --owner dcvuser --type virtual console 2>/dev/null || true
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
