#!/bin/bash
set -e

# Simple migration instance setup
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/migration-setup.log; }

log "Starting migration instance setup..."

# Update system
yum update -y

# Install essential packages
yum install -y git jq python3 python3-pip unzip wget curl vim htop tree amazon-ssm-agent

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Go migrate
curl -L "https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VERSION}/migrate.linux-amd64.tar.gz" -o /tmp/migrate.tar.gz
tar -xzf /tmp/migrate.tar.gz -C /tmp
mv /tmp/migrate /usr/local/bin/
chmod +x /usr/local/bin/migrate
rm -f /tmp/migrate.tar.gz

# Install PostgreSQL 15 client (to match Aurora version)
log "Installing PostgreSQL 15 client..."
cd /tmp
curl -LO https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-7-x86_64/postgresql15-libs-15.12-1PGDG.rhel7.x86_64.rpm
curl -LO https://download.postgresql.org/pub/repos/yum/15/redhat/rhel-7-x86_64/postgresql15-15.12-1PGDG.rhel7.x86_64.rpm
rpm -ivh --nodeps postgresql15-libs-15.12-1PGDG.rhel7.x86_64.rpm postgresql15-15.12-1PGDG.rhel7.x86_64.rpm
rm -f postgresql15-*.rpm

# Create symlinks for PostgreSQL 15 binaries
ln -sf /usr/pgsql-15/bin/psql /usr/local/bin/psql
ln -sf /usr/pgsql-15/bin/pg_dump /usr/local/bin/pg_dump
ln -sf /usr/pgsql-15/bin/pg_restore /usr/local/bin/pg_restore
log "PostgreSQL 15 client installed: $(pg_dump --version)"

# Configure SSM agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Install Python packages
pip3 install boto3 psycopg2-binary PyYAML click tabulate

# Create migration user and directories
useradd -m -s /bin/bash migration
mkdir -p /home/migration/{scripts,sql,config,logs}
chown -R migration:migration /home/migration
mkdir -p /opt/migrations/{scripts,sql,config,logs,migrate}
chmod 755 /opt/migrations

# Note: Migration files should be uploaded via SSM after instance creation
# Migration files are located in: backend/migrations/migrate/
# Use SSM Session Manager to connect and upload files, or use scripts from backend/migrations/
log "Migration directory created at /opt/migrations/migrate/"
log "Migration files should be uploaded via SSM Session Manager after instance creation"

# Create basic configuration
cat > /opt/migrations/config/migration-config.yaml << EOF
database:
  host: ${database_host}
  port: 5432
  name: ${database_name}
  engine: postgresql
  ssl_mode: require
  secret_arn: ${database_secret_arn}
migrations:
  directory: ./migrate
  table_name: schema_migrations
  timeout_minutes: 30
logging:
  level: info
  file: ./logs/migrations.log
EOF

# Create migration script that accepts commands (up, down, version, etc.)
cat > /opt/migrations/scripts/run-migrations.sh << 'EOF'
#!/bin/bash
set -e
PROJECT_ROOT="/opt/migrations"
CONFIG_FILE="$PROJECT_ROOT/config/migration-config.yaml"
LOG_FILE="$PROJECT_ROOT/logs/migrations.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Accept migrate command as argument, default to "up"
MIGRATE_CMD="$${@:-up}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

DATABASE_HOST=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "host:" | awk '{print $2}')
DATABASE_PORT=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "port:" | awk '{print $2}')
DATABASE_NAME=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "name:" | awk '{print $2}')

log "Retrieving database credentials from Secrets Manager..."
SECRET_ARN=$(grep -A 10 "database:" "$CONFIG_FILE" | grep "secret_arn:" | awk '{print $2}')
if [[ -z "$SECRET_ARN" ]]; then
    log "ERROR: Database secret ARN not found in configuration"
    exit 1
fi
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text)
DB_USERNAME=$(echo "$SECRET_VALUE" | jq -r '.username')
DB_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

DATABASE_URL="postgres://$${DB_USERNAME}:$${DB_PASSWORD}@$${DATABASE_HOST}:$${DATABASE_PORT}/$${DATABASE_NAME}?sslmode=require"

log "Running Go migrate command: $MIGRATE_CMD"
cd "$PROJECT_ROOT"

