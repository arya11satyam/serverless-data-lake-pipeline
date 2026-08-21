# Expected Behavior

This documents what the pipeline is *supposed* to do end-to-end, component by
component, so that when something breaks we have a baseline to diagnose
against instead of re-deriving it from scratch. Update this file whenever the
expected behavior changes intentionally.

## End-to-end flow (fully automated, no manual steps)

```
Postman  --POST /upload?filename=data.csv (binary body)-->  API Gateway
API Gateway --AWS_PROXY-->  Lambda (uploader)
Lambda  --writes-->  S3 source bucket (uploads/data.csv)
Lambda  --writes-->  DynamoDB metadata table (filename, arrival_time)
S3 source bucket  --ObjectCreated event-->  SNS topic
SNS topic  --subscription-->  SQS queue
EC2 instance (systemd service, polls forever)  --consumes-->  SQS queue
EC2 instance  --downloads CSV, converts, uploads-->  S3 target bucket (uploads/data.parquet)
S3 target bucket  --ObjectCreated event (*.parquet)-->  Lambda (crawler-trigger)
Lambda (crawler-trigger)  --glue:StartCrawler-->  Glue crawler
Glue crawler  --catalogs schema-->  Glue Data Catalog database
Athena workgroup  --queries-->  Glue Data Catalog table (backed by the Parquet in S3)
```

No step in this chain should require a human to run an AWS CLI command or
click a console button between "upload a CSV" and "query it in Athena."

## Component-by-component expectations

### API Gateway (`aws-infra-tf/modules/api-gateway/`)
- REST API, single resource `/upload`, single method `POST`.
- `binary_media_types = ["*/*"]` so any request body gets base64-encoded by
  API Gateway before Lambda sees it — clients must send the **raw file
  bytes** (Postman: Body → binary), not base64 themselves.
- Filename comes from the `filename` query string parameter, not the body.
- Stage is `v1`. Output `api_gateway_url` is the real invocable HTTPS URL
  (`https://{id}.execute-api.{region}.amazonaws.com/v1/upload`), not an ARN.

### Lambda: uploader (`back-end/lambda_function.py`)
- Env vars: `USER_BUCKET` (source bucket), `DYNAMO_DB_TABLE` (metadata table).
- Decodes the base64 body, writes it to `s3://{USER_BUCKET}/uploads/{filename}`.
- Writes `{filename, arrival_time}` to DynamoDB (hash key `filename`).
- Returns `200` with CORS header on success, `400` if `filename` (query
  param) or `body` is missing, `500` on `ClientError`.

### S3 source bucket (`aws-infra-tf/modules/data/`)
- KMS-encrypted, versioned.
- Every `ObjectCreated:*` event publishes to the SNS topic (policy scoped to
  this bucket's ARN + account ID).

### SNS → SQS (`aws-infra-tf/modules/messaging/`)
- SNS topic policy allows only `s3.amazonaws.com` from this account/bucket to
  publish.
- SQS queue policy allows only this SNS topic to send messages.
- Straight subscription, no filtering — every source-bucket event reaches the
  queue.

### EC2 processor (`aws-infra-tf/modules/compute/`)
- Runs as a **systemd service** (`csv-processor.service`), not a one-shot
  boot script — `Restart=always`, so it survives crashes and reboots and
  polls SQS **forever** (20s long-poll, loop).
- On each message: parses the SNS-wrapped S3 event, downloads the CSV from
  the source bucket, skips anything not ending in `.csv`, converts with
  pandas/pyarrow, uploads to
  `s3://{target_bucket}/uploads/{same-key-with-.parquet}`, deletes the SQS
  message.
- Errors are logged to `/tmp/script.log` and to the systemd journal
  (`journalctl -u csv-processor`); the loop keeps running afterward.
- AMI is pinned (`ami-051f8a213df8bc089`, AL2023). **Known gap:** this AMI is
  deprecated (since June 2024) — still launches today but may eventually stop
  working and need repinning to a current AL2023 AMI.

### S3 target bucket
- Same encryption/versioning as source.
- `ObjectCreated:*` events with suffix `.parquet` invoke the crawler-trigger
  Lambda directly (no SNS/SQS hop needed here — S3 can invoke Lambda
  directly).

### Lambda: crawler-trigger (`back-end/crawler-trigger/lambda_function.py`)
- Env var: `CRAWLER_NAME`.
- Calls `glue.start_crawler(Name=CRAWLER_NAME)`.
- If the crawler is already running (`CrawlerRunningException`), logs and
  exits cleanly — the in-progress crawl already covers whatever's currently
  in the bucket. **Known edge case:** if a second file lands *while* a crawl
  triggered by a first file is still running, and that second file wasn't
  yet visible to S3 listing when the crawl started, it won't be picked up
  until the *next* trigger. Not an issue for occasional single-file testing.

### Glue (`aws-infra-tf/main.tf`)
- One database (`{project_name}-database`), one crawler pointed at
  `s3://{target_bucket}/uploads/`.
- Crawler role has `AWSGlueServiceRole` + `AmazonS3FullAccess` (broad, but
  functional).
- No `schedule` on the crawler — it only ever runs when the crawler-trigger
  Lambda calls `StartCrawler`. If that Lambda/notification is ever removed,
  the crawler will never run and Athena will have no table.

### Athena (`aws-infra-tf/main.tf`)
- One workgroup (`{project_name}-workgroup`), results written to a dedicated
  `{project_name}-athena-results` S3 bucket (KMS-encrypted).
- Query the table the crawler creates in the Glue database — table name is
  whatever Glue derives from the S3 prefix (check via
  `aws glue get-tables --database-name {project_name}-database` or the Glue
  console) and is **not knowable ahead of time from Terraform**, hence the
  `<table_name_from_crawler>` placeholder in the `athena_sample_query`
  output.

## AWS account requirements

- `aws_account_id` in `aws-infra-tf/variables/dev-modular.tfvars` **must
  match** the account your local AWS CLI credentials resolve to
  (`aws sts get-caller-identity`). If they don't match, SNS/SQS resource
  policies get created with the wrong account ID baked into their ARNs and
  `terraform apply` fails with `MalformedPolicyDocument`.
- IAM identity needs broad permissions (VPC/EC2/S3/DynamoDB/SQS/SNS/Lambda/
  API Gateway/Glue/Athena/IAM role & policy creation). `AdministratorAccess`
  is what's in use; a scoped-down policy is possible but not currently
  defined.
- Region is hardcoded to `us-east-1` in `provider.tf` and the tfvars file —
  your CLI's default region doesn't matter, Terraform's own provider block
  wins.

## Deployment

```bash
cd aws-infra-tf
terraform init
terraform plan  -var-file="variables/dev-modular.tfvars"
terraform apply -var-file="variables/dev-modular.tfvars"
```

Useful outputs after apply:
- `api_gateway_url` — paste into Postman, append nothing (already includes
  `/upload`); add `?filename=...` yourself.
- `athena_workgroup_name`, `athena_results_bucket`, `athena_sample_query`.
- `source_bucket_name`, `target_bucket_name`, `dynamodb_table_name`,
  `glue_database_name`.

## Testing via Postman

- Method: `POST`
- URL: `{api_gateway_url}?filename=data.csv`
- Body: `binary`, select the CSV file directly
- Header: `Content-Type: application/octet-stream` (or let Postman infer it)
- Expect `200` with `"File uploaded successfully to S3 and metadata stored in DynamoDB"`.

## How to debug the pipeline if a step silently doesn't happen

1. **Nothing in DynamoDB / source bucket** → check the uploader Lambda's
   CloudWatch log group; check API Gateway execution logs; confirm the
   request actually hit `/upload` with a `filename` query param.
2. **File sits in source bucket forever, never becomes Parquet** → SSH/SSM
   into the EC2 instance, `systemctl status csv-processor` — should be
   `active (running)`. `journalctl -u csv-processor -f` to watch it consume
   messages. Check the SQS queue depth in the console — if messages are
   stuck, check the queue's redrive/DLQ config (none currently configured —
   a poison message just gets retried until visibility timeout expires
   repeatedly).
