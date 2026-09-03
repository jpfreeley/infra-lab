# ALB Access Logs — personal-vs-MagNet-Legal usage split
#
# Enabled to answer "how much traffic did each instance actually get"
# without depending on target-group ARNs, which churn on every
# idle-teardown destroy/recreate cycle (confirmed empirically 2026-09-03:
# a fresh ALB incarnation starts with zero CloudWatch history under its
# new ARN — there's no continuous per-instance metric history across
# teardown cycles). ALB access logs carry `domain_name` (the Host
# header) per request, which is stable across every recreation:
# mempalace.lintwiselabs.com vs magnetlegal.mempalace.lintwiselabs.com
# never change even though the ALB/target-group ARNs behind them do.
#
# Deliberately a standalone bucket, NOT the shared s3_secure_bucket
# module: that module hardcodes SSE-KMS, and AWS's ELB log-delivery
# service cannot write to a bucket using a customer-managed KMS key —
# only SSE-S3 (or no encryption) is supported for ALB access logging.
# Confirmed via AWS's own documented constraint, not discovered by
# trial and error against a real 403.
#
# Deliberately NOT reusing the WAF logging path (alb.tf's commented-out
# aws_wafv2_web_acl_logging_configuration) even though it already exists
# in this file — that path is off on purpose after a real incident
# (bearer token leaked in plaintext despite a redaction config verified
# live and still failing, see alb.tf's own header comment). ALB access
# logs are a structurally different, safer format: fixed fields only
# (timestamps, status codes, domain_name, the request line), no request
# headers captured at all, so the Authorization bearer token can never
# appear in them regardless of any redaction config working or not.

###############################################################################
# S3 bucket
###############################################################################

resource "aws_s3_bucket" "alb_access_logs" {
  # checkov:skip=CKV_AWS_144: "Cross-region replication not needed — these are operational logs for cost/usage analysis, not compliance evidence with a DR requirement"
  # checkov:skip=CKV_AWS_18: "Access logging ON this bucket (logs of who read the logs) not needed — this isn't a compliance evidence store, just usage-analysis input; matches this account's other non-evidence buckets"
  # checkov:skip=CKV_AWS_21: "Versioning not needed — ELB-delivered log objects are already append-only/immutable by nature, never overwritten in place; versioning would only retain noise from the 90-day expiration lifecycle rule"
  # checkov:skip=CKV2_AWS_62: "Event notifications not needed — nothing consumes bucket-write events here, this bucket is read via Athena/Glue, not event-driven"
  # checkov:skip=CKV_AWS_145: "SSE-S3, not KMS, is deliberate — see this file's header comment: AWS's ELB log-delivery service cannot write to a customer-managed-KMS-encrypted bucket, only SSE-S3 or no encryption is supported"
  bucket = "${local.name_prefix}-alb-access-logs"

  tags = merge(local.common_tags, {
    "Name" = "${local.name_prefix}-alb-access-logs"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3, not KMS — see file header for why
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id

  rule {
    id     = "expire_old_logs"
    status = "Enabled"

    expiration {
      days = 90 # matches this repo's other non-compliance-evidence retention default
    }

    filter {
      prefix = ""
    }
  }

  rule {
    id     = "abort_incomplete_multipart_upload"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      prefix = ""
    }
  }
}

# AWS's documented policy for ELB access-log delivery: the regional ELB
# service account (a fixed, AWS-published account ID per region — NOT
# this account's own ID) needs PutObject under the ALB's own log prefix.
# us-east-1's account is 127311923021, unchanged since ALB logging
# launched: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html
data "aws_iam_policy_document" "alb_access_logs" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::127311923021:root"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_access_logs.arn}/alb/AWSLogs/${var.mempalace_account_id}/*"]
  }
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  bucket = aws_s3_bucket.alb_access_logs.id
  policy = data.aws_iam_policy_document.alb_access_logs.json
}

###############################################################################
# Athena — query by domain_name to split personal vs magnetlegal usage
###############################################################################

resource "aws_athena_workgroup" "mempalace" {
  # checkov:skip=CKV_AWS_82: "Query-results encryption via SSE-S3 below is sufficient — no compliance requirement for CMK on ad-hoc usage-analysis queries"
  name = "${local.name_prefix}-alb-logs"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.alb_access_logs.id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = local.common_tags
}

