#!/bin/sh
# ABOUTME: Solanum startup script for host Tailscale deployment
# ABOUTME: Simplified startup without embedded Tailscale management

set -e

echo "Starting Solanum IRC server..."

# Create solanum user if it doesn't exist
if ! id solanum > /dev/null 2>&1; then
    adduser -D -u 1001 solanum
fi

# Create directories
mkdir -p /opt/solanum/var/log /opt/solanum/var/run /opt/solanum/etc

# Generate SSL certificates if they don't exist
if [ ! -f /opt/solanum/etc/ssl.pem ]; then
    echo "Generating SSL certificates..."
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${SERVER_NAME}.${TAILSCALE_DOMAIN}" \
        -keyout /opt/solanum/etc/ssl.key \
        -out /opt/solanum/etc/ssl.pem
    
    # Generate DH parameters
    openssl dhparam -out /opt/solanum/etc/dh.pem 2048
fi

# Generate secure passwords if not provided
if [ -z "$PASSWORD_9RL" ]; then
    export PASSWORD_9RL=$(openssl rand -base64 32)
    echo "Generated PASSWORD_9RL: $PASSWORD_9RL"
fi

if [ -z "$PASSWORD_1EU" ]; then
    export PASSWORD_1EU=$(openssl rand -base64 32)
    echo "Generated PASSWORD_1EU: $PASSWORD_1EU"
fi

if [ -z "$SERVICES_PASSWORD" ]; then
    export SERVICES_PASSWORD=$(openssl rand -base64 32)
    echo "Generated SERVICES_PASSWORD: $SERVICES_PASSWORD"
fi

# Process server configuration
echo "Processing IRC server configuration..."
envsubst < /opt/solanum/etc/common.conf.template > /opt/solanum/etc/ircd.conf

# Process operator configuration
envsubst < /opt/solanum/etc/opers.conf.template >> /opt/solanum/etc/ircd.conf

# Set permissions
chown -R solanum:solanum /opt/solanum/var /opt/solanum/etc

# Start Solanum
echo "Starting Solanum IRC daemon..."
exec su-exec solanum /opt/solanum/bin/solanum -foreground