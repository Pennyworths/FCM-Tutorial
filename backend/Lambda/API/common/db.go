package common

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/jackc/pgx/v5/pgxpool"
)

// GetDBConnection creates and returns a database connection using RDS configuration.
// Environment variables required:
//   - RDS_HOST: RDS instance hostname
//   - RDS_PORT: RDS instance port
//   - RDS_DB_NAME: Database name
//   - RDS_USERNAME: Database username
//   - RDS_PASSWORD_SECRET_ARN: ARN of the secret in AWS Secrets Manager that contains the DB password
//
// Returns:
//   - *pgxpool.Pool: Database connection pool instance
//   - error: Error if connection fails
func GetDBConnection() (*pgxpool.Pool, error) {
	// Read RDS connection info from environment variables
	rdsHost := os.Getenv("RDS_HOST")
	rdsPort := os.Getenv("RDS_PORT")
	rdsDBName := os.Getenv("RDS_DB_NAME")
	rdsUsername := os.Getenv("RDS_USERNAME")

	// Retrieve the RDS password from AWS Secrets Manager via RDS_PASSWORD_SECRET_ARN
	rdsPassword, err := getRDSPasswordFromSecret(context.Background())
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve RDS password from Secrets Manager: %w", err)
	}

	// Validate environment variables
	if rdsHost == "" || rdsPort == "" || rdsDBName == "" || rdsUsername == "" || rdsPassword == "" {
		return nil, fmt.Errorf("missing required RDS configuration: RDS_HOST, RDS_PORT, RDS_DB_NAME, RDS_USERNAME, RDS_PASSWORD_SECRET_ARN")
	}

	// Build PostgreSQL connection string
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=require",
		rdsHost, rdsPort, rdsUsername, rdsPassword, rdsDBName)

	// Parse connection string and create config
	config, err := pgxpool.ParseConfig(connStr)
	if err != nil {
		return nil, fmt.Errorf("failed to parse connection string: %w", err)
	}

	// Set connection pool settings for Lambda
	// Lambda functions typically need only 1 connection per instance
	config.MaxConns = 1
	config.MinConns = 1

	// Create connection pool
	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// Test connection
	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return pool, nil
}

// getRDSPasswordFromSecret retrieves the RDS password from AWS Secrets Manager.
// It expects the environment variable RDS_PASSWORD_SECRET_ARN to contain the ARN
// of a secret whose SecretString is the plaintext database password.
func getRDSPasswordFromSecret(ctx context.Context) (string, error) {
	secretARN := os.Getenv("RDS_PASSWORD_SECRET_ARN")
	if secretARN == "" {
		return "", fmt.Errorf("RDS_PASSWORD_SECRET_ARN environment variable is not set")
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

	return *result.SecretString, nil
}

// CloseDBConnection closes the database connection pool.
func CloseDBConnection(pool *pgxpool.Pool) error {
	if pool == nil {
		return nil
	}
	pool.Close()
	return nil
}
