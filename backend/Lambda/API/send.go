package main

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/fcm-tutorial/lambda/api/common"
	"github.com/fcm-tutorial/lambda/api/sqlc"
	"github.com/golang-jwt/jwt/v5"
)

type SendMessageRequest struct {
	UserID string          `json:"user_id"`
	Title  string          `json:"title"`
	Body   string          `json:"body"`
	Data   json.RawMessage `json:"data"`
}

type SendMessageResponse struct {
	OK        bool `json:"ok"`
	SentCount int  `json:"sent_count"`
}

func SendMessageHandler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	logger := common.NewLogger()
	logger.Info(ctx, "Received send message request")

	var sendMessageRequest SendMessageRequest
	if errorResp := logger.ParseRequestBody(ctx, request.Body, &sendMessageRequest); errorResp != nil {
		return logger.BadRequest(ctx, nil, "Invalid request body")
	}

	// Validate required fields
	if sendMessageRequest.UserID == "" || sendMessageRequest.Title == "" || sendMessageRequest.Body == "" {
		err := fmt.Errorf("missing required fields: user_id, title, body")
		return logger.BadRequest(ctx, err, "Missing required fields")
	}

	// Get database connection
	db, err := common.GetDBConnection()
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database connection failed")
	}
	defer common.CloseDBConnection(db)

	// Query devices for all rows where user_id = ? and is_active = TRUE (only android and ios)
	queries := sqlc.New(db)
	devices, err := queries.ListActiveDevicesByPlatforms(ctx, sendMessageRequest.UserID)
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database query failed")
	}

	// Send message to each device
	for _, device := range devices {
		err = sendMessageToDevice(ctx, device.FcmToken, sendMessageRequest.Title, sendMessageRequest.Body, sendMessageRequest.Data)
		if err != nil {
			return logger.InternalServerError(ctx, err, "Failed to send message to device")
		}
	}

	// If data.type == "e2e_test" and data.nonce is present, insert into test_runs
	if len(sendMessageRequest.Data) > 0 {
		var dataMap map[string]interface{}
		if err := json.Unmarshal(sendMessageRequest.Data, &dataMap); err == nil {
			if dataType, ok := dataMap["type"].(string); ok && dataType == "e2e_test" {
				if nonce, ok := dataMap["nonce"].(string); ok && nonce != "" {
					// Insert test run record
					err = queries.CreateTestRun(ctx, sqlc.CreateTestRunParams{
						Nonce:  nonce,
						UserID: sendMessageRequest.UserID,
					})
					if err != nil {
						logger.Error(ctx, err, "Failed to create test run record")
						// Don't fail the request if test run creation fails, just log it
					} else {
						logger.Info(ctx, "Created test run record: nonce=%s, user_id=%s", nonce, sendMessageRequest.UserID)
					}
				}
			}
		}
	}

	// Prepare success response
	response := SendMessageResponse{
		OK:        true,
		SentCount: len(devices),
	}

	return logger.Success(ctx, response)
}

// sendMessageToDevice sends a push notification to a single device using FCM HTTP v1 API
func sendMessageToDevice(ctx context.Context, fcmToken string, title string, body string, data json.RawMessage) error {
	// Get FCM credentials from Secrets Manager
	creds, err := common.GetFCMCredentials(ctx)
	if err != nil {
		return fmt.Errorf("failed to get FCM credentials: %w", err)
	}

	// Generate OAuth2 access token
	accessToken, err := generateAccessToken(ctx, creds)
	if err != nil {
		return fmt.Errorf("failed to generate access token: %w", err)
	}

	// Parse data if provided
	var dataMap map[string]string
	if len(data) > 0 {
		if err := json.Unmarshal(data, &dataMap); err != nil {
			// If data is not a map, treat it as a single string value
			fmt.Printf("WARNING: Invalid JSON for 'data' field: %v. Raw data: %s\n", err, string(data))
			dataMap = map[string]string{"data": string(data)}
		}
	}

	// Build FCM message payload
	message := map[string]interface{}{
		"message": map[string]interface{}{
			"token": fcmToken,
			"notification": map[string]string{
				"title": title,
				"body":  body,
			},
		},
	}

	// Add data if provided
	if len(dataMap) > 0 {
		message["message"].(map[string]interface{})["data"] = dataMap
	}

	// Marshal request body
	requestBody, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("failed to marshal request body: %w", err)
	}

	// Build FCM API URL
	fcmURL := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", creds.ProjectID)

	// Create HTTP request
	req, err := http.NewRequestWithContext(ctx, "POST", fcmURL, bytes.NewBuffer(requestBody))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %w", err)
	}

	// Set headers
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", accessToken))

	// Send request
	client := &http.Client{
		Timeout: 30 * time.Second,
	}
	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send HTTP request: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}

	// Check response status
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("FCM API returned error: status=%d, body=%s", resp.StatusCode, string(responseBody))
	}

	return nil
}

// generateAccessToken generates an OAuth2 access token from FCM service account credentials
func generateAccessToken(ctx context.Context, creds *common.FCMCredentials) (string, error) {
	// Parse RSA private key from PEM format
	block, _ := pem.Decode([]byte(creds.PrivateKey))
	if block == nil {
		return "", fmt.Errorf("failed to decode PEM block from private key")
	}

	privateKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return "", fmt.Errorf("failed to parse private key: %w", err)
	}

	rsaPrivateKey, ok := privateKey.(*rsa.PrivateKey)
	if !ok {
		return "", fmt.Errorf("private key is not RSA")
	}

	// Create JWT claims
	now := time.Now()
	claims := jwt.MapClaims{
		"iss":   creds.ClientEmail,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   creds.TokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(1 * time.Hour).Unix(),
	}

	// Create and sign JWT
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = creds.PrivateKeyID

	jwtString, err := token.SignedString(rsaPrivateKey)
	if err != nil {
		return "", fmt.Errorf("failed to sign JWT: %w", err)
	}

	// Exchange JWT for access token
	data := url.Values{}
	data.Set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer")
	data.Set("assertion", jwtString)

	req, err := http.NewRequestWithContext(ctx, "POST", creds.TokenURI, strings.NewReader(data.Encode()))
	if err != nil {
		return "", fmt.Errorf("failed to create token request: %w", err)
	}

	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to request access token: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("failed to get access token: status=%d, body=%s", resp.StatusCode, string(body))
	}

	// Parse response
	var tokenResponse struct {
		AccessToken string `json:"access_token"`
		TokenType   string `json:"token_type"`
		ExpiresIn   int    `json:"expires_in"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&tokenResponse); err != nil {
		return "", fmt.Errorf("failed to decode token response: %w", err)
	}

	return tokenResponse.AccessToken, nil
}
