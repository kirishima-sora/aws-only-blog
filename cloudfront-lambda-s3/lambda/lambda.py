import base64

#自分のIPアドレス
ALLOW_IP = ["X.X.X.X"]

ERROR_RESPONSE_AUTH = {
    'status': '401',
    'statusDescription': 'Unauthorized',
    'body': 'Authentication Failed',
    'headers': {
            'www-authenticate': [
                {
                    'key':'WWW-Authenticate',
                    'value':'IP address fault'
                }
            ]
    }
}

def lambda_handler(event, context):
    request = event['Records'][0]['cf']['request']
    client_ip = request['clientIp']

    if client_ip in ALLOW_IP:
        return request
    else:
        return ERROR_RESPONSE_AUTH
