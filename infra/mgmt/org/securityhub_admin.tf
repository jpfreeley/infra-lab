# securityhub_admin.tf

# Designate the Security Audit account as the delegated administrator for Security Hub

resource "aws_securityhub_organization_admin_account" "this" {
  admin_account_id = "881413600100"
}
