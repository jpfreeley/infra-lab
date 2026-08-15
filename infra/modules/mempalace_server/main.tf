# MemPalace Remote/Team Server on ECS Fargate
# ADR-034: Shared MemPalace Server as a Portable App on Dedicated Infra
#
# Deploys MemPalace's own documented Remote/Team Server mode unmodified:
# qdrant (internal-only, task-local) + `mempalace serve` (bearer-token auth,
# the ALB-facing container). Two containers, one task, one shared EFS-backed
# dataset — this is a singleton service, not a horizontally-scaled one.
#
# Deliberate scope boundary (mirrors infra/modules/ecs_service): this module
# owns compute + storage for the app itself. VPC, ALB, WAF, ACM, and the
# bearer-token secret's VALUE are owned by whatever environment consumes
# this module — that's what keeps it portable across infra-lab and any
# other AWS environment (see ADR-034's reuse goal).
#
# Deviation from ecs_service's convention: IAM roles are created INSIDE this
# module rather than passed in, because they're tightly coupled to exactly
# this app's two containers (EFS client access, one scoped secret read) and
# a module meant to be dropped into an unfamiliar environment shouldn't
# require that environment to hand-replicate infra-lab's bespoke iam_ecs.tf
# pattern first.

locals {
  name_prefix = var.name
  common_tags = merge(var.tags, {
    "ManagedBy" = "terraform"
    "Project"   = var.project
    "App"       = "mempalace-server"
  })
}

###############################################################################
# EFS — persistent storage for both containers, one filesystem, two access
# points (mirrors the upstream docker-compose's two named volumes)
###############################################################################

resource "aws_efs_file_system" "this" {
  # checkov:skip=CKV_AWS_184: "kms_key_arn null falls back to the aws/elasticfilesystem default key; caller controls via var.kms_key_arn"
  creation_token   = "${local.name_prefix}-data"
  encrypted        = true
  kms_key_id       = var.kms_key_arn
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-data"
  })
}

resource "aws_efs_mount_target" "this" {
  # Keyed by index, not toset(var.subnet_ids): on a fresh apply the subnet
  # IDs aren't known until the VPC module creates them, and Terraform can't
  # build a for_each set from not-yet-known values even when the element
  # count is statically known. Index-keyed avoids that entirely.
  for_each = { for idx, s in var.subnet_ids : idx => s }

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "qdrant" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/qdrant-storage"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-qdrant-storage"
  })
}

resource "aws_efs_access_point" "mempalace" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/mempalace-data"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-mempalace-data"
  })
}

###############################################################################
# Security Groups
###############################################################################

# Task SG: ingress only from the ALB's SG, on the mempalace port. qdrant is
# never given its own ingress rule — it's reachable only via localhost inside
# the task, exactly like the upstream docker-compose's internal-only service.
module "task_sg" {
  source = "../security_group"

  name        = "${local.name_prefix}-task"
  description = "MemPalace ECS task, ingress from ALB only, no direct public access"
  vpc_id      = var.vpc_id

  ingress = [
    {
      description     = "mempalace serve from ALB"
      from_port       = var.mempalace_port
      to_port         = var.mempalace_port
      protocol        = "tcp"
      security_groups = [var.alb_security_group_id]
    }
  ]

  egress = [
    {
      description = "All outbound (image pulls, EFS, Secrets Manager, CloudWatch Logs)"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = local.common_tags
}

# EFS SG: ingress only from the task SG, on NFS. No egress rules — mount
# targets only ever respond to connections the task initiates (stateful).
resource "aws_security_group" "efs" {
  name        = "${local.name_prefix}-efs"
  description = "MemPalace EFS mount targets, NFS from the task only"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-efs"
  })
}

resource "aws_security_group_rule" "efs_from_task" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  description              = "NFS from MemPalace ECS task"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = module.task_sg.id
}


###############################################################################
# IAM
###############################################################################

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: pulls images, writes logs, reads the one bearer-token secret
resource "aws_iam_role" "execution" {
  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-ecs-execution"
  })
}

resource "aws_iam_role_policy_attachment" "execution_base" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secret_access" {
  statement {
    sid       = "ReadBearerToken"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.bearer_token_secret_arn]
  }

  # If the secret is encrypted with a customer-managed key (the expected
  # case per ADR-034), GetSecretValue also needs kms:Decrypt on that key —
  # secretsmanager:GetSecretValue alone isn't sufficient once it's not the
  # AWS-managed default key. Root-account-full-access in the standard
  # kms_key module policy is what lets this IAM statement actually grant
  # usage without the key policy needing to name this role explicitly.
  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid       = "DecryptBearerTokenKey"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "execution_secret_access" {
  name   = "bearer-token-read"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secret_access.json
}

