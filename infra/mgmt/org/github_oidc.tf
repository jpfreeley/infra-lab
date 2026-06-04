####
# GitHub OIDC Identity Provider - E04-S005
#
# Creates an OpenID Connect identity provider for GitHub Actions.
# This allows GitHub Actions workflows to assume IAM roles without
# long-lived credentials (access keys), using short-lived OIDC tokens.
#
# The provider is created in the Management account. Deploy roles
# in target accounts will trust this provider via role chaining
# or direct trust policies.
####

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # GitHub's OIDC thumbprint (required but not used for validation)
  # AWS validates the certificate chain directly
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = merge(local.common_tags, { Story = "E04-S005" })
}

####
# GitHub Actions Deploy Role - E04-S006
#
# IAM role that GitHub Actions assumes via OIDC for Terraform deployments.
# Scoped to the infra-lab repository only.
####

resource "aws_iam_role" "github_actions_deploy" {
  name        = "${local.project_name}-github-actions-deploy"
  description = "Role assumed by GitHub Actions via OIDC for Terraform CI/CD deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # E04-S017: Tightened to main branch and pull_request events only
            "token.actions.githubusercontent.com:sub" = [
              "repo:jpfreeley/infra-lab:ref:refs/heads/main",
              "repo:jpfreeley/infra-lab:pull_request",
            ]
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, { Story = "E04-S006" })
}

# Attach AdministratorAccess for Terraform (scoped by OIDC trust to repo only)
# Future: Replace with a custom least-privilege policy
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  # checkov:skip=CKV_AWS_274:GitHub Actions deploy role needs admin for Terraform org management, scoped by OIDC trust policy to infra-lab repo only
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Output the role ARN for use in GitHub Actions workflows
output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions deploy role for use in workflow OIDC configuration"
  value       = aws_iam_role.github_actions_deploy.arn
}
