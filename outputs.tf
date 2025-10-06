output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = module.api_gateway.api_gateway_url
}

output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = module.data.source_bucket_name
}

output "target_bucket_name" {
  description = "Name of the target S3 bucket"
  value       = module.data.target_bucket_name
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = module.data.dynamodb_table_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "glue_database_name" {
  description = "Name of the Glue database"
  value       = aws_glue_catalog_database.data_catalog.name
}