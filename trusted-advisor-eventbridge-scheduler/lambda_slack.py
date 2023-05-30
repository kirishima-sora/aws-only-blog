import urllib3
import json
import os

http = urllib3.PoolManager()
HookURL = os.environ['HookURL']
ChannelName = os.environ['ChannelName']

def lambda_handler(event, context):
    url = HookURL
    msg = {
        "channel": ChannelName,
        "username": "AWS-TA-Notification",
        "text": event["Records"][0]["Sns"]["Message"],
        # "icon_emoji": "",
    }

    encoded_msg = json.dumps(msg).encode("utf-8")
    resp = http.request("POST", url, body=encoded_msg)
    print(
        {
            "message": event["Records"][0]["Sns"]["Message"],
            "status_code": resp.status,
            "response": resp.data,
        }
    )