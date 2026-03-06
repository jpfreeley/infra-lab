
data "aws_caller_identity" "current" {}

# KMS key for DynamoDB encryption with rotation and policy
resource "aws_kms_key" "dynamodb" {
  description             = "KMS key for DynamoDB table encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Allow administration of the key"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# KMS key for S3 bucket encryption with rotation and policy
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Allow administration of the key"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow use of the key"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 bucket for logs of the log bucket (access logging target)
resource "aws_s3_bucket" "log_bucket_logs" {
  bucket = "infra-lab-tf-state-log-bucket-logs-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "expire-logs"
    enabled = true

    expiration {
      days = 90
    }

    prefix = ""
  }
}

resource "aws_s3_bucket_acl" "log_bucket_logs_acl" {
  bucket = aws_s3_bucket.log_bucket_logs.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_public_access_block" "log_bucket_logs_public_access" {
  bucket                  = aws_s3_bucket.log_bucket_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "log_bucket_logs_notification" {
  bucket = aws_s3_bucket.log_bucket_logs.id
}

resource "aws_s3_bucket_notification" "log_bucket_logs_replica_notification" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_replica.id
}

# Replica bucket for log_bucket_logs in us-west-2
resource "aws_s3_bucket" "log_bucket_logs_replica" {
  provider = aws.replica
  bucket   = "infra-lab-tf-state-log-bucket-logs-replica-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "expire-logs"
    enabled = true

    expiration {
      days = 90
    }

    prefix = ""
  }
}

resource "aws_s3_bucket_acl" "log_bucket_logs_replica_acl" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_replica.id
  acl      = "private"
}

resource "aws_s3_bucket_public_access_block" "log_bucket_logs_replica_public_access" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.log_bucket_logs_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for log_bucket_logs replication
resource "aws_iam_role" "log_bucket_logs_replication_role" {
  name = "log-bucket-logs-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "log_bucket_logs_replication_policy" {
  name = "log-bucket-logs-replication-policy"
  role = aws_iam_role.log_bucket_logs_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.log_bucket_logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.log_bucket_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.log_bucket_logs_replica.arn}/*"
      }
    ]
  })
}

# Replication configuration for log_bucket_logs
resource "aws_s3_bucket_replication_configuration" "log_bucket_logs_replication" {
  bucket = aws_s3_bucket.log_bucket_logs.id
  role   = aws_iam_role.log_bucket_logs_replication_role.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.log_bucket_logs_replica.arn
      storage_class = "STANDARD"
    }

    filter {
      prefix = ""
    }
  }
}

# S3 bucket for Terraform state logs with access logging enabled
resource "aws_s3_bucket" "log_bucket" {
  bucket = "infra-lab-tf-state-logs-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.log_bucket_logs.id
    target_prefix = "log-bucket-logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "expire-logs"
    enabled = true

    expiration {
      days = 90
    }

    prefix = ""
  }
}

resource "aws_s3_bucket_acl" "log_bucket_acl" {
  bucket = aws_s3_bucket.log_bucket.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_public_access_block" "log_bucket_public_access" {
  bucket                  = aws_s3_bucket.log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "log_bucket_notification" {
  bucket = aws_s3_bucket.log_bucket.id
}

resource "aws_s3_bucket_notification" "log_bucket_replica_notification" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_replica.id
}

# Replica bucket for log_bucket in us-west-2
resource "aws_s3_bucket" "log_bucket_replica" {
  provider = aws.replica
  bucket   = "infra-lab-tf-state-logs-replica-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "expire-logs"
    enabled = true

    expiration {
      days = 90
    }

    prefix = ""
  }
}

resource "aws_s3_bucket_acl" "log_bucket_replica_acl" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_replica.id
  acl      = "private"
}

resource "aws_s3_bucket_public_access_block" "log_bucket_replica_public_access" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.log_bucket_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for log_bucket replication
resource "aws_iam_role" "log_bucket_replication_role" {
  name = "log-bucket-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "log_bucket_replication_policy" {
  name = "log-bucket-replication-policy"
  role = aws_iam_role.log_bucket_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.log_bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.log_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.log_bucket_replica.arn}/*"
      }
    ]
  })
}

# Replication configuration for log_bucket
resource "aws_s3_bucket_replication_configuration" "log_bucket_replication" {
  bucket = aws_s3_bucket.log_bucket.id
  role   = aws_iam_role.log_bucket_replication_role.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.log_bucket_replica.arn
      storage_class = "STANDARD"
    }

    filter {
      prefix = ""
    }
  }
}

# S3 bucket for Terraform state with KMS encryption and access logging
resource "aws_s3_bucket" "terraform_state" {
  bucket = "infra-lab-tf-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "terraform-state-logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "expire-logs"
    enabled = true

    expiration {
      days = 90
    }

    prefix = ""
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_public_access" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "terraform_state_notification" {
  bucket = aws_s3_bucket.terraform_state.id
}

resource "aws_s3_bucket_notification" "terraform_state_replica_notification" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id
}

# Replica bucket for terraform_state in us-west-2
resource "aws_s3_bucket" "terraform_state_replica" {
  provider = aws.replica
  bucket   = "infra-lab-tf-state-replica-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.s3.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  lifecycle_rule {
    id      = "expire-logs"
    enabled = true

    expiration {
      days = 90
    }

    prefix = ""
  }
}

resource "aws_s3_bucket_acl" "terraform_state_replica_acl" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id
  acl      = "private"
}

resource "aws_s3_bucket_public_access_block" "terraform_state_replica_public_access" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.terraform_state_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for terraform_state replication
resource "aws_iam_role" "terraform_state_replication_role" {
  name = "terraform-state-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "terraform_state_replication_policy" {
  name = "terraform-state-replication-policy"
  role = aws_iam_role.terraform_state_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.terraform_state_replica.arn}/*"
      }
    ]
  })
}

# Replication configuration for terraform_state
resource "aws_s3_bucket_replication_configuration" "terraform_state_replication" {
  bucket = aws_s3_bucket.terraform_state.id
  role   = aws_iam_role.terraform_state_replication_role.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.terraform_state_replica.arn
      storage_class = "STANDARD"
    }

    filter {
      prefix = ""
    }
  }
}

# DynamoDB table for Terraform state locking with PITR and KMS encryption
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "infra-lab-tf-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }
}
