#!/bin/sh
# ABOUTME: Atheme IRC services startup script with Tailscale integration
# ABOUTME: Handles ephemeral Tailscale auth, password generation, and opensex flat file backend

set -e

# Start Tailscale daemon in background
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Wait for daemon to start
sleep 5

# Connect to Tailscale network
HOSTNAME=${SERVER_NAME:-atheme-${FLY_REGION:-unknown}}
/usr/local/bin/tailscale up --auth-key=${TAILSCALE_AUTHKEY} --hostname=${HOSTNAME} --ssh --accept-routes=false --accept-dns=true

echo "Connected to Tailscale as ${HOSTNAME}"

# Generate Atheme passwords if they don't exist
if [ ! -f /atheme/etc/passwords.conf ]; then
    echo "Generating secure Atheme passwords..."

    # Use environment variables (secrets) if available, otherwise generate
    SERVICES_PASS=${SERVICES_PASSWORD:-$(pwgen -s 32 1)}
    OPERATOR_PASS=${OPERATOR_PASSWORD:-$(pwgen -s 24 1)}

    cat > /atheme/etc/passwords.conf << EOF
# Auto-generated secure passwords for Atheme - DO NOT COMMIT TO VCS
SERVICES_PASSWORD=$SERVICES_PASS
OPERATOR_PASSWORD=$OPERATOR_PASS
EOF
    chown atheme:atheme /atheme/etc/passwords.conf
    chmod 600 /atheme/etc/passwords.conf
fi

# Source the generated passwords
source /atheme/etc/passwords.conf

# Process atheme.conf template with generated passwords
echo "Instantiating atheme.conf from template..."

# Extract database details from DATABASE_URL if available
if [ -n "$DATABASE_URL" ]; then
    echo "Using DATABASE_URL for PostgreSQL connection"
    # Parse DATABASE_URL: postgres://user:pass@host:port/dbname
    export ATHEME_POSTGRES_HOST=$(echo "$DATABASE_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')
    export ATHEME_POSTGRES_DB=$(echo "$DATABASE_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')
    echo "Extracted from DATABASE_URL: host=$ATHEME_POSTGRES_HOST, db=$ATHEME_POSTGRES_DB"
fi

envsubst '${ATHEME_NETWORK} ${ATHEME_NETWORK_DOMAIN} ${SERVICES_PASSWORD} ${OPERATOR_PASSWORD} ${ATHEME_HUB_SERVER} ${ATHEME_HUB_HOSTNAME} ${DATABASE_URL}' \
    < /atheme/etc/atheme.conf.template \
    > /atheme/etc/atheme.conf

chown atheme:atheme /atheme/etc/atheme.conf
chmod 644 /atheme/etc/atheme.conf

echo "Atheme configuration instantiated successfully"
echo "Tailscale hostname: ${HOSTNAME}"
echo "Services password: ${SERVICES_PASSWORD}"

# Wait for PostgreSQL to be available (if DATABASE_URL is set)
if [ -n "$DATABASE_URL" ]; then
    echo "Waiting for PostgreSQL to be available..."
    max_attempts=30
    attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; then
            echo "PostgreSQL is ready!"
            break
        fi
        
        echo "PostgreSQL not ready, attempt $attempt/$max_attempts..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        echo "WARNING: PostgreSQL not available after $max_attempts attempts, proceeding anyway"
    fi
fi

# Simple HTTP health endpoint
(while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nAtheme Services Health OK" | nc -l -p 8080
done) &

# Start Atheme as atheme user
exec su-exec atheme /atheme/bin/atheme-services -n