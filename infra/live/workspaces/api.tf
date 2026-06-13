# Self-Service Desktop Provisioning API
# API Gateway + Lambda + DynamoDB

###############################################################################
# DynamoDB Table (user→instance tracking + rate limiting)
###############################################################################

resource "aws_dynamodb_table" "desktops" {
  name         = "${local.name_prefix}-desktops"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-desktops"
  })
}

###############################################################################
# Lambda Function
###############################################################################

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/desktop_provisioner.py"
  output_path = "${path.module}/lambda/desktop_provisioner.zip"
}

resource "aws_lambda_function" "desktop_provisioner" {
  function_name    = "${local.name_prefix}-provisioner"
  handler          = "desktop_provisioner.handler"
  runtime          = "python3.11"
  timeout          = 120
  memory_size      = 256
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      AMI_ID               = data.aws_ami.amazon_linux.id
      INSTANCE_TYPE        = var.instance_type
      SUBNET_ID            = module.workspaces_vpc.public_subnet_ids[0]
      SECURITY_GROUP_ID    = module.dcv_sg.id
      INSTANCE_PROFILE_ARN = aws_iam_instance_profile.dcv.arn
      API_SECRET           = var.api_secret
      TABLE_NAME           = aws_dynamodb_table.desktops.name
      RATE_LIMIT_SECONDS   = "60"
      OLLAMA_INSTANCE_ID   = aws_instance.ollama.id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-provisioner"
  })
}

###############################################################################
# Lambda IAM Role
###############################################################################

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "lambda_permissions" {
  # checkov:skip=CKV_AWS_290: "Lambda needs write access to create EC2 instances dynamically"
  # checkov:skip=CKV_AWS_355: "Lambda needs wildcard resource for EC2 RunInstances (instance IDs unknown at policy time)"
  name = "${local.name_prefix}-lambda-permissions"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Management"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:DescribeVolumes",
          "ec2:CreateTags",
        ]
        Resource = "*"
      },
      {
        Sid      = "PassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = module.dcv_instance_role.role_arn
      },
      {
        Sid    = "DynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
        ]
        Resource = aws_dynamodb_table.desktops.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "SSMRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:*:*:parameter/infra-lab/desktop/*"
      },
    ]
  })
}

###############################################################################
# API Gateway (REST)
###############################################################################

resource "aws_api_gateway_rest_api" "desktops" {
  name        = "${local.name_prefix}-api"
  description = "Self-service dev desktop provisioning API"

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "desktops" {
  rest_api_id = aws_api_gateway_rest_api.desktops.id
  parent_id   = aws_api_gateway_rest_api.desktops.root_resource_id
  path_part   = "desktops"
}

# POST /desktops
resource "aws_api_gateway_method" "post_desktops" {
  rest_api_id   = aws_api_gateway_rest_api.desktops.id
  resource_id   = aws_api_gateway_resource.desktops.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_desktops" {
  rest_api_id             = aws_api_gateway_rest_api.desktops.id
  resource_id             = aws_api_gateway_resource.desktops.id
  http_method             = aws_api_gateway_method.post_desktops.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.desktop_provisioner.invoke_arn
}

# GET /desktops
resource "aws_api_gateway_method" "get_desktops" {
  rest_api_id   = aws_api_gateway_rest_api.desktops.id
  resource_id   = aws_api_gateway_resource.desktops.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_desktops" {
  rest_api_id             = aws_api_gateway_rest_api.desktops.id
  resource_id             = aws_api_gateway_resource.desktops.id
  http_method             = aws_api_gateway_method.get_desktops.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.desktop_provisioner.invoke_arn
}

# OPTIONS /desktops (CORS preflight)
resource "aws_api_gateway_method" "options_desktops" {
  rest_api_id   = aws_api_gateway_rest_api.desktops.id
  resource_id   = aws_api_gateway_resource.desktops.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_desktops" {
  rest_api_id = aws_api_gateway_rest_api.desktops.id
  resource_id = aws_api_gateway_resource.desktops.id
  http_method = aws_api_gateway_method.options_desktops.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.desktops.id
  resource_id = aws_api_gateway_resource.desktops.id
  http_method = aws_api_gateway_method.options_desktops.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.desktops.id
  resource_id = aws_api_gateway_resource.desktops.id
  http_method = aws_api_gateway_method.options_desktops.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-API-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Deploy
resource "aws_api_gateway_deployment" "desktops" {
  rest_api_id = aws_api_gateway_rest_api.desktops.id

  triggers = {
    redeployment = sha1(join(",", [
      jsonencode(aws_api_gateway_integration.post_desktops),
      jsonencode(aws_api_gateway_integration.get_desktops),
      jsonencode(aws_api_gateway_integration.options_desktops),
      jsonencode(aws_api_gateway_integration_response.options_200),
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.post_desktops,
    aws_api_gateway_integration.get_desktops,
    aws_api_gateway_integration.options_desktops,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.desktops.id
  deployment_id = aws_api_gateway_deployment.desktops.id
  stage_name    = "v1"

  tags = local.common_tags
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.desktop_provisioner.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.desktops.execution_arn}/*/*"
}
