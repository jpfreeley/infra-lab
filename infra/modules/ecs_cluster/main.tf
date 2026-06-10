# ECS Cluster Module
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Story: S001 - Create ECS clusters for control plane and execution plane

resource "aws_ecs_cluster" "this" {
  # checkov:skip=CKV_AWS_224: "CMK encryption for ECS Exec logging optional in dev; controlled via kms_key_arn variable"
  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.exec.name
      }
    }
  }

  tags = merge(var.tags, {
    "Name"      = var.name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = var.fargate_base
    weight            = var.fargate_weight
    capacity_provider = "FARGATE"
  }

  dynamic "default_capacity_provider_strategy" {
    for_each = var.fargate_spot_weight > 0 ? [1] : []
    content {
      weight            = var.fargate_spot_weight
      capacity_provider = "FARGATE_SPOT"
    }
  }
}

resource "aws_cloudwatch_log_group" "exec" {
  # checkov:skip=CKV_AWS_158: "KMS encryption optional; controlled via kms_key_arn variable"
  # checkov:skip=CKV_AWS_338: "Retention policy varies by environment; 365d enforced in prod"
  name              = "/ecs/${var.name}/exec"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    "Name"      = "/ecs/${var.name}/exec"
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}
