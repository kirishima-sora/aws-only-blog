import boto3
import json
import os

SNSTopicArn = os.environ['SNSTopicArn']

def lambda_handler(event, context):
    client = boto3.client('support', region_name='us-east-1')
    message = []
    response = client.describe_trusted_advisor_check_result(
        checkId="1iG5NDGVre",
        language='ja'
    )
    check_result = response['result']

    # SNSに通知するメッセージを作成
    message.append("セキュリティグループ — 無制限アクセス")
    for flag in check_result['flaggedResources']:
        if flag["status"] == "error":
            message.append(f"Status: {flag['status']} ,Region: {flag['region']}, SecurtyGroupName: {flag['metadata'][1]}")

    # メッセージをSNSに送信
    sns_client = boto3.client('sns')
    # 通知を送信するSNSトピックのARNを指定
    sns_topic_arn = SNSTopicArn
    sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps(message, indent=3, ensure_ascii=False)
    )