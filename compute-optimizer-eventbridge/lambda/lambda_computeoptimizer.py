import boto3
import json
import os

AccountID = os.environ['AccountId']
SNSTopicArn = os.environ['SNSTopicArn']

def lambda_handler(event, context):
    # Compute Optimizerから推奨事項を取得
    # クライアント作成
    client = boto3.client('compute-optimizer')
    # リクエスト発信
    response = client.get_recommendation_summaries(
        accountIds=[AccountID],
        nextToken="",
        maxResults=10
    )

    # メッセージ生成に必要な情報の抽出
    message = []
    message.append("Compute OptimizerのEC2に関するコスト最適化の推奨事項を通知")

    # メッセージ作成
    for flag in response['recommendationSummaries']:
        if flag['recommendationResourceType'] == "Ec2Instance":
            for flag_summary in flag['summaries']:
                if flag_summary['name'] == "OVER_PROVISIONED":
                    message.append("EC2インスタンス")
                    message.append(f"ステータス: {flag_summary['name']} ,アカウントID: {flag['accountId']} 推定削減額: {flag_summary['value']}")

    # メッセージをSNSに送信
    # 通知を送信するSNSトピックのARNを指定
    sns_client = boto3.client('sns')
    sns_topic_arn = SNSTopicArn
    sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps(message, indent=3, ensure_ascii=False)
    )

