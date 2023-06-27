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
    # Compute Optimizerのチェック結果はバージニア北部から取得する必要がある
    region = "us-east-1"
}
#AWSアカウントIDの取得
data aws_caller_identity current {}


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
    name               = "EventBridge_ComputeOptimizer_Notification_Role"
    assume_role_policy = data.aws_iam_policy_document.events_assume_role.json
    managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSLambdaRole"]
}

##Lambda(Compute Optimizerからの情報取得用)
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
    name               = "Lambda_ComputeOptimizer_Notification_Role"
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
    managed_policy_arns = [
        "arn:aws:iam::aws:policy/ComputeOptimizerReadOnlyAccess"
    ]
}
#============ IAMロール作成 end ============


#============ リソース作成 start ============
##SNS（トピック）
###トピックの作成
resource aws_sns_topic compute_optimizer_topic {
    name = "ComputeOptimizer-notification-topic"
}
data aws_iam_policy_document sns_assume_role {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
        actions = ["sns:Publish"]
        resources = [aws_sns_topic.compute_optimizer_topic.arn]
    }
}
resource aws_sns_topic_policy sns_topic_policy {
    arn    = aws_sns_topic.compute_optimizer_topic.arn
    policy = data.aws_iam_policy_document.sns_assume_role.json
}

##Lambda(Compute Optimizerからの情報取得用)
data archive_file lambda_computeoptimizer {
    type        = "zip"
    source_file = "lambda/lambda_computeoptimizer.py"
    output_path = "lambda_computeoptimizer.zip"
}
resource aws_lambda_function lambda_computeoptimizer {
    filename      = "lambda_computeoptimizer.zip"
    function_name = "compute-optimizer-detection"
    role          = aws_iam_role.iam_for_lambda.arn
    handler       = "lambda_computeoptimizer.lambda_handler"
    source_code_hash = data.archive_file.lambda_computeoptimizer.output_base64sha256
    runtime = "python3.9"
    environment {
        variables = {
            SNSTopicArn = aws_sns_topic.compute_optimizer_topic.arn,
            AccountId = data.aws_caller_identity.current.account_id
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
    function_name = "compute-optimizer-to-slack"
    role          = aws_iam_role.iam_for_lambda.arn
    handler       = "lambda_slack.lambda_handler"
    source_code_hash = data.archive_file.lambda_slack.output_base64sha256
    runtime = "python3.9"
    #slack通知先
    environment {
        variables = {
            HookURL = "[SlackのWebHookURL]"
            ChannelName = "[チャンネル名]"
        }
    }
}
resource aws_lambda_permission lambda_slack_permission {
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_slack.function_name
    principal     = "sns.amazonaws.com"
    source_arn    = aws_sns_topic.compute_optimizer_topic.arn
}

##EventBridge Sheduler
resource aws_scheduler_schedule eventbridge {
    name = "compute-optimizer-notification-schedule"
    description = "Compute Optimizer Notification"
    flexible_time_window {
        mode = "OFF"
    }
    schedule_expression = "cron(0 0 1 * ? *)"
    schedule_expression_timezone = "Asia/Tokyo"
    target {
        arn = aws_lambda_function.lambda_computeoptimizer.arn
        role_arn = aws_iam_role.iam_for_events.arn
    }
}

##SNS（サブスクリプション）
resource aws_sns_topic_subscription slack_subscription {
    topic_arn = aws_sns_topic.compute_optimizer_topic.arn
    protocol  = "lambda"
    endpoint  = aws_lambda_function.lambda_slack.arn
}

