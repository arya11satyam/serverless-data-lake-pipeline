import base64
import json
import os
import boto3
from botocore.exceptions import ClientError
import logging
import time

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

SRC_BUCKET = os.environ.get('USER_BUCKET')
SRC_DYNAMO = os.environ.get('DYNAMO_DB_TABLE')

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(SRC_DYNAMO)

def lambda_handler(event, context):
    print(event)

    query_params = event.get('queryStringParameters') or {}
    filename = query_params.get('filename')
    body = event.get('body')

    if not filename or not body:
        return {
            'statusCode': 400,
            'body': json.dumps('Missing required "filename" query parameter or request body'),
            "headers": {
                "Access-Control-Allow-Origin": "*"
            }
        }

    file_content = base64.b64decode(body)
    file_key = 'uploads/' + filename

    try:
        s3.put_object(Body=file_content, Bucket=SRC_BUCKET, Key=file_key)

        arrival_time = time.time()
        table.put_item(
            Item={
                'filename': filename,
                'arrival_time': str(arrival_time),
            }
        )

        return {
            'statusCode': 200,
            'body': json.dumps('File uploaded successfully to S3 and metadata stored in DynamoDB'),
            "headers": {
                "Access-Control-Allow-Origin": "*"
            }
        }
    except ClientError as e:
        return {
            'statusCode': 500,
            'body': json.dumps('Failed to upload file to S3 or write to DynamoDB: {}'.format(str(e)))
        }