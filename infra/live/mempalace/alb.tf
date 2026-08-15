# MemPalace ALB + WAF
# ADR-034: fully public + WAF, bearer token as the primary access control.
#
# HTTPS is variable-gated (enable_https, default false) — see variables.tf
# for why: ACM can't issue a cert for the ALB's own *.elb.amazonaws.com
# name, and no domain has been decided yet. Until enable_https=true, this
# serves plain HTTP. That's a deliberate, temporary starting point per
# direct instruction — not something to leave as the end state.

###############################################################################
# ALB
###############################################################################

resource "aws_lb" "mempalace" {
  # checkov:skip=CKV_AWS_150: "Deletion protection off — matches infra-lab's other lab/dev ALBs, single-owner account"
  # checkov:skip=CKV_AWS_91: "Access logs off for cost; revisit if this account ever holds more than one person's data"
  # checkov:skip=CKV2_AWS_28: "WAF is associated below (aws_wafv2_web_acl_association) — checkov doesn't always resolve the cross-resource association statically"
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.sg_alb.id]
  subnets            = module.mempalace_vpc.public_subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-alb"
  })
}

###############################################################################
# Target Group
###############################################################################

resource "aws_lb_target_group" "mempalace" {
  name        = "${local.name_prefix}-tg"
  port        = 8765
  protocol    = "HTTP"
  vpc_id      = module.mempalace_vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-tg"
  })
}

###############################################################################
# Listeners
###############################################################################

# HTTP: forwards directly while enable_https=false; redirects to HTTPS once true
resource "aws_lb_listener" "http" {
  # checkov:skip=CKV_AWS_2: "Deliberate, temporary: no domain exists yet so ACM can't issue a cert for this ALB (see variables.tf enable_https, ADR-034). Bearer token + WAF apply regardless. Not the end state — flip enable_https once a domain is decided."
  load_balancer_arn = aws_lb.mempalace.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.enable_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.enable_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.mempalace.arn
    }
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.mempalace.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mempalace.arn
  }

  tags = local.common_tags
}

###############################################################################
# WAF — managed rules + rate limiting only (ADR-034: keep it cheap; skip
# Bot Control / Fraud Control, not proportionate to a personal endpoint)
###############################################################################

resource "aws_wafv2_web_acl" "mempalace" {
  name        = "${local.name_prefix}-waf"
  description = "MemPalace ALB, AWS managed common rules + rate limiting"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-managed-common"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Covers Log4Shell (CVE-2021-44228) among other known-bad-input patterns —
  # cheap, small rule group, no reason to skip this one instead of adding it.
  rule {
    name     = "aws-managed-known-bad-inputs"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000 # requests per 5-minute window per IP
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_association" "mempalace" {
  resource_arn = aws_lb.mempalace.arn
  web_acl_arn  = aws_wafv2_web_acl.mempalace.arn
}
