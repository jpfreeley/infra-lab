# ACM Certificate for mempalace.lintwiselabs.com
# ADR-034: domain decided 2026-08-14 (see "Decided, Not Yet Built").
#
# The cert must live in this account (us-east-1, matching the ALB's
# region) — ACM certs can't be attached to an ALB across accounts. DNS
# validation, though, needs a record in the lintwiselabs.com zone, which
# lives in the management account — hence the aliased aws.dns provider.
#
# Issuing this doesn't depend on the ALB existing. It can (and does) run
# independently of whether the ALB/WAF/ECS service are currently torn
# down or spun up.

data "aws_route53_zone" "lintwiselabs" {
  provider     = aws.dns
  name         = "lintwiselabs.com."
  private_zone = false
}

resource "aws_acm_certificate" "mempalace" {
  domain_name       = "mempalace.lintwiselabs.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_route53_record" "mempalace_cert_validation" {
  provider = aws.dns

  for_each = {
    for dvo in aws_acm_certificate.mempalace.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.lintwiselabs.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "mempalace" {
  certificate_arn         = aws_acm_certificate.mempalace.arn
  validation_record_fqdns = [for r in aws_route53_record.mempalace_cert_validation : r.fqdn]
}

# The actual service record — distinct from the cert validation CNAME
# above. Alias records reference the ALB's live dns_name/zone_id, so this
# stays correct automatically across every ALB recreate (nightly
# teardown/spinup, or any other reason it gets replaced) in the same
# apply — no manual re-pointing, ever.
resource "aws_route53_record" "mempalace" {
  provider = aws.dns

  zone_id = data.aws_route53_zone.lintwiselabs.zone_id
  name    = "mempalace.lintwiselabs.com"
  type    = "A"

  alias {
    name                   = aws_lb.mempalace.dns_name
    zone_id                = aws_lb.mempalace.zone_id
    evaluate_target_health = true
  }
}

# Second cert, second host, same ALB — the MagNet Legal instance
# (docs/adr/034-shared-mempalace-server.md, "MagNet Legal Instance" section).
# Deliberately a separate aws_acm_certificate rather than adding a SAN to
# the existing one: SANs require reissuing/revalidating the cert that's
# already live and in use, where a second cert attached via SNI
# (aws_lb_listener_certificate.magnetlegal in alb.tf) leaves the existing
# mempalace.lintwiselabs.com cert and listener completely untouched.

resource "aws_acm_certificate" "magnetlegal" {
  domain_name       = "magnetlegal.mempalace.lintwiselabs.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_route53_record" "magnetlegal_cert_validation" {
  provider = aws.dns

  for_each = {
    for dvo in aws_acm_certificate.magnetlegal.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.lintwiselabs.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "magnetlegal" {
  certificate_arn         = aws_acm_certificate.magnetlegal.arn
  validation_record_fqdns = [for r in aws_route53_record.magnetlegal_cert_validation : r.fqdn]
}

resource "aws_route53_record" "magnetlegal" {
  provider = aws.dns

  zone_id = data.aws_route53_zone.lintwiselabs.zone_id
  name    = "magnetlegal.mempalace.lintwiselabs.com"
  type    = "A"

  alias {
    name                   = aws_lb.mempalace.dns_name
    zone_id                = aws_lb.mempalace.zone_id
    evaluate_target_health = true
  }
}
