#!/bin/bash
yum update -y
yum install -y python3
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py
pip install boto3 pandas pyarrow

cat <<EOF > /tmp/csv_to_parquet.py
import boto3
import pandas as pd
import json
from io import BytesIO
import time
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Initialize clients
sqs = boto3.client('sqs', region_name='${aws_region}')
s3 = boto3.client('s3', region_name='${aws_region}')

# Configuration
QUEUE_URL = '${sqs_queue_url}'
SOURCE_BUCKET = '${source_bucket_name}'
TARGET_BUCKET = '${target_bucket_name}'

def process_message(message):
    try:
        logging.info("Processing message: %s", message.get('MessageId', 'Unknown'))
        
        if 'Body' not in message:
            logging.warning("No body in message")
            return
            
        body = json.loads(message['Body'])
        
        if 'Message' not in body:
            logging.warning("No Message key in body")
            return
            
        message_body = json.loads(body['Message'])
        
        if 'Records' not in message_body:
            logging.warning("No Records in message")
            return
            
        # Process S3 event
        s3_info = message_body['Records'][0]['s3']
        bucket = s3_info['bucket']['name']
        key = s3_info['object']['key']
        
        # Only process CSV files
        if not key.endswith('.csv'):
            logging.info("Skipping non-CSV file: %s", key)
            return
            
        # Download CSV file
        response = s3.get_object(Bucket=bucket, Key=key)
        csv_content = response['Body'].read()
        logging.info("Downloaded file %s from bucket %s", key, bucket)
        
        # Convert to DataFrame
        df = pd.read_csv(BytesIO(csv_content))
        
        # Convert to Parquet
        parquet_buffer = BytesIO()
        df.to_parquet(parquet_buffer, index=False)
        
        # Upload Parquet file
        parquet_buffer.seek(0)
        parquet_key = key.replace('.csv', '.parquet')
        s3.put_object(Bucket=TARGET_BUCKET, Key=parquet_key, Body=parquet_buffer)
        logging.info("Uploaded file %s to bucket %s", parquet_key, TARGET_BUCKET)
        
    except Exception as e:
        logging.error("Error processing message: %s", e)
        raise

def main():
    max_iterations = 10
    iteration = 0
    
    while iteration < max_iterations:
        try:
            response = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=1,
                VisibilityTimeout=60,
                WaitTimeSeconds=20
            )
            
            if 'Messages' in response:
                for message in response['Messages']:
                    process_message(message)
                    # Delete processed message
                    sqs.delete_message(
                        QueueUrl=QUEUE_URL,
                        ReceiptHandle=message['ReceiptHandle']
                    )
            else:
                logging.info("No messages in queue")
                
            iteration += 1
            time.sleep(1)
            
        except Exception as e:
            logging.error("Error in main loop: %s", e)
            with open("/tmp/script.log", "a") as log_file:
                log_file.write(f"Error: {str(e)}\n")

if __name__ == "__main__":
    main()
EOF

python3 /tmp/csv_to_parquet.py