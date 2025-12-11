package common

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// KlaviyoEventRequest represents the Klaviyo event request structure
type KlaviyoEventRequest struct {
	Data KlaviyoEventData `json:"data"`
}

type KlaviyoEventData struct {
	Type       string                 `json:"type"`
	Attributes KlaviyoEventAttributes `json:"attributes"`
}

type KlaviyoEventAttributes struct {
	Metric     KlaviyoMetricData      `json:"metric"`
	Profile    KlaviyoProfileData     `json:"profile"`
	Properties map[string]interface{} `json:"properties"`
}

type KlaviyoMetricData struct {
	Data KlaviyoMetricDataInner `json:"data"`
}

type KlaviyoMetricDataInner struct {
	Type       string                  `json:"type"`
	Attributes KlaviyoMetricAttributes `json:"attributes"`
}

type KlaviyoMetricAttributes struct {
	Name string `json:"name"`
}

type KlaviyoProfileData struct {
	Data KlaviyoProfileDataInner `json:"data"`
}

type KlaviyoProfileDataInner struct {
	Type       string                   `json:"type"`
	Attributes KlaviyoProfileAttributes `json:"attributes"`
}

type KlaviyoProfileAttributes struct {
	Email string `json:"email"`
}

// KlaviyoEventResponse represents the Klaviyo event response
type KlaviyoEventResponse struct {
	Data   *KlaviyoEventResponseData `json:"data,omitempty"`
	Errors []KlaviyoError            `json:"errors,omitempty"`
}

type KlaviyoEventResponseData struct {
	Type string `json:"type"`
	ID   string `json:"id"`
}

type KlaviyoError struct {
	ID     string `json:"id"`
	Status int    `json:"status"`
	Code   string `json:"code"`
	Title  string `json:"title"`
	Detail string `json:"detail"`
}

// GetKlaviyoAPIKey retrieves Klaviyo API Key from AWS Secrets Manager.
// Environment variable required:
//   - KLAVIYO_API_KEY_SECRET_ARN: ARN of the secret in Secrets Manager (optional, falls back to SECRET_ARN)
//
// Returns:
//   - string: Klaviyo API Key
//   - error: Error if retrieval fails
func GetKlaviyoAPIKey(ctx context.Context) (string, error) {
	// Try KLAVIYO_API_KEY_SECRET_ARN first, then fall back to SECRET_ARN
	secretARN := os.Getenv("KLAVIYO_API_KEY_SECRET_ARN")
	if secretARN == "" {
		secretARN = os.Getenv("SECRET_ARN")
	}
	if secretARN == "" {
		return "", fmt.Errorf("KLAVIYO_API_KEY_SECRET_ARN or SECRET_ARN environment variable is not set")
	}

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return "", fmt.Errorf("failed to load AWS config: %w", err)
	}

	svc := secretsmanager.NewFromConfig(cfg)

	input := &secretsmanager.GetSecretValueInput{
		SecretId:     aws.String(secretARN),
		VersionStage: aws.String("AWSCURRENT"),
	}

	result, err := svc.GetSecretValue(ctx, input)
	if err != nil {
		return "", fmt.Errorf("failed to get secret value: %w", err)
	}

	if result.SecretString == nil {
		return "", fmt.Errorf("secret %s does not contain a SecretString value", secretARN)
	}

	secretString := *result.SecretString

	// Try to parse as JSON first (in case it's stored as JSON with "klaviyo_api_key" field)
	// This allows storing Klaviyo API Key in the same secret as FCM credentials
	var secretJSON map[string]interface{}
	if err := json.Unmarshal([]byte(secretString), &secretJSON); err == nil {
		// Try various possible field names (case-insensitive check)
		possibleKeys := []string{
			"klaviyo_api_key",
			"KLAVIYO_API_KEY",
			"klaviyoApiKey",
			"KlaviyoApiKey",
			"api_key",
			"API_KEY",
			"klaviyo_key",
			"KLAVIYO_KEY",
		}

		for _, key := range possibleKeys {
			if apiKey, ok := secretJSON[key].(string); ok && apiKey != "" {
				return apiKey, nil
			}
		}

		// If JSON but no matching key found, return error with helpful message
		return "", fmt.Errorf("klaviyo API key not found in secret JSON. Expected one of: %v", possibleKeys)
	}

	// If not JSON, treat entire secret as the API key (for standalone Klaviyo secret)
	return secretString, nil
}