if migrate -path ./migrate -database "$DATABASE_URL" $MIGRATE_CMD; then
    log "Migration command '$MIGRATE_CMD' completed successfully!"
else
    log "ERROR: Migration command '$MIGRATE_CMD' failed"
    exit 1
fi
EOF

chmod +x /opt/migrations/scripts/run-migrations.sh

# Create connection script
cat > /opt/migrations/scripts/connect-to-db.sh << 'EOF'
#!/bin/bash
set -e
PROJECT_ROOT="/opt/migrations"
CONFIG_FILE="$PROJECT_ROOT/config/migration-config.yaml"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

DATABASE_HOST=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "host:" | awk '{print $2}')
DATABASE_PORT=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "port:" | awk '{print $2}')
DATABASE_NAME=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "name:" | awk '{print $2}')

SECRET_ARN=$(grep -A 10 "database:" "$CONFIG_FILE" | grep "secret_arn:" | awk '{print $2}')
if [[ -z "$SECRET_ARN" ]]; then
    echo "ERROR: Database secret ARN not found in configuration"
    exit 1
fi
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text)
DB_USERNAME=$(echo "$SECRET_VALUE" | jq -r '.username')
DB_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

echo "Connecting to database: $${DATABASE_HOST}:$${DATABASE_PORT}/$${DATABASE_NAME}"
PGPASSWORD="$${DB_PASSWORD}" psql -h "$${DATABASE_HOST}" -p "$${DATABASE_PORT}" -U "$${DB_USERNAME}" -d "$${DATABASE_NAME}"
EOF

chmod +x /opt/migrations/scripts/connect-to-db.sh

# Create backup script
cat > /opt/migrations/scripts/backup-db.sh << 'EOF'
#!/bin/bash
set -e
PROJECT_ROOT="/opt/migrations"
CONFIG_FILE="$PROJECT_ROOT/config/migration-config.yaml"
BACKUP_DIR="/tmp"

# Parse arguments
BACKUP_FILENAME="$${1:-backup_$(date +%Y%m%d_%H%M%S).sql}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

DATABASE_HOST=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "host:" | awk '{print $2}')
DATABASE_PORT=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "port:" | awk '{print $2}')
DATABASE_NAME=$(grep -A 5 "database:" "$CONFIG_FILE" | grep "name:" | awk '{print $2}')

SECRET_ARN=$(grep -A 10 "database:" "$CONFIG_FILE" | grep "secret_arn:" | awk '{print $2}')
if [[ -z "$SECRET_ARN" ]]; then
    echo "ERROR: Database secret ARN not found in configuration"
    exit 1
fi
SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text)
DB_USERNAME=$(echo "$SECRET_VALUE" | jq -r '.username')
DB_PASSWORD=$(echo "$SECRET_VALUE" | jq -r '.password')

echo "Creating backup: $BACKUP_FILENAME"
PGPASSWORD="$${DB_PASSWORD}" pg_dump -h "$${DATABASE_HOST}" -p "$${DATABASE_PORT}" -U "$${DB_USERNAME}" -d "$${DATABASE_NAME}" > "$BACKUP_DIR/$BACKUP_FILENAME"

echo "Backup created: $BACKUP_DIR/$BACKUP_FILENAME"
echo "Size: $(du -h "$BACKUP_DIR/$BACKUP_FILENAME" | cut -f1)"
EOF

chmod +x /opt/migrations/scripts/backup-db.sh

# Set proper permissions
chown -R migration:migration /opt/migrations

# Create welcome message
cat > /etc/motd << 'EOF'
===========================================
   FCM Tutorial - Migration Instance
===========================================
This instance is configured for database migrations using SSM Session Manager.

Available commands:
- /opt/migrations/scripts/run-migrations.sh [command]
    Commands: up (default), down, down N, version, force N, goto N
    Examples:
      ./run-migrations.sh          # Run all pending migrations
      ./run-migrations.sh down     # Rollback all migrations
      ./run-migrations.sh down 1   # Rollback 1 migration
      ./run-migrations.sh version  # Check current version
- /opt/migrations/scripts/connect-to-db.sh
- /opt/migrations/scripts/backup-db.sh [filename]

Migration files: /opt/migrations/migrate/
Configuration: /opt/migrations/config/
Logs: /opt/migrations/logs/
===========================================
EOF

log "Migration instance setup completed successfully!"
log "Instance is ready for database migrations via SSM Session Manager"
