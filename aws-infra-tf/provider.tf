terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "serverless-data-lake-pipeline-tf-state-598451516076"
    key            = "aws-infra-tf/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "serverless-data-lake-pipeline-tf-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "serverless-data-lake-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
