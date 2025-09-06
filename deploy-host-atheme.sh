#!/bin/bash
# ABOUTME: Deploy magnet-atheme IRC services with host-level Tailscale
# ABOUTME: Installs Tailscale on host OS for direct SSH access

set -e

export SERVER_NAME="magnet-atheme"
export TAILSCALE_DOMAIN="camel-kanyu.ts.net"
export TAILSCALE_AUTHKEY="tskey-auth-k8QSBCo5Sj11CNTRL-4Di3tc4Jszb6n4pgUvssyb8TpLSszTvUd"
export SERVICES_PASSWORD="vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj"
export PASSWORD_9RL="vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj"
export PASSWORD_1EU="vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj"

echo "Deploying magnet-atheme with host Tailscale integration..."

# Stop and remove existing containers/sidecars
docker stop magnet-atheme-tailscale 2>/dev/null || true
docker rm magnet-atheme-tailscale 2>/dev/null || true
docker stop magnet-atheme 2>/dev/null || true
docker rm magnet-atheme 2>/dev/null || true

# Install Tailscale on host
echo "Setting up host Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname="${SERVER_NAME}" --ssh --accept-dns

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf 2>/dev/null || true
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf 2>/dev/null || true
sysctl -p

# Build Atheme services image
echo "Building Atheme services image..."
docker build -t atheme-host -f Dockerfile.atheme-host atheme/

# Start Atheme services container
echo "Starting Atheme services container..."
docker run -d --name magnet-atheme \
  --restart unless-stopped \
  -e SERVER_NAME="${SERVER_NAME}" \
  -e TAILSCALE_DOMAIN="${TAILSCALE_DOMAIN}" \
  -e SERVICES_PASSWORD="${SERVICES_PASSWORD}" \
  -e ADMIN_NAME="Chris Prather" \
  -e ADMIN_EMAIL="chris@prather.org" \
  -e ATHEME_NETWORK="Magnet" \
  -e ATHEME_HUB_HOSTNAME="magnet-9rl.${TAILSCALE_DOMAIN}" \
  -e ATHEME_FALLBACK_HOSTNAME="magnet-1eu.${TAILSCALE_DOMAIN}" \
  -e PASSWORD_9RL="${PASSWORD_9RL}" \
  -e PASSWORD_1EU="${PASSWORD_1EU}" \
  -v magnet-atheme-data:/opt/atheme/var \
  atheme-host

echo "Waiting for container to start..."
sleep 5

echo "Container status:"
docker ps | grep magnet-atheme
echo "Atheme services logs:"
docker logs magnet-atheme --tail 10

echo "Deployment complete!"
echo "Server accessible at: ${SERVER_NAME}.${TAILSCALE_DOMAIN}"
echo "SSH access: ssh root@${SERVER_NAME}.${TAILSCALE_DOMAIN}"