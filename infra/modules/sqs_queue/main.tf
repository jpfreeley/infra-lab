# SQS Queue Module
# Epic: E08 - Orchestration (SQS + Step Functions)
# Story: S001 - Create SQS queues per worker tier + DLQs

###############################################################################
# Dead Letter Queue
###############################################################################

resource "aws_sqs_queue" "dlq" {
  # checkov:skip=CKV_AWS_27: "DLQ encryption matches main queue; SSE-SQS is sufficient for dev"
  name = "${var.queue_name}-dlq"

  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = var.kms_key_arn == null ? true : null
  kms_master_key_id         = var.kms_key_arn

  tags = merge(var.tags, {
    "Name"      = "${var.queue_name}-dlq"
    "ManagedBy" = "terraform"
    "Project"   = var.project
    "Purpose"   = "dead-letter-queue"
  })
}

###############################################################################
# Main Queue
###############################################################################

resource "aws_sqs_queue" "this" {
  # checkov:skip=CKV_AWS_27: "SSE-SQS encryption is sufficient for dev; CMK used in prod"
  name = var.queue_name

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  max_message_size           = var.max_message_size
  delay_seconds              = var.delay_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  # Content-based deduplication for FIFO (E08-S003)
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null
  deduplication_scope         = var.fifo_queue ? "messageGroup" : null
  fifo_throughput_limit       = var.fifo_queue ? "perMessageGroupId" : null

  sqs_managed_sse_enabled = var.kms_key_arn == null ? true : null
  kms_master_key_id       = var.kms_key_arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, {
    "Name"      = var.queue_name
    "ManagedBy" = "terraform"
    "Project"   = var.project
  })
}

###############################################################################
# Redrive Allow Policy (DLQ accepts from main queue only)
###############################################################################

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}
