#!/bin/bash
# ABOUTME: Solanum IRCd startup script with Tailscale integration and password generation
# ABOUTME: Handles ephemeral Tailscale auth, secure password generation, and template processing

set -e

# Start Tailscale daemon in background (per official guide)
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Wait for daemon to start
sleep 5

# Connect to Tailscale network with dynamic hostname
HOSTNAME=${SERVER_NAME:-solanum-${FLY_REGION:-unknown}}
/usr/local/bin/tailscale up --auth-key=${TAILSCALE_AUTHKEY} --hostname=${HOSTNAME} --ephemeral --ssh --accept-routes=false --accept-dns=false

echo "Connected to Tailscale as ${HOSTNAME}"

# Generate secure passwords if they don't exist
if [ ! -f /opt/solanum/etc/passwords.conf ]; then
    echo "Generating secure passwords..."

    # Use environment variables (secrets) if available, otherwise generate
    LINK_PASS=${LINK_PASSWORD_9RL_1EU:-$(pwgen -s 32 1)}
    OPER_PASS=${OPER_PASSWORD:-$(pwgen -s 24 1)}
    SERVICES_PASS=${SERVICES_PASSWORD:-$(pwgen -s 32 1)}

    cat > /opt/solanum/etc/passwords.conf << EOF
# Auto-generated secure passwords - DO NOT COMMIT TO VCS
LINK_PASSWORD_9RL_1EU=$LINK_PASS
OPER_PASSWORD=$OPER_PASS
SERVICES_PASSWORD=$SERVICES_PASS
EOF
    chown ircd:ircd /opt/solanum/etc/passwords.conf
    chmod 600 /opt/solanum/etc/passwords.conf
fi

# Source the generated passwords
source /opt/solanum/etc/passwords.conf

# Process ircd.conf template with generated passwords
echo "Instantiating ircd.conf from template..."
envsubst '${SERVER_NAME} ${SERVER_SID} ${SERVER_DESCRIPTION} ${LINK_PASSWORD_9RL_1EU} ${OPER_PASSWORD} ${SERVICES_PASSWORD}' \
    < /opt/solanum/etc/ircd.conf.template \
    > /opt/solanum/etc/ircd.conf

chown ircd:ircd /opt/solanum/etc/ircd.conf
chmod 644 /opt/solanum/etc/ircd.conf

echo "Configuration instantiated successfully"
echo "Tailscale hostname: ${HOSTNAME}"
echo "Operator password: ${OPER_PASSWORD}"
echo "Services password: ${SERVICES_PASSWORD}"

# Simple HTTP health endpoint
(while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nSolanum IRCd Health OK" | nc -l -p 8080 -q 1
done) &

# Start Solanum as ircd user
exec su-exec ircd /opt/solanum/bin/solanum -foreground