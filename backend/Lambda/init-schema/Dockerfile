# Build stage
FROM golang:1.23-alpine AS builder

# Install sqlc
RUN go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest

# Set working directory
WORKDIR /build

# Copy Schema directory first (needed for sqlc)
COPY Schema/ ./Schema/

# Copy go mod files
COPY Lambda/init-schema/go.mod Lambda/init-schema/go.sum ./
RUN go mod download

# Copy source code
COPY Lambda/init-schema/ ./

# Generate sqlc code
RUN sqlc generate

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o bootstrap .

# Runtime stage
FROM public.ecr.aws/lambda/provided:al2023

# Copy the binary from builder
# Lambda provided runtime entrypoint script (/lambda-entrypoint.sh) 
# hardcodes RUNTIME_ENTRYPOINT=/var/runtime/bootstrap
# So we need to place bootstrap at /var/runtime/bootstrap
COPY --from=builder /build/bootstrap /var/runtime/bootstrap
RUN chmod 755 /var/runtime/bootstrap

# Also copy to /var/task/bootstrap for compatibility
COPY --from=builder /build/bootstrap /var/task/bootstrap
RUN chmod 755 /var/task/bootstrap

# Copy Schema directory to runtime (needed for init.sql)
COPY --from=builder /build/Schema /var/task/Schema

# Set the CMD to your handler
# The entrypoint script expects the handler name as first argument
CMD ["bootstrap"]

