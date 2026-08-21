# AWS Serverless File Processor

A serverless pipeline that converts uploaded CSV files to Parquet and makes
them queryable via Athena, with no manual steps between upload and query.
Built on Lambda, S3, DynamoDB, SNS/SQS, EC2, and AWS Glue, all provisioned
with Terraform.

## Architecture

```
Client  --POST /upload?filename=data.csv-->  API Gateway
API Gateway  --AWS_PROXY-->  Lambda (uploader)
Lambda  -->  S3 (source bucket)
Lambda  -->  DynamoDB (upload metadata)
S3 source bucket  --ObjectCreated-->  SNS  -->  SQS
EC2 (systemd service, long-polling)  --consumes-->  SQS
EC2  --CSV to Parquet-->  S3 (target bucket)
S3 target bucket  --ObjectCreated-->  Lambda (crawler-trigger)
Lambda (crawler-trigger)  -->  Glue Crawler  -->  Glue Data Catalog
Athena  --queries-->  Glue Data Catalog table
```

Every arrow above fires automatically. Uploading a file is the only manual
action; everything from S3 storage through to a queryable Athena table
happens on its own.

## Project Structure

```
.
├── aws-infra-tf/                  # Terraform infrastructure
│   ├── main.tf                    # Root module: Glue, Athena, crawler-trigger Lambda
│   ├── outputs.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── variables/dev-modular.tfvars
│   └── modules/
│       ├── networking/            # VPC, subnet, security group
│       ├── messaging/             # SNS topic, SQS queue
│       ├── data/                  # S3 buckets, DynamoDB table
│       ├── api-gateway/           # API Gateway + uploader Lambda
│       └── compute/               # EC2 processor + its boot script
├── back-end/
│   ├── lambda_function.py         # Upload handler (S3 + DynamoDB write)
│   └── crawler-trigger/
│       └── lambda_function.py     # Starts the Glue crawler on new Parquet files
└── test/
    ├── data.csv                   # Sample input
    ├── data.parquet               # Sample output
    └── test.py                    # Local Parquet read check
```

## Prerequisites

- AWS CLI configured with credentials for the target account
- Terraform >= 1.5
- (Optional, for `test/test.py`) Python 3.8+ with `pandas` and `pyarrow`

No AWS account ID needs to be configured anywhere — Terraform resolves it
at apply time from whichever credentials are active
(`data.aws_caller_identity`), so the same config works unmodified against
any account.

## Deployment

```bash
cd aws-infra-tf
terraform init
terraform plan  -var-file="variables/dev-modular.tfvars"
terraform apply -var-file="variables/dev-modular.tfvars"
```

Resource names follow the pattern `{environment}-{region}-{project_suffix}-{resource_type}`,
configurable in `variables/dev-modular.tfvars`. The EC2 processor takes a
few minutes after `apply` to finish its boot-time setup before it starts
consuming from SQS.

Useful outputs after apply:

```bash
terraform output api_gateway_url        # POST endpoint
terraform output athena_workgroup_name  # select this in the Athena console
terraform output glue_database_name
```

## Usage

Upload a file:

```bash
curl -X POST \
  "$(terraform output -raw api_gateway_url)?filename=data.csv" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @test/data.csv
```

Once converted and cataloged (usually well under a minute after upload),
query it in Athena — select the workgroup from `athena_workgroup_name`
first, then:

```sql
SELECT * FROM "<glue_database_name>"."uploads" LIMIT 10;
```

## AWS Resources Created

| Category | Resources |
|---|---|
| Ingress | API Gateway REST API, uploader Lambda |
| Storage | 2 S3 buckets (source, target), DynamoDB table |
| Messaging | SNS topic, SQS queue |
| Processing | EC2 instance running a supervised `systemd` service |
| Cataloging | Glue database, Glue crawler, crawler-trigger Lambda |
| Querying | Athena workgroup, Athena results bucket |
| Networking | VPC, subnet, internet gateway, route table, security group |
| IAM | One role per service (Lambda x2, EC2, Glue) |

## Security

- S3 buckets and the DynamoDB table use server-side encryption (KMS)
- Each compute component (uploader Lambda, crawler-trigger Lambda, EC2
  processor) has its own IAM role, scoped to its own service — but action
  permissions within those roles are currently `Resource: "*"` rather than
  scoped to specific ARNs (see Known Limitations)
- No AWS account ID or other account-specific values are hardcoded or
  committed to this repo

## Testing

```bash
cd test
python test.py
```

Reads `data.parquet` and prints it as a DataFrame — a quick sanity check
that a Parquet file produced by the pipeline is well-formed.

## Cleanup

```bash
cd aws-infra-tf
terraform destroy -var-file="variables/dev-modular.tfvars"
```

## Known Limitations

- IAM policies use `Resource: "*"` rather than being scoped to specific ARNs
- No CORS `OPTIONS` method on `/upload` — browser-based uploads (as opposed
  to curl/Postman/server-to-server) will fail CORS preflight
- SQS has no dead-letter queue; a message that repeatedly fails processing
  retries indefinitely rather than being parked for inspection
- Terraform state is local only — no remote backend/locking configured yet
- The EC2 processor is a single instance with no auto-scaling or
  multi-AZ redundancy

## Roadmap

- Remote Terraform state (S3 + DynamoDB lock table)
- Scope IAM policies down to least privilege
- CORS support for browser-based uploads
- SQS dead-letter queue
- CI pipeline for `terraform validate`/`plan` on PRs
