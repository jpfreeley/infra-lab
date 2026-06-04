####
# IAM Account Password Policy - E03-S018
#
# Sets a restrictive IAM password policy for all accounts in the organization.
# Since all human access uses IAM Identity Center (SSO), IAM passwords are
# only relevant for break-glass scenarios and service accounts (which should
# not exist per our SCP). This policy ensures any residual IAM users meet
# strong password requirements.
####

resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  hard_expiry                    = false
}
