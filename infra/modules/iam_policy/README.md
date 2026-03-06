
# IAM Policy Module

This module creates an AWS IAM Policy with a JSON policy document and supports attachment to users, roles, and groups.

## Usage

```hcl
module "example_iam_policy" {
  source      = "../modules/iam_policy"
  policy_name = "example-policy"
  description = "Example IAM policy managed by Terraform"
  policy      = data.aws_iam_policy_document.example.json
  attach_to = {
    "example" = {
      roles = ["example-role"]
    }
  }
  tags = {
    Environment = "dev"
  }
  project = "infra-lab"
}
```
