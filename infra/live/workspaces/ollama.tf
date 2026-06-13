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
    values = ["Deep Learning Base OSS Nvidia Driver AMI (Amazon Linux 2) *"]
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
  private_ip             = "10.0.96.100"
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

    # NVIDIA drivers are pre-installed in the Deep Learning AMI
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
    for i in $(seq 1 60); do
      curl -s http://localhost:11434/api/tags && break
      sleep 5
    done

    # Pull models
    ollama pull qwen2.5-coder:14b

    # Idle auto-stop: no API requests for 30 min → stop
    # Grace period: don't stop within first 60 min of boot
    BOOT_TIME=$(date +%s)
    cat > /usr/local/bin/ollama-idle-check.sh << IDLE
    #!/bin/bash
    IDLE_THRESHOLD_MINUTES=30
    BOOT_TIME=$BOOT_TIME
    GRACE_MINUTES=60
    STATE_FILE="/var/run/last-ollama-activity"
    INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=\$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

    # Grace period — don't stop within first hour
    NOW=\$(date +%s)
    UPTIME_MIN=\$(( (NOW - BOOT_TIME) / 60 ))
    if [ "\$UPTIME_MIN" -lt "\$GRACE_MINUTES" ]; then exit 0; fi

    # Check if any requests in the last interval
    RECENT=\$(journalctl -u ollama --since "5 min ago" --no-pager 2>/dev/null | grep -c "POST\|completion")
    if [ "\$RECENT" -gt 0 ]; then
      date +%s > "\$STATE_FILE"
      exit 0
    fi
    if [ ! -f "\$STATE_FILE" ]; then
      date +%s > "\$STATE_FILE"
      exit 0
    fi
    LAST_ACTIVITY=\$(cat "\$STATE_FILE")
    IDLE_MINUTES=\$(( (NOW - LAST_ACTIVITY) / 60 ))
    if [ "\$IDLE_MINUTES" -ge "\$IDLE_THRESHOLD_MINUTES" ]; then
      logger -t ollama-idle "No requests for \$IDLE_MINUTES min. Stopping."
      aws ec2 stop-instances --instance-ids "\$INSTANCE_ID" --region "\$REGION"
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


###############################################################################
# SSM Parameter for Ollama IP (read at runtime by Lambda + desktops)
###############################################################################

resource "aws_ssm_parameter" "ollama_ip" {
  name        = "/infra-lab/desktop/ollama-ip"
  description = "Private IP of the shared Ollama GPU instance"
  type        = "String"
  value       = aws_instance.ollama.private_ip

  tags = local.common_tags
}

resource "aws_ssm_parameter" "ollama_instance_id" {
  name        = "/infra-lab/desktop/ollama-instance-id"
  description = "Instance ID of the shared Ollama GPU instance"
  type        = "String"
  value       = aws_instance.ollama.id

  tags = local.common_tags
}
