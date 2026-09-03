# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Lambda IAM Policy
resource "aws_iam_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "dynamodb:PutItem"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda Function
data "archive_file" "lambda_zip" {
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/lambda_function.zip"
  type        = "zip"
}

resource "aws_lambda_function" "file_uploader" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = 20
  memory_size      = 128
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      USER_BUCKET     = var.source_bucket_name
      DYNAMO_DB_TABLE = var.dynamodb_table_name
    }
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "upload_api" {
  name = var.api_name
  # Scoped to exactly what clients send, not a "*/*" wildcard - that
  # wildcard applies API-wide and silently breaks MOCK integrations
  # elsewhere on the API (e.g. the OPTIONS CORS preflight below), which
  # is not obvious from either config in isolation.
  binary_media_types = ["application/octet-stream"]
}

resource "aws_api_gateway_resource" "upload_resource" {
  parent_id   = aws_api_gateway_rest_api.upload_api.root_resource_id
  path_part   = "upload"
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
}

resource "aws_api_gateway_method" "upload_method" {
  authorization = "NONE"
  http_method   = "POST"
  resource_id   = aws_api_gateway_resource.upload_resource.id
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
}

resource "aws_api_gateway_integration" "upload_integration" {
  http_method             = aws_api_gateway_method.upload_method.http_method
  resource_id             = aws_api_gateway_resource.upload_resource.id
  rest_api_id             = aws_api_gateway_rest_api.upload_api.id
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.file_uploader.invoke_arn
}

resource "aws_api_gateway_method_response" "upload_method_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# CORS preflight - lets a browser page (not just curl/Postman) call /upload
resource "aws_api_gateway_method" "upload_options" {
  authorization = "NONE"
  http_method   = "OPTIONS"
  resource_id   = aws_api_gateway_resource.upload_resource.id
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
}

resource "aws_api_gateway_integration" "upload_options_integration" {
  http_method = aws_api_gateway_method.upload_options.http_method
  resource_id = aws_api_gateway_resource.upload_resource.id
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "upload_options_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

resource "aws_api_gateway_integration_response" "upload_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_options.http_method
  status_code = aws_api_gateway_method_response.upload_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
  }
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.upload_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.upload_api.binary_media_types,
      aws_api_gateway_resource.upload_resource.id,
      aws_api_gateway_method.upload_method.id,
      aws_api_gateway_integration.upload_integration.id,
      aws_api_gateway_method.upload_options.id,
      aws_api_gateway_integration.upload_options_integration.id,
      aws_api_gateway_integration_response.upload_options_integration_response.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.upload_integration,
    aws_api_gateway_integration.upload_options_integration,
  ]
}

resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.upload_api.id
  stage_name    = "v1"
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_uploader.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.upload_api.execution_arn}/*/*"
}