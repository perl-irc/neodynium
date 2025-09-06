#!/bin/sh
# ABOUTME: Solanum IRCd startup script with Fly.io .internal networking and password generation
# ABOUTME: Handles secure password generation, template processing, and IRC server startup
# Cache buster: v2024-08-28-1

set -e

# Start Tailscale daemon in background with userspace networking for containers
/usr/local/bin/tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Wait for daemon to start
sleep 3

# Connect to Tailscale network (using same logic as atheme)
/usr/local/bin/tailscale up --auth-key=${TAILSCALE_AUTHKEY} --hostname=${SERVER_NAME} --ssh --accept-dns

echo "Connected to Tailscale as ${HOSTNAME}"

chown ircd:ircd -R /opt/solanum
find /opt/solanum -type d -exec chmod 755 {} \;
find /opt/solanum -type f -exec chmod 644 {} \;
find /opt/solanum/bin -type f -exec chmod 755 {} \;

# Verify directories exist (should be created by Dockerfile)
echo "Verifying directory setup..."
df -h /opt/solanum
ls -la /opt/solanum/*


# Use environment variables (secrets) - REQUIRED, no fallbacks
echo "Using passwords from environment variables..."

# Check required secrets are present
if [ -z "${PASSWORD_9RL}" ]; then
    echo "ERROR: PASSWORD_9RL secret not set!"
    exit 1
fi

if [ -z "${PASSWORD_1EU}" ]; then
    echo "ERROR: PASSWORD_1EU secret not set!"
    exit 1
fi

if [ -z "${OPERATOR_PASSWORD}" ]; then
    echo "ERROR: OPERATOR_PASSWORD secret not set!"
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

# SSL certificate configuration
SSL_CERT="/opt/solanum/etc/ssl.pem"
SSL_KEY="/opt/solanum/etc/ssl.key"
SSL_DH="/opt/solanum/etc/dh.pem"

# Check if we should use Let's Encrypt (requires domains and email)
if [ -n "${SSL_DOMAINS}" ] && [ -n "${ADMIN_EMAIL}" ]; then
    echo "Setting up Let's Encrypt certificate for domains: ${SSL_DOMAINS}..."

    # Create webroot directory for ACME challenge
    mkdir -p /var/www/.well-known/acme-challenge

    # Build domain arguments for certbot
    DOMAIN_ARGS=""
    PRIMARY_DOMAIN=""
    for domain in $(echo "${SSL_DOMAINS}" | tr ',' ' '); do
        domain=$(echo "$domain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')  # trim whitespace
        if [ -z "$PRIMARY_DOMAIN" ]; then
            PRIMARY_DOMAIN="$domain"
        fi
        DOMAIN_ARGS="$DOMAIN_ARGS --domains $domain"
    done

    echo "Primary domain: $PRIMARY_DOMAIN"
    echo "All domains: $DOMAIN_ARGS"

    # Try to get/renew Let's Encrypt certificate
    if certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "${ADMIN_EMAIL}" \
        $DOMAIN_ARGS \
        --keep-until-expiring \
        --cert-path "$SSL_CERT" \
        --key-path "$SSL_KEY" \
        --http-01-port 8080 2>/dev/null; then

        echo "Let's Encrypt certificate obtained successfully"

        # Create symlinks to Let's Encrypt certificates (using primary domain)
        ln -sf "/etc/letsencrypt/live/${PRIMARY_DOMAIN}/fullchain.pem" "$SSL_CERT"
        ln -sf "/etc/letsencrypt/live/${PRIMARY_DOMAIN}/privkey.pem" "$SSL_KEY"
    else
        echo "Let's Encrypt certificate request failed, falling back to self-signed"
    fi
fi

# Generate self-signed certificate if Let's Encrypt didn't work or wasn't configured
if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
    echo "Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -newkey rsa:4096 \
        -keyout "$SSL_KEY" \
        -out "$SSL_CERT" \
        -days 365 \
        -subj "/C=US/ST=State/L=City/O=MagNET IRC Network/CN=${SERVER_NAME}.${TAILSCALE_DOMAIN}"
fi

# Generate DH parameters if they don't exist
if [ ! -f "$SSL_DH" ]; then
    echo "Generating DH parameters (this may take a while)..."
    openssl dhparam -out "$SSL_DH" 2048
fi

# Set proper permissions
chmod 600 "$SSL_KEY" "$SSL_CERT" "$SSL_DH" 2>/dev/null
chown ircd:ircd "$SSL_KEY" "$SSL_CERT" "$SSL_DH" 2>/dev/null

echo "SSL configuration complete"

# Set up cron job for certificate renewal if Let's Encrypt is configured
if [ -n "${SSL_DOMAINS}" ] && [ -n "${ADMIN_EMAIL}" ]; then
    echo "Setting up certificate renewal cron job..."
    # Export variables for the cron job
    echo "SSL_DOMAINS=${SSL_DOMAINS}" >> /etc/environment
    echo "ADMIN_EMAIL=${ADMIN_EMAIL}" >> /etc/environment
    echo "0 2 * * * /opt/solanum/bin/renew-cert.sh" > /tmp/certbot-cron
    crontab -u root /tmp/certbot-cron
    crond -b  # Start cron daemon in background
    echo "Certificate renewal cron job configured"
fi

# Process server-specific configuration and concatenate with common config
echo "Processing server-specific configuration..."
if [ -f /opt/solanum/conf/server.conf.template ]; then
    echo "Building complete ircd.conf from server.conf + common.conf + opers.conf"

    # Process all templates
    envsubst < /opt/solanum/conf/server.conf.template > /tmp/server.conf
    envsubst < /opt/solanum/conf/common.conf.template > /tmp/common.conf
    envsubst < /opt/solanum/conf/opers.conf.template > /tmp/opers.conf

    # Concatenate into final ircd.conf
    cat /tmp/server.conf /tmp/common.conf /tmp/opers.conf > /opt/solanum/etc/ircd.conf

    # Cleanup temp files
    rm /tmp/server.conf /tmp/common.conf /tmp/opers.conf
else
    echo "ERROR: No server-specific configuration found at /opt/solanum/conf/server.conf.template"
    echo "Each server must have its own server.conf file in the build context"
    exit 1
fi

chown ircd:ircd /opt/solanum/etc/ircd.conf
chmod 600 /opt/solanum/etc/ircd.conf

# Test Solanum configuration
su-exec ircd /opt/solanum/bin/solanum -configfile /opt/solanum/etc/ircd.conf -conftest

# Cleanup function - only called when health check fails
cleanup() {
    echo "Solanum unhealthy, cleaning up..."
    echo "Logging out of Tailscale..."
    /usr/local/bin/tailscale logout 2>/dev/null || true
    echo "Cleanup complete"
}

# Start Solanum as ircd user (foreground mode for debugging)
echo "Starting Solanum in foreground mode for debugging..."

su-exec ircd /opt/solanum/bin/solanum -foreground -configfile /opt/solanum/etc/ircd.conf

# Wait a moment for daemon to start
sleep 2

# Function to check if Solanum is still running
check_solanum() {
    if ! pgrep -f "/opt/solanum/bin/solanum" > /dev/null; then
        echo "Solanum process died, exiting health endpoint"
        return 1
    fi
}

# Keep container running and monitor Solanum process
while true; do
    if ! check_solanum; then
        echo "Solanum process died, initiating cleanup and exit"
        cleanup
        exit 1
    fi
    sleep 15
done
