# ECS Service Module
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Stories: S003 (API Service), S005 (Worker Services)

###############################################################################
# CloudWatch Log Group
###############################################################################

resource "aws_cloudwatch_log_group" "this" {
  # checkov:skip=CKV_AWS_158: "KMS encryption optional; controlled via kms_key_arn variable"
  # checkov:skip=CKV_AWS_338: "Retention policy varies by environment; 365d enforced in prod"
  name              = "/ecs/${var.cluster_name}/${var.service_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    "Name"      = "/ecs/${var.cluster_name}/${var.service_name}"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Task Definition
###############################################################################

resource "aws_ecs_task_definition" "this" {
  family                   = var.service_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.container_image
      cpu       = var.cpu
      memory    = var.memory
      essential = true

      portMappings = var.container_port != null ? [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ] : []

      environment = [for k, v in var.environment_variables : {
        name  = k
        value = v
      }]

      secrets = [for k, v in var.secrets : {
        name      = k
        valueFrom = v
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = var.container_name
        }
      }

      healthCheck = var.health_check_command != null ? {
        command     = ["CMD-SHELL", var.health_check_command]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = var.health_check_grace_period
      } : null
    }
  ])

  tags = merge(var.tags, {
    "Name"      = var.service_name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# ECS Service
###############################################################################

resource "aws_ecs_service" "this" {
  name            = var.service_name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  # ALB configuration (for API services)
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # Blue/Green deployment (CodeDeploy)
  dynamic "deployment_controller" {
    for_each = var.enable_blue_green ? [1] : []
    content {
      type = "CODE_DEPLOY"
    }
  }

  # Rolling deployment (default)
  dynamic "deployment_controller" {
    for_each = var.enable_blue_green ? [] : [1]
    content {
      type = "ECS"
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  propagate_tags = "TASK_DEFINITION"

  lifecycle {
    ignore_changes = [
      desired_count,   # Managed by autoscaling
      task_definition, # Managed by CI/CD deployments
    ]
  }

  tags = merge(var.tags, {
    "Name"      = var.service_name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}
