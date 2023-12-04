# Step 1: Create an S3 bucket
resource "aws_s3_bucket" "leumi" {
  bucket = var.project
  tags   = {
    Name        = var.project
    Environment = var.env
  }
}

# Step 2: Create a ZIP archive of Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/python"
  output_path = "${path.module}/python/lambda_function.zip"
}

# Step 3: Create an IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = var.project

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Step 4: Create an IAM role for API Gateway
resource "aws_iam_role" "api_gateway_role" {
  name = "leumi_api_gateway_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# Step 5: Define IAM policy for S3 bucket write access
resource "aws_iam_policy" "s3_write_policy" {
  name        = "s3_write_policy"
  description = "Policy to allow writing to S3 bucket"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = [
          aws_s3_bucket.leumi.arn,
          "${aws_s3_bucket.leumi.arn}/*"
        ],
      },
    ],
  })
}

# Step 6: Define IAM policy for API Gateway to invoke Lambda function
resource "aws_iam_policy" "api_gateway_policy" {
  name        = "api_gateway_policy"
  description = "Policy for API Gateway to invoke Lambda function"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "lambda:InvokeFunctionUrl",
          "lambda:InvokeFunction",
        ],
        Effect = "Allow",
        Resource = aws_lambda_function.leumi.arn,
      }
    ],
  })
}

# Step 7: Attach IAM policies to IAM roles
resource "aws_iam_role_policy_attachment" "lambda_s3_write_policy" {
  policy_arn = aws_iam_policy.s3_write_policy.arn
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy_attachment" "api_gateway_lambda_policy" {
  policy_arn = aws_iam_policy.api_gateway_policy.arn
  role       = aws_iam_role.api_gateway_role.name
}

# Step 8: Create Lambda function
resource "aws_lambda_function" "leumi" {
  function_name    = var.project
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64(data.archive_file.lambda_zip.output_path)

  role = aws_iam_role.lambda_role.arn
}

# Step 9: Create CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "leumi_lambda" {
  name = "/aws/lambda/${aws_lambda_function.leumi.function_name}"
}

# Step 10: Allow S3 to invoke Lambda function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.leumi.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.leumi.arn
}

# Step 11: Upload Lambda function code to S3
resource "aws_s3_object" "handler" {
  bucket  = aws_s3_bucket.leumi.id
  key     = "lambda_function.zip"
  source  = data.archive_file.lambda_zip.output_path
  etag    = filemd5(data.archive_file.lambda_zip.output_path)
}

# Step 12: Create API Gateway REST API
resource "aws_api_gateway_rest_api" "leumi" {
  name               = "leumirestapi"
  binary_media_types = ["*/*"]
}

# Step 13: Create API Gateway resource
resource "aws_api_gateway_resource" "leumi_resource" {
  rest_api_id = aws_api_gateway_rest_api.leumi.id
  parent_id   = aws_api_gateway_rest_api.leumi.root_resource_id
  path_part   = "leumi"
}

# Step 14: Define Lambda function URL
resource "aws_lambda_function_url" "publish_latest" {
  function_name      = aws_lambda_function.leumi.function_name
  authorization_type = "NONE"
}

# Step 15: Create API Gateway integration
resource "aws_api_gateway_integration" "leumi_integration" {
  rest_api_id             = aws_api_gateway_rest_api.leumi.id
  resource_id             = aws_api_gateway_resource.leumi_resource.id
  http_method             = aws_api_gateway_method.leumi_method.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function_url.publish_latest.function_url
  content_handling        = "CONVERT_TO_BINARY"

  request_parameters = {
    "integration.request.header.X-Amz-Invocation-Type" = "'Event'"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_s3_write_policy,
    aws_iam_role_policy_attachment.api_gateway_lambda_policy,
  ]
}

# Step 16: Create API Gateway method
resource "aws_api_gateway_method" "leumi_method" {
  rest_api_id    = aws_api_gateway_rest_api.leumi.id
  resource_id    = aws_api_gateway_resource.leumi_resource.id
  http_method    = "GET"
  authorization  = "NONE"
}

# Step 17: Define API Gateway method response
resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.leumi.id
  resource_id = aws_api_gateway_resource.leumi_resource.id
  http_method = aws_api_gateway_method.leumi_method.http_method
  status_code = "200"
}

# Step 18: Define API Gateway integration response
resource "aws_api_gateway_integration_response" "leumi" {
  rest_api_id      = aws_api_gateway_rest_api.leumi.id
  resource_id      = aws_api_gateway_resource.leumi_resource.id
  http_method      = aws_api_gateway_method.leumi_method.http_method
  status_code      = aws_api_gateway_method_response.response_200.status_code
  content_handling = "CONVERT_TO_BINARY"
  depends_on       = [aws_api_gateway_integration.leumi_integration]
}

# Step 19: Create API Gateway deployment
resource "aws_api_gateway_deployment" "leumi_deployment" {
  depends_on  = [aws_api_gateway_integration.leumi_integration]
  rest_api_id = aws_api_gateway_rest_api.leumi.id
}

# Step 20: Create API Gateway stage
resource "aws_api_gateway_stage" "leumi_stage" {
  rest_api_id          = aws_api_gateway_rest_api.leumi.id
  stage_name           = "leumi"
  deployment_id        = aws_api_gateway_deployment.leumi_deployment.id
  xray_tracing_enabled = true
}

# Step 21: Output API Gateway invoke URL and Lambda function invoke ARN
output "api_gateway_invoke_url" {
  value = aws_api_gateway_stage.leumi_stage.invoke_url
}

output "lambda_invoke_arn" {
  value = aws_lambda_function.leumi.invoke_arn
}
