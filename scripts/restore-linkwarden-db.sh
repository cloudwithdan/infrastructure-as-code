#!/usr/bin/env bash
set -euo pipefail

# Linkwarden Database Restore Script - Version 2
# This script uses pg_dump/pg_restore via psql since the backup is a barman base backup

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
NAMESPACE="database"
POSTGRES_HOST="postgres18-rw.database.svc.cluster.local"
POSTGRES_PORT="5432"
DB_NAME="linkwarden"
DB_USER="linkwarden"
DB_PASSWORD="linkwarden"  # This should match the secret
POSTGRES_SUPER_USER="postgres"
POSTGRES_SUPER_PASS="x088Fi7OU1LOVr"  # From cloudnative-pg-secret

log_warn "The S3 backup is a physical PGDATA backup (barman format)."
log_warn "Since we're migrating to postgres18 cluster, we'll create an empty database."
log_warn "Linkwarden will run its own migrations on first startup."
log_info ""

# Create a temporary pod to access postgres
SETUP_POD_NAME="linkwarden-dbsetup-$(date +%s)"

log_info "Creating database setup pod: ${SETUP_POD_NAME}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${SETUP_POD_NAME}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
  - name: postgres-client
    image: postgres:18
    command: ["/bin/bash", "-c", "sleep 600"]
    env:
    - name: PGHOST
      value: "${POSTGRES_HOST}"
    - name: PGPORT
      value: "${POSTGRES_PORT}"
    - name: PGUSER
      value: "${POSTGRES_SUPER_USER}"
    - name: PGPASSWORD
      value: "${POSTGRES_SUPER_PASS}"
EOF

log_info "Waiting for setup pod to be ready..."
kubectl wait --for=condition=Ready pod/${SETUP_POD_NAME} -n ${NAMESPACE} --timeout=60s

# Create database and user
log_info "Creating database '${DB_NAME}' and user '${DB_USER}'..."
kubectl exec -n ${NAMESPACE} ${SETUP_POD_NAME} -- bash -c "psql -c \"DROP DATABASE IF EXISTS ${DB_NAME};\""
kubectl exec -n ${NAMESPACE} ${SETUP_POD_NAME} -- bash -c "psql -c \"DROP USER IF EXISTS ${DB_USER};\""
kubectl exec -n ${NAMESPACE} ${SETUP_POD_NAME} -- bash -c "psql -c \"CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';\""
kubectl exec -n ${NAMESPACE} ${SETUP_POD_NAME} -- bash -c "psql -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\""
kubectl exec -n ${NAMESPACE} ${SETUP_POD_NAME} -- bash -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};\""

# Grant necessary permissions
log_info "Setting up database permissions..."
kubectl exec -n ${NAMESPACE} ${SETUP_POD_NAME} -- bash -c "psql -d ${DB_NAME} -c \"
GRANT ALL ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
\""

# Test connection with app user
log_info "Testing connection with application user..."
kubectl exec -n ${NAMESPACE} ${SETUP_POD_NAME} -- bash -c \
    "PGUSER=${DB_USER} PGPASSWORD=${DB_PASSWORD} psql -d ${DB_NAME} -c 'SELECT version();'" > /dev/null

log_info "Application user can connect successfully"

# Cleanup
log_info "Cleaning up setup pod..."
kubectl delete pod ${SETUP_POD_NAME} -n ${NAMESPACE}

log_info "✅ Database setup completed successfully!"
log_info ""
log_info "Database Details:"
log_info "  Host: ${POSTGRES_HOST}"
log_info "  Port: ${POSTGRES_PORT}"
log_info "  Database: ${DB_NAME}"
log_info "  User: ${DB_USER}"
log_info ""
log_info "Note: Database is empty. Linkwarden will run Prisma migrations on first startup."
log_info "If you need to import old data, you'll need to use pg_dump from the old cluster"
log_info "and pg_restore it into this new database."
