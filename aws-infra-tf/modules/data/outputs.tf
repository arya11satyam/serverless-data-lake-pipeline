output "source_bucket_name" {
  value = aws_s3_bucket.source_bucket.bucket
}

output "target_bucket_name" {
  value = aws_s3_bucket.target_bucket.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.metadata_table.name
}