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

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup to run queries in"
  value       = aws_athena_workgroup.data_pipeline_wg.name
}

output "athena_results_bucket" {
  description = "S3 bucket holding Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_sample_query" {
  description = "Run this in the Athena console (select the workgroup above first) once the Glue crawler has run at least once"
  value       = "SELECT * FROM \"${aws_glue_catalog_database.data_catalog.name}\".\"<table_name_from_crawler>\" LIMIT 10;"
}