# Task role: EFS client access via IAM authorization (defense-in-depth on top
# of the security-group boundary — both must allow the mount, not either/or)
data "aws_iam_policy_document" "task_efs_access" {
  statement {
    sid    = "EfsClientAccess"
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]
    resources = [aws_efs_file_system.this.arn]
    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [aws_efs_access_point.qdrant.arn, aws_efs_access_point.mempalace.arn]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-ecs-task"
  })
}

resource "aws_iam_role_policy" "task_efs_access" {
  name   = "efs-client-access"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_efs_access.json
}

###############################################################################
# CloudWatch Logs
###############################################################################

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_158: "KMS encryption optional; controlled via var.kms_key_arn"
  # checkov:skip=CKV_AWS_338: "Retention policy varies by environment; default var.log_retention_days=30, override to 365 in prod (same convention as ecs_service module)"
  name              = "/ecs/${var.cluster_name}/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(local.common_tags, {
    "Name" = "/ecs/${var.cluster_name}/${local.name_prefix}"
  })
}

###############################################################################
# Task Definition — two containers, task-local networking (qdrant reachable
# only via localhost from the mempalace container, never its own ENI ingress)
###############################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = local.name_prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  volume {
    name = "qdrant-storage"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.qdrant.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "mempalace-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.this.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.mempalace.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "qdrant"
      image     = var.qdrant_image
      essential = true
      # No portMappings: internal-only, reached by the mempalace container
      # over localhost within the shared task network namespace.
      mountPoints = [
        {
          sourceVolume  = "qdrant-storage"
          containerPath = "/qdrant/storage"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "qdrant"
        }
      }
    },
    {
      name      = "mempalace"
      image     = var.mempalace_image
      essential = true
      command   = ["serve", "--host", "0.0.0.0", "--port", tostring(var.mempalace_port), "--backend", "qdrant"]
      dependsOn = [
        {
          containerName = "qdrant"
          condition     = "START"
        }
      ]
      portMappings = [
        {
          containerPort = var.mempalace_port
          protocol      = "tcp"
        }
      ]
      environment = concat(
        [
          {
            name  = "MEMPALACE_QDRANT_URL"
            value = "http://localhost:${var.qdrant_port}"
          }
        ],
        var.embedding_device != null ? [
          {
            name  = "MEMPALACE_EMBEDDING_DEVICE"
            value = var.embedding_device
          }
        ] : []
      )
      secrets = [
        {
          name      = "MEMPALACE_MCP_HTTP_TOKEN"
          valueFrom = var.bearer_token_secret_arn
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "mempalace-data"
          containerPath = "/data"
          readOnly      = false
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "python3 -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:${var.mempalace_port}/healthz', timeout=3).status == 200 else 1)\" || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = var.health_check_grace_period
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "mempalace"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    "Name" = local.name_prefix
  })
}

###############################################################################
# ECS Service
###############################################################################

resource "aws_ecs_service" "this" {
  # checkov:skip=CKV_AWS_333: "assign_public_ip default true is deliberate (ADR-034/ADR-031 no-NAT-Gateway cost pattern) — task SG only accepts ingress from alb_security_group_id, never direct public ingress, so the public IP alone doesn't expose the task port"
  name            = local.name_prefix
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Stop-then-start, not the ECS default of start-then-stop (200%/100%).
  # Found the hard way (2026-08-15): mempalace holds a single-writer lock
  # on the shared EFS palace, so a default rolling deployment — where the
  # new task starts and tries to acquire that lock WHILE the old task is
  # still running and holding it — reliably fails every single redeploy
  # ("Writable MCP HTTP startup refused: ... palace is held by PID 1"),
  # not occasionally. The deployment circuit breaker catches this and
  # rolls back automatically, so it's self-healing rather than silently
  # broken, but it means a token rotation or task-definition update never
  # actually takes effect without this fix. Consistent with the module's
  # own singleton design (desired_count capped at 1 elsewhere) — this is
  # the deployment-strategy half of that same constraint.
  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  # EFS mount targets must exist before tasks try to mount them
  depends_on = [aws_efs_mount_target.this]

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [module.task_sg.id]
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = "mempalace"
      container_port   = var.mempalace_port
    }
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  propagate_tags = "TASK_DEFINITION"

  lifecycle {
    ignore_changes = [
      task_definition, # Managed by CI/CD deployments once those exist
      desired_count,   # Managed by CLI/CI scaling (matches ecs_service module's own pattern)
    ]
  }

  tags = merge(local.common_tags, {
    "Name" = local.name_prefix
  })
}
