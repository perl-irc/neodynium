#!/bin/bash
# ABOUTME: Atheme IRC services startup script with Tailscale integration and database connectivity
# ABOUTME: Handles ephemeral Tailscale auth, password generation, and PostgreSQL connection

set -e

# Start Tailscale daemon in background
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Wait for daemon to start
sleep 5

# Connect to Tailscale network
HOSTNAME=${SERVER_NAME:-atheme-${FLY_REGION:-unknown}}
/usr/local/bin/tailscale up --auth-key=${TAILSCALE_AUTHKEY} --hostname=${HOSTNAME} --ephemeral --ssh --accept-routes=false --accept-dns=true

echo "Connected to Tailscale as ${HOSTNAME}"

# Generate Atheme passwords if they don't exist
if [ ! -f /opt/atheme/etc/passwords.conf ]; then
    echo "Generating secure Atheme passwords..."

    # Use environment variables (secrets) if available, otherwise generate
    SERVICES_PASS=${SERVICES_PASSWORD:-$(pwgen -s 32 1)}
    OPERATOR_PASS=${OPERATOR_PASSWORD:-$(pwgen -s 24 1)}

    cat > /opt/atheme/etc/passwords.conf << EOF
# Auto-generated secure passwords for Atheme - DO NOT COMMIT TO VCS
SERVICES_PASSWORD=$SERVICES_PASS
OPERATOR_PASSWORD=$OPERATOR_PASS
EOF
    chown atheme:atheme /opt/atheme/etc/passwords.conf
    chmod 600 /opt/atheme/etc/passwords.conf
fi

# Source the generated passwords
source /opt/atheme/etc/passwords.conf

# Process atheme.conf template with generated passwords
echo "Instantiating atheme.conf from template..."
envsubst '${ATHEME_NETWORK} ${ATHEME_NETWORK_DOMAIN} ${SERVICES_PASSWORD} ${OPERATOR_PASSWORD} ${ATHEME_POSTGRES_HOST} ${ATHEME_POSTGRES_DB} ${ATHEME_HUB_SERVER} ${ATHEME_HUB_HOSTNAME}' \
    < /opt/atheme/etc/atheme.conf.template \
    > /opt/atheme/etc/atheme.conf

chown atheme:atheme /opt/atheme/etc/atheme.conf
chmod 644 /opt/atheme/etc/atheme.conf

echo "Atheme configuration instantiated successfully"
echo "Tailscale hostname: ${HOSTNAME}"
echo "Services password: ${SERVICES_PASSWORD}"

# Simple HTTP health endpoint
(while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nAtheme Services Health OK" | nc -l -p 8080 -q 1
done) &

# Start Atheme as atheme user
exec su-exec atheme /opt/atheme/bin/atheme-services -n