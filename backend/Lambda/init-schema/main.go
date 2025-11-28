package main

import (
	"context"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
	dbgen "github.com/fcm-tutorial/lambda/init-schema/sqlc"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	lambda.Start(handler)
}

func handler(ctx context.Context) error {
	// Get RDS connection info from environment variables
	rdsHost := os.Getenv("RDS_HOST")
	rdsPort := os.Getenv("RDS_PORT")
	rdsDBName := os.Getenv("RDS_DB_NAME")
	rdsUsername := os.Getenv("RDS_USERNAME")
	rdsPassword := os.Getenv("RDS_PASSWORD")

	if rdsHost == "" || rdsPort == "" || rdsDBName == "" || rdsUsername == "" || rdsPassword == "" {
		return fmt.Errorf("missing required RDS environment variables: RDS_HOST, RDS_PORT, RDS_DB_NAME, RDS_USERNAME, RDS_PASSWORD")
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

	return nil
}
