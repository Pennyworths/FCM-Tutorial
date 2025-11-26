package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/lambda"
	_ "github.com/lib/pq"
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

	// Connect to database
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}
	defer db.Close()

	// Test connection
	if err := db.Ping(); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	// Set connection pool settings
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)

	// Read SQL schema from file
	sqlScriptPath := "/var/task/init.sql"
	if _, err := os.Stat(sqlScriptPath); os.IsNotExist(err) {
		// Fallback: try relative path (for local testing)
		sqlScriptPath = "../../Schema/init.sql"
	}

	sqlScriptBytes, err := os.ReadFile(sqlScriptPath)
	if err != nil {
		return fmt.Errorf("failed to read SQL script from %s: %w", sqlScriptPath, err)
	}
	sqlScript := string(sqlScriptBytes)

	// Execute SQL statements in a transaction
	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Split SQL script by semicolon and process each statement
	statements := strings.Split(sqlScript, ";")
	for _, stmt := range statements {
		// Remove leading/trailing whitespace and newlines
		stmt = strings.TrimSpace(stmt)

		// Skip empty statements
		if stmt == "" {
			continue
		}

		// Remove comment lines (lines starting with --)
		lines := strings.Split(stmt, "\n")
		var cleanedLines []string
		for _, line := range lines {
			trimmedLine := strings.TrimSpace(line)
			if trimmedLine != "" && !strings.HasPrefix(trimmedLine, "--") {
				cleanedLines = append(cleanedLines, line)
			}
		}
		stmt = strings.Join(cleanedLines, "\n")
		stmt = strings.TrimSpace(stmt)

		// Skip if statement is empty after removing comments
		if stmt == "" {
			continue
		}

		// Execute the statement
		if _, err := tx.Exec(stmt); err != nil {
			return fmt.Errorf("failed to execute SQL: %w\nStatement: %s", err, stmt)
		}
	}

	// Commit the transaction
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Verify tables were created
	var tableCount int
	if err := db.QueryRow(`
		SELECT COUNT(*) 
		FROM information_schema.tables 
		WHERE table_schema = 'public' 
		AND table_name IN ('devices', 'test_runs')
	`).Scan(&tableCount); err != nil {
		return fmt.Errorf("failed to verify tables: %w", err)
	}

	if tableCount != 2 {
		return fmt.Errorf("expected 2 tables in public schema, but found %d", tableCount)
	}

	return nil
}
