# AWS Serverless File Processor

Upload a CSV, get back a queryable table. That's the whole idea: drop a
file through an API, and it's automatically converted to Parquet,
cataloged, and ready to query in Athena — no manual steps in between.

Built with Lambda, S3, DynamoDB, SNS/SQS, EC2, and Glue, all provisioned
through Terraform.

## Architecture

```mermaid
flowchart TD
    Client(["Client<br/>POST /upload"]):::client --> APIGW["API Gateway<br/>REST endpoint"]:::compute
    APIGW --> Lambda["Lambda<br/>file + metadata"]:::compute
    Lambda --> Dynamo[("DynamoDB<br/>file metadata")]:::storage
    Lambda --> S3Src[("S3 source<br/>raw CSV")]:::storage
    S3Src --> SNS{{"SNS<br/>fan-out on upload"}}:::messaging
    SNS --> SQS{{"SQS<br/>buffers, retries"}}:::messaging
    SQS --> EC2["EC2 worker<br/>CSV to Parquet"]:::compute
    EC2 --> S3Dst[("S3 processed<br/>Parquet output")]:::storage
    S3Dst --> Glue["Glue crawler<br/>catalogs output"]:::compute
    Glue --> Athena["Athena<br/>SQL queries"]:::compute

    classDef client fill:#ece7da,stroke:#8a8371,color:#2b2718
    classDef compute fill:#e2ddfb,stroke:#7266d6,color:#2f2a5c
    classDef storage fill:#d7f0e2,stroke:#3f9967,color:#153826
    classDef messaging fill:#fbe1d3,stroke:#c96a3d,color:#5c2a10
```

Everything past the initial upload runs on its own — S3 events fan out
through SNS/SQS to trigger the conversion, and another S3 event on the
output bucket triggers cataloging. Nothing in the middle needs a human.

## Project Structure

```
.
├── aws-infra-tf/               Terraform infrastructure
│   ├── main.tf                 Root module: Glue, Athena, crawler-trigger Lambda
│   └── modules/
│       ├── networking/         VPC, subnet, security group
│       ├── messaging/          SNS topic, SQS queue
│       ├── data/                S3 buckets, DynamoDB table
│       ├── api-gateway/        API Gateway + uploader Lambda
│       └── compute/            EC2 processor + boot script
├── back-end/
│   ├── lambda_function.py             Upload handler
│   └── crawler-trigger/lambda_function.py   Starts the Glue crawler
└── test/                       Sample CSV/Parquet + a quick read check
```

## Prerequisites

- AWS CLI configured with credentials for the target account
- Terraform >= 1.5
- Python 3.8+ with `pandas`/`pyarrow`, only if you want to run `test/test.py`

There's no AWS account ID to configure anywhere — Terraform picks it up
from whatever credentials are active, so this deploys unmodified to any
account.

## Deploy

```bash
cd aws-infra-tf
terraform init
terraform apply -var-file="variables/dev-modular.tfvars"
```

Give the EC2 processor a few minutes after `apply` finishes — it's still
installing packages before it starts consuming from SQS.

```bash
terraform output api_gateway_url        # your POST endpoint
terraform output athena_workgroup_name  # select this in the Athena console
terraform output glue_database_name
```

## Usage

```bash
curl -X POST \
  "$(terraform output -raw api_gateway_url)?filename=data.csv" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @test/data.csv
```

Within about a minute, it's queryable — select the workgroup from
`athena_workgroup_name` in the Athena console, then:

```sql
SELECT * FROM "<glue_database_name>"."uploads" LIMIT 10;
```

## What Gets Created

| Category | Resources |
|---|---|
| Ingress | API Gateway, uploader Lambda |
| Storage | 2 S3 buckets, DynamoDB table |
| Messaging | SNS topic, SQS queue |
| Processing | EC2 instance running a `systemd` service |
| Cataloging | Glue database + crawler, crawler-trigger Lambda |
| Querying | Athena workgroup + results bucket |
| Networking | VPC, subnet, internet gateway, route table, security group |

## Security

S3 and DynamoDB are encrypted at rest. Each Lambda and the EC2 instance
get their own IAM role, scoped to their own service — though the
permissions within those roles are still `Resource: "*"` rather than
locked to specific ARNs, and nothing account-specific is hardcoded
anywhere in this repo.

## Testing

```bash
cd test
python test.py
```

Reads `data.parquet` back into a DataFrame — a quick check that the
pipeline's output is a well-formed Parquet file.

## Cleanup

```bash
cd aws-infra-tf
terraform destroy -var-file="variables/dev-modular.tfvars"
```

## Known Limitations

- IAM policies are broader than they need to be (`Resource: "*"`)
- No CORS support, so uploads only work from curl/Postman/server-to-server, not a browser
- No dead-letter queue — a message that keeps failing just retries forever
- Terraform state is local, no remote backend yet
- Single EC2 instance, no redundancy

## Roadmap

- Remote state (S3 + DynamoDB lock table)
- Least-privilege IAM policies
- CORS support
- SQS dead-letter queue
- CI for `terraform validate`/`plan` on PRs
