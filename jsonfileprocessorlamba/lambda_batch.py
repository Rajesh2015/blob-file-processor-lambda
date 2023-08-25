import json
import boto3
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
        
        return result
    except Exception as e:
        print(e)
        raise e
