import json
import boto3
import time
from datetime import datetime

firehose_client = boto3.client("firehose")

def process_record(record):
    try:
        bucket_name = record['s3']['bucket']['name']
        file_key = record['s3']['object']['key']

        s3 = boto3.resource('s3')
        obj = s3.Object(bucket_name, file_key)
        file_content = obj.get()['Body'].read().decode('utf-8')
        json_content = json.loads(file_content)

        result_list = []

        for item in json_content['events']:
            if int(item['maskLeakage']) > 40:
                start_time = datetime.fromtimestamp(int(item['startTime']) / 1000)
                end_time = datetime.fromtimestamp(int(item['endTime']) / 1000)
                item['startTime'] = start_time.strftime("%m-%d-%Y, %H:%M:%S.%f")
                item['endTime'] = end_time.strftime("%m-%d-%Y, %H:%M:%S.%f")
                result_list.append(item)
        
        return result_list

    except Exception as e:
        print(e)
        return []

def send_messages_to_firehose_with_backoff(stream_name, records):
    max_retries = 5
    base_delay = 0.1  # Initial delay in seconds, adjust as needed
    retries = 0
    
    while retries < max_retries:
        try:
            response = firehose_client.put_record_batch(
                DeliveryStreamName=stream_name,
                Records=[
                    {"Data": json.dumps(record) + "\n"} for record in records
                ]
            )
            return response
        except Exception as e:
            print(e)
            retries += 1
            delay = base_delay * (2 ** retries)  # Exponential backoff formula
            print(f"Retrying in {delay} seconds...")
            time.sleep(delay)
    
    print(f"Max retries reached. Failed to send messages to {stream_name}")
    return None

def lambda_handler(event, context):
    try:
        output_messages = []

        for record in event['invocation']['inputMessages']:
            payload = json.loads(record['body'])
            result_list = process_record(payload)
            if result_list:
                output_messages.extend(result_list)
        
        result_string = json.dumps([msg["name"] for msg in output_messages])
        
        result = {
            "invocationSchemaVersion": "1.0",
            "treatMissingKeysAs": "PermanentFailure",
            "invocationId": event['invocationId'],
            "results": [
                {
                    "taskId": "task1",
                    "resultCode": "Succeeded",
                    "resultString": result_string
                }
            ]
        }
        
        if output_messages:
            response = send_messages_to_firehose_with_backoff("demo-json-blob-ingestion-firehose", output_messages)
            print(response)
        
        return result
    except Exception as e:
        print(e)
        raise e
