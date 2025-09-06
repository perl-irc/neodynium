#!/bin/sh
# ABOUTME: Simple Atheme services startup without Tailscale integration  
# ABOUTME: Used with Tailscale sidecar containers for networking

set -e

echo "Starting Atheme IRC services..."

# Create atheme user if it doesn't exist
if ! id atheme > /dev/null 2>&1; then
    adduser -D -u 1001 atheme
fi

# Create directories
mkdir -p /opt/atheme/var/log /opt/atheme/var/run /opt/atheme/etc /opt/atheme/conf

# Process configuration with environment variables
echo "Processing Atheme configuration..."
envsubst < /opt/atheme/conf/atheme.conf.template > /opt/atheme/etc/atheme.conf

# Set up data directory and permissions
mkdir -p /opt/atheme/var
chown -R atheme:atheme /opt/atheme/var /opt/atheme/etc

# Start Atheme services
echo "Starting Atheme services..."
# Create new database if it doesn't exist
if [ ! -f /opt/atheme/etc/services.db ]; then
    echo "Creating new services database..."
    exec su-exec atheme /opt/atheme/bin/atheme-services -n -b -c /opt/atheme/etc/atheme.conf
else
    exec su-exec atheme /opt/atheme/bin/atheme-services -n -c /opt/atheme/etc/atheme.conf
fi