#!/bin/sh
# ABOUTME: Solanum IRCd startup script with Fly.io .internal networking and password generation
# ABOUTME: Handles secure password generation, template processing, and IRC server startup

set -e

# Start Tailscale for admin access (also using Fly.io .internal for server communication)
echo "Starting Tailscale for admin access..."
echo "Also using Fly.io .internal networking for server communication"

# Start Tailscale daemon in background
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Wait for Tailscale daemon to be ready
sleep 2

# Connect to Tailscale with ephemeral key
if [ -n "${TAILSCALE_AUTHKEY}" ]; then
    /usr/local/bin/tailscale up \
        --authkey="${TAILSCALE_AUTHKEY}" \
        --hostname="${HOSTNAME}" \
        --advertise-tags=tag:server \
        --ssh || echo "Tailscale connection failed, continuing..."
else
    echo "Warning: TAILSCALE_AUTHKEY not set, skipping Tailscale connection"
fi

# Create required directories and set permissions
mkdir -p /opt/solanum/logs /opt/solanum/var/run /opt/solanum/var/log
chown -R ircd:ircd /opt/solanum/logs /opt/solanum/var

# Use environment variables (secrets) - REQUIRED, no fallbacks
echo "Using passwords from environment variables..."

# Check required secrets are present
if [ -z "${LINK_PASSWORD_9RL_1EU}" ]; then
    echo "ERROR: LINK_PASSWORD_9RL_1EU secret not set!"
    exit 1
fi

if [ -z "${OPER_PASSWORD}" ]; then
    echo "ERROR: OPER_PASSWORD secret not set!"
    exit 1
fi

if [ -z "${SERVICES_PASSWORD}" ]; then
    echo "ERROR: SERVICES_PASSWORD secret not set!"
    exit 1
fi

# Extract SID from server name if not explicitly set (e.g., magnet-9rl -> 9RL)
if [ -z "${SERVER_SID}" ]; then
    SERVER_SID=$(echo "${SERVER_NAME}" | sed 's/magnet-//' | tr '[:lower:]' '[:upper:]')
fi

# Process ircd.conf template with generated passwords
echo "Instantiating ircd.conf from template..."

# Set hub-specific configuration based on server name
if [ "${SERVER_NAME}" = "magnet-9rl" ]; then
    # Hub server accepts connections from leaves and services
    export HUB_CONFIG="/* Hub server - accepts connections from leaves and services */
server \"magnet-1eu.internal\" {
    host = \"magnet-1eu.internal\";
    send_password = \"${LINK_PASSWORD_9RL_1EU}\";
    accept_password = \"${LINK_PASSWORD_9RL_1EU}\";
    class = \"server\";
};

/* Server authentication - allow server connections */
auth {
    user = \"*@magnet-1eu.internal\";
    class = \"server\";
};

service { name = \"services.internal\"; };"
else
    # Leaf servers connect to hub
    export HUB_CONFIG="/* Leaf server - connects to hub */
connect \"magnet-9rl.internal\" {
    host = \"magnet-9rl.internal\";
    send_password = \"${LINK_PASSWORD_9RL_1EU}\";
    accept_password = \"${LINK_PASSWORD_9RL_1EU}\";
    port = 6667;
    class = \"server\";
    autoconn = yes;
};"
fi

envsubst '${SERVER_NAME} ${SERVER_SID} ${SERVER_DESCRIPTION} ${LINK_PASSWORD_9RL_1EU} ${OPER_PASSWORD} ${SERVICES_PASSWORD} ${HUB_CONFIG}' \
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
    echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nSolanum IRCd Health OK" | nc -l -p 8080
done) &

# Start Solanum as ircd user
exec su-exec ircd /opt/solanum/bin/solanum -foreground