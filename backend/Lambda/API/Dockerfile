# Build stage
FROM golang:1.23-alpine AS builder

# Install sqlc
RUN go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest

# Set working directory
WORKDIR /build

# Copy Schema directory (build context should be backend/ to access Schema/)
# This matches local dev structure: backend/Schema/init.sql
COPY Schema/ ./Schema/

# Copy Lambda/API to maintain directory structure matching local dev
# This creates /build/Lambda/API/ structure
COPY Lambda/API/ ./Lambda/API/

# Set working directory to Lambda/API for sqlc and build
WORKDIR /build/Lambda/API

# Copy go mod files to current directory
COPY Lambda/API/go.mod Lambda/API/go.sum ./
RUN go mod download

# Generate sqlc code
# sqlc.yaml is at /build/Lambda/API/sqlc.yaml
# ../../Schema/init.sql resolves to /build/Schema/init.sql ✅
RUN sqlc generate

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o bootstrap .

# Runtime stage
FROM public.ecr.aws/lambda/provided:al2023

# Accept LAMBDA_HANDLER as build argument
# This allows each function to have its own image with default handler
ARG LAMBDA_HANDLER="RegisterDeviceHandler"

# Copy the binary from builder
# Lambda provided runtime entrypoint script (/lambda-entrypoint.sh)
# hardcodes RUNTIME_ENTRYPOINT=/var/runtime/bootstrap
# So we need to place bootstrap at /var/runtime/bootstrap
COPY --from=builder /build/Lambda/API/bootstrap /var/runtime/bootstrap
RUN chmod 755 /var/runtime/bootstrap

# Also copy to /var/task/bootstrap for compatibility
COPY --from=builder /build/Lambda/API/bootstrap /var/task/bootstrap
RUN chmod 755 /var/task/bootstrap

# Set default LAMBDA_HANDLER environment variable
# Each image will have its own default handler
ENV LAMBDA_HANDLER=${LAMBDA_HANDLER}

# Set the CMD to your handler
# The entrypoint script expects the handler name as first argument
CMD ["bootstrap"]

