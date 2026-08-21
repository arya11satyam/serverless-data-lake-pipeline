output "api_gateway_url" {
  value = "${aws_api_gateway_stage.api_stage.invoke_url}/upload"
}

output "lambda_function_name" {
  value = aws_lambda_function.file_uploader.function_name
}