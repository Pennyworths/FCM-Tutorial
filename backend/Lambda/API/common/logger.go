package common

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/aws/aws-lambda-go/events"
)

// Logger provides basic logging functionality
type Logger struct{}

// NewLogger creates a new logger instance
func NewLogger() *Logger {
	return &Logger{}
}

// Info logs an info message
func (l *Logger) Info(ctx context.Context, format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	log.Printf("[INFO] %s", msg)
}

// Error logs an error message
func (l *Logger) Error(ctx context.Context, err error, format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	if err != nil {
		log.Printf("[ERROR] %s: %v", msg, err)
	} else {
		log.Printf("[ERROR] %s", msg)
	}
}

// ErrorResponse represents a standardized error response for API Gateway
type ErrorResponse struct {
	Error     string `json:"error"`
	Message   string `json:"message,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

// ToJSON converts ErrorResponse to JSON string
func (e *ErrorResponse) ToJSON() string {
	jsonBytes, err := json.Marshal(e)
	if err != nil {
		return fmt.Sprintf(`{"error": "%s", "message": "%s"}`, e.Error, e.Message)
	}
	return string(jsonBytes)
}

// HandleError logs the error and returns a formatted error response
func (l *Logger) HandleError(ctx context.Context, err error, message string) *ErrorResponse {
	// Log the error
	l.Error(ctx, err, message)

	// Extract request ID from context if available
	requestID := ""
	if requestIDVal := ctx.Value("request_id"); requestIDVal != nil {
		if id, ok := requestIDVal.(string); ok {
			requestID = id
		}
	}

	// Create error response
	errorMsg := "unknown_error"
	if err != nil {
		errorMsg = err.Error()
	}

	return &ErrorResponse{
		Error:     errorMsg,
		Message:   message,
		RequestID: requestID,
	}
}

// ParseRequestBody parses JSON request body into the provided struct
// Returns error response if parsing fails
func (l *Logger) ParseRequestBody(ctx context.Context, body string, v interface{}) *ErrorResponse {
	if err := json.Unmarshal([]byte(body), v); err != nil {
		l.Error(ctx, err, "Failed to parse request body")
		return l.HandleError(ctx, err, "Invalid request body")
	}
	return nil
}

// BadRequest returns a 400 Bad Request response
func (l *Logger) BadRequest(ctx context.Context, err error, message string) (events.APIGatewayProxyResponse, error) {
	errorResp := l.HandleError(ctx, err, message)
	return events.APIGatewayProxyResponse{
		StatusCode: 400,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       errorResp.ToJSON(),
	}, nil
}

// InternalServerError returns a 500 Internal Server Error response
func (l *Logger) InternalServerError(ctx context.Context, err error, message string) (events.APIGatewayProxyResponse, error) {
	errorResp := l.HandleError(ctx, err, message)
	return events.APIGatewayProxyResponse{
		StatusCode: 500,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       errorResp.ToJSON(),
	}, nil
}

// NotFound returns a 404 Not Found response
func (l *Logger) NotFound(ctx context.Context, err error, message string) (events.APIGatewayProxyResponse, error) {
	errorResp := l.HandleError(ctx, err, message)
	return events.APIGatewayProxyResponse{
		StatusCode: 404,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       errorResp.ToJSON(),
	}, nil
}

// Success returns a 200 OK response with JSON body
func (l *Logger) Success(ctx context.Context, data interface{}) (events.APIGatewayProxyResponse, error) {
	responseBody, err := json.Marshal(data)
	if err != nil {
		l.Error(ctx, err, "Failed to marshal response")
		return l.InternalServerError(ctx, err, "Failed to create response")
	}
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(responseBody),
	}, nil
}
