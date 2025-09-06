#!/bin/sh
# ABOUTME: Tailscale sidecar container startup script
# ABOUTME: Handles Tailscale networking for IRC server containers

set -e

echo "Starting Tailscale sidecar container..."
echo "SERVER_NAME: ${SERVER_NAME}"

# Start Tailscale daemon in background
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Wait for daemon to start
sleep 5

# Connect to Tailscale network
echo "Connecting to Tailscale network..."
echo "DEBUG: TAILSCALE_AUTHKEY length: ${#TAILSCALE_AUTHKEY}"
echo "DEBUG: TAILSCALE_AUTHKEY starts with: ${TAILSCALE_AUTHKEY:0:20}..."

/usr/local/bin/tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname="${SERVER_NAME}" --ssh --accept-dns

echo "Connected to Tailscale network"

# Display network status
/usr/local/bin/tailscale status

# Keep container running - the IRC server will connect via network sharing
echo "Tailscale sidecar ready. Keeping container alive..."
tail -f /dev/null