3. **Parquet lands in target bucket, but no Glue table** → check the
   crawler-trigger Lambda's CloudWatch logs for `StartCrawler` errors; check
   `aws glue get-crawler --name {project_name}-crawler` for its last run
   status.
4. **Table exists but Athena query fails/returns nothing** → confirm you
   selected the right workgroup in the Athena console before running the
   query; confirm the crawler's most recent run succeeded (not just
   started).

## Known limitations (intentionally deferred, not yet fixed)

- No CORS `OPTIONS` method on `/upload` — browser-based (non-Postman/curl)
  uploads will fail CORS preflight.
- IAM policies throughout use `Resource = "*"` rather than being scoped to
  specific resource ARNs.
- SQS queue has no dead-letter queue — a message that repeatedly fails
  processing just keeps retrying indefinitely.
- EC2 AMI is pinned to a now-deprecated image.

## Fixed issues log

| Issue | Fix |
|---|---|
| `aws_account_id` in tfvars pointed at an expired/wrong account | Updated to the active account (598451516076) |
| `api_gateway_url` output was an unusable ARN, not a URL | Changed to `aws_api_gateway_stage.api_stage.invoke_url` |
| EC2 processor exited permanently after 10 SQS polls | Rewritten as a `systemd` service with `Restart=always`, infinite polling loop |
| No Athena layer existed at all | Added Athena workgroup + dedicated results bucket |
| Glue crawler required a manual `start-crawler` call | Added an S3-event-triggered Lambda that calls `glue:StartCrawler` automatically |
| `t2.micro` not Free Tier eligible on this account (`InvalidParameterCombination`) | Changed default `instance_type` to `t3.micro` (x86_64, matches the pinned AMI's architecture) |
| No way to remotely inspect the EC2 instance (no SSH key, no SSM) | Attached `AmazonSSMManagedInstanceCore` to the EC2 role |
| Missing `filename` query param crashed the uploader Lambda with an unhandled `TypeError` → raw 502 | Added validation returning a clean `400` when `filename` or `body` is missing |
| `get-pip.py` silently failed on AL2023's Python 3.9 (requires >=3.10), so `boto3`/`pandas`/`pyarrow` never installed and `csv-processor.service` crash-looped forever (`ModuleNotFoundError: No module named 'boto3'`) | Switched to `yum install -y python3-pip` (no external bootstrap script needed); also set `user_data_replace_on_change = true` so future script fixes actually redeploy instead of being silently ignored on an already-running instance |
| `terraform destroy` failed with `WorkGroup ... is not empty` once test queries had run in it | Added `force_destroy = true` to the `aws_athena_workgroup` resource |

## Validated

A full `terraform destroy` followed by `terraform apply` (fresh account,
zero manual steps) has been confirmed to bring the entire pipeline up
correctly and automatically end to end: Postman upload → S3/DynamoDB →
SNS/SQS → EC2 conversion → Glue crawl → Athena query, with no SSM/console
intervention required. Note that the API Gateway URL changes on every
redeploy (AWS assigns a new REST API ID) — grab the fresh one via
`terraform output api_gateway_url` and update Postman.

## Teardown

```bash
cd aws-infra-tf
terraform destroy -var-file="variables/dev-modular.tfvars"
```
