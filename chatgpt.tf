
■Terraform

provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_s3_bucket" "example_bucket" {
  bucket = "example-bucket"
}

resource "aws_s3_bucket_object" "index_html" {
  bucket = aws_s3_bucket.example_bucket.id
  key    = "index.html"
  source = "index.html"
}

resource "aws_cloudfront_distribution" "example_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.example_bucket.bucket_regional_domain_name
    origin_id   = "example-s3-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.s3_access_identity.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "example-s3-origin"

    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type   = "viewer-request"
      include_body = false
      lambda_arn   = aws_lambda_function.auth_lambda.qualified_arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    ssl_support_method  = "sni-only"
  }
}

resource "aws_cloudfront_origin_access_identity" "s3_access_identity" {}

resource "aws_lambda_function" "auth_lambda" {
  filename         = "auth_lambda.zip"
  source_code_hash = filebase64sha256("auth_lambda.zip")
  role             = aws_iam_role.auth_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
}

resource "aws_iam_role" "auth_lambda_role" {
  name = "auth_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "auth_lambda_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.auth_lambda_role.name
}

locals {
  auth_lambda_arn = aws_lambda_function.auth_lambda.arn
}

resource "aws_lambda_permission" "auth_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = local.auth_lambda_arn
  principal     = "edgelambda.amazonaws.com"

  source_arn = aws_cloudfront_distribution.example_distribution.arn
}

この例では、S3にexample-bucketというバケットが作成され、そこにindex.htmlがアップロードされます。
その次に、CloudFrontディストリビューションが作成され、そのディストリビューションのオリジンとしてS3バケットが指定されます。デフォルトのキャッシュ動作は、GETとHEADメソッドで許可され、クエリ文字列とCookieはキャッシュされません。Cognito認証を実行するために、Lambda@Edge関数がViewer Requestイベントに関連付けられます。この関数は、Cognitoで認証されたユーザーのみがコンテンツにアクセスできるようにします。Lambda関数は、認証情報を検証し、要求を許可または拒否します。

次に、Lambda関数が使用するIAMロールが定義されます。このロールには、Lambda関数が実行されるために必要な権限が与えられます。また、Lambda関数がCloudFrontから呼び出されるために必要なIAMポリシーもアタッチされます。
最後に、Lambda関数にCloudFrontからの呼び出しを許可するためのLambda Permissionが定義されます。このPermissionには、CloudFrontのARNとLambda関数のARNが含まれます。

以上で、S3にあるHTMLファイルをCloudFront経由で表示させるTerraformのコードが完成します。ただし、Lambda関数の実装は特定の要件に応じて変更する必要があります。


-----
■Lambda(Go)
package main

import (
	"context"
	"errors"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

func handler(ctx context.Context, request events.CloudFrontRequest) (events.CloudFrontResponse, error) {
	headers := request.Headers

	// Check if user is authenticated with Cognito
	if cookies, ok := headers["Cookie"]; ok {
		for _, cookie := range cookies {
			if strings.Contains(cookie.Value, "CognitoIdentityServiceProvider") {
				// User is authenticated, allow access to content
				return request.ToResponse(), nil
			}
		}
	}

	// User is not authenticated, redirect to login page
	response := events.CloudFrontResponse{
		Status:            "302",
		StatusDescription: "Found",
		Headers: map[string][]events.CloudFrontHeader{
			"Location": {
				{
					Key:    "Location",
					Value:  "https://example.com/login",
				},
			},
		},
	}
	return response, errors.New("redirecting to login page")
}

func main() {
	lambda.Start(handler)
}

この関数は、context.Contextとevents.CloudFrontRequestを引数に取り、events.CloudFrontResponseとerrorを返します。まず、ユーザーがCognitoで認証されているかどうかを確認します。headers["Cookie"]からCookieの値を取得し、ユーザーがCognitoで認証されている場合は、Cookieの値に"CognitoIdentityServiceProvider"という文字列が含まれることを期待しています。含まれている場合は、リクエストオブジェクトをevents.CloudFrontResponseに変換して返します。
ユーザーが認証されていない場合は、302リダイレクトレスポンスを返します。locationヘッダーには、ログインページのURLが含まれます。また、エラーを返しているため、エラーメッセージも含まれます。最後に、main関数でLambda関数を実行します。

