package common

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

// FCMCredentials represents the FCM service account JSON structure.
type FCMCredentials struct {
	Type                    string `json:"type"`
	ProjectID               string `json:"project_id"`
	PrivateKeyID            string `json:"private_key_id"`
	PrivateKey              string `json:"private_key"`
	ClientEmail             string `json:"client_email"`
	ClientID                string `json:"client_id"`
	AuthURI                 string `json:"auth_uri"`
	TokenURI                string `json:"token_uri"`
	AuthProviderX509CertURL string `json:"auth_provider_x509_cert_url"`
	ClientX509CertURL       string `json:"client_x509_cert_url"`
	UniverseDomain          string `json:"universe_domain"`
}

// GetFCMCredentials retrieves FCM service account JSON from AWS Secrets Manager.
// Environment variable required:
//   - SECRET_ARN: ARN of the secret in Secrets Manager
//
// Returns:
//   - *FCMCredentials: Parsed FCM credentials
//   - error: Error if retrieval or parsing fails
func GetFCMCredentials(ctx context.Context) (*FCMCredentials, error) {
	// Read SECRET_ARN from environment variable
	secretARN := os.Getenv("SECRET_ARN")
	if secretARN == "" {
		return nil, fmt.Errorf("SECRET_ARN environment variable is not set")
	}

	// Get AWS region from environment variable (default to us-east-1)
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	// Load AWS SDK config
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS config: %w", err)
	}

	// Create Secrets Manager client
	svc := secretsmanager.NewFromConfig(cfg)

	// Call GetSecretValue with SECRET_ARN
	input := &secretsmanager.GetSecretValueInput{
		SecretId:     aws.String(secretARN),
		VersionStage: aws.String("AWSCURRENT"), // VersionStage defaults to AWSCURRENT if unspecified
	}

	result, err := svc.GetSecretValue(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("failed to get secret value: %w", err)
	}

	// Decrypts secret using the associated KMS key
	secretString := *result.SecretString

	// Parse JSON response into FCMCredentials struct
	var creds FCMCredentials
	if err := json.Unmarshal([]byte(secretString), &creds); err != nil {
		return nil, fmt.Errorf("failed to parse secret JSON: %w", err)
	}

	// Validate required fields
	if creds.ProjectID == "" || creds.PrivateKey == "" || creds.ClientEmail == "" {
		return nil, fmt.Errorf("invalid FCM credentials: missing required fields")
	}

	return &creds, nil
}
