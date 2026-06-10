# RDS Proxy Module
# Epic: E07 - Data Plane (Aurora + RDS Proxy + S3)
# Story: S002 - Configure RDS Proxy with Secrets Manager auth

###############################################################################
# IAM Role for RDS Proxy (reads secrets)
###############################################################################

resource "aws_iam_role" "proxy" {
  name = "${var.proxy_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    "Name"      = "${var.proxy_name}-role"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_iam_role_policy" "proxy_secrets" {
  name = "secrets-access"
  role = aws_iam_role.proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secret_arns
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = var.kms_key_arn != null ? [var.kms_key_arn] : ["*"]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

###############################################################################
# RDS Proxy
###############################################################################

resource "aws_db_proxy" "this" {
  name                   = var.proxy_name
  debug_logging          = var.debug_logging
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = var.idle_client_timeout
  require_tls            = true
  role_arn               = aws_iam_role.proxy.arn
  vpc_security_group_ids = var.security_group_ids
  vpc_subnet_ids         = var.subnet_ids

  dynamic "auth" {
    for_each = var.secret_arns
    content {
      auth_scheme = "SECRETS"
      description = "Auth via Secrets Manager"
      iam_auth    = "DISABLED"
      secret_arn  = auth.value
    }
  }

  tags = merge(var.tags, {
    "Name"      = var.proxy_name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Default Target Group
###############################################################################

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    connection_borrow_timeout    = var.connection_borrow_timeout
    max_connections_percent      = var.max_connections_percent
    max_idle_connections_percent = var.max_idle_connections_percent
    session_pinning_filters      = var.session_pinning_filters
  }
}

###############################################################################
# Target (Aurora Cluster)
###############################################################################

resource "aws_db_proxy_target" "this" {
  db_proxy_name         = aws_db_proxy.this.name
  target_group_name     = aws_db_proxy_default_target_group.this.name
  db_cluster_identifier = var.cluster_identifier
}
