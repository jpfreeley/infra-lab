# IAM Instance Profile Module

Reusable Terraform module for AWS IAM Instance Profiles.

## Usage Example

```hcl
module "instance_profile_example" {
  source    = "../../modules/iam_instance_profile"
  name      = "example-instance-profile"
  role_name = "example-iam-role"

  tags = {
    Environment = "dev"
  }
}
```
