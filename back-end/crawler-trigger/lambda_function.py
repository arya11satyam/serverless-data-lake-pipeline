import os
import logging
import boto3
from botocore.exceptions import ClientError

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

CRAWLER_NAME = os.environ.get('CRAWLER_NAME')

glue = boto3.client('glue')


def lambda_handler(event, context):
    LOGGER.info("New object event: %s", event)

    try:
        glue.start_crawler(Name=CRAWLER_NAME)
        LOGGER.info("Started crawler %s", CRAWLER_NAME)
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code')
        if error_code == 'CrawlerRunningException':
            LOGGER.info("Crawler %s is already running; skipping", CRAWLER_NAME)
        else:
            LOGGER.error("Failed to start crawler %s: %s", CRAWLER_NAME, e)
            raise

    return {'statusCode': 200}
