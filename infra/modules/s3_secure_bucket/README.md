# S3 Secure Bucket Module

This module creates an S3 bucket with enforced security best practices:

- **SSE-KMS Encryption**: Uses a customer-managed KMS key.
- **Versioning**: Enabled to protect against accidental deletes.
- **Public Access Block**: Blocks all public access by default.
- **Lifecycle Policy**: Expires non-current versions and aborts incomplete multipart uploads.
- **Access Logging**: Optional logging to a target bucket.
- **Event Notifications**: Optional event notifications to Lambda, SNS, or SQS.
- **Cross-Region Replication**: Optional replication to a destination bucket.

## Usage

~~~hcl
module "secure_bucket" {
  source = "../../modules/s3_secure_bucket"

  name         = "my-secure-app-bucket-12345"
  kms_key_arn  = module.kms_example.key_arn

  enable_access_logging       = true
  logging_target_bucket       = "my-logging-bucket"

  enable_event_notifications  = true
  event_notifications = {
    lambda_functions = [
      {
        arn    = "arn:aws:lambda:us-east-1:123456789012:function:my-function"
        events = ["s3:ObjectCreated:*"]
      }
    ]
    sns_topics = []
    sqs_queues = []
  }

  enable_replication          = true
  replication_role_arn        = "arn:aws:iam::123456789012:role/my-replication-role"
  replication_destination_bucket = "arn:aws:s3:::my-replica-bucket"

  lifecycle_days              = 90
  abort_multipart_days        = 7
}
~~~

## Requirements

| Name      | Version  |
| :-------- | :------- |
| terraform | >= 1.7.0 |
| aws       | ~> 5.0   |
