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
    bucket = aws_s3_bucket.origin_contents.arn
    key = "index.html"
    source = ""
}

#CloudFrontディストリビューション
resource aws_cloudfront_distribution cf_distribution {
    origin {
        domain_name = aws_s3_bucket.origin_contents.bucket_regional_domain_name
        origin_id = aws_s3_bucket.origin_contents.id
        origin_access_control_id = aws_cloudfront_origin_access_control.main.id
    }
    enabled = true
    viewer_certificate {
        cloudfront_default_certificate = true
    }
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
    }
    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }
}
# OAC を作成
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
        actions = ["s3:GetObject"]
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

#Cognito
# resource aws_cognito_user_pool cognito_pool {
#     name = "cloudfront_access_pool"
#     alias_attributes = "email"
#     password_policy = {
#         minimum_length = 8
#         require_symbols = false
#     }
#     email_configuration = {
#         email_sending_account = "COGNITO_DEFAULT"
#     }
# }

#Lambda@Edge



