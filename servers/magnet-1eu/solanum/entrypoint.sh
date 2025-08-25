#!/bin/sh
# ABOUTME: Solanum IRCd startup script with Fly.io .internal networking and password generation
# ABOUTME: Handles secure password generation, template processing, and IRC server startup

set -e

# Skip Tailscale - using Fly.io .internal networking for server linking
echo "Using Fly.io .internal networking for server communication"

# Create required directories and set permissions
mkdir -p /opt/solanum/logs /opt/solanum/var/run /opt/solanum/var/log
chown -R ircd:ircd /opt/solanum/logs /opt/solanum/var

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

# Set hub-specific configuration based on server name
if [ "${SERVER_NAME}" = "magnet-9rl" ]; then
    # Hub server gets both server linking and services
    export HUB_CONFIG="/* Server linking (hub server) */
connect \"magnet-1eu.${HUB_NAME}\" {
    host = \"magnet-1eu.${HUB_NAME}\";
    send_password = \"${LINK_PASSWORD_9RL_1EU}\";
    accept_password = \"${LINK_PASSWORD_9RL_1EU}\";
    port = 7000;
    hub_mask = \"*\";
    class = \"server\";
    flags = ssl;
};

/* Services linking (hub server only) */
service { name = \"services.${HUB_NAME}\"; };
connect \"services.${HUB_NAME}\" {
    host = \"magnet-atheme.${HUB_NAME}\";
    send_password = \"${SERVICES_PASSWORD}\";
    accept_password = \"${SERVICES_PASSWORD}\";
    port = 6667;
    class = \"server\";
};"
else
    # Leaf servers get no outbound connections (they accept connections from hub)
    export HUB_CONFIG='/* Leaf server - accepts connections from hub */'
fi

envsubst '${SERVER_NAME} ${SERVER_SID} ${SERVER_DESCRIPTION} ${LINK_PASSWORD_9RL_1EU} ${OPER_PASSWORD} ${SERVICES_PASSWORD} ${HUB_CONFIG} ${HUB_NAME}' \
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