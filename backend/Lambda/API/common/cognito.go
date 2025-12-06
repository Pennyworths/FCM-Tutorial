package common

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
)

// CognitoUserInfo contains user information extracted from Cognito token claims
type CognitoUserInfo struct {
	UserID string // Cognito sub (user ID)
	Email  string // User email
}

// GetCognitoUserInfo extracts user information from API Gateway request context
// Returns an error if Cognito authorizer is not configured or user info is missing
func GetCognitoUserInfo(ctx context.Context, request events.APIGatewayProxyRequest) (*CognitoUserInfo, error) {
	// Check if authorizer exists
	if request.RequestContext.Authorizer == nil {
		return nil, fmt.Errorf("authorizer not configured - Cognito authentication required")
	}

	// Extract claims from authorizer
	claims, ok := request.RequestContext.Authorizer["claims"].(map[string]interface{})
	if !ok {
		return nil, fmt.Errorf("invalid authorizer claims format")
	}

	// Extract user ID (sub claim)
	sub, ok := claims["sub"].(string)
	if !ok || sub == "" {
		return nil, fmt.Errorf("missing or invalid 'sub' claim in Cognito token")
	}

	// Extract email (optional)
	email := ""
	if emailVal, ok := claims["email"].(string); ok {
		email = emailVal
	}

	return &CognitoUserInfo{
		UserID: sub,
		Email:  email,
	}, nil
}

// ValidateUserID checks if the provided user_id matches the Cognito user ID
// This prevents users from accessing other users' data
func ValidateUserID(ctx context.Context, request events.APIGatewayProxyRequest, requestedUserID string) error {
	cognitoUser, err := GetCognitoUserInfo(ctx, request)
	if err != nil {
		return err
	}

	if cognitoUser.UserID != requestedUserID {
		return fmt.Errorf("unauthorized: user_id mismatch - cannot access another user's data")
	}

	return nil
}

