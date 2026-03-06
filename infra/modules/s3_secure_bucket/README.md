# S3 Secure Bucket Module

This module creates an S3 bucket with enforced security best practices:
- **SSE-KMS Encryption**: Uses a customer-managed KMS key.
- **Versioning**: Enabled to protect against accidental deletes.
- **Public Access Block**: Blocks all public access by default.
- **Lifecycle Policy**: Expires non-current versions after a set number of days.

## Usage

```hcl
module "secure_bucket" {
  source = "../../modules/s3_secure_bucket"

  name         = "my-secure-app-bucket-12345"
  kms_key_arn  = module.kms_example.key_arn
  lifecycle_days = 90
}
```

## Requirements
| Name | Version |
|------|---------|
| terraform | >= 1.7.0 |
| aws | ~> 5.0 |
