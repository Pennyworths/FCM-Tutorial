package common

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

// GetDBConnection creates and returns a database connection using RDS environment variables.
// Environment variables required:
//   - RDS_HOST: RDS instance hostname
//   - RDS_PORT: RDS instance port
//   - RDS_DB_NAME: Database name
//   - RDS_USERNAME: Database username
//   - RDS_PASSWORD: Database password
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
	rdsPassword := os.Getenv("RDS_PASSWORD")

	// Validate environment variables
	if rdsHost == "" || rdsPort == "" || rdsDBName == "" || rdsUsername == "" || rdsPassword == "" {
		return nil, fmt.Errorf("missing required RDS environment variables: RDS_HOST, RDS_PORT, RDS_DB_NAME, RDS_USERNAME, RDS_PASSWORD")
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

// CloseDBConnection closes the database connection pool.
func CloseDBConnection(pool *pgxpool.Pool) error {
	if pool == nil {
		return nil
	}
	pool.Close()
	return nil
}
