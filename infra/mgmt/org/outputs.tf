# outputs.tf

output "securityhub_admin_account_id" {
  description = "The AWS Account ID designated as the Security Hub administrator"
  value       = aws_securityhub_organization_admin_account.this.admin_account_id
}

output "securityhub_organization_auto_enable" {
  description = "Whether Security Hub is automatically enabled in new accounts"
  value       = aws_securityhub_organization_configuration.this.auto_enable
}

output "enabled_standards" {
  description = "List of enabled Security Hub standards"
  value = [
    aws_securityhub_standards_subscription.foundational.standards_arn,
    aws_securityhub_standards_subscription.cis.standards_arn
  ]
}
