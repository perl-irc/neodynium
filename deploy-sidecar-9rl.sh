#!/bin/bash
# ABOUTME: Sidecar deployment script for magnet-9rl IRC server on DigitalOcean droplet
# ABOUTME: Uses separate Tailscale sidecar container for networking

set -e

echo "Starting sidecar deployment of magnet-9rl IRC server..."

# Wait for Docker to be ready
while ! docker info > /dev/null 2>&1; do
    echo "Waiting for Docker to be ready..."
    sleep 5
done

echo "Docker is ready. Proceeding with deployment..."

# Stop and remove any existing containers
docker stop magnet-9rl-tailscale 2>/dev/null || true
docker rm magnet-9rl-tailscale 2>/dev/null || true
docker stop magnet-9rl 2>/dev/null || true
docker rm magnet-9rl 2>/dev/null || true

# Build Tailscale sidecar image
echo "Building Tailscale sidecar image..."
docker build -t magnet-9rl-tailscale -f Dockerfile.tailscale .

# Build IRC server image
echo "Building IRC server image..."
cp servers/magnet-9rl/server.conf solanum/server.conf
docker build -t magnet-9rl-irc -f Dockerfile.solanum-simple solanum/

# Start Tailscale sidecar container
echo "Starting Tailscale sidecar container..."
docker run -d --name magnet-9rl-tailscale \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --device /dev/net/tun \
  -v magnet-9rl-tailscale-state:/var/lib/tailscale \
  -e SERVER_NAME=magnet-9rl \
  -e TAILSCALE_AUTHKEY=tskey-auth-k8QSBCo5Sj11CNTRL-4Di3tc4Jszb6n4pgUvssyb8TpLSszTvUd \
  -e TAILSCALE_DOMAIN=camel-kanyu.ts.net \
  magnet-9rl-tailscale

# Wait for Tailscale to connect
echo "Waiting for Tailscale to connect..."
sleep 15

# Start IRC server container linked to Tailscale sidecar
echo "Starting IRC server container..."
docker run -d --name magnet-9rl \
  --restart unless-stopped \
  --network container:magnet-9rl-tailscale \
  -e SERVER_NAME=magnet-9rl \
  -e SERVER_SID=9RL \
  -e SERVER_DESCRIPTION="Magnet IRC Network - US Hub" \
  -e PRIMARY_REGION=tor \
  -e TAILSCALE_DOMAIN=camel-kanyu.ts.net \
  -e PASSWORD_9RL=4piymLRtsf4BG0AkYU4mQKeOB3BUT0oy \
  -e PASSWORD_1EU=Appe0lOSyzjwc8fVJ2ZJpDJKOl2rs250 \
  -e SERVICES_PASSWORD=vRH6PLBIQeZpTrla0QH3iR2Hn42WY1pj \
  -e OPERATOR_PASSWORD=jK6NtLemTHoBq9AXbvCZClPI \
  -e OPER_PERIGRIN_PASSWORD=Rl9ZymR45Wm7Q \
  -e OPER_CORWIN_PASSWORD=exp.Io1AElUUY \
  -e OPER_ETHER_PASSWORD='$6$npQvleL/7byRtUhh$w/nMUQ9IC5uKBZfMKbpJCLn4yCaynT6KOZ6PM/RZhId7RczUfd2GnPM50IRGPSMCZvmSh9A1hc8tK7b5zu0Dg0' \
  -e OPER_MASON_PASSWORD='$6$CkKAhkuCpBfI0H3n$0iy2s1gnDBZAQeo6C6two6CnACdwgm5JaBdC/pb9x6pQUSu41OCMlWCdviLuuMhjXvzYXiUIbfcbUgj6V5UBd/' \
  -e ADMIN_NAME="Chris Prather" \
  -e ADMIN_EMAIL="chris@prather.org" \
  magnet-9rl-irc

echo "Waiting for containers to start..."
sleep 10

# Check container status
echo "Container status:"
docker ps | grep magnet-9rl
echo "Tailscale sidecar logs:"
docker logs magnet-9rl-tailscale --tail 10
echo "IRC server logs:"
docker logs magnet-9rl --tail 10

echo "Sidecar deployment complete! IRC server should be accessible via Tailscale"