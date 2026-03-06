# IAM Role OIDC Module

This module creates an IAM role designed for GitHub Actions OIDC authentication.

## Usage

```hcl
module "github_oidc_role" {
  source = "../../modules/iam_role_oidc"

  role_name         = "github-actions-deployer"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  subject_claims    = ["repo:my-org/my-repo:*"]
}
```
