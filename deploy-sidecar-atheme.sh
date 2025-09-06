#!/bin/bash
# ABOUTME: Sidecar deployment script for magnet-atheme IRC services on DigitalOcean droplet  
# ABOUTME: Uses separate Tailscale sidecar container for networking

set -e

echo "Starting sidecar deployment of magnet-atheme IRC services..."

# Wait for Docker to be ready
while ! docker info > /dev/null 2>&1; do
    echo "Waiting for Docker to be ready..."
    sleep 5
done

echo "Docker is ready. Proceeding with deployment..."

# Stop and remove any existing containers
docker stop magnet-atheme-tailscale 2>/dev/null || true
docker rm magnet-atheme-tailscale 2>/dev/null || true
docker stop magnet-atheme 2>/dev/null || true
docker rm magnet-atheme 2>/dev/null || true

# Build Tailscale sidecar image
echo "Building Tailscale sidecar image..."
docker build -t magnet-atheme-tailscale -f Dockerfile.tailscale .

# Build Atheme services image  
echo "Building Atheme services image..."
docker build -t magnet-atheme-services -f Dockerfile.atheme-simple atheme/

# Start Tailscale sidecar container
echo "Starting Tailscale sidecar container..."
docker run -d --name magnet-atheme-tailscale \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v magnet-atheme-tailscale-state:/var/lib/tailscale \
  -e SERVER_NAME=magnet-atheme \
  -e TAILSCALE_AUTHKEY=tskey-auth-k8QSBCo5Sj11CNTRL-4Di3tc4Jszb6n4pgUvssyb8TpLSszTvUd \
  -e TAILSCALE_DOMAIN=camel-kanyu.ts.net \
  magnet-atheme-tailscale

# Wait for Tailscale to connect
echo "Waiting for Tailscale to connect..."
sleep 15

# Start Atheme services container linked to Tailscale sidecar
echo "Starting Atheme services container..."
docker run -d --name magnet-atheme \
  --restart unless-stopped \
  --network container:magnet-atheme-tailscale \
  -e SERVER_NAME=magnet-atheme \
  -e TAILSCALE_DOMAIN=camel-kanyu.ts.net \
  -e SERVICES_PASSWORD=vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj \
  -e ADMIN_NAME="Chris Prather" \
  -e ADMIN_EMAIL="chris@prather.org" \
  -e ATHEME_NETWORK=Magnet \
  -e ATHEME_HUB_HOSTNAME=magnet-9rl.camel-kanyu.ts.net \
  -e ATHEME_FALLBACK_HOSTNAME=magnet-1eu.camel-kanyu.ts.net \
  -e PASSWORD_9RL=vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj \
  -e PASSWORD_1EU=vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj \
  magnet-atheme-services

echo "Waiting for containers to start..."
sleep 10

# Check container status
echo "Container status:"
docker ps | grep magnet-atheme
echo "Tailscale sidecar logs:"
docker logs magnet-atheme-tailscale --tail 10
echo "Atheme services logs:"
docker logs magnet-atheme --tail 10

echo "Sidecar deployment complete! Atheme services should be accessible via Tailscale"