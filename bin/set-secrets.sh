#!/bin/sh
# ABOUTME: Script to generate and set secure passwords for Magnet IRC Network components
# ABOUTME: Creates individual passwords for each server and sets them as Fly.io secrets

set -e

echo "Generating secure passwords for Magnet IRC Network..."

# Generate individual passwords for each server using openssl
SERVICES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
OPERATOR_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-24)
PASSWORD_1EU=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
PASSWORD_9RL=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

echo "Setting secrets for magnet-9rl..."
fly secrets set \
    SERVICES_PASSWORD="$SERVICES_PASSWORD" \
    OPERATOR_PASSWORD="$OPERATOR_PASSWORD" \
    PASSWORD_1EU="$PASSWORD_1EU" \
    PASSWORD_9RL="$PASSWORD_9RL" \
    --app magnet-9rl

echo "Setting secrets for magnet-1eu..."
fly secrets set \
    SERVICES_PASSWORD="$SERVICES_PASSWORD" \
    OPERATOR_PASSWORD="$OPERATOR_PASSWORD" \
    PASSWORD_1EU="$PASSWORD_1EU" \
    PASSWORD_9RL="$PASSWORD_9RL" \
    --app magnet-1eu

echo "Setting secrets for magnet-atheme..."
fly secrets set \
    SERVICES_PASSWORD="$SERVICES_PASSWORD" \
    OPERATOR_PASSWORD="$OPERATOR_PASSWORD" \
    PASSWORD_1EU="$PASSWORD_1EU" \
    PASSWORD_9RL="$PASSWORD_9RL" \
    --app magnet-atheme

echo "All secrets set successfully!"
echo "SERVICES_PASSWORD: $SERVICES_PASSWORD"
echo "OPERATOR_PASSWORD: $OPERATOR_PASSWORD"
echo "PASSWORD_1EU: $PASSWORD_1EU"
echo "PASSWORD_9RL: $PASSWORD_9RL"