# MemPalace ALB + WAF
# ADR-034: fully public + WAF, bearer token as the primary access control.
#
# HTTPS is variable-gated (enable_https, default true as of the
# mempalace.lintwiselabs.com ACM cert being issued and validated — see
# variables.tf and acm.tf). Kept as a variable rather than hardcoded so a
# domain-less deployment (e.g. before Magnet Legal has one) can still set
# it false and get plain HTTP behind WAF + bearer token as a bootstrap.

###############################################################################
# ALB
###############################################################################

resource "aws_lb" "mempalace" {
  # checkov:skip=CKV_AWS_150: "Deletion protection off — matches infra-lab's other lab/dev ALBs, single-owner account"
  # checkov:skip=CKV_AWS_91: "Access logs off for cost; revisit if this account ever holds more than one person's data"
  # checkov:skip=CKV2_AWS_28: "WAF is associated below (aws_wafv2_web_acl_association) — checkov doesn't always resolve the cross-resource association statically"
  # checkov:skip=CKV2_AWS_76: "The Log4j-covering rule group (AWSManagedRulesKnownBadInputsRuleSet) IS attached, in aws_wafv2_web_acl.mempalace below (see its 'aws-managed-known-bad-inputs' rule) — checkov can't resolve that across the ALB/WebACL/rule resource graph"
  # checkov:skip=CKV2_AWS_20: "The HTTP listener below DOES redirect to HTTPS when enable_https=true (its first dynamic default_action block, type=redirect to :443) — checkov isn't resolving that dynamic-block ternary against the variable's default for this specific check, though it does for CKV_AWS_2 on the same resource"
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
  # checkov:skip=CKV_AWS_378: "Deliberate: TLS terminates at the ALB (the HTTPS listener above), this is the ALB-to-task hop inside the VPC, not the client-facing one — standard pattern, not a gap"
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
  # checkov:skip=CKV_AWS_103: "This is the plain HTTP listener (port 80) that redirects to HTTPS when enable_https=true — it never terminates TLS itself, so an ssl_policy doesn't apply here. The actual TLS 1.2+ requirement is enforced on aws_lb_listener.https below (ssl_policy = ELBSecurityPolicy-TLS13-1-2-2021-06)."
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

  # Default action stays the personal instance, unchanged — the MagNet
  # Legal host below is matched by an explicit listener_rule (host_header
  # condition) instead, added on top rather than replacing this. Any
  # request that doesn't match magnetlegal.mempalace.lintwiselabs.com
  # keeps hitting this default action exactly as it always has.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.mempalace.arn
  }

  tags = local.common_tags
}

###############################################################################
# MagNet Legal instance — second target on the same ALB
# (docs/adr/034-shared-mempalace-server.md, "MagNet Legal Instance" section)
###############################################################################

resource "aws_lb_target_group" "magnetlegal" {
  # checkov:skip=CKV_AWS_378: "Same deliberate TLS-terminates-at-ALB pattern as aws_lb_target_group.mempalace above — this is the ALB-to-task hop inside the VPC."
  name        = "${local.magnetlegal_prefix}-tg"
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
    "Name" = "${local.magnetlegal_prefix}-tg"
  })
}

# SNI: ALB HTTPS listeners support more than one certificate once you
# attach additional ones this way — no listener changes needed, no
# second HTTPS port, and aws_lb_listener.https's own certificate_arn
# (the personal instance's cert) is untouched.
resource "aws_lb_listener_certificate" "magnetlegal" {
  count = var.enable_https ? 1 : 0

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = aws_acm_certificate_validation.magnetlegal.certificate_arn
}

resource "aws_lb_listener_rule" "magnetlegal" {
  count = var.enable_https ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.magnetlegal.arn
  }

  condition {
    host_header {
      values = ["magnetlegal.mempalace.lintwiselabs.com"]
    }
  }

  tags = local.common_tags
}

