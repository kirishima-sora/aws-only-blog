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
    #Lambda@Edgeがバージニアリージョンでのみ使用可能なため
    region = "us-east-1"
}

#S3
resource aws_s3_bucket origin_contents {
    bucket = "cloudfront-origin-contents"
}
#ファイルアップロード
resource aws_s3_object object {
    bucket = aws_s3_bucket.origin_contents.id
    key = "index.html"
    source = "front/front.html"
    #content-typeを指定しない場合、ページが表示されずにダウンロードになる場合があるため指定する
    content_type = "text/html"
}

#Lambda用IAMロールの信頼関係の定義
data aws_iam_policy_document assume_role {
    statement {
        effect = "Allow"
        principals {
            type = "Service"
            identifiers = [
                "lambda.amazonaws.com",
                "edgelambda.amazonaws.com"
            ]
        }
        actions = ["sts:AssumeRole"]
    }
}
#Lambda用IAMロールの作成
resource aws_iam_role iam_for_lambda {
    name               = "cloudfront_access_lambda"
    assume_role_policy = data.aws_iam_policy_document.assume_role.json
    inline_policy {
        name = "my_inline_policy"
        policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
                {
                    Action   = [
                        "lambda:InvokeFunction",
                        "lambda:GetFunction",
                        "lambda:EnableReplication",
                        "cloudfront:UpdateDistribution"
                    ]
                    Effect   = "Allow"
                    Resource = "*"
                },
            ]
        })
    }
}
data archive_file lambda {
    type        = "zip"
    source_file = "lambda/lambda.py"
    output_path = "lambda_handler.zip"
}
resource aws_lambda_function lambda {
    filename      = "lambda_handler.zip"
    function_name = "IPAuth"
    role          = aws_iam_role.iam_for_lambda.arn
    handler       = "lambda.lambda_handler"
    source_code_hash = data.archive_file.lambda.output_base64sha256
    runtime = "python3.8"
}

#CloudFrontディストリビューション
resource aws_cloudfront_distribution cf_distribution {
    enabled = true
    default_root_object = "index.html"
    #オリジンの設定
    origin {
        domain_name = aws_s3_bucket.origin_contents.bucket_regional_domain_name
        origin_id = aws_s3_bucket.origin_contents.id
        origin_access_control_id = aws_cloudfront_origin_access_control.main.id
    }
    viewer_certificate {
        cloudfront_default_certificate = true
    }
    #キャッシュの設定
    default_cache_behavior {
        target_origin_id       = aws_s3_bucket.origin_contents.id
        viewer_protocol_policy = "redirect-to-https"
        cached_methods         = ["GET", "HEAD"]
        allowed_methods        = ["GET", "HEAD"]
        forwarded_values {
            query_string = false
            headers      = []
            cookies {
                forward = "none"
            }
        }
        #ビューワーリクエストにLambdaを設定する
        lambda_function_association {
            event_type   = "viewer-request"
            lambda_arn   = aws_lambda_function.lambda.qualified_arn
            include_body = false
        }
    }
    #国ごとのコンテンツ制限がある場合はここで設定（今回はなし）
    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }
}
# OACを作成
resource aws_cloudfront_origin_access_control main {
    name                              = "cloudfront-oac"
    origin_access_control_origin_type = "s3"
    signing_behavior                  = "always"
    signing_protocol                  = "sigv4"
}

#S3バケットポリシー（OACのみから許可する）
##ポリシーの定義
data aws_iam_policy_document allow_access_from_cloudfront {
    statement {
        principals {
            type        = "Service"
            identifiers = ["cloudfront.amazonaws.com"]
        }
        actions = [
            "s3:GetObject"
            ]
        resources = [
            "${aws_s3_bucket.origin_contents.arn}/*"
        ]
        condition {
            test     = "StringEquals"
            variable = "AWS:SourceArn"
            values   = [aws_cloudfront_distribution.cf_distribution.arn]
        }
    }
}
##バケットポリシーのアタッチ
resource aws_s3_bucket_policy allow_access_from_cloudfront {
    bucket = aws_s3_bucket.origin_contents.id
    policy = data.aws_iam_policy_document.allow_access_from_cloudfront.json
}
