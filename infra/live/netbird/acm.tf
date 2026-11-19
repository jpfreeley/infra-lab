# ACM Certificate and DNS for the NetBird server
#
# The certificate lives in this account (NLB TLS listeners can't use a
# certificate from another account); DNS validation and the service record
# go into the lintwiselabs.com zone in the management account through the
# aws.dns provider. Same layout as infra/live/mempalace/acm.tf.
#
# The certificate and its validation are NOT part of teardown: they're
# free, don't depend on the NLB, and re-validating on every up/down cycle
# would be pure friction. Created in both tls_modes so switching modes
# never waits on validation.

data "aws_route53_zone" "lintwiselabs" {
  provider     = aws.dns
  name         = "lintwiselabs.com."
  private_zone = false
}

resource "aws_acm_certificate" "netbird" {
  domain_name       = var.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_route53_record" "netbird_cert_validation" {
  provider = aws.dns

  for_each = {
    for dvo in aws_acm_certificate.netbird.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "netbird" {
  certificate_arn         = aws_acm_certificate.netbird.arn
  validation_record_fqdns = [for r in aws_route53_record.netbird_cert_validation : r.fqdn]
}

# Service record. An alias to the NLB's live attributes, so it follows the
# NLB through every teardown/bring-up; destroying the NLB takes this record
# with it.
resource "aws_route53_record" "netbird" {
  provider = aws.dns

  zone_id = data.aws_route53_zone.lintwiselabs.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_lb.netbird.dns_name
    zone_id                = aws_lb.netbird.zone_id
    evaluate_target_health = true
  }
}
