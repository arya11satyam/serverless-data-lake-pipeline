output "sns_topic_arn" {
  value = aws_sns_topic.processing_topic.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.processing_queue.url
}