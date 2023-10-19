variable tidb_public_key {}
variable tidb_private_key {}
variable slack_webhook_url {}
variable slack_channel_name {}

terraform {
    #AWSプロバイダーのバージョン指定
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 5.19.0"
        }
    }
    #tfstateファイルをS3に配置する(配置先のS3は事前に作成済み)
    backend s3 {
        bucket = ""
        region = "ap-northeast-1"
        key    = "tidb-api.tfstate"
    }
}
#AWSプロバイダーの定義
provider aws {
    region = "ap-northeast-1"
}

#============ IAMロール作成 start ============
##EventBridge Sheduler 
data aws_iam_policy_document events_assume_role {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = ["scheduler.amazonaws.com"]
        }
        actions = ["sts:AssumeRole"]
    }
}
resource aws_iam_role iam_for_events {
    name               = "EventBridge_TiDB_API_Role"
    assume_role_policy = data.aws_iam_policy_document.events_assume_role.json
    managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaRole"]
}

##Lambda(TIDB APIの情報取得用)
data aws_iam_policy_document lambda_assume_role {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
        actions = ["sts:AssumeRole"]
    }
}
resource aws_iam_role iam_for_lambda {
    name               = "Lambda_TiDB_API_Role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
    inline_policy {
        name = "my_inline_policy"
        policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
                {
                    Action   = ["sns:Publish"]
                    Effect   = "Allow"
                    Resource = "*"
                },
            ]
        })
    }
}
#============ IAMロール作成 end ============


#============ リソース作成 start ============
##SNS（トピック）
###トピックの作成
resource aws_sns_topic tidb_api_topic {
    name = "TiDB-API-topic"
}
data aws_iam_policy_document sns_assume_role {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
        actions = ["sns:Publish"]
        resources = [aws_sns_topic.tidb_api_topic.arn]
    }
}
resource aws_sns_topic_policy sns_topic_policy {
    arn    = aws_sns_topic.tidb_api_topic.arn
    policy = data.aws_iam_policy_document.sns_assume_role.json
}

##Lambda(tidb-apiからの情報取得用)
data archive_file lambda_tidbapi {
    type        = "zip"
    source_dir = "lambda/tidb-api/dist"
    output_path = "tidb_api.zip"
}
resource aws_lambda_function lambda_tidbapi {
    filename      = "tidb_api.zip"
    function_name = "tidb-api-execution"
    role          = aws_iam_role.iam_for_lambda.arn
    handler       = "tidb_api.lambda_handler"
    source_code_hash = data.archive_file.lambda_tidbapi.output_base64sha256
    runtime = "python3.10"
    timeout = 30
    environment {
        variables = {
            SNSTopicArn = aws_sns_topic.tidb_api_topic.arn
            TiDBPublicKey = var.tidb_public_key
            TiDBPrivateKey = var.tidb_private_key
        }
    }
}

##Lambda(Slack通知用)
data archive_file lambda_slack {
    type        = "zip"
    source_file = "lambda/slack_notification.py"
    output_path = "slack_notification.zip"
}
resource aws_lambda_function lambda_slack {
    filename      = "slack_notification.zip"
    function_name = "tidb-api-to-slack"
    role          = aws_iam_role.iam_for_lambda.arn
    handler       = "slack_notification.lambda_handler"
    source_code_hash = data.archive_file.lambda_slack.output_base64sha256
    runtime = "python3.9"
    #slack通知先
    environment {
        variables = {
            HookURL = var.slack_webhook_url
            ChannelName = var.slack_channel_name
        }
    }
}
resource aws_lambda_permission lambda_slack_permission {
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_slack.function_name
    principal     = "sns.amazonaws.com"
    source_arn    = aws_sns_topic.tidb_api_topic.arn
}

##EventBridge Sheduler
resource aws_scheduler_schedule eventbridge {
    name = "tidb-api-schedule"
    description = "TiDB API Notification"
    flexible_time_window {
        mode = "OFF"
    }
    schedule_expression = "cron(0 8 1,15 * ? *)"
    schedule_expression_timezone = "Asia/Tokyo"
    target {
        arn = aws_lambda_function.lambda_tidbapi.arn
        role_arn = aws_iam_role.iam_for_events.arn
    }
}

##SNS（サブスクリプション）
resource aws_sns_topic_subscription slack_subscription {
    topic_arn = aws_sns_topic.tidb_api_topic.arn
    protocol  = "lambda"
    endpoint  = aws_lambda_function.lambda_slack.arn
}
#============ リソース作成 end ============
