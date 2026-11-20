# Tablet Monitor on EC2
# ADR-038: Tablet Monitor on NetBird, Four Daily Check-Ins
#
# One small instance that joins the NetBird overlay as a peer, checks every
# kiosk tablet over ADB at each check-in, sends a ntfy message when one is
# red, and serves a status page on its NetBird address only.
#
# Not Fargate: the NetBird client needs a TUN device, which Fargate does
# not provide (ADR-038). x86_64, not Graviton: Google publishes the Linux
# adb for x86_64 only.
#
# Stopped between check-ins, never terminated by the schedule: NetBird's
# peer identity lives on the root volume. A user_data change replaces the
# instance, and the replacement needs a fresh one-use setup key (README).

locals {
  common_tags = merge(var.tags, {
    Component = "tablet-monitor"
  })

  secret_arns = [
    var.setup_key_secret_arn,
    var.adb_key_secret_arn,
    var.ntfy_topic_secret_arn,
    var.inventory_secret_arn,
  ]
}

data "aws_region" "current" {}

# Latest Amazon Linux 2023 at the time of each apply. ignore_changes on the
# instance keeps a newer AMI from replacing a running monitor; a replacement
# (user_data change) picks up the newest one.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################################################################
# IAM: SSM Session Manager, plus read access to the monitor's four secrets
###############################################################################

resource "aws_iam_role" "this" {
  name = "${var.name}-tablet-monitor"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "secrets" {
  name = "read-tablet-monitor-secrets"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadMonitorSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.secret_arns
      },
      {
        Sid      = "DecryptMonitorSecrets"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.secrets_kms_key_arn]
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.${data.aws_region.current.name}.amazonaws.com" }
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-tablet-monitor"
  role = aws_iam_role.this.name
  tags = local.common_tags
}

###############################################################################
# Network: no inbound rules at all (ADR-038 section 2)
###############################################################################

resource "aws_security_group" "this" {
  # checkov:skip=CKV_AWS_382: "Outbound to anywhere is the design: NetBird management and relay, WireGuard hole punching to peers at unknown addresses, ntfy, package and binary downloads, AWS APIs. There are no inbound rules."
  name        = "${var.name}-tablet-monitor"
  description = "Tablet monitor: no inbound, all outbound (NetBird, WireGuard, ntfy, AWS APIs)"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-tablet-monitor"
  })
}

###############################################################################
# Instance
###############################################################################

resource "aws_instance" "this" {
  # checkov:skip=CKV_AWS_88: "Public IPv4 is needed for outbound access: the VPC has no NAT gateway (ADR-037). The security group has no inbound rules."
  # checkov:skip=CKV_AWS_126: "Detailed monitoring not needed: the instance runs about an hour per check-in."
  # checkov:skip=CKV2_AWS_41: "False positive: an instance profile is attached."
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = true
  ebs_optimized               = true
  monitoring                  = false

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data_base64 = base64gzip(templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region                 = data.aws_region.current.name
    management_url         = var.management_url
    netbird_hostname       = var.netbird_hostname
    checkins               = var.checkins
    setup_key_secret_arn   = var.setup_key_secret_arn
    adb_key_secret_arn     = var.adb_key_secret_arn
    ntfy_topic_secret_arn  = var.ntfy_topic_secret_arn
    inventory_secret_arn   = var.inventory_secret_arn
    netbird_version        = var.netbird_version
    netbird_sha256         = var.netbird_sha256
    platform_tools_version = var.platform_tools_version
    platform_tools_sha256  = var.platform_tools_sha256
    monitor_py             = file("${path.module}/files/monitor.py")
  }))
  user_data_replace_on_change = true

  lifecycle {
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-tablet-monitor"
  })
  volume_tags = merge(local.common_tags, {
    Name = "${var.name}-tablet-monitor"
  })
}
