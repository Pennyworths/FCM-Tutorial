terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "API Gateway"
    }
  }
}

resource "aws_api_gateway_rest_api" "fcm_api" {
  name        = "${var.project_name}-${var.environment}-fcm-api"
  description = "REST API for starting FCM"
}


# /devices
resource "aws_api_gateway_resource" "devices" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  parent_id   = aws_api_gateway_rest_api.fcm_api.root_resource_id
  path_part   = "devices"
}

# /devices/register
resource "aws_api_gateway_resource" "devices_register" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  parent_id   = aws_api_gateway_resource.devices.id
  path_part   = "register"
}

# POST /devices/register
resource "aws_api_gateway_method" "devices_register_post" {
  rest_api_id   = aws_api_gateway_rest_api.fcm_api.id
  resource_id   = aws_api_gateway_resource.devices_register.id
  http_method   = "POST"
  authorization = var.cognito_user_pool_arn != "" ? "COGNITO_USER_POOLS" : "NONE"
  authorizer_id = var.cognito_user_pool_arn != "" ? aws_api_gateway_authorizer.cognito_authorizer[0].id : null
}

# Lambda integration for POST /devices/register
resource "aws_api_gateway_integration" "devices_register_integration" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  resource_id = aws_api_gateway_resource.devices_register.id
  http_method = aws_api_gateway_method.devices_register_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.register_device_lambda_arn}/invocations"
}

# Lambda permission for API Gateway to invoke register_device
resource "aws_lambda_permission" "devices_register_permission" {
  statement_id  = "AllowAPIGatewayInvokeRegisterDevice"
  action        = "lambda:InvokeFunction"
  function_name = var.register_device_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.fcm_api.execution_arn}/*/*"
}

# /messages
resource "aws_api_gateway_resource" "messages" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  parent_id   = aws_api_gateway_rest_api.fcm_api.root_resource_id
  path_part   = "messages"
}

# /messages/send
resource "aws_api_gateway_resource" "messages_send" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  parent_id   = aws_api_gateway_resource.messages.id
  path_part   = "send"
}

# POST /messages/send
resource "aws_api_gateway_method" "messages_send_post" {
  rest_api_id   = aws_api_gateway_rest_api.fcm_api.id
  resource_id   = aws_api_gateway_resource.messages_send.id
  http_method   = "POST"
  authorization = "NONE"  # Cognito authentication removed
  authorizer_id = null
}

# Lambda integration for POST /messages/send
resource "aws_api_gateway_integration" "messages_send_integration" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  resource_id = aws_api_gateway_resource.messages_send.id
  http_method = aws_api_gateway_method.messages_send_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.send_message_lambda_arn}/invocations"
}

# Lambda permission for API Gateway to invoke send_message
resource "aws_lambda_permission" "messages_send_permission" {
  statement_id  = "AllowAPIGatewayInvokeSendMessage"
  action        = "lambda:InvokeFunction"
  function_name = var.send_message_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.fcm_api.execution_arn}/*/*"
}


# /test
resource "aws_api_gateway_resource" "test" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  parent_id   = aws_api_gateway_rest_api.fcm_api.root_resource_id
  path_part   = "test"
}

# /test/ack
resource "aws_api_gateway_resource" "test_ack" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  parent_id   = aws_api_gateway_resource.test.id
  path_part   = "ack"
}

# /test/status
resource "aws_api_gateway_resource" "test_status" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  parent_id   = aws_api_gateway_resource.test.id
  path_part   = "status"
}

# POST /test/ack
resource "aws_api_gateway_method" "test_ack_post" {
  rest_api_id   = aws_api_gateway_rest_api.fcm_api.id
  resource_id   = aws_api_gateway_resource.test_ack.id
  http_method   = "POST"
  authorization = "NONE"  # Cognito authentication removed
  authorizer_id = null
}

# Lambda integration for POST /test/ack
resource "aws_api_gateway_integration" "test_ack_integration" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  resource_id = aws_api_gateway_resource.test_ack.id
  http_method = aws_api_gateway_method.test_ack_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.test_ack_lambda_arn}/invocations"
}

# Lambda permission for API Gateway to invoke test_ack
resource "aws_lambda_permission" "test_ack_permission" {
  statement_id  = "AllowAPIGatewayInvokeTestAck"
  action        = "lambda:InvokeFunction"
  function_name = var.test_ack_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.fcm_api.execution_arn}/*/*"
}

# GET /test/status
resource "aws_api_gateway_method" "test_status_get" {
  rest_api_id   = aws_api_gateway_rest_api.fcm_api.id
  resource_id   = aws_api_gateway_resource.test_status.id
  http_method   = "GET"
  authorization = "NONE"  # Cognito authentication removed
  authorizer_id = null
}

# Lambda integration for GET /test/status
resource "aws_api_gateway_integration" "test_status_integration" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id
  resource_id = aws_api_gateway_resource.test_status.id
  http_method = aws_api_gateway_method.test_status_get.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.test_status_lambda_arn}/invocations"
}

# Lambda permission for API Gateway to invoke test_status
resource "aws_lambda_permission" "test_status_permission" {
  statement_id  = "AllowAPIGatewayInvokeTestStatus"
  action        = "lambda:InvokeFunction"
  function_name = var.test_status_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.fcm_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "fcm_deployment" {
  rest_api_id = aws_api_gateway_rest_api.fcm_api.id

  triggers = {
    redeploy_hash = sha1(jsonencode([
      aws_api_gateway_method.devices_register_post.id,
      aws_api_gateway_method.messages_send_post.id,
      aws_api_gateway_method.test_ack_post.id,
      aws_api_gateway_method.test_status_get.id,
      aws_api_gateway_integration.devices_register_integration.id,
      aws_api_gateway_integration.messages_send_integration.id,
      aws_api_gateway_integration.test_ack_integration.id,
      aws_api_gateway_integration.test_status_integration.id,
      var.cognito_user_pool_arn != "" ? aws_api_gateway_authorizer.cognito_authorizer[0].id : null,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "fcm_stage" {
  rest_api_id   = aws_api_gateway_rest_api.fcm_api.id
  deployment_id = aws_api_gateway_deployment.fcm_deployment.id
  stage_name    = var.environment  

  description = "Stage for ${var.environment}"
}

# Cognito Authorizer for API Gateway (only created if cognito_user_pool_arn is provided)
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  count           = var.cognito_user_pool_arn != "" ? 1 : 0
  name            = "${var.project_name}-${var.environment}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.fcm_api.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [var.cognito_user_pool_arn]
  identity_source = "method.request.header.Authorization"
}