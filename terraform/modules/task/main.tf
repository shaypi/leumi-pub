resource "aws_s3_bucket" "leumi" {
  bucket = var.project
  tags   = {
    Name        = var.project
    Environment = var.env
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/python"
  output_path = "${path.module}/python/lambda_function.zip"
}

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

resource "aws_lambda_function" "leumi" {
  function_name    = var.project
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.8"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64(data.archive_file.lambda_zip.output_path)

  role = aws_iam_role.lambda_role.arn
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.leumi.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.leumi.arn
}

resource "aws_api_gateway_rest_api" "leumi" {
  name               = "leumirestapi"
  binary_media_types = ["*/*"]
}

resource "aws_api_gateway_resource" "leumi_resource" {
  rest_api_id = aws_api_gateway_rest_api.leumi.id
  parent_id   = aws_api_gateway_rest_api.leumi.root_resource_id
  path_part   = "leumi"
}

resource "aws_api_gateway_method" "leumi_method" {
  rest_api_id = aws_api_gateway_rest_api.leumi.id
  resource_id = aws_api_gateway_resource.leumi_resource.id
  http_method = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "leumi_integration" {
  rest_api_id             = aws_api_gateway_rest_api.leumi.id
  resource_id             = aws_api_gateway_resource.leumi_resource.id
  http_method             = aws_api_gateway_method.leumi_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.leumi.invoke_arn
  content_handling        = "CONVERT_TO_BINARY"
  depends_on              = [aws_lambda_function.leumi]
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.leumi.id
  resource_id = aws_api_gateway_resource.leumi_resource.id
  http_method = aws_api_gateway_method.leumi_method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "leumi" {
  rest_api_id = aws_api_gateway_rest_api.leumi.id
  resource_id = aws_api_gateway_resource.leumi_resource.id
  http_method = aws_api_gateway_method.leumi_method.http_method
  status_code = aws_api_gateway_method_response.response_200.status_code
  content_handling = "CONVERT_TO_BINARY"
  depends_on = [aws_api_gateway_integration.leumi_integration]
}

resource "aws_api_gateway_deployment" "leumi_deployment" {
  depends_on  = [aws_api_gateway_integration.leumi_integration]
  rest_api_id = aws_api_gateway_rest_api.leumi.id
}

resource "aws_api_gateway_stage" "leumi_stage" {
  rest_api_id  = aws_api_gateway_rest_api.leumi.id
  stage_name   = "leumi"
  deployment_id = aws_api_gateway_deployment.leumi_deployment.id
  xray_tracing_enabled = true
}

output "api_gateway_invoke_url" {
  value = aws_api_gateway_stage.leumi_stage.invoke_url
}

output "lambda_invoke_arn" {
  value = aws_lambda_function.leumi.invoke_arn
}
