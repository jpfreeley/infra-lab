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

# Dedicated access log bucket for log_bucket_logs
resource "aws_s3_bucket" "log_bucket_logs_access_logs" {
  bucket = "infra-lab-tf-log-bucket-access-logs-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_acl" "log_bucket_logs_access_logs_acl" {
  bucket = aws_s3_bucket.log_bucket_logs_access_logs.id
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket_public_access_block" "log_bucket_logs_access_logs_public_access" {
  bucket                  = aws_s3_bucket.log_bucket_logs_access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "log_bucket_logs_access_logs_notification" {
  bucket = aws_s3_bucket.log_bucket_logs_access_logs.id
}

resource "aws_s3_bucket_logging" "log_bucket_logs_access_logs_logging" {
  bucket        = aws_s3_bucket.log_bucket_logs_access_logs.id
  target_bucket = aws_s3_bucket.log_bucket_logs_access_logs.id
  target_prefix = "self-logs/"
}

resource "aws_s3_bucket_versioning" "log_bucket_logs_access_logs_versioning" {
  bucket = aws_s3_bucket.log_bucket_logs_access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_logs_access_logs_encryption" {
  bucket = aws_s3_bucket.log_bucket_logs_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_logs_access_logs_lifecycle" {
  bucket = aws_s3_bucket.log_bucket_logs_access_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
}

# Replica bucket for log_bucket_logs_access_logs
resource "aws_s3_bucket" "log_bucket_logs_access_logs_replica" {
  provider = aws.replica
  bucket   = "infra-lab-tf-log-bucket-access-logs-rep-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_acl" "log_bucket_logs_access_logs_replica_acl" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_access_logs_replica.id
  acl      = "private"
}

resource "aws_s3_bucket_public_access_block" "log_bucket_logs_access_logs_replica_public_access" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.log_bucket_logs_access_logs_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "log_bucket_logs_access_logs_replica_notification" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_access_logs_replica.id
}

resource "aws_s3_bucket_logging" "log_bucket_logs_access_logs_replica_logging" {
  provider      = aws.replica
  bucket        = aws_s3_bucket.log_bucket_logs_access_logs_replica.id
  target_bucket = aws_s3_bucket.log_bucket_logs_access_logs.id
  target_prefix = "replica-logs/"
}

resource "aws_s3_bucket_versioning" "log_bucket_logs_access_logs_replica_versioning" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_access_logs_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_logs_access_logs_replica_encryption" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_access_logs_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_logs_access_logs_replica_lifecycle" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_access_logs_replica.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
}

resource "aws_iam_role" "log_bucket_logs_access_logs_replication_role" {
  name = "log-bucket-logs-access-logs-replication-role"

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

resource "aws_iam_role_policy" "log_bucket_logs_access_logs_replication_policy" {
  name = "log-bucket-logs-access-logs-replication-policy"
  role = aws_iam_role.log_bucket_logs_access_logs_replication_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.log_bucket_logs_access_logs.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.log_bucket_logs_access_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = "${aws_s3_bucket.log_bucket_logs_access_logs_replica.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "log_bucket_logs_access_logs_replication" {
  bucket = aws_s3_bucket.log_bucket_logs_access_logs.id
  role   = aws_iam_role.log_bucket_logs_access_logs_replication_role.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.log_bucket_logs_access_logs_replica.arn
      storage_class = "STANDARD"
    }

    filter {
      prefix = ""
    }
  }
  depends_on = [aws_s3_bucket_versioning.log_bucket_logs_access_logs_versioning]
}

# S3 bucket for logs of the log bucket (access logging target)
resource "aws_s3_bucket" "log_bucket_logs" {
  bucket = "infra-lab-tf-log-bucket-logs-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
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

resource "aws_s3_bucket_logging" "log_bucket_logs_logging" {
  bucket        = aws_s3_bucket.log_bucket_logs.id
  target_bucket = aws_s3_bucket.log_bucket_logs_access_logs.id
  target_prefix = "log-bucket-logs-logs/"
}

resource "aws_s3_bucket_versioning" "log_bucket_logs_versioning" {
  bucket = aws_s3_bucket.log_bucket_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_logs_encryption" {
  bucket = aws_s3_bucket.log_bucket_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_logs_lifecycle" {
  bucket = aws_s3_bucket.log_bucket_logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
}

# Replica bucket for log_bucket_logs in us-west-2
resource "aws_s3_bucket" "log_bucket_logs_replica" {
  provider = aws.replica
  bucket   = "infra-lab-tf-log-bucket-logs-rep-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
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

resource "aws_s3_bucket_notification" "log_bucket_logs_replica_notification" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_replica.id
}

resource "aws_s3_bucket_logging" "log_bucket_logs_replica_logging" {
  provider      = aws.replica
  bucket        = aws_s3_bucket.log_bucket_logs_replica.id
  target_bucket = aws_s3_bucket.log_bucket_logs_access_logs.id
  target_prefix = "log-bucket-logs-replica-logs/"
}

resource "aws_s3_bucket_versioning" "log_bucket_logs_replica_versioning" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_logs_replica_encryption" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_logs_replica_lifecycle" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_logs_replica.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
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

resource "aws_s3_bucket_logging" "log_bucket_logging" {
  bucket        = aws_s3_bucket.log_bucket.id
  target_bucket = aws_s3_bucket.log_bucket_logs.id
  target_prefix = "log-bucket-logs/"
}

resource "aws_s3_bucket_versioning" "log_bucket_versioning" {
  bucket = aws_s3_bucket.log_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_encryption" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_lifecycle" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
}

# Replica bucket for log_bucket in us-west-2
resource "aws_s3_bucket" "log_bucket_replica" {
  provider = aws.replica
  bucket   = "infra-lab-tf-state-logs-replica-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
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

resource "aws_s3_bucket_notification" "log_bucket_replica_notification" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_replica.id
}

resource "aws_s3_bucket_logging" "log_bucket_replica_logging" {
  provider      = aws.replica
  bucket        = aws_s3_bucket.log_bucket_replica.id
  target_bucket = aws_s3_bucket.log_bucket_logs.id
  target_prefix = "log-bucket-replica-logs/"
}

resource "aws_s3_bucket_versioning" "log_bucket_replica_versioning" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_replica_encryption" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_bucket_replica_lifecycle" {
  provider = aws.replica
  bucket   = aws_s3_bucket.log_bucket_replica.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
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

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "infra-lab-tf-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_acl" "terraform_state_acl" {
  bucket = aws_s3_bucket.terraform_state.id
  acl    = "private"
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

resource "aws_s3_bucket_logging" "terraform_state_logging" {
  bucket        = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "terraform-state-logs/"
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_lifecycle" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
}

# Replica bucket for Terraform state in us-west-2
resource "aws_s3_bucket" "terraform_state_replica" {
  provider = aws.replica
  bucket   = "infra-lab-tf-state-replica-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
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

resource "aws_s3_bucket_notification" "terraform_state_replica_notification" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id
}

resource "aws_s3_bucket_logging" "terraform_state_replica_logging" {
  provider      = aws.replica
  bucket        = aws_s3_bucket.terraform_state_replica.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "terraform-state-replica-logs/"
}

resource "aws_s3_bucket_versioning" "terraform_state_replica_versioning" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_replica_encryption" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state_replica_lifecycle" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
}

# IAM role for Terraform state replication
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

# Replication configuration for Terraform state
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

# DynamoDB table for Terraform state locking
resource "aws_dynamodb_table" "terraform_state_locks" {
  name         = "infra-lab-tf-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }
}
