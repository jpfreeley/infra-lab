# S3 Secure Bucket Module
# Epic: E02 - Terraform Foundations + State
# Story: S005 - Create Terraform module interface: s3_secure_bucket

resource "aws_s3_bucket" "this" {
  bucket = var.name

  dynamic "logging" {
    for_each = var.enable_access_logging ? [1] : []
    content {
      target_bucket = var.logging_target_bucket
      target_prefix = "${var.name}/"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire_noncurrent"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_days
    }

    filter {
      prefix = ""
    }
  }

  rule {
    id     = "abort_incomplete_multipart_upload"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_multipart_days
    }

    filter {
      prefix = ""
    }
  }
}

resource "aws_s3_bucket_notification" "this" {
  bucket = aws_s3_bucket.this.id

  dynamic "lambda_function" {
    for_each = var.enable_event_notifications ? var.event_notifications.lambda_functions : []
    content {
      lambda_function_arn = lambda_function.value.arn
      events              = lambda_function.value.events
      filter_prefix       = lookup(lambda_function.value, "filter_prefix", null)
      filter_suffix       = lookup(lambda_function.value, "filter_suffix", null)
    }
  }

  dynamic "topic" {
    for_each = var.enable_event_notifications ? var.event_notifications.sns_topics : []
    content {
      topic_arn     = topic.value.arn
      events        = topic.value.events
      filter_prefix = lookup(topic.value, "filter_prefix", null)
      filter_suffix = lookup(topic.value, "filter_suffix", null)
    }
  }

  dynamic "queue" {
    for_each = var.enable_event_notifications ? var.event_notifications.sqs_queues : []
    content {
      queue_arn     = queue.value.arn
      events        = queue.value.events
      filter_prefix = lookup(queue.value, "filter_prefix", null)
      filter_suffix = lookup(queue.value, "filter_suffix", null)
    }
  }
}

# Requires HTTPS for every request. S3 encrypts in transit on any HTTPS
# request already, so this does not add encryption that was missing — it
# removes the possibility of a client falling back to plain HTTP, which
# S3 allows unless a bucket policy explicitly blocks it. Safe for every
# consumer of this module: every real client here (Terraform, the AWS
# CLI, the AWS SDKs, Synology Hyper Backup, AWS service log delivery)
# already uses HTTPS by default, so this denies a request pattern nothing
# legitimate was actually sending.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this.arn,
          "${aws_s3_bucket.this.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count  = var.enable_replication ? 1 : 0
  bucket = aws_s3_bucket.this.id
  role   = var.replication_role_arn

  rule {
    id     = "replication_rule"
    status = "Enabled"

    destination {
      bucket        = var.replication_destination_bucket
      storage_class = "STANDARD"
    }

    filter {
      prefix = ""
    }
  }
}
