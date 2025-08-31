#!/bin/sh
# ABOUTME: Post-renewal hook for Let's Encrypt to reload Solanum with new certificates
# ABOUTME: Called automatically by certbot after successful certificate renewal

set -e

echo "Certificate renewed, reloading Solanum..."

# Send SIGHUP to Solanum to reload configuration and certificates
pkill -HUP -f "/opt/solanum/bin/solanum" || true

echo "Solanum reloaded with new certificate"