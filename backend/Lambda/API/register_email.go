package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/fcm-tutorial/lambda/api/common"
	"github.com/fcm-tutorial/lambda/api/sqlc"
	"github.com/jackc/pgx/v5"
)

type RegisterEmailRequest struct {
	Email    string `json:"email"`
	DeviceId string `json:"device_id"`
	FcmToken string `json:"fcm_token"`
	Platform string `json:"platform"`
}

type RegisterEmailResponse struct {
	OK     bool   `json:"ok"`
	UserID string `json:"user_id,omitempty"`
}

// generateUserID generates a deterministic user_id from email
func generateUserID(email string) string {
	hash := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	return "user_" + hex.EncodeToString(hash[:])[:16] // Use first 16 chars of hash
}

// RegisterEmailHandler is the Lambda handler for email-based registration
func RegisterEmailHandler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	logger := common.NewLogger()
	logger.Info(ctx, "Received email-based registration request")

	// Parse request body
	var registerEmailRequest RegisterEmailRequest
	if errorResp := logger.ParseRequestBody(ctx, request.Body, &registerEmailRequest); errorResp != nil {
		return logger.BadRequest(ctx, nil, "Invalid request body")
	}

	// Validate required fields
	if registerEmailRequest.Email == "" || registerEmailRequest.DeviceId == "" ||
		registerEmailRequest.FcmToken == "" || registerEmailRequest.Platform == "" {
		err := fmt.Errorf("missing required fields: email, device_id, fcm_token, platform")
		return logger.BadRequest(ctx, err, "Missing required fields")
	}

	// Basic email validation
	email := strings.ToLower(strings.TrimSpace(registerEmailRequest.Email))
	if !strings.Contains(email, "@") {
		err := fmt.Errorf("invalid email format: %s", email)
		return logger.BadRequest(ctx, err, "Invalid email format")
	}

	// Validate platform must be "android" or "ios"
	validPlatforms := map[string]bool{
		"android": true,
		"ios":     true,
	}
	if !validPlatforms[registerEmailRequest.Platform] {
		err := fmt.Errorf("invalid platform: %s (must be 'android' or 'ios')", registerEmailRequest.Platform)
		return logger.BadRequest(ctx, err, "Platform must be 'android' or 'ios'")
	}

	// Get database connection
	db, err := common.GetDBConnection()
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database connection failed")
	}
	defer common.CloseDBConnection(db)

	// Start database transaction
	tx, err := db.Begin(ctx)
	if err != nil {
		return logger.InternalServerError(ctx, err, "Failed to start transaction")
	}
	defer tx.Rollback(ctx) // Rollback if not committed

	queries := sqlc.New(db).WithTx(tx)

	// Step 1: Get or create user by email
	var userID string
	existingUser, err := queries.GetUserByEmail(ctx, email)
	if err == nil {
		// User exists, use existing user_id
		userID = existingUser.UserID
		logger.Info(ctx, "User found: email=%s, user_id=%s", email, userID)
	} else if errors.Is(err, pgx.ErrNoRows) {
		// User doesn't exist, create new user
		// Generate deterministic user_id from email
		userID = generateUserID(email)

		// Try to upsert user (in case of race condition)
		user, err := queries.UpsertUserByEmail(ctx, sqlc.UpsertUserByEmailParams{
			Email:  email,
			UserID: userID,
		})
		if err != nil {
			// If upsert failed (e.g., unique constraint violation), try to get the user again
			// (might have been created by another concurrent request)
			existingUser, getErr := queries.GetUserByEmail(ctx, email)
			if getErr != nil {
				return logger.InternalServerError(ctx, err, "Failed to create user")
			}
			userID = existingUser.UserID
		} else {
			userID = user.UserID
		}
		logger.Info(ctx, "User created: email=%s, user_id=%s", email, userID)
	} else {
		// Other database error
		return logger.InternalServerError(ctx, err, "Database query failed")
	}

	// Step 2: Check if device_id already exists with a different user_id
	existingDevice, err := queries.GetDeviceByDeviceID(ctx, registerEmailRequest.DeviceId)
	if err == nil {
		// Device exists, check if it belongs to a different user
		if existingDevice.UserID != userID {
			err := fmt.Errorf("device_id '%s' already registered to user '%s'", registerEmailRequest.DeviceId, existingDevice.UserID)
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

	// Step 3: Upsert device record
	err = queries.UpsertDevice(ctx, sqlc.UpsertDeviceParams{
		UserID:   userID,
		DeviceID: registerEmailRequest.DeviceId,
		Platform: registerEmailRequest.Platform,
		FcmToken: registerEmailRequest.FcmToken,
	})
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database operation failed")
	}

	// Step 4: Send event to Klaviyo
	// Prepare Klaviyo event properties
	klaviyoProperties := map[string]interface{}{
		"result":         "success",
		"application_id": registerEmailRequest.DeviceId,
		"loan_amount":    0, // You can customize this based on your needs
	}

	klaviyoSuccess, err := common.SendKlaviyoEvent(ctx, email, klaviyoProperties)
	if err != nil {
		logger.Error(ctx, err, "Failed to send Klaviyo event")
		// Klaviyo failed, registration should fail
		return logger.InternalServerError(ctx, err, "Registration failed: Klaviyo event not sent")
	}

	if !klaviyoSuccess {
		// Klaviyo returned failure
		err := fmt.Errorf("Klaviyo event returned failure")
		logger.Error(ctx, err, "Klaviyo event failed")
		return logger.InternalServerError(ctx, err, "Registration failed: Klaviyo event not successful")
	}

	// Step 5: Commit transaction (only if Klaviyo succeeded)
	if err := tx.Commit(ctx); err != nil {
		return logger.InternalServerError(ctx, err, "Failed to commit transaction")
	}

	logger.Info(ctx, "Registration successful: email=%s, user_id=%s, device_id=%s, Klaviyo event sent",
		email, userID, registerEmailRequest.DeviceId)

	// Prepare success response
	response := RegisterEmailResponse{
		OK:     true,
		UserID: userID,
	}

	return logger.Success(ctx, response)
}
