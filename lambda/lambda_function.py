# Description: This Lambda function reads a JSON file from an S3 bucket and imports its content to a DynamoDB table.
import boto3
import json
import os
import logging
from decimal import Decimal

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb", region_name="eu-west-2")
s3_client = boto3.client("s3")

# Custom JSON encoder for Decimal objects
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return str(obj)
        return super(DecimalEncoder, self).default(obj)

def lambda_handler(event, context):
    table_name = os.environ["DYNAMODB_TABLE_NAME"]
    table = dynamodb.Table(table_name)

    # Iterate over all S3 records
    for record in event.get("Records", []):
        if record["eventName"].startswith("ObjectCreated"):
            bucket_name = record["s3"]["bucket"]["name"]
            object_key = record["s3"]["object"]["key"]

            try:
                # Get the file content from S3
                response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
                file_content = response["Body"].read().decode("utf-8")
                json_content = json.loads(file_content, parse_float=Decimal)

                # Import JSON content to DynamoDB
                for item in json_content:
                    # Convert all Decimal types to string
                    item = json.loads(json.dumps(item, cls=DecimalEncoder))
                    table.put_item(Item=item)
                logger.info(f"Successfully imported {object_key} from {bucket_name} to {table_name}")

            except Exception as e:
                logger.error(f"Error processing {object_key} from {bucket_name}: {e}")

    return {
        "statusCode": 200,
        "body": json.dumps("Processing complete")
    }