// SendKlaviyoEvent sends an event to Klaviyo API with default metric "application_result"
// Returns true if the event was sent successfully, false otherwise
func SendKlaviyoEvent(ctx context.Context, email string, properties map[string]interface{}) (bool, error) {
	return SendKlaviyoEventWithMetric(ctx, email, "application_result", properties)
}

// SendKlaviyoEventWithMetric sends an event to Klaviyo API with custom metric name
// Returns true if the event was sent successfully, false otherwise
func SendKlaviyoEventWithMetric(ctx context.Context, email string, metricName string, properties map[string]interface{}) (bool, error) {
	// Get Klaviyo API Key
	apiKey, err := GetKlaviyoAPIKey(ctx)
	if err != nil {
		return false, fmt.Errorf("failed to get Klaviyo API key: %w", err)
	}

	// Build request payload
	requestPayload := KlaviyoEventRequest{
		Data: KlaviyoEventData{
			Type: "event",
			Attributes: KlaviyoEventAttributes{
				Metric: KlaviyoMetricData{
					Data: KlaviyoMetricDataInner{
						Type: "metric",
						Attributes: KlaviyoMetricAttributes{
							Name: metricName,
						},
					},
				},
				Profile: KlaviyoProfileData{
					Data: KlaviyoProfileDataInner{
						Type: "profile",
						Attributes: KlaviyoProfileAttributes{
							Email: email,
						},
					},
				},
				Properties: properties,
			},
		},
	}

	// Marshal to JSON
	requestBody, err := json.Marshal(requestPayload)
	if err != nil {
		return false, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Create HTTP request
	req, err := http.NewRequestWithContext(ctx, "POST", "https://a.klaviyo.com/api/events/", bytes.NewBuffer(requestBody))
	if err != nil {
		return false, fmt.Errorf("failed to create HTTP request: %w", err)
	}

	// Set headers
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Klaviyo-API-Key %s", apiKey))
	req.Header.Set("revision", "2024-02-15")

	// Send request
	client := &http.Client{
		Timeout: 30 * time.Second,
	}
	resp, err := client.Do(req)
	if err != nil {
		return false, fmt.Errorf("failed to send HTTP request: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, fmt.Errorf("failed to read response body: %w", err)
	}

	// Check response status
	// Klaviyo API returns 202 (Accepted) for successful event creation
	// Also accept 200 (OK) and 201 (Created) as success
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusAccepted {
		// Try to parse error response
		var errorResp KlaviyoEventResponse
		if err := json.Unmarshal(responseBody, &errorResp); err == nil && len(errorResp.Errors) > 0 {
			return false, fmt.Errorf("klaviyo API error: %s (status: %d, detail: %s)",
				errorResp.Errors[0].Title, resp.StatusCode, errorResp.Errors[0].Detail)
		}
		return false, fmt.Errorf("klaviyo API returned status %d: %s", resp.StatusCode, string(responseBody))
	}

	// Parse successful response
	var klaviyoResp KlaviyoEventResponse
	if err := json.Unmarshal(responseBody, &klaviyoResp); err != nil {
		// If response is not JSON or doesn't parse, but status is OK, consider it success
		return true, nil
	}

	// Check if response indicates success
	if klaviyoResp.Data != nil && klaviyoResp.Data.ID != "" {
		return true, nil
	}

	// If there are errors in the response, it's a failure
	if len(klaviyoResp.Errors) > 0 {
		return false, fmt.Errorf("klaviyo API returned errors: %s", klaviyoResp.Errors[0].Detail)
	}

	// Default to success if status code was OK/Created
	return true, nil
}
