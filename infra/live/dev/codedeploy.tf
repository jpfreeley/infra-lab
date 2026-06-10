# CodeDeploy Blue/Green Deployment
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Story: S004 - Blue/Green deployment wiring (CodeDeploy)
#
# Only deployed when ALB is enabled (var.enable_alb = true)

###############################################################################
# CodeDeploy Application
###############################################################################

resource "aws_codedeploy_app" "api" {
  count = var.enable_alb ? 1 : 0

  compute_platform = "ECS"
  name             = "${local.name_prefix}-api"

  tags = local.common_tags
}

###############################################################################
# CodeDeploy Deployment Group
###############################################################################

resource "aws_codedeploy_deployment_group" "api" {
  count = var.enable_alb ? 1 : 0

  app_name               = aws_codedeploy_app.api[0].name
  deployment_group_name  = "${local.name_prefix}-api-dg"
  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  service_role_arn       = aws_iam_role.codedeploy[0].arn

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  ecs_service {
    cluster_name = module.control_cluster.cluster_name
    service_name = module.api_service.service_name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.api_https[0].arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.api_test[0].arn]
      }

      target_group {
        name = aws_lb_target_group.api_blue[0].name
      }

      target_group {
        name = aws_lb_target_group.api_green[0].name
      }
    }
  }

  tags = local.common_tags
}

###############################################################################
# CodeDeploy IAM Role
###############################################################################

resource "aws_iam_role" "codedeploy" {
  count = var.enable_alb ? 1 : 0

  name = "${local.name_prefix}-codedeploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-codedeploy"
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  count = var.enable_alb ? 1 : 0

  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
