#!/bin/bash
# ABOUTME: Script to manage IRC operators with hashed passwords stored in Fly secrets
# ABOUTME: Supports add/remove operations - requires manual updates to opers.conf.template

set -e

# Function to show usage
usage() {
    echo "Usage: $0 <command> <oper-name> [options]"
    echo ""
    echo "Commands:"
    echo "  add <oper-name>         Add operator password to secrets"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -a, --app <app>         Fly.io app name (default: magnet-9rl, or 'all' for all servers)"
    echo "  -p, --password <pass>   Provide password on command line (plaintext)"
    echo "  -P, --prehashed <hash>  Provide pre-hashed password on command line"
    echo ""
    echo "Examples:"
    echo "  $0 add john               # Add operator 'john' password to secrets (prompts for password)"
    echo "  $0 add alice -a all       # Add operator 'alice' to all IRC servers"
    echo "  $0 add bob -p mypass      # Add operator 'bob' with plaintext password 'mypass'"
    echo "  $0 add carol -P '\$6\$...' # Add operator 'carol' with pre-hashed password"
    echo ""
    echo "Note: You must manually add the operator block to solanum/opers.conf.template"
    exit 0
}

# Parse arguments
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

COMMAND="$1"
shift

if [ "$COMMAND" != "add" ]; then
    echo "Error: Unknown command '$COMMAND'"
    echo "Supported commands: add"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Error: Missing operator name"
    usage
fi

OPER_NAME="$1"
shift

# Default values
FLY_APP="all"
PREHASHED=false
CMDLINE_PASSWORD=""
PREHASHED_PASSWORD=""

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app)
            FLY_APP="$2"
            shift 2
            ;;
        -p|--password)
            CMDLINE_PASSWORD="$2"
            shift 2
            ;;
        -P|--prehashed)
            PREHASHED=true
            PREHASHED_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Determine which apps to update
if [ "$FLY_APP" = "all" ]; then
    APPS=("magnet-9rl" "magnet-1eu")
else
    APPS=("$FLY_APP")
fi

if [ "$PREHASHED" = true ]; then
    # Use pre-hashed password from command line
    HASH="$PREHASHED_PASSWORD"
    if [ -z "$HASH" ]; then
        echo "Error: Empty password hash provided with -P"
        exit 1
    fi
    echo "Using provided hash: ${HASH:0:20}..."
elif [ -n "$CMDLINE_PASSWORD" ]; then
    # Use password provided on command line
    PASSWORD="$CMDLINE_PASSWORD"
    echo "Using provided password for operator '$OPER_NAME'"

    # Generate hashed password using mkpasswd via SSH (use first app in list)
    echo "Generating password hash..."
    HASH=$(fly ssh console --app "${APPS[0]}" -C "/opt/solanum/bin/mkpasswd" <<< "$PASSWORD" 2>/dev/null | grep '^\$' | head -1)

    if [ -z "$HASH" ]; then
        echo "Error: Failed to generate password hash"
        echo "Make sure ${APPS[0]} is running and has mkpasswd installed"
        echo "Alternatively, use -P flag with a pre-hashed password"
        exit 1
    fi

    echo "Generated hash: ${HASH:0:20}..."
else
    # Prompt for plaintext password
    echo "Enter password for operator '$OPER_NAME':"
    read -s PASSWORD
    echo "Confirm password:"
    read -s PASSWORD_CONFIRM

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo "Error: Passwords do not match"
        exit 1
    fi

    # Generate hashed password using mkpasswd via SSH (use first app in list)
    echo "Generating password hash..."
    HASH=$(fly ssh console --app "${APPS[0]}" -C "/opt/solanum/bin/mkpasswd" <<< "$PASSWORD" 2>/dev/null | grep '^\$' | head -1)

    if [ -z "$HASH" ]; then
        echo "Error: Failed to generate password hash"
        echo "Make sure ${APPS[0]} is running and has mkpasswd installed"
        echo "Alternatively, use -P flag with a pre-hashed password"
        exit 1
    fi

    echo "Generated hash: ${HASH:0:20}..."
fi

# Set password secret for each app
for APP in "${APPS[@]}"; do
    echo "Setting password secret for $APP..."

    # Store just the hashed password as a secret
    SECRET_NAME="OPER_$(echo "$OPER_NAME" | tr '[:lower:]' '[:upper:]')_PASSWORD"
    fly secrets set "$SECRET_NAME=$HASH" --app "$APP"
done

# Add operator block to template file
OPER_BLOCK="
operator \"$OPER_NAME\" {
    user = \"*@*.camel-kanyu.ts.net\", \"*@100.*\";
    password = \"\${OPER_$(echo "$OPER_NAME" | tr '[:lower:]' '[:upper:]')_PASSWORD}\";
    snomask = \"+Zbfkrsuy\";
    privset = \"admin\";
};"

echo "Adding operator block to solanum/opers.conf.template..."
echo "$OPER_BLOCK" >> /Users/perigrin/dev/magnet/solanum/opers.conf.template

echo ""
echo "✓ Password for operator '$OPER_NAME' has been set successfully!"
echo "✓ Operator block added to solanum/opers.conf.template"
echo ""
echo "Next steps:"
echo "1. Rebuild the server(s) to include the new operator config:"
for APP in "${APPS[@]}"; do
    echo "   fly deploy --app $APP"
done
echo ""
echo "2. The operator can then use /oper $OPER_NAME <password>"
