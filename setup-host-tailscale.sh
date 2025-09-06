#!/bin/bash
# ABOUTME: Install Tailscale on DigitalOcean host OS for administration access
# ABOUTME: Replaces sidecar containers with host-level Tailscale integration

set -e

echo "Installing Tailscale on host OS..."

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Start and connect with ephemeral key
tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname="${SERVER_NAME}" --ssh --accept-dns

# Enable IP forwarding for containers
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p

# Create Tailscale network for containers
docker network create --driver bridge tailscale-bridge || true

echo "Host Tailscale setup complete!"
echo "Server should be accessible at: ${SERVER_NAME}.${TAILSCALE_DOMAIN}"