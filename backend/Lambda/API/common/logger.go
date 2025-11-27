package common

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
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
