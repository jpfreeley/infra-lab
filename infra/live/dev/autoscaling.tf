# ECS Autoscaling Policies
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Story: S006 - Autoscaling policies (queue depth, CPU, memory)

###############################################################################
# API Service Autoscaling (CPU-based)
###############################################################################

resource "aws_appautoscaling_target" "api" {
  max_capacity       = 10
  min_capacity       = 0
  resource_id        = "service/${module.control_cluster.cluster_name}/${module.api_service.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "api_cpu" {
  name               = "${local.name_prefix}-api-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "api_memory" {
  name               = "${local.name_prefix}-api-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api.resource_id
  scalable_dimension = aws_appautoscaling_target.api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

###############################################################################
# Worker Nano Autoscaling (CPU-based, scales 1-5)
###############################################################################

resource "aws_appautoscaling_target" "worker_nano" {
  max_capacity       = 5
  min_capacity       = 0
  resource_id        = "service/${module.execution_cluster.cluster_name}/${module.worker_nano.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_nano_cpu" {
  name               = "${local.name_prefix}-worker-nano-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker_nano.resource_id
  scalable_dimension = aws_appautoscaling_target.worker_nano.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker_nano.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

###############################################################################
# Worker Medium Autoscaling (CPU-based, scales 1-10)
###############################################################################

resource "aws_appautoscaling_target" "worker_medium" {
  max_capacity       = 10
  min_capacity       = 0
  resource_id        = "service/${module.execution_cluster.cluster_name}/${module.worker_medium.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_medium_cpu" {
  name               = "${local.name_prefix}-worker-medium-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker_medium.resource_id
  scalable_dimension = aws_appautoscaling_target.worker_medium.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker_medium.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

###############################################################################
# Worker XLarge Autoscaling (scales 0-5, queue-driven)
###############################################################################

resource "aws_appautoscaling_target" "worker_xlarge" {
  max_capacity       = 5
  min_capacity       = 0
  resource_id        = "service/${module.execution_cluster.cluster_name}/${module.worker_xlarge.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_xlarge_cpu" {
  name               = "${local.name_prefix}-worker-xlarge-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker_xlarge.resource_id
  scalable_dimension = aws_appautoscaling_target.worker_xlarge.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker_xlarge.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 50.0
    scale_in_cooldown  = 600
    scale_out_cooldown = 60
  }
}
