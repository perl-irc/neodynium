#!/bin/bash
# ABOUTME: Server control script for Magnet IRC Network applications
# ABOUTME: Manages server applications in the servers/ directory with start/stop/rebuild commands

set -e

# Function to show usage
usage() {
    echo "Usage: $0 <command> [options] <server-name>"
    echo ""
    echo "Commands:"
    echo "  start     Start an existing server"
    echo "  stop      Stop a running server"
    echo "  deploy    Deploy the server (initial deployment)"
    echo "  rebuild   Rebuild and deploy the server"
    echo "  destroy   Destroy the app and all its resources"
    echo ""
    echo "Available servers:"
    for server in servers/*/; do
        if [ -d "$server" ] && [ -f "$server/fly.toml" ]; then
            basename "$server"
        fi
    done
    echo ""
    echo "Examples:"
    echo "  $0 start magnet-9rl     # Start existing server"
    echo "  $0 stop magnet-9rl      # Stop running server"
    echo "  $0 deploy magnet-9rl    # Deploy server (initial deployment)"
    echo "  $0 rebuild magnet-9rl   # Rebuild and deploy server"
    echo "  $0 destroy magnet-9rl   # Destroy server and all resources"
}

# Parse command
if [ $# -eq 0 ]; then
    echo "Error: No command provided"
    usage
    exit 1
fi

COMMAND="$1"
shift

# Handle help flag
if [ "$COMMAND" = "-h" ] || [ "$COMMAND" = "--help" ] || [ "$COMMAND" = "help" ]; then
    usage
    exit 0
fi

# Validate command
case "$COMMAND" in
    start|stop|deploy|rebuild|destroy)
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        usage
        exit 1
        ;;
esac

# Check if server name is provided
if [ $# -eq 0 ]; then
    echo "Error: No server name provided"
    usage
    exit 1
fi

SERVER_NAME="$1"
SERVER_DIR="servers/$SERVER_NAME"

# Validate server directory exists
if [ ! -d "$SERVER_DIR" ]; then
    echo "Error: Server directory '$SERVER_DIR' not found"
    usage
    exit 1
fi

# Validate fly.toml exists
if [ ! -f "$SERVER_DIR/fly.toml" ]; then
    echo "Error: No fly.toml found in '$SERVER_DIR'"
    exit 1
fi

# Change to server directory
cd "$SERVER_DIR"

# Get machine ID for the app (needed for start/stop commands)
if [ "$COMMAND" != "rebuild" ] && [ "$COMMAND" != "deploy" ] && [ "$COMMAND" != "destroy" ]; then
    MACHINE_ID=$(fly machine list --app "$SERVER_NAME" --json | jq -r '.[0].id' 2>/dev/null)

    if [ "$MACHINE_ID" = "null" ] || [ -z "$MACHINE_ID" ]; then
        echo "Error: No machines found for app '$SERVER_NAME'"
        echo "You may need to deploy the app first with: fly deploy --app $SERVER_NAME"
        exit 1
    fi

    echo "Found machine: $MACHINE_ID"
fi

# Execute command
case "$COMMAND" in
    start)
        echo "Starting $SERVER_NAME..."
        fly machine start "$MACHINE_ID" --app "$SERVER_NAME"
        echo "Waiting for $SERVER_NAME to become healthy..."
        fly machine list --app "$SERVER_NAME"
        echo "$SERVER_NAME started successfully!"
        ;;
    stop)
        echo "Stopping $SERVER_NAME..."
        fly machine stop "$MACHINE_ID" --app "$SERVER_NAME"
        echo "$SERVER_NAME stopped successfully!"
        ;;
    deploy)
        echo "Deploying $SERVER_NAME..."
        
        # Check if app exists, create if it doesn't
        if ! fly apps list --org magnet-irc | grep -q "^$SERVER_NAME" 2>/dev/null; then
            echo "App $SERVER_NAME doesn't exist, creating it..."
            fly apps create "$SERVER_NAME" --org magnet-irc
        else
            echo "App $SERVER_NAME already exists"
        fi
        
        # Copy shared app directory from root to build context
        echo "Copying shared app directory from root..."
        if [[ "$SERVER_NAME" == magnet-atheme ]]; then
            # Copy entire atheme directory
            cp -r ../../atheme . || echo "Warning: Could not copy atheme directory"
        else
            # Copy entire solanum directory
            cp -r ../../solanum . || echo "Warning: Could not copy solanum directory"
        fi
        
        # Deploy
        fly deploy --app "$SERVER_NAME"
        
        # Clean up copied directory
        echo "Cleaning up temporary directory..."
        if [[ "$SERVER_NAME" == magnet-atheme ]]; then
            rm -rf atheme
        else
            rm -rf solanum
        fi
        
        echo "$SERVER_NAME deployed successfully!"
        ;;
    rebuild)
        echo "Rebuilding and deploying $SERVER_NAME..."
        
        # Copy shared app directory from root to build context
        echo "Copying shared app directory from root..."
        if [[ "$SERVER_NAME" == magnet-atheme ]]; then
            # Copy entire atheme directory
            cp -r ../../atheme . || echo "Warning: Could not copy atheme directory"
        else
            # Copy entire solanum directory
            cp -r ../../solanum . || echo "Warning: Could not copy solanum directory"
        fi
        
        # Deploy
        fly deploy --app "$SERVER_NAME" --no-cache
        
        # Clean up copied directory
        echo "Cleaning up temporary directory..."
        if [[ "$SERVER_NAME" == magnet-atheme ]]; then
            rm -rf atheme
        else
            rm -rf solanum
        fi
        
        echo "$SERVER_NAME rebuilt and deployed successfully!"
        ;;
    destroy)
        echo "WARNING: This will permanently destroy $SERVER_NAME and all its data!"
        echo "Are you sure you want to continue? (yes/no)"
        read -r confirmation
        
        if [ "$confirmation" = "yes" ]; then
            echo "Destroying $SERVER_NAME..."
            
            # Delete all volumes associated with the app
            echo "Deleting volumes..."
            fly volumes list --app "$SERVER_NAME" --json | jq -r '.[].id' | while read -r volume_id; do
                if [ -n "$volume_id" ]; then
                    echo "Deleting volume: $volume_id"
                    fly volumes delete "$volume_id" --app "$SERVER_NAME" --yes || echo "Warning: Failed to delete volume $volume_id"
                fi
            done
            
            # Delete the app
            echo "Deleting app..."
            fly apps destroy "$SERVER_NAME" --yes
            
            echo "$SERVER_NAME destroyed successfully!"
        else
            echo "Destroy cancelled."
            exit 0
        fi
        ;;
esac