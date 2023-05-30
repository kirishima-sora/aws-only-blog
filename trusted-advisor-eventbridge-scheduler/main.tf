terraform {
    #AWSプロバイダーのバージョン指定
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 4.51.0"
        }
    }
}
#AWSプロバイダーの定義
provider aws {
    # Trusted Advisorのチェック結果はバージニア北部から取得する必要がある
    region = "us-east-1"
}


#============ IAMロール作成 ============
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
    name               = "EventBridge_TrustedAdvisor_Notification_Role"
    assume_role_policy = data.aws_iam_policy_document.events_assume_role.json
    managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaRole"]
}

##Lambda(Trusted Advisorからの情報取得用)
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
    name               = "Lambda_TrustedAdvisor_Notification_Role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
    inline_policy {
        name = "my_inline_policy"
        policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
                {
                    Action   = ["support:DescribeTrustedAdvisorCheckResult"]
                    Effect   = "Allow"
                    Resource = "*"
                },
            ]
        })
    }
    managed_policy_arns = [
        "arn:aws:iam::aws:policy/AWSTrustedAdvisorPriorityReadOnlyAccess",
        "arn:aws:iam::aws:policy/service-role/AWSIoTDeviceDefenderPublishFindingsToSNSMitigationAction"
    ]
}


#============ リソース作成 ============
##SNS（トピック）
###トピックの作成
resource aws_sns_topic trusted_advisor_topic {
    name = "TrustedAdvisor-notification-topic"
}

##Lambda(Trusted Advisorからの情報取得用)
data archive_file lambda_trustedadvisor {
    type        = "zip"
    source_file = "lambda/lambda_trustedadvisor.py"
    output_path = "lambda_trustedadvisor.zip"
}
resource aws_lambda_function lambda_trustedadvisor {
    filename      = "lambda_trustedadvisor.zip"
    function_name = "trusted-advisor-detection"
    role          = aws_iam_role.iam_for_lambda.arn
    handler       = "lambda_trustedadvisor.lambda_handler"
    source_code_hash = data.archive_file.lambda_trustedadvisor.output_base64sha256
    runtime = "python3.9"
    environment {
        variables = {
            SNSTopicArn = aws_sns_topic.trusted_advisor_topic.arn
        }
    }
}

##Lambda(Slack通知用)
data archive_file lambda_slack {
    type        = "zip"
    source_file = "lambda/lambda_slack.py"
    output_path = "lambda_slack.zip"
}
resource aws_lambda_function lambda_slack {
    filename      = "lambda_slack.zip"
    function_name = "trusted-advisor-notification-to-slack"
    role          = aws_iam_role.iam_for_lambda.arn
    handler       = "lambda_slack.lambda_handler"
    source_code_hash = data.archive_file.lambda_slack.output_base64sha256
    runtime = "python3.9"
    environment {
        variables = {
            ChannelName = "<Slackのチャンネル名>",
            HookURL = "<HookURL>"
        }
    }
}
resource aws_lambda_permission lambda_slack_permission {
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_slack.function_name
    principal     = "sns.amazonaws.com"
    source_arn    = aws_sns_topic.trusted_advisor_topic.arn
}


##EventBridge Sheduler
resource aws_scheduler_schedule eventbridge {
    name = "trusted-advisor-notification-schedule"
    description = "Trusted Advisor Notification"
    flexible_time_window {
        mode = "OFF"
    }
    schedule_expression = "cron(0 0 1 * ? *)"
    schedule_expression_timezone = "Asia/Tokyo"
    target {
        arn = aws_lambda_function.lambda_trustedadvisor.arn
        role_arn = aws_iam_role.iam_for_events.arn
    }
}


##SNS（サブスクリプション）
###サブスクリプションの登録
resource aws_sns_topic_subscription slack_subscription {
    topic_arn = aws_sns_topic.trusted_advisor_topic.arn
    protocol  = "lambda"
    endpoint  = aws_lambda_function.lambda_slack.arn
}

