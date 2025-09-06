#!/bin/bash
# ABOUTME: Deploy magnet-9rl IRC server with host-level Tailscale
# ABOUTME: Installs Tailscale on host OS for direct SSH access

set -e

export SERVER_NAME="magnet-9rl"
export SERVER_SID="9RL"
export SERVER_DESCRIPTION="Magnet IRC Network - US Hub"
export TAILSCALE_DOMAIN="camel-kanyu.ts.net"
export TAILSCALE_AUTHKEY="tskey-auth-k8QSBCo5Sj11CNTRL-4Di3tc4Jszb6n4pgUvssyb8TpLSszTvUd"

echo "Deploying magnet-9rl with host Tailscale integration..."

# Stop and remove existing containers/sidecars
docker stop magnet-9rl-tailscale 2>/dev/null || true
docker rm magnet-9rl-tailscale 2>/dev/null || true
docker stop magnet-9rl 2>/dev/null || true
docker rm magnet-9rl 2>/dev/null || true

# Install Tailscale on host
echo "Setting up host Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname="${SERVER_NAME}" --ssh --accept-dns

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf 2>/dev/null || true
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf 2>/dev/null || true
sysctl -p

# Build IRC server image
echo "Building Solanum IRC server image..."
docker build -t solanum-host -f Dockerfile.solanum-host solanum/

# Start IRC server container
echo "Starting IRC server container..."
docker run -d --name magnet-9rl \
  --restart unless-stopped \
  -p 6667:6667 \
  -p 6697:6697 \
  -e SERVER_NAME="${SERVER_NAME}" \
  -e SERVER_SID="${SERVER_SID}" \
  -e SERVER_DESCRIPTION="${SERVER_DESCRIPTION}" \
  -e TAILSCALE_DOMAIN="${TAILSCALE_DOMAIN}" \
  -e PASSWORD_9RL="${PASSWORD_9RL:-$(openssl rand -base64 32)}" \
  -e PASSWORD_1EU="${PASSWORD_1EU:-$(openssl rand -base64 32)}" \
  -e SERVICES_PASSWORD="${SERVICES_PASSWORD:-$(openssl rand -base64 32)}" \
  -v magnet-9rl-data:/opt/solanum/var \
  solanum-host

echo "Waiting for container to start..."
sleep 5

echo "Container status:"
docker ps | grep magnet-9rl
echo "IRC server logs:"
docker logs magnet-9rl --tail 10

echo "Deployment complete!"
echo "Server accessible at: ${SERVER_NAME}.${TAILSCALE_DOMAIN}"
echo "SSH access: ssh root@${SERVER_NAME}.${TAILSCALE_DOMAIN}"