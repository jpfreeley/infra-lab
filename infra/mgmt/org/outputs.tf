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

output "workspaces_account_id" {
  description = "The AWS Account ID of the dedicated WorkSpaces account"
  value       = aws_organizations_account.workspaces.id
}

output "mempalace_account_id" {
  description = "The AWS Account ID of the dedicated MemPalace account. Needed to fill in infra/live/mempalace/providers.tf's assume_role ARN after this account is created."
  value       = aws_organizations_account.mempalace.id
}
