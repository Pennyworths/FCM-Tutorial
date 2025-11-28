output "endpoint_devices_register" {
  description = "POST /devices/register"
  value       = "https://${aws_api_gateway_rest_api.fcm_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.fcm_stage.stage_name}/devices/register"
}

output "endpoint_messages_send" {
  description = "POST /messages/send"
  value       = "https://${aws_api_gateway_rest_api.fcm_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.fcm_stage.stage_name}/messages/send"
}

output "endpoint_test_ack" {
  description = "POST /test/ack"
  value       = "https://${aws_api_gateway_rest_api.fcm_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.fcm_stage.stage_name}/test/ack"
}

output "endpoint_test_status" {
  description = "GET /test/status"
  value       = "https://${aws_api_gateway_rest_api.fcm_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.fcm_stage.stage_name}/test/status"
}

output "api_base_url" {
  description = "API Gateway base URL"
  value       = "https://${aws_api_gateway_rest_api.fcm_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.fcm_stage.stage_name}"
}
