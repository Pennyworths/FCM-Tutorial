package main

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	dbgen "github.com/fcm-tutorial/lambda/init-schema/sqlc"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	lambda.Start(handler)
}

// getSecret retrieves a secret value from AWS Secrets Manager
func getSecret(ctx context.Context, secretARN string) (string, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to load AWS config: %w", err)
	}

	client := secretsmanager.NewFromConfig(cfg)
	input := &secretsmanager.GetSecretValueInput{
		SecretId: &secretARN,
	}

	result, err := client.GetSecretValue(ctx, input)
	if err != nil {
		return "", fmt.Errorf("failed to get secret value: %w", err)
	}

	if result.SecretString == nil {
		return "", fmt.Errorf("secret value is nil")
	}

	return *result.SecretString, nil
}

func handler(ctx context.Context) error {
	// Get RDS connection info from environment variables
	rdsHost := os.Getenv("RDS_HOST")
	rdsPort := os.Getenv("RDS_PORT")
	rdsDBName := os.Getenv("RDS_DB_NAME")
	rdsUsername := os.Getenv("RDS_USERNAME")
	rdsPasswordSecretARN := os.Getenv("RDS_PASSWORD_SECRET_ARN")

	if rdsHost == "" || rdsPort == "" || rdsDBName == "" || rdsUsername == "" || rdsPasswordSecretARN == "" {
		return fmt.Errorf("missing required RDS environment variables: RDS_HOST, RDS_PORT, RDS_DB_NAME, RDS_USERNAME, RDS_PASSWORD_SECRET_ARN")
	}

	// Get RDS password from Secrets Manager
	rdsPassword, err := getSecret(ctx, rdsPasswordSecretARN)
	if err != nil {
		return fmt.Errorf("failed to retrieve RDS password from Secrets Manager: %w", err)
	}

	// Build connection string
	connStr := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=require",
		rdsHost, rdsPort, rdsUsername, rdsPassword, rdsDBName)

	// Connect to database using pgx/v5
	pool, err := pgxpool.New(ctx, connStr)
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}
	defer pool.Close()

	// Test connection
	if err := pool.Ping(ctx); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	// Read and execute SQL schema from file
	// Try multiple possible paths (Lambda container paths)
	sqlScriptPaths := []string{
		"/var/task/Schema/init.sql",
		"/var/runtime/Schema/init.sql",
		"./Schema/init.sql",
		"../../Schema/init.sql",
	}

	var sqlScript string
	var sqlScriptPath string
	for _, path := range sqlScriptPaths {
		if data, err := os.ReadFile(path); err == nil {
			sqlScript = string(data)
			sqlScriptPath = path
			break
		}
	}

	if sqlScript == "" {
		return fmt.Errorf("failed to find init.sql in any of the expected paths: %v", sqlScriptPaths)
	}

	// Execute SQL script to create tables
	// pgx can handle multiple statements
	if _, err := pool.Exec(ctx, sqlScript); err != nil {
		return fmt.Errorf("failed to execute SQL script from %s: %w", sqlScriptPath, err)
	}

	// Verify tables exist using sqlc
	queries := dbgen.New(pool)
	tableCount, err := queries.CountTables(ctx)
	if err != nil {
		return fmt.Errorf("failed to verify tables: %w", err)
	}

	if tableCount != 2 {
		return fmt.Errorf("expected 2 tables in public schema, but found %d", tableCount)
	}

	// Query and print devices table
	fmt.Println("==========================================")
	fmt.Println("Querying devices table...")
	fmt.Println("==========================================")

	rows, err := pool.Query(ctx, "SELECT id, user_id, device_id, platform, fcm_token, is_active, updated_at FROM devices ORDER BY updated_at DESC")
	if err != nil {
		return fmt.Errorf("failed to query devices: %w", err)
	}
	defer rows.Close()

	deviceCount := 0
	fmt.Printf("%-5s | %-20s | %-20s | %-10s | %-30s | %-8s | %-20s\n", 
		"ID", "User ID", "Device ID", "Platform", "FCM Token", "Active", "Updated At")
	fmt.Println("----------------------------------------------------------------------------------------------------------------------------------")

	for rows.Next() {
		var id int32
		var userID, deviceID, platform, fcmToken string
		var isActive bool
		var updatedAt pgtype.Timestamptz

		err := rows.Scan(&id, &userID, &deviceID, &platform, &fcmToken, &isActive, &updatedAt)
		if err != nil {
			fmt.Printf("Error scanning row: %v\n", err)
			continue
		}

		updatedAtStr := "N/A"
		if updatedAt.Valid {
			updatedAtStr = updatedAt.Time.Format("2006-01-02 15:04:05")
		}

		// Truncate long FCM token for display
		fcmTokenDisplay := fcmToken
		if len(fcmTokenDisplay) > 30 {
			fcmTokenDisplay = fcmTokenDisplay[:27] + "..."
		}

		fmt.Printf("%-5d | %-20s | %-20s | %-10s | %-30s | %-8v | %-20s\n",
			id, userID, deviceID, platform, fcmTokenDisplay, isActive, updatedAtStr)
		deviceCount++
	}

	if err := rows.Err(); err != nil {
		return fmt.Errorf("error iterating rows: %w", err)
	}

	fmt.Println("----------------------------------------------------------------------------------------------------------------------------------")
	fmt.Printf("Total devices: %d\n", deviceCount)
	fmt.Println("==========================================")

	return nil
}