###############################################################################
# WAF — managed rules + rate limiting only (ADR-034: keep it cheap; skip
# Bot Control / Fraud Control, not proportionate to a personal endpoint)
###############################################################################

resource "aws_wafv2_web_acl" "mempalace" {
  # checkov:skip=CKV2_AWS_31: "Logging deliberately disabled 2026-08-15 after its Authorization-header redaction was verified NOT to work, leaking the bearer token in plaintext into CloudWatch Logs on every request. See the commented-out logging resources below for the full incident note. Re-enable only once redaction is proven working with a throwaway token first."
  name        = "${local.name_prefix}-waf"
  description = "MemPalace ALB, AWS managed common rules + rate limiting"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-managed-common"
    priority = 1

    # Whole rule group set to Count, not Block, as of 2026-08-15 — was
    # override_action=none with a single rule_action_override for
    # GenericLFI_BODY, but that turned into whack-a-mole: confirmed a
    # SECOND generic body-inspection rule (CrossSiteScripting_BODY) also
    # false-positiving on ordinary stored content within the same test
    # session (via aws wafv2 get-sampled-requests, since full WAF logging
    # is off — see the logging-disabled note below).
    #
    # Stepping back rather than continuing to patch individually: this
    # rule group's generic content-inspection rules (LFI, XSS, SQLi) are
    # built for anonymous public form traffic, where "does this look like
    # an injection attempt" is a meaningful signal. This endpoint's real
    # access control is the bearer token — everything reaching /mcp is
    # either an authenticated call legitimately storing arbitrary
    # text/code/HTML verbatim, or gets 401'd before content inspection
    # matters at all. The Common Rule Set is the wrong shape for a
    # token-gated arbitrary-content-storage API. Kept for visibility
    # (Count, not removed) rather than dropped entirely.
    #
    # AWSManagedRulesKnownBadInputsRuleSet below (Log4Shell-class exploit
    # signatures — about attacking the server, not about stored content
    # looking suspicious) and the rate-limit rule still actively block;
    # only this group's blocking was disabled.
    override_action {
      count {}
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
        # Was temporarily bumped 2000 -> 20000 on 2026-08-15 for the bulk
        # EFS migration (the migration script's own traffic, a single
        # trusted authenticated IP, was tripping this well below the
        # cpu=2048 task's real capacity). Reverted back to 2000 the same
        # day once the ~41k-record migration finished, alongside the
        # cpu/memory revert in variables.tf.
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

# WAF logging is DISABLED, deliberately, as of 2026-08-15 — was enabled
# with a redacted_fields block for the Authorization header (which for
# this deployment IS the bearer token, the only access control on the
# whole service), but that redaction was verified NOT to work: the token
# kept showing up in plaintext in CloudWatch Logs on every request even
# after the redacted config was live and confirmed correct via
# `aws wafv2 get-logging-configuration`, and after waiting well past any
# reasonable propagation delay. Rather than keep leaking the token while
# investigating why AWS's redaction didn't take effect, logging was cut
# off immediately (`aws wafv2 delete-logging-configuration`) and the
# token was rotated on the assumption it was already exposed.
#
# Re-enabling this needs the redaction actually proven to work first, not
# just configured — test with a throwaway header value and confirm the
# log shows REDACTED before trusting it with the real token again.
#
# resource "aws_cloudwatch_log_group" "waf" {
#   name              = "aws-waf-logs-${local.name_prefix}"
#   retention_in_days = var.log_retention_days
#   kms_key_id        = module.mempalace_kms.key_arn
#   tags              = local.common_tags
# }
#
# resource "aws_wafv2_web_acl_logging_configuration" "mempalace" {
#   resource_arn            = aws_wafv2_web_acl.mempalace.arn
#   log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
#   redacted_fields {
#     single_header {
#       name = "authorization"
#     }
#   }
# }

resource "aws_wafv2_web_acl_association" "mempalace" {
  resource_arn = aws_lb.mempalace.arn
  web_acl_arn  = aws_wafv2_web_acl.mempalace.arn
}
