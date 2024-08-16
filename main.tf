provider "aws" {
  region = "us-west-2"
}

provider "archive" {
  # No configuration needed
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/my_lambda"
  output_path = "${path.module}/lambda_function.zip"
}

# Role for Lambda function to write logs
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Attach the basic execution policy for Lambda (includes logging to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Role for AppSync to invoke the Lambda function
resource "aws_iam_role" "appsync_datasource_role" {
  name = "appsync-datasource-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "appsync.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Policy that allows AppSync to invoke the Lambda function
resource "aws_iam_policy" "appsync_invoke_lambda_policy" {
  name        = "appsync-invoke-lambda-policy"
  description = "Policy that allows AppSync to invoke Lambda functions"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "lambda:InvokeFunction",
        Resource = aws_lambda_function.hello_function.arn
      }
    ]
  })
}

# Attach the invoke policy to the AppSync role
resource "aws_iam_role_policy_attachment" "attach_invoke_policy" {
  role       = aws_iam_role.appsync_datasource_role.name
  policy_arn = aws_iam_policy.appsync_invoke_lambda_policy.arn
}

resource "aws_lambda_function" "hello_function" {
  filename      = "lambda_function.zip" # Zip of your Python or JS function
  function_name = "helloFunction"
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      ENV = "prod"
    }
  }
}

resource "aws_appsync_graphql_api" "api" {
  name = "helloAppSyncAPI"

  authentication_type = "API_KEY"
  schema = <<EOF
type Query {
  hello(name: String): HelloResponse
}

type HelloResponse {
  message: String
}

schema {
  query: Query
}
EOF

}

resource "aws_appsync_datasource" "lambda_datasource" {
  api_id           = aws_appsync_graphql_api.api.id
  name             = "LambdaDataSource"
  type             = "AWS_LAMBDA"
  lambda_config {
    function_arn = aws_lambda_function.hello_function.arn
  }
  service_role_arn = aws_iam_role.appsync_datasource_role.arn
}

resource "aws_appsync_resolver" "query_resolver" {
  api_id          = aws_appsync_graphql_api.api.id
  type            = "Query"
  field           = "hello"
  data_source     = aws_appsync_datasource.lambda_datasource.name
  request_template  = <<EOF
{
  "version": "2017-02-28",
  "operation": "Invoke",
  "payload": {
    "name": "$util.defaultIfNull($ctx.arguments.name, 'World')"
  }
}
EOF

  response_template = <<EOF
$util.toJson($ctx.result)
EOF
}

# Create an API key for the AppSync API
resource "aws_appsync_api_key" "api_key" {
  api_id = aws_appsync_graphql_api.api.id
  expires = timeadd(timestamp(), "2592000s")  # This sets the expiration 30 days from now
}
