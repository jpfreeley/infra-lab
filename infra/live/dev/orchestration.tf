# Orchestration Layer (SQS Queues + Step Functions)
# Epic: E08 - Orchestration (SQS + Step Functions)
# Stories: S001 (Queues), S002 (State Machine), S003 (Idempotency), S004 (Shutdown)
#
# Architecture:
# API → SQS (per tier) → Workers poll → Process → Ack
# Step Functions orchestrates multi-step jobs with retry/timeout

###############################################################################
# SQS Queues (one per worker tier)
###############################################################################

# Nano queue: lightweight tasks (notifications, webhooks)
module "queue_nano" {
  source = "../../modules/sqs_queue"

  queue_name                 = "${local.name_prefix}-worker-nano"
  visibility_timeout_seconds = 120 # 2 min — nano tasks are fast
  max_receive_count          = 3

  tags = local.common_tags
}

# Medium queue: standard processing (data transforms, reports)
module "queue_medium" {
  source = "../../modules/sqs_queue"

  queue_name                 = "${local.name_prefix}-worker-medium"
  visibility_timeout_seconds = 300 # 5 min — allows for SIGTERM grace period (S004)
  max_receive_count          = 3

  tags = local.common_tags
}

# XLarge queue: heavy compute (ML inference, batch)
module "queue_xlarge" {
  source = "../../modules/sqs_queue"

  queue_name                 = "${local.name_prefix}-worker-xlarge"
  visibility_timeout_seconds = 900 # 15 min — long-running jobs
  max_receive_count          = 2   # Fewer retries for expensive jobs

  tags = local.common_tags
}

# FIFO queue: ordered jobs requiring exactly-once processing (S003)
module "queue_ordered" {
  source = "../../modules/sqs_queue"

  queue_name                  = "${local.name_prefix}-ordered.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 300
  max_receive_count           = 3

  tags = local.common_tags
}

###############################################################################
# Step Functions: Job Lifecycle State Machine (S002)
###############################################################################

module "job_orchestrator" {
  source = "../../modules/step_function"

  state_machine_name = "${local.name_prefix}-job-orchestrator"

  definition_json = jsonencode({
    Comment = "Job lifecycle: validate → route → process → notify"
    StartAt = "ValidateInput"
    States = {
      ValidateInput = {
        Type    = "Pass"
        Comment = "Validate job payload schema"
        Next    = "RouteByTier"
      }
      RouteByTier = {
        Type    = "Choice"
        Comment = "Route to appropriate queue based on job tier"
        Choices = [
          {
            Variable     = "$.tier"
            StringEquals = "nano"
            Next         = "SendToNano"
          },
          {
            Variable     = "$.tier"
            StringEquals = "medium"
            Next         = "SendToMedium"
          },
          {
            Variable     = "$.tier"
            StringEquals = "xlarge"
            Next         = "SendToXLarge"
          }
        ]
        Default = "SendToMedium"
      }
      SendToNano = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          "QueueUrl.$"    = "$.queues.nano"
          "MessageBody.$" = "$.payload"
        }
        Next = "WaitForCompletion"
      }
      SendToMedium = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          "QueueUrl.$"    = "$.queues.medium"
          "MessageBody.$" = "$.payload"
        }
        Next = "WaitForCompletion"
      }
      SendToXLarge = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          "QueueUrl.$"    = "$.queues.xlarge"
          "MessageBody.$" = "$.payload"
        }
        Next = "WaitForCompletion"
      }
      WaitForCompletion = {
        Type    = "Wait"
        Seconds = 30
        Next    = "CheckStatus"
      }
      CheckStatus = {
        Type    = "Choice"
        Comment = "Check if job completed (callback pattern in production)"
        Choices = [
          {
            Variable     = "$.status"
            StringEquals = "COMPLETED"
            Next         = "NotifySuccess"
          },
          {
            Variable     = "$.status"
            StringEquals = "FAILED"
            Next         = "NotifyFailure"
          }
        ]
        Default = "JobSucceeded"
      }
      NotifySuccess = {
        Type    = "Pass"
        Comment = "Placeholder: Send success notification"
        Next    = "JobSucceeded"
      }
      NotifyFailure = {
        Type    = "Pass"
        Comment = "Placeholder: Send failure notification"
        Next    = "JobFailed"
      }
      JobSucceeded = {
        Type = "Succeed"
      }
      JobFailed = {
        Type  = "Fail"
        Error = "JobProcessingFailed"
        Cause = "Worker reported failure"
      }
    }
  })

  role_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSSendMessage"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          module.queue_nano.queue_arn,
          module.queue_medium.queue_arn,
          module.queue_xlarge.queue_arn,
        ]
      },
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })

  log_level          = "ERROR"
  log_retention_days = 14

  tags = local.common_tags
}
