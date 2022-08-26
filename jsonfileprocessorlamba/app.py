import json
import boto3
from datetime import datetime

s3 = boto3.resource('s3')
session = boto3.Session()
firehose_client = session.client("firehose")

def lambda_handler(event, context):
    bucket_name_from_event = event['Records'][0]['s3']['bucket']['name']
    file_key = event['Records'][0]['s3']['object']['key']
    obj = s3.Object(bucket_name_from_event, file_key)
    data = json.load(obj.get()['Body']) 

    list=[]

    for item in data['events']:
        if(int(item['maskLeakage'])>40):
            time=datetime.fromtimestamp(int(item['startTime'])/1000)
            starttime = time.strftime("%m-%d-%Y, %H:%M:%S.%f")
            time=datetime.fromtimestamp(int(item['endTime'])/1000)
            endtime = time.strftime("%m-%d-%Y, %H:%M:%S.%f")
            item['startTime']= starttime
            item['endTime']= endtime
            list.append(item)
    return sendMessagesToFirehose("Test_jsonProcess",data['events'])


def sendMessagesToFirehose(stream_name, stores):
    try:
        records = []

        for store in stores:
            store = dict(store)
            record = {
                "Data": (json.dumps(store)+"\n")
            }
            records.append(record)
        if len(records) > 0:
            response = firehose_client.put_record_batch(
                DeliveryStreamName=stream_name,
                Records=records
            )
            return response
            print(records)
    except Exception as e:
        return e


