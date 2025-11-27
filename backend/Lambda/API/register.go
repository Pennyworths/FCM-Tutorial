package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/fcm-tutorial/lambda/api/common"
	"github.com/fcm-tutorial/lambda/api/sqlc"
	"github.com/jackc/pgx/v5"
)

type RegisterDeviceRequest struct {
	UserId   string `json:"user_id"`
	DeviceId string `json:"device_id"`
	FcmToken string `json:"fcm_token"`
	Platform string `json:"platform"`
}

type RegisterDeviceResponse struct {
	Success   bool   `json:"success"`
	Message   string `json:"message"`
	RequestId string `json:"request_id"`
}

// RegisterDeviceHandler is the Lambda handler for device registration
func RegisterDeviceHandler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	logger := common.NewLogger()
	logger.Info(ctx, "Received device registration request")

	// Parse request body
	var registerDeviceRequest RegisterDeviceRequest
	if err := json.Unmarshal([]byte(request.Body), &registerDeviceRequest); err != nil {
		logger.Error(ctx, err, "Failed to parse request body")
		errorResp := logger.HandleError(ctx, err, "Invalid request body")
		return events.APIGatewayProxyResponse{
			StatusCode: 400,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       errorResp.ToJSON(),
		}, nil
	}

	// Validate required fields
	if registerDeviceRequest.UserId == "" || registerDeviceRequest.DeviceId == "" ||
		registerDeviceRequest.FcmToken == "" || registerDeviceRequest.Platform == "" {
		err := fmt.Errorf("missing required fields: user_id, device_id, fcm_token, platform")
		logger.Error(ctx, err, "Validation failed")
		errorResp := logger.HandleError(ctx, err, "Missing required fields")
		return events.APIGatewayProxyResponse{
			StatusCode: 400,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       errorResp.ToJSON(),
		}, nil
	}

	// Validate platform must be "android" or "ios"
	validPlatforms := map[string]bool{
		"android": true,
		"ios":     true,
	}
	if !validPlatforms[registerDeviceRequest.Platform] {
		err := fmt.Errorf("invalid platform: %s (must be 'android' or 'ios')", registerDeviceRequest.Platform)
		logger.Error(ctx, err, "Validation failed")
		errorResp := logger.HandleError(ctx, err, "Platform must be 'android' or 'ios'")
		return events.APIGatewayProxyResponse{
			StatusCode: 400,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       errorResp.ToJSON(),
		}, nil
	}

	// Get database connection
	db, err := common.GetDBConnection()
	if err != nil {
		logger.Error(ctx, err, "Failed to connect to database")
		errorResp := logger.HandleError(ctx, err, "Database connection failed")
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       errorResp.ToJSON(),
		}, nil
	}
	defer common.CloseDBConnection(db)

	// Check if device_id already exists with a different user_id
	// device_id should be globally unique (one device can only belong to one user)
	// Using raw SQL query until sqlc generates GetDeviceByDeviceID method
	var existingUserID string
	checkQuery := "SELECT user_id FROM devices WHERE device_id = $1 LIMIT 1"
	err = db.QueryRow(ctx, checkQuery, registerDeviceRequest.DeviceId).Scan(&existingUserID)
	if err == nil {
		// Device exists, check if it belongs to a different user
		if existingUserID != registerDeviceRequest.UserId {
			err := fmt.Errorf("device_id '%s' already registered to user '%s'", registerDeviceRequest.DeviceId, existingUserID)
			logger.Error(ctx, err, "Device already belongs to another user")
			errorResp := logger.HandleError(ctx, err, "Device already registered to another user")
			return events.APIGatewayProxyResponse{
				StatusCode: 409, // Conflict
				Headers:    map[string]string{"Content-Type": "application/json"},
				Body:       errorResp.ToJSON(),
			}, nil
		}
		// Device exists and belongs to the same user, will be updated by UPSERT
		logger.Info(ctx, "Device exists for same user, will update")
	} else if errors.Is(err, pgx.ErrNoRows) {
		// Device not found - this is OK, we'll insert it
		logger.Info(ctx, "Device not found, will insert new record")
	} else {
		// Other database error
		logger.Error(ctx, err, "Failed to check existing device")
		errorResp := logger.HandleError(ctx, err, "Database query failed")
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       errorResp.ToJSON(),
		}, nil
	}

	// Upsert device record using sqlc
	// Database has UNIQUE constraint on (user_id, device_id)
	// - If (user_id, device_id) combination exists: update fcm_token, is_active = TRUE, updated_at = NOW()
	// - If (user_id, device_id) combination does not exist: insert a new row
	queries := sqlc.New(db)
	err = queries.UpsertDevice(ctx, sqlc.UpsertDeviceParams{
		UserID:   registerDeviceRequest.UserId,
		DeviceID: registerDeviceRequest.DeviceId,
		Platform: registerDeviceRequest.Platform,
		FcmToken: registerDeviceRequest.FcmToken,
	})
	if err != nil {
		logger.Error(ctx, err, "Failed to upsert device record")
		errorResp := logger.HandleError(ctx, err, "Database operation failed")
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       errorResp.ToJSON(),
		}, nil
	}

	logger.Info(ctx, "Device registered successfully: user_id=%s, device_id=%s",
		registerDeviceRequest.UserId, registerDeviceRequest.DeviceId)

	// Prepare success response
	response := RegisterDeviceResponse{
		Success:   true,
		Message:   "Device registered successfully",
		RequestId: request.RequestContext.RequestID,
	}

	responseBody, err := json.Marshal(response)
	if err != nil {
		logger.Error(ctx, err, "Failed to marshal response")
		errorResp := logger.HandleError(ctx, err, "Failed to create response")
		return events.APIGatewayProxyResponse{
			StatusCode: 500,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       errorResp.ToJSON(),
		}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(responseBody),
	}, nil
}
