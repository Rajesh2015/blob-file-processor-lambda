import json
import boto3
import time
from datetime import datetime

firehose_client = boto3.client("firehose")

def process_record(bucket_name,file_key):
    try:
        objWithKey = get_object_with_key(bucket_name,file_key)
        file_content = objWithKey['obj']['Body'].read().decode('utf-8')
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
        raise e

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
        print("---- Debug Print ----")
        print(event)
        task_id = event["tasks"][0]["taskId"]
        s3_bucket_arn = event['tasks'][0]['s3BucketArn']
        bucketName = s3_bucket_arn.split(':::')[-1]
        key = event['tasks'][0]['s3Key']
        print(f"Calling json parser with bucket: {bucketName} and key: {key}")
        
        results = []
        result_code = "Succeeded"
        result_string = ''        
        if bucketName:
           resultList=run_throttled(bucketName, key)
           response = send_messages_to_firehose_with_backoff("demo-json-blob-ingestion-firehose", resultList)
           print(response)
        else:
            raise Exception(f'Bucket name not found in task: {json.dumps("task1")}')
    except Exception as e:
        result_code = "PermanentFailure"
        result_string = str(e)       
        print(e)
    finally:
        results.append(
            {
                "taskId": task_id,
                "resultCode": result_code,
                "resultString": result_string,
            }
        )    
    return {
            "invocationSchemaVersion": event['invocationSchemaVersion'],
            "treatMissingKeysAs": "PermanentFailure",
            'invocationId': event['invocationId'],
            "results": results,
        }

    
def get_object_with_key(bucket, key):
    s3 = boto3.client('s3')
    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        return {'obj': obj, 'key': key}
    except Exception as err:
        print("key not found", key)
        raise err

def run_throttled(bucketName, key):
    time.sleep(1)
    return process_record(bucketName, key)    