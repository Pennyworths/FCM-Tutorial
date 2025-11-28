package main

import (
	"os"

	"github.com/aws/aws-lambda-go/lambda"
)

func main() {
	// Select handler based on LAMBDA_HANDLER environment variable
	// Default to RegisterDeviceHandler for backward compatibility
	handler := os.Getenv("LAMBDA_HANDLER")
	switch handler {
	case "SendMessageHandler", "send":
		lambda.Start(SendMessageHandler)
	case "TestAckHandler", "ack":
		lambda.Start(TestAckHandler)
	case "TestStatusHandler", "status":
		lambda.Start(TestStatusHandler)
	case "RegisterDeviceHandler", "register", "":
		lambda.Start(RegisterDeviceHandler)
	default:
		lambda.Start(RegisterDeviceHandler)
	}
}
