# Shared Ollama GPU Instance
# Serves LLM inference for all dev desktops via API (port 11434)
# Models: Qwen 2.5 Coder 14B

###############################################################################
# GPU AMI (Amazon Linux 2 with NVIDIA drivers)
###############################################################################

data "aws_ami" "gpu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

###############################################################################
# Ollama Security Group
###############################################################################

module "ollama_sg" {
  source = "../../modules/security_group"

  name        = "${local.name_prefix}-ollama"
  description = "Security group for shared Ollama inference server"
  vpc_id      = module.workspaces_vpc.vpc_id

  ingress = [
    {
      description = "Ollama API from VPC"
      from_port   = 11434
      to_port     = 11434
      protocol    = "tcp"
      cidr_blocks = [local.vpc_cidr]
    },
    {
      description = "SSH from allowed IPs (admin)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ip_cidrs
    },
  ]

  egress = [
    {
      description = "All outbound"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    },
  ]

  tags = local.common_tags
}

###############################################################################
# Ollama Instance (On-Demand GPU — switch to spot when quota approved)
###############################################################################

resource "aws_instance" "ollama" {
  ami                    = data.aws_ami.gpu.id
  instance_type          = "g4dn.xlarge"
  subnet_id              = module.workspaces_vpc.public_subnet_ids[0]
  vpc_security_group_ids = [module.ollama_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.dcv.name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -x
    exec > /var/log/user-data.log 2>&1

    # Install NVIDIA drivers
    yum install -y gcc kernel-devel-$(uname -r)
    aws s3 cp --region us-east-1 s3://ec2-linux-nvidia-drivers/latest/NVIDIA-Linux-x86_64.run /tmp/NVIDIA-install.run
    chmod +x /tmp/NVIDIA-install.run
    /tmp/NVIDIA-install.run --silent --disable-nouveau
    nvidia-smi

    # Install Ollama
    curl -fsSL https://ollama.com/install.sh | sh

    # Configure Ollama to listen on all interfaces
    mkdir -p /etc/systemd/system/ollama.service.d
    cat > /etc/systemd/system/ollama.service.d/override.conf << 'OVERRIDE'
    [Service]
    Environment="OLLAMA_HOST=0.0.0.0:11434"
    OVERRIDE

    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama

    # Wait for Ollama to be ready
    for i in $(seq 1 30); do
      curl -s http://localhost:11434/api/tags && break
      sleep 2
    done

    # Pull models
    ollama pull qwen2.5-coder:14b

    # Idle auto-stop: no API requests for 30 min → stop
    cat > /usr/local/bin/ollama-idle-check.sh << 'IDLE'
    #!/bin/bash
    IDLE_THRESHOLD_MINUTES=30
    STATE_FILE="/var/run/last-ollama-activity"
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

    # Check if any requests in the last interval (via Ollama logs)
    RECENT=$(journalctl -u ollama --since "5 min ago" --no-pager 2>/dev/null | grep -c "POST\|completion")
    if [ "$RECENT" -gt 0 ]; then
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
      logger -t ollama-idle "No requests for $IDLE_MINUTES min. Stopping."
      aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
    fi
    IDLE
    chmod +x /usr/local/bin/ollama-idle-check.sh
    date +%s > /var/run/last-ollama-activity
    echo "*/5 * * * * root /usr/local/bin/ollama-idle-check.sh" > /etc/cron.d/ollama-idle

    echo "=== Ollama setup complete ==="
  EOF
  )

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ollama"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
