import boto3
import json
import os
import requests
from requests.auth import HTTPDigestAuth
import datetime
from dateutil.relativedelta import relativedelta
from zoneinfo import ZoneInfo

SNSTopicArn = os.environ['SNSTopicArn']
TiDBAPIPublicKey = os.environ['TiDBPublicKey']
TiDBAPIPrivateKey = os.environ['TiDBPrivateKey']

def lambda_handler(event, context):
    public_key = TiDBAPIPublicKey
    private_key = TiDBAPIPrivateKey
    # 実行する年月を取得
    date_source = datetime.datetime.now(ZoneInfo("Asia/Tokyo")).date()
    if date_source.day == 1:
        date_source = date_source - relativedelta(months=1)
    date = str(date_source)
    year_month = date[0:7]
    r_get = requests.get('https://billing.tidbapi.com/v1beta1/bills/' + year_month, auth=HTTPDigestAuth(public_key, private_key))
    billing_source = r_get.json()
    print(billing_source)

    message = []
    message.append("TiDB Cloudの利用料を通知します。")
    message.append(f"利用年月: {billing_source['overview']['billedMonth']} ,利用料: {billing_source['overview']['runningTotal']}")
    if billing_source['overview']['runningTotal'] != "0":
        for project in billing_source['summaryByProject']['projects']:
            message.append(f"プロジェクト名： {project['projectName']} ,プロジェクト利用料: {project['runningTotal']}")
    print(message)

    # メッセージをSNSに送信
    # 通知を送信するSNSトピックのARNを指定
    sns_client = boto3.client('sns')
    sns_topic_arn = SNSTopicArn
    sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps(message, indent=3, ensure_ascii=False)
    )
