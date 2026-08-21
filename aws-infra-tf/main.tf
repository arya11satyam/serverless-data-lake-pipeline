locals {
  project_name = "${var.environment}-${var.aws_region}-${var.project_suffix}"
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  project_name      = local.project_name
  vpc_cidr_block    = var.vpc_cidr_block
  subnet_cidr_block = var.subnet_cidr_block
}

# Messaging Module
module "messaging" {
  source = "./modules/messaging"

  sqs_queue_name     = "${local.project_name}-queue"
  sns_topic_name     = "${local.project_name}-topic"
  aws_region         = var.aws_region
  source_bucket_name = "${local.project_name}-source-bucket"
}

# Data Module
module "data" {
  source = "./modules/data"

  source_bucket_name  = "${local.project_name}-source-bucket"
  target_bucket_name  = "${local.project_name}-target-bucket"
  dynamodb_table_name = "${local.project_name}-metadata-table"
  sns_topic_arn       = module.messaging.sns_topic_arn
}

# API Gateway Module
module "api_gateway" {
  source = "./modules/api-gateway"

  project_name         = local.project_name
  lambda_function_name = "${local.project_name}-uploader"
  lambda_runtime       = var.lambda_runtime
  lambda_source_dir    = var.lambda_source_dir
  source_bucket_name   = module.data.source_bucket_name
  dynamodb_table_name  = module.data.dynamodb_table_name
  api_name             = "${local.project_name}-api"
}

# Compute Module
module "compute" {
  source = "./modules/compute"

  project_name       = local.project_name
  ami_id             = var.ami_id
  instance_type      = var.instance_type
  subnet_id          = module.networking.subnet_id
  security_group_id  = module.networking.security_group_id
  sqs_queue_url      = module.messaging.sqs_queue_url
  source_bucket_name = module.data.source_bucket_name
  target_bucket_name = module.data.target_bucket_name
  aws_region         = var.aws_region
}

# AWS Glue Resources
resource "aws_iam_role" "glue_crawler_role" {
  name = "${local.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy_attachment" "glue_service_role" {
  name       = "${local.project_name}-glue-service-role"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  roles      = [aws_iam_role.glue_crawler_role.name]
}

resource "aws_iam_policy_attachment" "glue_s3_access" {
  name       = "${local.project_name}-glue-s3-access"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  roles      = [aws_iam_role.glue_crawler_role.name]
}

resource "aws_glue_catalog_database" "data_catalog" {
  name = "${local.project_name}-database"
}

resource "aws_glue_crawler" "data_crawler" {
  name          = "${local.project_name}-crawler"
  database_name = aws_glue_catalog_database.data_catalog.name
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target {
    path = "s3://${module.data.target_bucket_name}/uploads/"
  }

  depends_on = [aws_glue_catalog_database.data_catalog]
}

# Crawler Trigger Lambda - starts the Glue crawler when a new Parquet file lands
resource "aws_iam_role" "crawler_trigger_role" {
  name = "${local.project_name}-crawler-trigger-role"

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

resource "aws_iam_policy" "crawler_trigger_policy" {
  name = "${local.project_name}-crawler-trigger-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["glue:StartCrawler"]
      Resource = aws_glue_crawler.data_crawler.arn
    }]
  })
}

resource "aws_iam_policy_attachment" "crawler_trigger_policy_attachment" {
  name       = "${local.project_name}-crawler-trigger-policy-attachment"
  policy_arn = aws_iam_policy.crawler_trigger_policy.arn
  roles      = [aws_iam_role.crawler_trigger_role.name]
}

data "archive_file" "crawler_trigger_zip" {
  source_dir  = "../back-end/crawler-trigger/"
  output_path = "${path.module}/crawler_trigger_lambda.zip"
  type        = "zip"
}

resource "aws_lambda_function" "crawler_trigger" {
  filename         = data.archive_file.crawler_trigger_zip.output_path
  function_name    = "${local.project_name}-crawler-trigger"
  role             = aws_iam_role.crawler_trigger_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = 20
  memory_size      = 128
  source_code_hash = data.archive_file.crawler_trigger_zip.output_base64sha256

  environment {
    variables = {
      CRAWLER_NAME = aws_glue_crawler.data_crawler.name
    }
  }
}

resource "aws_lambda_permission" "target_bucket_invoke" {
  statement_id  = "AllowExecutionFromS3TargetBucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crawler_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${module.data.target_bucket_name}"
}

resource "aws_s3_bucket_notification" "target_bucket_notification" {
  bucket = module.data.target_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.crawler_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".parquet"
  }

  depends_on = [aws_lambda_permission.target_bucket_invoke]
}

# Athena Resources
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${local.project_name}-athena-results"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results_encryption" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = "alias/aws/s3"
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_athena_workgroup" "data_pipeline_wg" {
  name          = "${local.project_name}-workgroup"
  force_destroy = true # allow destroy even with existing query history

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
    }
  }
}