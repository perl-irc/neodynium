#!/bin/sh
# ABOUTME: Certificate renewal script for Let's Encrypt SSL certificates
# ABOUTME: Run periodically via cron to keep IRC SSL certificates current

set -e

# Load environment variables
if [ -f /etc/environment ]; then
    . /etc/environment
fi

# Check if Let's Encrypt is configured
if [ -z "${SSL_DOMAINS}" ] || [ -z "${ADMIN_EMAIL}" ]; then
    echo "Let's Encrypt not configured, skipping renewal"
    exit 0
fi

echo "Checking certificate renewal for domains: ${SSL_DOMAINS}..."

# Attempt to renew certificate
if certbot renew \
    --non-interactive \
    --quiet \
    --deploy-hook "/opt/solanum/bin/renew-hook.sh"; then
    echo "Certificate renewal check completed"
else
    echo "Certificate renewal failed"
    exit 1
fi