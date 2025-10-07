# AWS Data Processing Pipeline

A serverless data processing pipeline that automatically converts CSV files to Parquet format using AWS services including Lambda, S3, SQS, SNS, EC2, and AWS Glue.

## Architecture Overview

This project implements a complete data processing pipeline with the following components:

- **API Gateway**: REST API endpoint for file uploads
- **Lambda Function**: Handles file uploads and metadata storage
- **S3 Buckets**: Source and destination storage for files
- **DynamoDB**: Metadata storage for uploaded files
- **SNS/SQS**: Event-driven messaging for file processing
- **EC2 Instance**: Processes CSV to Parquet conversion
- **AWS Glue**: Data catalog and crawler for processed files

## Project Structure

```
aws-serverless-file-processor
├── aws-infra-tf/           # Terraform infrastructure code
│   ├── modules/            # Modular Terraform components
│   │   ├── api-gateway/    # Lambda + API Gateway module
│   │   ├── compute/        # EC2 processing module
│   │   ├── data/          # S3 + DynamoDB module
│   │   ├── messaging/     # SNS + SQS module
│   │   └── networking/    # VPC + Security Groups module
│   ├── main.tf            # Root module orchestration
│   ├── variables.tf       # Simplified variable definitions
│   ├── outputs.tf         # Clean output definitions
│   ├── provider.tf        # AWS provider configuration
│   └── variables/
│       └── dev-modular.tfvars  # Simplified environment config
├── back-end/
│   └── lambda_function.py  # Lambda function for file uploads
├── test/
    ├── data.csv            # Sample CSV file
    ├── data.parquet        # Sample Parquet file
    └── test.py             # Test script file
```

## Features

- **Serverless File Upload**: REST API endpoint for uploading files
- **Automatic Format Conversion**: CSV files automatically converted to Parquet
- **Event-Driven Processing**: S3 events trigger processing pipeline
- **Metadata Tracking**: File metadata stored in DynamoDB
- **Data Cataloging**: AWS Glue crawler for data discovery
- **Secure Infrastructure**: Encrypted storage and proper IAM roles

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 0.12
- Python 3.8+
- Required Python packages: `boto3`, `pandas`, `pyarrow`

## Deployment

### 1. Infrastructure Deployment

```bash
cd aws-infra-tf
terraform init
terraform plan -var-file="variables/dev-modular.tfvars"
terraform apply -var-file="variables/dev-modular.tfvars"
```

### 2. Configuration

Update the following variables in `variables/dev-modular.tfvars`:
- `aws_account_id`: Your AWS account ID
- `aws_region`: Target AWS region (default: us-east-1)
- `environment`: Environment name (default: dev)
- `project_suffix`: Project identifier (default: data-pipeline)

Resource names are automatically generated using the pattern: `{environment}-{region}-{project_suffix}-{resource_type}`

## Usage

### File Upload

Send a POST request to the API Gateway endpoint:

```bash
curl -X POST \
  https://your-api-id.execute-api.us-east-1.amazonaws.com/v1/upload?filename=data.csv \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @data.csv
```

### Processing Flow

1. File uploaded via API Gateway
2. Lambda function stores file in S3 and metadata in DynamoDB
3. S3 event triggers SNS notification
4. SNS message sent to SQS queue
5. EC2 instance processes SQS messages
6. CSV files converted to Parquet format
7. Processed files stored in destination S3 bucket
8. Glue crawler catalogs the processed data

## AWS Resources Created

- **S3 Buckets**: 2 buckets for source and processed files
- **Lambda Function**: File upload handler
- **API Gateway**: REST API with POST endpoint
- **DynamoDB Table**: Metadata storage
- **SNS Topic**: Event notifications
- **SQS Queue**: Message processing
- **EC2 Instance**: Data processing worker
- **VPC**: Isolated network environment
- **IAM Roles**: Secure service permissions
- **AWS Glue**: Database and crawler for data catalog


## Future Enhancements

- Add support for multiple file formats
- Implement data validation and quality checks
- Add CloudWatch dashboards for monitoring
- Implement dead letter queues for error handling
- Add automated testing pipeline
