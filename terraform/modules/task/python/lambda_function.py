import json
import boto3

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket_name = 'leumi-shay-task'
    
    data = {"example_key": "example_value"}
    
    s3.put_object(
        Bucket=bucket_name,
        Key='example_key.json',
        Body=json.dumps(data),
        ContentType='application/json'
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Data saved to S3 successfully!')
    }
