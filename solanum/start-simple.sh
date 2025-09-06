#!/bin/sh
# ABOUTME: Simple IRC server startup without Tailscale integration
# ABOUTME: Used with Tailscale sidecar containers for networking

set -e

echo "Starting Solanum IRC server..."

# Copy the directory contents to see what we have
ls -la /opt/solanum/

# List config files
ls -la /opt/solanum/conf/

# Process server-specific configuration
echo "Processing server-specific configuration..."
cp /opt/solanum/conf/server.conf.template /opt/solanum/etc/server.conf

# Build complete ircd.conf from server.conf + common.conf + opers.conf
echo "Building complete ircd.conf from server.conf + common.conf + opers.conf"
envsubst < /opt/solanum/conf/common.conf.template > /tmp/common.conf
envsubst < /opt/solanum/conf/opers.conf.template > /tmp/opers.conf
envsubst < /opt/solanum/etc/server.conf > /tmp/server.conf

# Combine all config files
cat /tmp/server.conf /tmp/common.conf /tmp/opers.conf > /opt/solanum/etc/ircd.conf

# Use environment variables in configuration
echo "Using passwords from environment variables..."

# Generate self-signed SSL certificate
echo "Generating self-signed SSL certificate..."
if [ ! -f /opt/solanum/etc/ssl.pem ]; then
    openssl req -x509 -newkey rsa:4096 -keyout /opt/solanum/etc/ssl.key -out /opt/solanum/etc/ssl.pem -days 365 -nodes -subj "/CN=${SERVER_NAME}.${TAILSCALE_DOMAIN}"
fi

# Generate DH parameters (this may take a while)
echo "Generating DH parameters (this may take a while)..."
if [ ! -f /opt/solanum/etc/dh.pem ]; then
    openssl dhparam -out /opt/solanum/etc/dh.pem 2048
fi

# Test configuration
echo "Beginning config test"
su-exec ircd /opt/solanum/bin/solanum -configfile /opt/solanum/etc/ircd.conf -conftest

echo "Config testing complete."

# Start Solanum
echo "Starting Solanum IRC server..."
exec su-exec ircd /opt/solanum/bin/solanum -configfile /opt/solanum/etc/ircd.conf -foreground