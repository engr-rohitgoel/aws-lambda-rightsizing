terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# -------------------------
# DynamoDB
# -------------------------
resource "aws_dynamodb_table" "lab" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = var.tags
}

# -------------------------
# IAM for Lambda
# -------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = var.lambda_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

# DynamoDB permissions (table only)
data "aws_iam_policy_document" "lambda_dynamo_policy" {
  statement {
    sid     = "DynamoDBAccess"
    effect  = "Allow"
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
      "dynamodb:DescribeTable"
    ]
    resources = [aws_dynamodb_table.lab.arn]
  }
}

resource "aws_iam_policy" "lambda_dynamo" {
  name   = var.iam_policy_name
  policy = data.aws_iam_policy_document.lambda_dynamo_policy.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamo.arn
}

# CloudWatch Logs for Lambda (recommended managed policy)
resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -------------------------
# Lambda packaging
# -------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "lab" {
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 10
  memory_size = 128

  tags = var.tags
}

# -------------------------
# API Gateway REST API
# -------------------------
resource "aws_api_gateway_rest_api" "lab" {
  name = var.apigw_name
  tags = var.tags
}

resource "aws_api_gateway_resource" "dynamodb_manager" {
  rest_api_id = aws_api_gateway_rest_api.lab.id
  parent_id   = aws_api_gateway_rest_api.lab.root_resource_id
  path_part   = "DynamoDBManager"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.lab.id
  resource_id   = aws_api_gateway_resource.dynamodb_manager.id
  http_method   = "POST"
  authorization = "NONE"
}

# -------------------------
# NON-PROXY integration (type = AWS)
# This makes Lambda receive the JSON body directly as the event.
# -------------------------
resource "aws_api_gateway_integration" "lambda_nonproxy" {
  rest_api_id = aws_api_gateway_rest_api.lab.id
  resource_id = aws_api_gateway_resource.dynamodb_manager.id
  http_method = aws_api_gateway_method.post.http_method

  integration_http_method = "POST"
  type                    = "AWS"

  uri = "arn:aws:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.lab.arn}/invocations"

  passthrough_behavior = "WHEN_NO_MATCH"

  request_templates = {
    "application/json" = <<-VTL
      $input.json('$')
    VTL
  }
}

# Required in NON-PROXY: method response + integration response
resource "aws_api_gateway_method_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.lab.id
  resource_id = aws_api_gateway_resource.dynamodb_manager.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "post_200" {
  rest_api_id = aws_api_gateway_rest_api.lab.id
  resource_id = aws_api_gateway_resource.dynamodb_manager.id
  http_method = aws_api_gateway_method.post.http_method
  status_code = aws_api_gateway_method_response.post_200.status_code

  depends_on = [aws_api_gateway_integration.lambda_nonproxy]
}

# Allow API Gateway to invoke Lambda
resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lab.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.lab.execution_arn}/*/POST/DynamoDBManager"
}

# Deployment + Stage (Prod)
resource "aws_api_gateway_deployment" "lab" {
  rest_api_id = aws_api_gateway_rest_api.lab.id

  depends_on = [
    aws_api_gateway_integration.lambda_nonproxy,
    aws_api_gateway_method_response.post_200,
    aws_api_gateway_integration_response.post_200
  ]

  triggers = {
    redeploy = sha1(jsonencode({
      resource_id = aws_api_gateway_resource.dynamodb_manager.id
      method_id   = aws_api_gateway_method.post.id
      integ_id    = aws_api_gateway_integration.lambda_nonproxy.id
      template    = aws_api_gateway_integration.lambda_nonproxy.request_templates["application/json"]
      lambda_hash = aws_lambda_function.lab.source_code_hash
    }))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.lab.id
  deployment_id = aws_api_gateway_deployment.lab.id
  stage_name    = var.stage_name

  tags = var.tags
}