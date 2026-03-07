# 1. Create the Organization-wide Configuration Aggregator
# This allows the Security Audit account to pull compliance data from all accounts
resource "aws_config_configuration_aggregator" "org" {
  name = "infra-lab-org-aggregator"

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator_role.arn
  }

  tags = {
    Name = "infra-lab-org-aggregator"
  }
}

# 2. IAM Role for the Aggregator to describe the Organization
resource "aws_iam_role" "config_aggregator_role" {
  name = "infra-lab-config-org-aggregator-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

# 3. Attach the AWS-managed policy for Organization Config
resource "aws_iam_role_policy_attachment" "config_aggregator_policy" {
  role       = aws_iam_role.config_aggregator_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}
