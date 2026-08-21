variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for EC2 instance"
  type        = string
}

variable "sqs_queue_url" {
  description = "SQS queue URL"
  type        = string
}

variable "source_bucket_name" {
  description = "Source S3 bucket name"
  type        = string
}

variable "target_bucket_name" {
  description = "Target S3 bucket name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}