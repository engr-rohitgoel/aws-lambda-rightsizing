data "aws_region" "current" {}

output "api_invoke_url" {
  value = "https://${aws_api_gateway_rest_api.lab.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/DynamoDBManager"
}

output "lambda_name" {
  value = aws_lambda_function.lab.function_name
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.lab.name
}