# Sandbox Account
#
# A general-purpose account for trying things out, under the Sandbox OU
# (which until now held no account). Its first use is a from-zero test of
# the NetBird tablet kit, a portable copy of infra/live/netbird plus a
# bootstrap and a Lambda lease trigger, before it is handed to another
# team.
#
# No service-boundary SCP, unlike the workload accounts: a sandbox exists to
# run whatever is being evaluated. The Sandbox OU still applies the deny-IAM-
# users, deny-root and protect-security-services SCPs. Cost is the risk a
# broad sandbox carries, so it gets its own budget with alerts, below.
#
# Hygiene: resources in this account are expected to be torn down after
# each experiment. Nothing here should be depended on.

resource "aws_organizations_account" "sandbox" {
  name      = "infra-lab-sandbox"
  email     = "infra-lab+sandbox@${var.org_email_domain}"
  parent_id = aws_organizations_organizational_unit.sandbox.id

  role_name = "OrganizationAccountAccessRole"

  # Account closure is a manual process (90-day suspension)
  close_on_deletion = false

  tags = merge(local.common_tags, {
    Environment = "sandbox"
    Service     = "sandbox"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_budgets_budget" "sandbox_monthly" {
  name         = "sandbox-monthly-cost-budget"
  budget_type  = "COST"
  limit_amount = "25.0"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = [aws_organizations_account.sandbox.id]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }
}
