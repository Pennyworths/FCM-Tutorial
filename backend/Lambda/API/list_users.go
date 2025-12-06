package main

import (
	"context"

	"github.com/aws/aws-lambda-go/events"
	"github.com/fcm-tutorial/lambda/api/common"
)

type ListUsersResponse struct {
	OK    bool     `json:"ok"`
	Users []string `json:"users"`
	Count int      `json:"count"`
}

// ListUsersHandler is the Lambda handler for listing all users
func ListUsersHandler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	logger := common.NewLogger()
	logger.Info(ctx, "Received list users request")

	// Extract Cognito user information (authentication required)
	cognitoUser, err := common.GetCognitoUserInfo(ctx, request)
	if err != nil {
		return logger.Unauthorized(ctx, err, "Authentication required: Cognito user information not found")
	}

	logger.Info(ctx, "Authenticated user: %s requesting user list", cognitoUser.UserID)

	// Get database connection
	db, err := common.GetDBConnection()
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database connection failed")
	}
	defer common.CloseDBConnection(db)

	// Query all unique user IDs from devices table
	rows, err := db.Query(ctx, "SELECT DISTINCT user_id FROM devices ORDER BY user_id")
	if err != nil {
		return logger.InternalServerError(ctx, err, "Database query failed")
	}
	defer rows.Close()

	// Extract user IDs from rows
	users := make([]string, 0)
	for rows.Next() {
		var userID string
		if err := rows.Scan(&userID); err != nil {
			return logger.InternalServerError(ctx, err, "Failed to scan user ID")
		}
		users = append(users, userID)
	}

	if err := rows.Err(); err != nil {
		return logger.InternalServerError(ctx, err, "Error iterating rows")
	}

	logger.Info(ctx, "Found %d users with registered devices", len(users))

	// Prepare response
	response := ListUsersResponse{
		OK:    true,
		Users: users,
		Count: len(users),
	}

	return logger.Success(ctx, response)
}

