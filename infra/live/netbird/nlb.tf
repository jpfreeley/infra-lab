# NetBird Network Load Balancer
# ADR-037: NLB instead of ALB + WAF. STUN needs public UDP, and the server's
# gRPC routes need h2c to the backend, which Traefik in the task handles.
#
# Teardown target list (for the toggle workflow; everything else stays):
#   aws_route53_record.netbird
#   aws_lb_listener.https
#   aws_lb_listener.stun        (only when embedded STUN is in use)
#   aws_lb_target_group.https
#   aws_lb_target_group.stun    (only when embedded STUN is in use)
#   aws_lb.netbird
#   module.netbird.aws_ecs_service.this
# Never EFS, KMS, the secrets, the ACM certificate, the VPC, or the cluster.

resource "aws_lb" "netbird" {
  # checkov:skip=CKV_AWS_150: "Deletion protection off: the NLB is destroyed and recreated by the lease teardown (ADR-037)"
  # checkov:skip=CKV_AWS_91: "No access logs: single-user endpoint, NLB TLS access logs would only show the owner's own sessions; revisit if the account ever serves anyone else"
  name               = "${local.name_prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [module.sg_nlb.id]
  subnets            = module.netbird_vpc.public_subnet_ids

  # The singleton task runs in one AZ. Without cross-zone, a client that
  # resolves the other AZ's NLB node gets no healthy target.
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-nlb"
  })
}

###############################################################################
# HTTPS: TCP 443 to Traefik
###############################################################################

resource "aws_lb_target_group" "https" {
  name        = "${local.name_prefix}-https"
  port        = module.netbird.https_port
  protocol    = "TCP"
  vpc_id      = module.netbird_vpc.vpc_id
  target_type = "ip"

  # Traefik accepting connections is what the NLB can usefully check here;
  # the server's own /health is checked by the STUN target group.
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-https"
  })
}

resource "aws_lb_listener" "https" {
  # checkov:skip=CKV_AWS_2: "In tls_mode nlb this listener IS TLS; in tls_mode traefik it is deliberately TCP passthrough so Traefik terminates TLS (ADR-037 Option B)"
  # checkov:skip=CKV_AWS_103: "TLS 1.2+ policy is set whenever the listener is TLS; TCP passthrough mode has no listener TLS policy to set"
  load_balancer_arn = aws_lb.netbird.arn
  port              = 443
  protocol          = var.tls_mode == "nlb" ? "TLS" : "TCP"
  certificate_arn   = var.tls_mode == "nlb" ? aws_acm_certificate_validation.netbird.certificate_arn : null
  ssl_policy        = var.tls_mode == "nlb" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  alpn_policy       = var.tls_mode == "nlb" ? "HTTP2Preferred" : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }

  tags = local.common_tags
}

###############################################################################
# STUN: UDP 3478 to netbird-server, only while embedded STUN is in use
###############################################################################

resource "aws_lb_target_group" "stun" {
  count = local.embedded_stun ? 1 : 0

  name        = "${local.name_prefix}-stun"
  port        = 3478
  protocol    = "UDP"
  vpc_id      = module.netbird_vpc.vpc_id
  target_type = "ip"

  # UDP target groups need a TCP/HTTP health check. NOT the server's
  # /health on :9000: found in the 2026-11-19 spike that it includes the
  # relay self-check, which dials the server's own public name through this
  # NLB. A newly registered target receives no NLB traffic until it passes
  # health checks, so /health could never go green, the target was marked
  # unhealthy, and ECS replaced the task in a loop. TCP on Traefik's port
  # (the same check the HTTPS target group passes) breaks the cycle;
  # netbird-server is an essential container, so if it dies the whole task
  # is replaced anyway.
  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = tostring(module.netbird.https_port)
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  deregistration_delay = 30

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-stun"
  })
}

resource "aws_lb_listener" "stun" {
  # checkov:skip=CKV_AWS_2: "STUN is UDP by protocol definition; there is no TLS variant to use"
  # checkov:skip=CKV_AWS_103: "UDP listener, no TLS policy applies"
  count = local.embedded_stun ? 1 : 0

  load_balancer_arn = aws_lb.netbird.arn
  port              = 3478
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stun[0].arn
  }

  tags = local.common_tags
}
