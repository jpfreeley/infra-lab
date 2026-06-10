# ECS IAM Roles
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Story: S002 - Task execution roles and task roles (least privilege)

###############################################################################
# Task Execution Role (pulls images, writes logs, reads secrets)
###############################################################################

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.name_prefix}-ecs-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-ecs-task-execution"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_base" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow reading secrets from Secrets Manager (for container secrets)
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${local.name_prefix}/*"
      }
    ]
  })
}

###############################################################################
# API Task Role (what the API container can do at runtime)
###############################################################################

resource "aws_iam_role" "ecs_task_api" {
  name = "${local.name_prefix}-ecs-task-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-ecs-task-api"
  })
}

resource "aws_iam_role_policy" "ecs_task_api" {
  name = "api-permissions"
  role = aws_iam_role.ecs_task_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSPublish"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:*:${local.name_prefix}-*"
      },
      {
        Sid    = "S3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${local.name_prefix}-*",
          "arn:aws:s3:::${local.name_prefix}-*/*"
        ]
      }
    ]
  })
}

###############################################################################
# Worker Task Role (what worker containers can do at runtime)
###############################################################################

resource "aws_iam_role" "ecs_task_worker" {
  name = "${local.name_prefix}-ecs-task-worker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-ecs-task-worker"
  })
}

resource "aws_iam_role_policy" "ecs_task_worker" {
  name = "worker-permissions"
  role = aws_iam_role.ecs_task_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:*:${local.name_prefix}-*"
      },
      {
        Sid    = "S3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::${local.name_prefix}-*/*"
        ]
      }
    ]
  })
}
