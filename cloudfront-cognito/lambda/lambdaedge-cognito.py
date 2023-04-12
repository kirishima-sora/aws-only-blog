import json
import urllib.parse

import boto3
from botocore.exceptions import ClientError

COGNITO_CLIENT_ID = '<your-cognito-client-id>'
COGNITO_USER_POOL_ID = '<your-cognito-user-pool-id>'

def lambda_handler(event, context):
    # Extract the request from the CloudFront event that is sent to Lambda@Edge
    request = event['Records'][0]['cf']['request']
    headers = request['headers']

    # Check if user is authenticated with Cognito
    if 'cookie' in headers:
        for cookie in headers['cookie']:
            if 'CognitoIdentityServiceProvider' in cookie['value']:
                # User is authenticated, allow access to content
                return request

    # User is not authenticated, redirect to login page
    redirect_url = 'https://example.com/login'
    response = {
        'status': '302',
        'statusDescription': 'Found',
        'headers': {
            'location': [{
                'key': 'Location',
                'value': redirect_url,
            }],
            'set-cookie': [{
                'key': 'Set-Cookie',
                'value': 'redirect_url=' + urllib.parse.quote(request['uri'], safe=''),
            }],
        },
    }
    return response
