resource "aws_securityhub_organization_configuration" "this" {
  provider    = aws.audit
  auto_enable = true
}

# Standards for the Management Account (must use default provider)
resource "aws_securityhub_standards_subscription" "foundational" {
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
}

# Aggregator (must use audit provider)
resource "aws_securityhub_finding_aggregator" "this" {
  provider = aws.audit

  linking_mode = "ALL_REGIONS"
}
