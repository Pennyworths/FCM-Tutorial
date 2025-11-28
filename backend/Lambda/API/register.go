package main

import (
	"context"
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
	OK bool `json:"ok"`
}

// RegisterDeviceHandler is the Lambda handler for device registration
func RegisterDeviceHandler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	logger := common.NewLogger()
	logger.Info(ctx, "Received device registration request")

	// Parse request body
	var registerDeviceRequest RegisterDeviceRequest
	if errorResp := logger.ParseRequestBody(ctx, request.Body, &registerDeviceRequest); errorResp != nil {
		return logger.BadRequest(ctx, nil, "Invalid request body")
	}

	// Validate required fields
	if registerDeviceRequest.UserId == "" || registerDeviceRequest.DeviceId == "" ||
		registerDeviceRequest.FcmToken == "" || registerDeviceRequest.Platform == "" {
		err := fmt.Errorf("missing required fields: user_id, device_id, fcm_token, platform")
		return logger.BadRequest(ctx, err, "Missing required fields")
	}

	// Validate platform must be "android" or "ios"
	validPlatforms := map[string]bool{
		"android": true,
		"ios":     true,
	}
	if !validPlatforms[registerDeviceRequest.Platform] {
		err := fmt.Errorf("invalid platform: %s (must be 'android' or 'ios')", registerDeviceRequest.Platform)
		return logger.BadRequest(ctx, err, "Platform must be 'android' or 'ios'")
	}

	// Get database connection
	db, err := common.GetDBConnection()
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database connection failed")
	}
	defer common.CloseDBConnection(db)

	// Check if device_id already exists with a different user_id
	// device_id should be globally unique (one device can only belong to one user)
	queries := sqlc.New(db)
	existingDevice, err := queries.GetDeviceByDeviceID(ctx, registerDeviceRequest.DeviceId)
	if err == nil {
		// Device exists, check if it belongs to a different user
		if existingDevice.UserID != registerDeviceRequest.UserId {
			err := fmt.Errorf("device_id '%s' already registered to user '%s'", registerDeviceRequest.DeviceId, existingDevice.UserID)
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
		return logger.InternalServerError(ctx, err, "Database query failed")
	}

	// Upsert device record using sqlc
	// Database has UNIQUE constraint on (user_id, device_id)
	// - If (user_id, device_id) combination exists: update fcm_token, is_active = TRUE, updated_at = NOW()
	// - If (user_id, device_id) combination does not exist: insert a new row
	err = queries.UpsertDevice(ctx, sqlc.UpsertDeviceParams{
		UserID:   registerDeviceRequest.UserId,
		DeviceID: registerDeviceRequest.DeviceId,
		Platform: registerDeviceRequest.Platform,
		FcmToken: registerDeviceRequest.FcmToken,
	})
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database operation failed")
	}

	logger.Info(ctx, "Device registered successfully: user_id=%s, device_id=%s",
		registerDeviceRequest.UserId, registerDeviceRequest.DeviceId)

	// Prepare success response (README requires: { "ok": true })
	response := RegisterDeviceResponse{
		OK: true,
	}

	return logger.Success(ctx, response)
}
