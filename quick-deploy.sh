#!/bin/bash
# ABOUTME: Quick deployment script for IRC servers on DigitalOcean droplets
# ABOUTME: Run this on each droplet with SERVER_TYPE environment variable

# Detect which server to deploy based on hostname or parameter
if [ "$1" = "9rl" ] || [ "$(hostname)" = "magnet-9rl-droplet" ]; then
    SERVER_TYPE="9rl"
elif [ "$1" = "1eu" ] || [ "$(hostname)" = "magnet-1eu-droplet" ]; then
    SERVER_TYPE="1eu"
else
    echo "Usage: $0 [9rl|1eu]"
    echo "Or run on a droplet named magnet-9rl-droplet or magnet-1eu-droplet"
    exit 1
fi

echo "Deploying magnet-$SERVER_TYPE server..."

# One-liner to download and run the deployment
if [ "$SERVER_TYPE" = "9rl" ]; then
    curl -fsSL https://raw.githubusercontent.com/perl-irc/neodynium/digitalocean-migration/deploy-9rl.sh | bash
else
    curl -fsSL https://raw.githubusercontent.com/perl-irc/neodynium/digitalocean-migration/deploy-1eu.sh | bash
fi