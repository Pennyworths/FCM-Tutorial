package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/fcm-tutorial/lambda/api/common"
	"github.com/fcm-tutorial/lambda/api/sqlc"
	"github.com/jackc/pgx/v5"
)

type StatusResponse struct {
	Nonce   string     `json:"nonce"`
	Status  string     `json:"status"`
	AckedAt *time.Time `json:"acked_at,omitempty"` // Omit if nil (PENDING status)
}

// TestStatusHandler is the Lambda handler for querying test run status
func TestStatusHandler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	logger := common.NewLogger()
	logger.Info(ctx, "Received test status request")

	// GET request: get nonce from query string parameters
	nonce := ""
	if request.QueryStringParameters != nil {
		nonce = request.QueryStringParameters["nonce"]
	}

	// Validate nonce
	if nonce == "" {
		err := fmt.Errorf("missing required query parameter: nonce")
		return logger.BadRequest(ctx, err, "Missing required query parameter: nonce")
	}

	// Get database connection
	db, err := common.GetDBConnection()
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database connection failed")
	}
	defer common.CloseDBConnection(db)

	// Query test run by nonce
	queries := sqlc.New(db)
	testRun, err := queries.GetTestRunByNonce(ctx, nonce)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// nonce not found → 404
			err := fmt.Errorf("test run not found: nonce=%s", nonce)
			return logger.NotFound(ctx, err, "Test run not found")
		}
		// Other database errors → 500
		return logger.InternalServerError(ctx, err, "Database query failed")
	}

	// Note: User verification removed (Cognito authentication disabled)

	// Build response
	response := StatusResponse{
		Nonce:  testRun.Nonce,
		Status: testRun.Status,
	}

	// Only include acked_at if status is ACKED and acked_at is valid
	if testRun.Status == "ACKED" && testRun.AckedAt.Valid {
		ackedAt := testRun.AckedAt.Time
		response.AckedAt = &ackedAt
	}

	logger.Info(ctx, "Test run status queried: nonce=%s, status=%s", nonce, testRun.Status)

	return logger.Success(ctx, response)
}
