# Pipeline Validation Runbook

Validation checklist for a deployment or change to this pipeline — run
it after `terraform apply` (local or CI), a code change to either
Lambda, or a change to the EC2 processor. Each section states what to
check, the command, and the expected result. Known failure modes are
called out where they apply.

Validation statements follow **what was done → why → result**: short,
evidence-based, no interpretation beyond what the evidence shows.

## Prerequisites

```bash
cd aws-infra-tf
terraform output   # confirms state is reachable and populated
```

If this returns nothing or errors, stop here — nothing below will work
against infrastructure Terraform doesn't think exists.

## 1. Installation / Upgrade

**Check:** the apply completed without error and nothing drifted
immediately after.

```bash
terraform plan -var-file="variables/dev-modular.tfvars"
```

**Expected:** `No changes. Your infrastructure matches the
configuration.` A non-empty plan right after a supposedly-complete apply
means something didn't finish.

> Verified `terraform plan` reports no changes after apply. Infrastructure
> matches the committed configuration.

## 2. Service Health

**EC2 processor:**
```bash
INSTANCE_ID=$(terraform state show module.compute.aws_instance.processor | grep -m1 '"id"' | awk -F'"' '{print $4}')
aws ssm send-command --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status csv-processor --no-pager"]' \
  --region us-east-1
```
**Expected:** `Active: active (running)`. A crash-looping service shows
`activating (auto-restart)` with a climbing restart counter — check
`journalctl -u csv-processor` for the actual error.

**Lambda functions:**
```bash
aws lambda get-function --function-name dev-us-east-1-data-pipeline-uploader --query "Configuration.State"
aws lambda get-function --function-name dev-us-east-1-data-pipeline-crawler-trigger --query "Configuration.State"
```
**Expected:** `"Active"` for both.

**API Gateway:**
```bash
curl -s -o /dev/null -w "%{http_code}\n" "$(terraform output -raw api_gateway_url)"
```
**Expected:** any response code at all (405 is normal — GET isn't
supported here — the point is confirming the endpoint is live and
routed, not DNS-dead or 5xx from a broken deployment).

## 3. Configuration

**Check:** the values Terraform actually wrote match intent, not just
that the resource exists.

```bash
# Env vars point at the current bucket/table names, not a prior deploy's
aws lambda get-function-configuration --function-name dev-us-east-1-data-pipeline-uploader \
  --query "Environment.Variables"

# Instance type hasn't silently drifted off the Free Tier eligible default
terraform state show module.compute.aws_instance.processor | grep instance_type
```

> Verified the uploader Lambda's `USER_BUCKET`/`DYNAMO_DB_TABLE` environment
> variables match the source bucket and metadata table created by this
> apply. No stale references to a prior deployment's resource names.

## 4. Logs

```bash
aws logs tail /aws/lambda/dev-us-east-1-data-pipeline-uploader --region us-east-1 --since 15m
aws logs tail /aws/lambda/dev-us-east-1-data-pipeline-crawler-trigger --region us-east-1 --since 15m
```

**Expected:** no `[ERROR]` lines from a normal request. Empty output on
a fresh deploy with no traffic yet is normal, not a sign of broken
logging — confirm the log group itself exists if in doubt:
`aws logs describe-log-groups --log-group-name-prefix /aws/lambda/dev-us-east-1-data-pipeline`.

## 5. Data Flow

The check that actually proves the pipeline works end to end, not just
that each piece exists in isolation. Upload a real file and trace it
through every hop.

```bash
NAME=validation-$(date +%s).csv
curl -X POST "$(terraform output -raw api_gateway_url)?filename=$NAME" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @test/data.csv

sleep 5
aws dynamodb get-item --table-name "$(terraform output -raw dynamodb_table_name)" \
  --key "{\"filename\":{\"S\":\"$NAME\"}}"
aws s3 ls "s3://$(terraform output -raw source_bucket_name)/uploads/$NAME"

sleep 60   # EC2 worker needs time to consume the SQS message and convert
aws s3 ls "s3://$(terraform output -raw target_bucket_name)/uploads/${NAME%.csv}.parquet"
```

**Expected:** the DynamoDB item, the source object, and the converted
Parquet object all exist within about a minute of upload. If the chain
breaks partway (e.g. source has the file, target doesn't), that pinpoints
the failing hop — check SQS queue depth and EC2 service health next.

> Uploaded a test file and confirmed it was written to the source bucket,
> recorded in DynamoDB, converted to Parquet, and written to the target
> bucket — the full data-flow path completed within 60 seconds of upload.

## 6. Metrics

No dashboard yet (tracked in `README.md`'s roadmap) — check the raw
numbers directly:

```bash
QUEUE_URL=$(aws sqs get-queue-url --queue-name dev-us-east-1-data-pipeline-queue --region us-east-1 --query QueueUrl --output text)
aws sqs get-queue-attributes --queue-url "$QUEUE_URL" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible

START=$(python3 -c "import datetime; print((datetime.datetime.utcnow()-datetime.timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%S'))")
END=$(python3 -c "import datetime; print(datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S'))")
aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Errors \
  --dimensions Name=FunctionName,Value=dev-us-east-1-data-pipeline-uploader \
  --start-time "$START" --end-time "$END" --period 3600 --statistics Sum --region us-east-1
```

**Expected:** queue depth at 0 outside active processing; Lambda error
sum at 0 under normal operation.

## 7. Functional Behavior

Full happy path through the actual query engine, not just confirming
files landed:

```bash
aws glue get-tables --database-name "$(terraform output -raw glue_database_name)" --query "TableList[].Name"
terraform output -raw athena_workgroup_name
```

Select that workgroup in the Athena console, then:

```sql
SELECT * FROM "<database>"."<table_matching_your_upload>" LIMIT 10;
```

**Expected:** rows matching the uploaded CSV's content. Zero rows with
no error is a known failure mode — see Regression #3 before assuming
the data is missing.

## 8. Regression / Negative Scenarios

Failure modes this pipeline has actually hit — worth re-checking after
any change to the areas involved.

1. **Missing `filename` query param** should return a clean `400`, not
   a raw `502`:
   ```bash
   curl -i -X POST "$(terraform output -raw api_gateway_url)" --data-binary @test/data.csv
   ```
   Expected: `400`, JSON body naming the missing parameter.

2. **EC2 processor survives a reboot** — `Restart=always` at the
   systemd level should self-heal without intervention:
   ```bash
   aws ec2 reboot-instances --instance-ids "$INSTANCE_ID"
   # wait ~2 min, then re-run the Service Health check above
   ```
   Expected: `csv-processor.service` is `active (running)` again on its own.

3. **Two files with different schemas uploaded close together** — check
   the resulting Glue table's location:
   ```bash
   aws glue get-table --database-name "$(terraform output -raw glue_database_name)" \
     --name <table_name> --query "Table.StorageDescriptor.Location"
   ```
   A location ending in a specific filename (not a trailing `/`) returns
   zero rows from Athena with no error. This happens when the crawler
   can't group files under one schema into a shared-folder table — see
   the "Honest Status" section in `README.md`.

4. **CI apply after a merge** actually pauses for approval at the
   `production` environment rather than running unattended. If it
   doesn't pause, the environment's required-reviewer setting has been
   lost or misconfigured — fix before merging anything else.
