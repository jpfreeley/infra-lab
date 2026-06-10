# Application Load Balancer
# Epic: E06 - Compute (ECS Fargate API + Workers)
# Story: S003 - API Service: ALB + target groups + health checks

###############################################################################
# ALB
###############################################################################

resource "aws_lb" "api" {
  # checkov:skip=CKV_AWS_150: "Deletion protection disabled in dev for teardown flexibility"
  # checkov:skip=CKV_AWS_91: "ALB access logs disabled in dev for cost optimization"
  name               = "${local.name_prefix}-api-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.sg_alb_control.id]
  subnets            = module.control_vpc.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = false # Dev only — enable in prod

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-api-alb"
  })
}

###############################################################################
# Target Group (Blue)
###############################################################################

resource "aws_lb_target_group" "api_blue" {
  name        = "${local.name_prefix}-api-blue"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.control_vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-api-blue"
  })
}

###############################################################################
# Target Group (Green) - for Blue/Green deployments
###############################################################################

resource "aws_lb_target_group" "api_green" {
  name        = "${local.name_prefix}-api-green"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.control_vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-api-green"
  })
}

###############################################################################
# Listener (HTTPS) - production traffic
###############################################################################

resource "aws_lb_listener" "api_https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_blue.arn
  }

  lifecycle {
    ignore_changes = [default_action] # Managed by CodeDeploy
  }

  tags = local.common_tags
}

###############################################################################
# Listener (HTTP to HTTPS redirect)
###############################################################################

resource "aws_lb_listener" "api_http_redirect" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.common_tags
}

###############################################################################
# Test Listener (for Blue/Green validation)
###############################################################################

resource "aws_lb_listener" "api_test" {
  load_balancer_arn = aws_lb.api.arn
  port              = 8443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_green.arn
  }

  lifecycle {
    ignore_changes = [default_action] # Managed by CodeDeploy
  }

  tags = local.common_tags
}
