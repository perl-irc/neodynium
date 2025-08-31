#!/bin/bash
# ABOUTME: Generate Solanum connect blocks from Fly.io DNS _instances.internal lookup
# ABOUTME: Creates dynamic server linking configuration based on running instances

set -e

# Function to show usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -a, --app <name>        Fly.io app name (default: from FLY_APP_NAME env)"
    echo "  -r, --region <region>   Current region (default: from FLY_REGION env)"
    echo "  -o, --output <file>     Output file (default: stdout)"
    echo ""
    echo "Example:"
    echo "  $0 --app magnet-irc --region ams"
    echo "  $0 > /opt/solanum/etc/connects.conf"
    exit 0
}

# Parse arguments
OUTPUT=""
APP_NAME="${FLY_APP_NAME}"
CURRENT_REGION="${FLY_REGION}"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -a|--app)
            APP_NAME="$2"
            shift 2
            ;;
        -r|--region)
            CURRENT_REGION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT="$2"
            shift 2
            ;;
        --simulate)
            SIMULATE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [ -z "$APP_NAME" ]; then
    echo "Error: App name not specified and FLY_APP_NAME not set" >&2
    exit 1
fi

# Function to generate SID from region and instance number
generate_sid() {
    local region="$1"
    local instance_num="$2"
    local region_prefix=$(echo "$region" | cut -c1-2 | tr '[:lower:]' '[:upper:]')
    echo "${instance_num}${region_prefix}"
}

# Function to generate connect block
generate_connect_block() {
    local instance_id="$1"
    local region="$2"
    local ipv6="$3"
    local instance_num="$4"
    
    # Skip self
    if [ "$region" = "$CURRENT_REGION" ] && [ "$instance_num" = "1" ]; then
        return
    fi
    
    local sid=$(generate_sid "$region" "$instance_num")
    local server_name="magnet-${region}"
    
    cat <<EOF
/* Connection to ${server_name} (${instance_id}) */
connect "${server_name}.internal" {
    host = "[${ipv6}]";
    send_password = "\${LINK_PASSWORD_OUT}";
    accept_password = "\${LINK_PASSWORD_IN}";
    port = 6667;
    class = "server";
    flags = topicburst;
};

EOF
}

# Function to parse DNS TXT record response
parse_instances() {
    local dns_response="$1"
    local instance_num=0
    local current_region=""
    
    echo "/* Generated connect blocks from _instances.internal */"
    echo "/* Generated at: $(date -u '+%Y-%m-%d %H:%M:%S UTC') */"
    echo "/* Current region: ${CURRENT_REGION} */"
    echo ""
    
    # Parse each line of the DNS response
    # Format expected: "instance_id region ipv6_address"
    echo "$dns_response" | while IFS=' ' read -r instance region ipv6 rest; do
        # Skip empty lines or comments
        [ -z "$instance" ] && continue
        [[ "$instance" =~ ^#.*$ ]] && continue
        
        # Reset counter if region changes
        if [ "$region" != "$current_region" ]; then
            instance_num=1
            current_region="$region"
        else
            instance_num=$((instance_num + 1))
        fi
        
        generate_connect_block "$instance" "$region" "$ipv6" "$instance_num"
    done
}

# Main execution
echo "Querying _instances.${APP_NAME}.internal for running instances..." >&2

# For testing/development: simulate DNS response if needed
if [ "$SIMULATE" = "true" ]; then
    echo "Using simulated DNS response..." >&2
    DNS_RESULT="3287e444b64708 ord fdaa:27:74d0:a7b:569:4950:e79e:2
56837dddad4268 ams fdaa:27:74d0:a7b:569:1c37:481e:2
78945bccef5512 sin fdaa:27:74d0:a7b:569:8821:912a:2"
else
    # Query DNS for instances
    # Using dig for TXT records which Fly.io uses for instance discovery
    DNS_RESULT=$(dig +short TXT "_instances.${APP_NAME}.internal" 2>/dev/null || true)

    if [ -z "$DNS_RESULT" ]; then
        echo "Warning: No instances found via DNS query" >&2
        echo "Trying alternative query method..." >&2
        
        # Alternative: Try using nslookup
        DNS_RESULT=$(nslookup -type=TXT "_instances.${APP_NAME}.internal" 2>/dev/null | grep "text =" | sed 's/.*text = "\(.*\)"/\1/' || true)
    fi

    if [ -z "$DNS_RESULT" ]; then
        echo "Warning: Could not retrieve instance list" >&2
        echo "/* No instances found - manual configuration required */"
        exit 0
    fi
fi

# Generate the configuration
if [ -n "$OUTPUT" ]; then
    parse_instances "$DNS_RESULT" > "$OUTPUT"
    echo "Connect blocks written to: $OUTPUT" >&2
else
    parse_instances "$DNS_RESULT"
fi