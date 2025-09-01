#!/bin/bash
# ABOUTME: Deployment script for magnet-9rl IRC server on DigitalOcean droplet
# ABOUTME: Builds containers and runs Solanum IRCd with Tailscale networking

set -e

echo "Starting deployment of magnet-9rl IRC server..."

# Wait for Docker to be ready (from user-data script)
while ! docker info > /dev/null 2>&1; do
    echo "Waiting for Docker to be ready..."
    sleep 5
done

echo "Docker is ready. Proceeding with deployment..."

# Clone repository
cd /opt
if [ ! -d "neodynium" ]; then
    git clone https://github.com/perl-irc/neodynium.git
fi
cd neodynium
git checkout digitalocean-migration
git pull

# Build Solanum image
echo "Building Solanum IRC server image..."
docker build -t registry.digitalocean.com/magnet-irc/solanum:9rl -f solanum/Dockerfile solanum/

# Copy server-specific config
cp servers/magnet-9rl/server.conf solanum/server.conf

# Build with server-specific config
docker build -t registry.digitalocean.com/magnet-irc/solanum:9rl -f solanum/Dockerfile solanum/

# Stop and remove any existing container
docker stop magnet-9rl 2>/dev/null || true
docker rm magnet-9rl 2>/dev/null || true

# Run the Solanum container
echo "Starting Solanum IRC server container..."
docker run -d --name magnet-9rl \
  --restart unless-stopped \
  --cap-add NET_ADMIN \
  --device /dev/net/tun \
  -p 6667:6667 \
  -p 6697:6697 \
  -p 7000:7000 \
  -e SERVER_NAME=magnet-9rl \
  -e SERVER_SID=9RL \
  -e SERVER_DESCRIPTION="Magnet IRC Network - US Hub" \
  -e PRIMARY_REGION=tor \
  -e TAILSCALE_AUTHKEY=<TAILSCALE_AUTH_KEY> \
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
  registry.digitalocean.com/magnet-irc/solanum:9rl

echo "Waiting for container to start..."
sleep 10

# Check container status
docker ps | grep magnet-9rl
docker logs magnet-9rl --tail 20

echo "Deployment complete! IRC server should be accessible on port 6667"
echo "Server IP: $(curl -s ifconfig.me)"