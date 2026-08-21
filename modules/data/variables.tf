variable "source_bucket_name" {
  description = "Name of the source S3 bucket"
  type        = string
}

variable "target_bucket_name" {
  description = "Name of the target S3 bucket"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic for S3 notifications"
  type        = string
}