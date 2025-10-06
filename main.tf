locals {
  project_name = "${var.environment}-${var.aws_region}-${var.project_suffix}"
}

# Networking Module
module "networking" {
  source = "./modules/networking"

  project_name       = local.project_name
  vpc_cidr_block     = var.vpc_cidr_block
  subnet_cidr_block  = var.subnet_cidr_block
}

# Messaging Module
module "messaging" {
  source = "./modules/messaging"

  sqs_queue_name     = "${local.project_name}-queue"
  sns_topic_name     = "${local.project_name}-topic"
  aws_region         = var.aws_region
  aws_account_id     = var.aws_account_id
  source_bucket_name = "${local.project_name}-source-bucket"
}

# Data Module
module "data" {
  source = "./modules/data"

  source_bucket_name   = "${local.project_name}-source-bucket"
  target_bucket_name   = "${local.project_name}-target-bucket"
  dynamodb_table_name  = "${local.project_name}-metadata-table"
  sns_topic_arn        = module.messaging.sns_topic_arn
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
  api_name            = "${local.project_name}-api"
}

# Compute Module
module "compute" {
  source = "./modules/compute"

  project_name        = local.project_name
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