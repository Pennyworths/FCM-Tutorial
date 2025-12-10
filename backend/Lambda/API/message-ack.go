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

type MessageAckRequest struct {
	Nonce string `json:"nonce"`
}

type MessageAckResponse struct {
	OK bool `json:"ok"`
}

// MessageAckHandler is the Lambda handler for message acknowledgment
// Similar to TestAckHandler but for non-e2e_test messages
func MessageAckHandler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	logger := common.NewLogger()
	logger.Info(ctx, "Received message ack request")

	// Parse request body
	var ackRequest MessageAckRequest
	if errorResp := logger.ParseRequestBody(ctx, request.Body, &ackRequest); errorResp != nil {
		return logger.BadRequest(ctx, nil, "Invalid request body")
	}

	// Validate required fields
	if ackRequest.Nonce == "" {
		err := fmt.Errorf("missing required field: nonce")
		return logger.BadRequest(ctx, err, "Missing required field: nonce")
	}

	// Get database connection
	db, err := common.GetDBConnection()
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database connection failed")
	}
	defer common.CloseDBConnection(db)

	// Update test run status to ACKED
	// This will only update if nonce exists AND status is 'PENDING'
	// If nonce doesn't exist or already ACKED, returns pgx.ErrNoRows
	queries := sqlc.New(db)
	_, err = queries.AckTestRun(ctx, ackRequest.Nonce)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// nonce not found or already ACKED → 404
			err := fmt.Errorf("message run not found or already acknowledged: nonce=%s", ackRequest.Nonce)
			return logger.NotFound(ctx, err, "Message run not found or already acknowledged")
		}
		// Other database errors → 500
		return logger.InternalServerError(ctx, err, "Database operation failed")
	}

	logger.Info(ctx, "Message run acknowledged successfully: nonce=%s", ackRequest.Nonce)

	// Prepare success response
	response := MessageAckResponse{
		OK: true,
	}

	return logger.Success(ctx, response)
}
