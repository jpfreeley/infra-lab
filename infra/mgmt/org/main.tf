resource "aws_organizations_organization" "org" {
  aws_service_access_principals = [
    "controltower.amazonaws.com",
    "iam.amazonaws.com",
    "sso.amazonaws.com",
    "securityhub.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com",
    "guardduty.amazonaws.com",
    "malware-protection.guardduty.amazonaws.com"
  ]
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
  ]
  feature_set = "ALL"
}
