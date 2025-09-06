#!/bin/bash
# ABOUTME: Script to restart Atheme with proper uplink configuration
# ABOUTME: Run this on the magnet-atheme server to update the container

set -e

echo "Stopping existing Atheme container..."
docker stop magnet-atheme 2>/dev/null || true
docker rm magnet-atheme 2>/dev/null || true

echo "Starting Atheme services container with uplinks configured..."
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

echo "Waiting for container to start..."
sleep 5

echo "Container status:"
docker ps | grep magnet-atheme

echo "Atheme logs:"
docker logs magnet-atheme --tail 10

echo "Atheme services restarted with uplink configuration!"