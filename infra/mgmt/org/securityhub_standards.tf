resource "aws_securityhub_organization_configuration" "this" {
  provider    = aws.audit
  auto_enable = true
}

resource "aws_securityhub_standards_subscription" "foundational" {
  # No provider override here - uses default (Management account)
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  # No provider override here - uses default (Management account)
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"

  depends_on = [aws_securityhub_organization_configuration.this]
}
