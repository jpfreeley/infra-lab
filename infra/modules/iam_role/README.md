
# IAM Role Module

This module creates an AWS IAM Role with configurable assume role policy, description, session duration, and attached managed policies.

## Usage

```hcl
module "example_iam_role" {
  source             = "../modules/iam_role"
  role_name          = "example-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  description        = "Example IAM role managed by Terraform"
  max_session_duration = 3600
  attach_policy_arns = {
    "AmazonS3ReadOnlyAccess" = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  }
  tags = {
    Environment = "dev"
  }
  project = "infra-lab"
}
```