resource "aws_glue_catalog_database" "alb_logs" {
  name = replace("${local.name_prefix}_alb_logs", "-", "_")
}

# Standard AWS-documented DDL for ALB access logs, using partition
# projection (no manual ALTER TABLE ADD PARTITION or crawler needed —
# Athena computes date partitions from the query's own date range).
# Schema: https://docs.aws.amazon.com/athena/latest/ug/application-load-balancer-logs.html
resource "aws_glue_catalog_table" "alb_logs" {
  name          = "alb_logs"
  database_name = aws_glue_catalog_database.alb_logs.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "skip.header.line.count"       = "0"
    "projection.enabled"           = "true"
    "projection.day.type"          = "date"
    "projection.day.range"         = "2026/09/01,NOW"
    "projection.day.format"        = "yyyy/MM/dd"
    "projection.day.interval"      = "1"
    "projection.day.interval.unit" = "DAYS"
    "storage.location.template"    = "s3://${aws_s3_bucket.alb_access_logs.id}/alb/AWSLogs/${var.mempalace_account_id}/elasticloadbalancing/${var.aws_region}/$${day}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.alb_access_logs.id}/alb/AWSLogs/${var.mempalace_account_id}/elasticloadbalancing/${var.aws_region}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.RegexSerDe"
      parameters = {
        "serialization.format" = "1"
        "input.regex"          = "([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*):([0-9]*) ([^ ]*)[:-]([0-9]*) ([-.0-9]*) ([-.0-9]*) ([-.0-9]*) (|[-0-9]*) (-|[-0-9]*) ([-0-9]*) ([-0-9]*) \"([^ ]*) (.*) (- |[^ ]*)\" \"([^\"]*)\" ([A-Z0-9-_]+) ([A-Za-z0-9.-]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^\"]*)\" ([-.0-9]*) ([^ ]*) \"([^\"]*)\" \"([^\"]*)\" \"([^ ]*)\" \"([^\\s]+?)\" \"([^\\s]+)\" \"([^ ]*)\" \"([^ ]*)\" ?([^ ]*)? ?( .*)?"
      }
    }

    # A plain map's for_each iterates in sorted-key order, not the order
    # written here — that silently scrambled every column against the
    # regex's positional capture groups on first deploy (confirmed live:
    # domain_name came back empty for every row; `aws glue get-table`
    # showed columns alphabetized, actions_executed first instead of
    # type). A list of objects preserves definition order, which
    # positional regex-group mapping actually requires.
    dynamic "columns" {
      for_each = [
        { name = "type", type = "string" },
        { name = "time", type = "string" },
        { name = "elb", type = "string" },
        { name = "client_ip", type = "string" },
        { name = "client_port", type = "int" },
        { name = "target_ip", type = "string" },
        { name = "target_port", type = "int" },
        { name = "request_processing_time", type = "double" },
        { name = "target_processing_time", type = "double" },
        { name = "response_processing_time", type = "double" },
        { name = "elb_status_code", type = "int" },
        { name = "target_status_code", type = "string" },
        { name = "received_bytes", type = "bigint" },
        { name = "sent_bytes", type = "bigint" },
        { name = "request_verb", type = "string" },
        { name = "request_url", type = "string" },
        { name = "request_proto", type = "string" },
        { name = "user_agent", type = "string" },
        { name = "ssl_cipher", type = "string" },
        { name = "ssl_protocol", type = "string" },
        { name = "target_group_arn", type = "string" },
        { name = "trace_id", type = "string" },
        { name = "domain_name", type = "string" },
        { name = "chosen_cert_arn", type = "string" },
        { name = "matched_rule_priority", type = "string" },
        { name = "request_creation_time", type = "string" },
        { name = "actions_executed", type = "string" },
        { name = "redirect_url", type = "string" },
        { name = "lambda_error_reason", type = "string" },
        { name = "target_port_list", type = "string" },
        { name = "target_status_code_list", type = "string" },
        { name = "classification", type = "string" },
        { name = "classification_reason", type = "string" },
        { name = "conn_trace_id", type = "string" }, # added 2026-09-03 — AWS's own docs show this field plus a forward-compat catch-all tail on the regex; my first version omitted both and every row came back null (Hive's RegexSerDe requires a FULL-line match, not just a prefix like Python's re.match — confirmed live against a real log line)
      ]
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  partition_keys {
    name = "day"
    type = "string"
  }
}
