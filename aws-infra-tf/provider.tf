terraform {
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
}
