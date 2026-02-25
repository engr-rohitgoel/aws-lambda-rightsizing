variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "dynamodb_table_name" {
  type        = string
  default     = "db-serverless"
  description = "DynamoDB table name"
}

variable "lambda_function_name" {
  type        = string
  default     = "ServerlessLambda"
  description = "Lambda function name"
}

variable "lambda_runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda runtime"
}

variable "iam_policy_name" {
  type        = string
  default     = "lambda-policy"
  description = "Custom IAM policy name for DynamoDB access"
}

variable "lambda_role_name" {
  type        = string
  default     = "lambda-apigw-role"
  description = "IAM role name for Lambda"
}

variable "apigw_name" {
  type        = string
  default     = "DynamoDBOperations"
  description = "API Gateway REST API name"
}

variable "stage_name" {
  type        = string
  default     = "Prod"
  description = "API Gateway stage name"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Optional tags"
}