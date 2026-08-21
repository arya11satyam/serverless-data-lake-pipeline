variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
}

variable "lambda_source_dir" {
  description = "Directory containing Lambda source code"
  type        = string
}

variable "source_bucket_name" {
  description = "Name of the source S3 bucket"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
}