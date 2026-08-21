# Resolves the caller's AWS account ID dynamically instead of requiring it
# as a variable, so nothing account-specific needs to be hardcoded or
# committed to version control.
data "aws_caller_identity" "current" {}

# SQS Queue
resource "aws_sqs_queue" "processing_queue" {
  name = var.sqs_queue_name

  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "sns.amazonaws.com"
      }
      Action = [
        "sqs:SendMessage",
        "kms:Encrypt",
        "kms:Decrypt"
      ]
      Resource = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.sqs_queue_name}"
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sns_topic.processing_topic.arn
        }
      }
    }]
  })
}

# SNS Topic
resource "aws_sns_topic" "processing_topic" {
  name = var.sns_topic_name

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "s3-notification-policy"
    Statement = [{
      Sid    = "AllowS3Publish"
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.sns_topic_name}"
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:s3:::${var.source_bucket_name}"
        }
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

# SNS to SQS Subscription
resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.processing_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.processing_queue.arn
}