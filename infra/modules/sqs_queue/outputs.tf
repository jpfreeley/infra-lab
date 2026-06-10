output "queue_id" {
  description = "The URL of the SQS queue"
  value       = aws_sqs_queue.this.id
}

output "queue_arn" {
  description = "The ARN of the SQS queue"
  value       = aws_sqs_queue.this.arn
}

output "queue_url" {
  description = "The URL of the SQS queue"
  value       = aws_sqs_queue.this.url
}

output "queue_name" {
  description = "The name of the SQS queue"
  value       = aws_sqs_queue.this.name
}

output "dlq_id" {
  description = "The URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "The ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "The URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.url
}
