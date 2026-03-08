resource "aws_iam_role" "organization_account_access_role" {
  # Force it to use the audit alias
  provider = aws.audit
  name     = "OrganizationAccountAccessRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::551452024305:user/terraform-admin"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "admin_access" {
  # checkov:skip=CKV_AWS_274:AdministratorAccess is required for the OrganizationAccountAccessRole to manage the Audit account
  provider   = aws.audit
  role       = aws_iam_role.organization_account_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
