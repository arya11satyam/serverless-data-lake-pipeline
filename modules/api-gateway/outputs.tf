output "api_gateway_url" {
  value = "${aws_api_gateway_rest_api.upload_api.execution_arn}/v1/upload"
}

output "lambda_function_name" {
  value = aws_lambda_function.file_uploader.function_name
}