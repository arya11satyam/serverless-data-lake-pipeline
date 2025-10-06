variable "sqs_queue_name" {
  description = "Name of the SQS queue"
  type        = string
}

variable "sns_topic_name" {
  description = "Name of the SNS topic"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "source_bucket_name" {
  description = "Name of the source S3 bucket"
  type        = string
}