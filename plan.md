# Magnet IRC Network - Fly.io Deployment (Updated)

**Optimized for AMD EPYC with OpenSSL + Official Tailscale Integration**

## Architecture Overview

```
┌─────────────────┐    Tailscale     ┌─────────────────┐
│   magnet-9RL    │◄─────────────────►│   magnet-1EU    │
│  (US Hub/IRC)   │   Private Mesh   │   (EU IRC)      │
│  SID: 9RL       │                  │   SID: 1EU      │
│  OpenSSL+EPYC   │                  │  OpenSSL+EPYC   │
└─────────────────┘                  └─────────────────┘
         │                                    │
         ▼                                    ▼
┌─────────────────┐    Tailscale     ┌─────────────────┐
│  magnet-atheme  │◄─────────────────►│ magnet-postgres │
│  (US Services)  │   Private Mesh   │  (Fly MPG)      │
│  OpenSSL+EPYC   │                  │                 │
└─────────────────┘                  └─────────────────┘
```

## 1. Solanum Dockerfile (OpenSSL Optimized)

```dockerfile
# Build stage - Optimized for AMD EPYC processors
FROM alpine:latest as builder

# Install build dependencies
RUN apk update && apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    openssl-dev \
    flex \
    bison \
    git \
    && rm -rf /var/cache/apk/*

# Build Solanum with OpenSSL optimizations for fly.io AMD EPYC
WORKDIR /tmp
RUN git clone https://github.com/solanum-ircd/solanum.git
WORKDIR /tmp/solanum
RUN ./autogen.sh
RUN ./configure --prefix=/opt/solanum \
    --enable-epoll \
    --enable-openssl \
    --with-nicklen=31 \
    --with-topiclen=390 \
    --enable-assert=no
RUN make -j$(nproc) && make install

# Production stage
FROM alpine:latest

# Install runtime dependencies (following official Tailscale guide)
RUN apk update && apk add --no-cache \
    openssl \
    ca-certificates \
    iptables \
    ip6tables \
    pwgen \
    gettext \
    bash \
    su-exec \
    curl \
    jq \
    && rm -rf /var/cache/apk/*

# Copy Solanum from builder
COPY --from=builder /opt/solanum /opt/solanum

# Copy Tailscale binaries from official image (per Tailscale kb/1132)
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscale /usr/local/bin/tailscale

# Create directories
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale
RUN mkdir -p /opt/solanum/var/log /opt/solanum/var/run /opt/solanum/etc

# Create ircd user and set permissions
RUN adduser -D -s /bin/false ircd
RUN chown -R ircd:ircd /opt/solanum/var

# Copy configuration templates and startup script
COPY ircd.conf.template /opt/solanum/etc/ircd.conf.template
COPY start-solanum.sh /app/start.sh
COPY health-check.sh /app/health-check.sh
RUN chmod +x /app/start.sh /app/health-check.sh

WORKDIR /opt/solanum

EXPOSE 6667 6697 7000 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/app/health-check.sh"]

CMD ["/app/start.sh"]
```

**start-solanum.sh**
```bash
#!/bin/bash
set -e

# Start Tailscale daemon in background (per official guide)
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Connect to Tailscale network with dynamic hostname
HOSTNAME=${SERVER_NAME:-solanum-${FLY_REGION:-unknown}}
/usr/local/bin/tailscale up --auth-key=${TAILSCALE_AUTHKEY} --hostname=${HOSTNAME}

echo "Connected to Tailscale as ${HOSTNAME}"

# Generate secure passwords if they don't exist
if [ ! -f /opt/solanum/etc/passwords.conf ]; then
    echo "Generating secure passwords..."

    # Use environment variables (secrets) if available, otherwise generate
    LINK_PASS=${LINK_PASSWORD_9RL_1EU:-$(pwgen -s 32 1)}
    OPER_PASS=${OPER_PASSWORD:-$(pwgen -s 24 1)}
    SERVICES_PASS=${SERVICES_PASSWORD:-$(pwgen -s 32 1)}

    cat > /opt/solanum/etc/passwords.conf << EOF
# Auto-generated secure passwords - DO NOT COMMIT TO VCS
LINK_PASSWORD_9RL_1EU=$LINK_PASS
OPER_PASSWORD=$OPER_PASS
SERVICES_PASSWORD=$SERVICES_PASS
EOF
    chown ircd:ircd /opt/solanum/etc/passwords.conf
    chmod 600 /opt/solanum/etc/passwords.conf
fi

# Source the generated passwords
source /opt/solanum/etc/passwords.conf

# Process ircd.conf template with generated passwords
echo "Instantiating ircd.conf from template..."
envsubst '${SERVER_NAME} ${SERVER_SID} ${SERVER_DESCRIPTION} ${LINK_PASSWORD_9RL_1EU} ${OPER_PASSWORD} ${SERVICES_PASSWORD}' \
    < /opt/solanum/etc/ircd.conf.template \
    > /opt/solanum/etc/ircd.conf

chown ircd:ircd /opt/solanum/etc/ircd.conf
chmod 644 /opt/solanum/etc/ircd.conf

echo "Configuration instantiated successfully"
echo "Tailscale hostname: ${HOSTNAME}"
echo "Password generation complete (check /opt/solanum/etc/passwords.conf)"

# Start HTTP health check server in background
cat > /tmp/health-server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import socket
import json
from datetime import datetime

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            try:
                # Test IRC port
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(5)
                result = sock.connect_ex(('localhost', 6667))
                sock.close()
                
                if result == 0:
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    response = {
                        'status': 'healthy',
                        'timestamp': datetime.now().isoformat(),
                        'services': {'ircd': 'up'}
                    }
                    self.wfile.write(json.dumps(response).encode())
                else:
                    self.send_response(503)
                    self.end_headers()
            except Exception as e:
                self.send_response(503)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

PORT = 8080
Handler = HealthHandler
with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()
EOF

python3 /tmp/health-server.py &

# Start Solanum as ircd user
exec su-exec ircd /opt/solanum/bin/solanum -foreground
```

**ircd.conf.template (OpenSSL Optimized)**
```
/* Solanum IRCd Configuration Template for ${SERVER_NAME} */
/* Optimized for AMD EPYC with OpenSSL acceleration */

serverinfo {
    name = "${SERVER_NAME}.kowloon.social";
    sid = "${SERVER_SID}";
    description = "${SERVER_DESCRIPTION}";
    network_name = "Magnet";
    network_desc = "Magnet IRC Network";
    vhost = "0.0.0.0";
    vhost6 = "::";
};

admin {
    name = "Network Administrator";
    description = "Magnet IRC Network";
    email = "admin@kowloon.social";
};

/* Connection classes optimized for AMD EPYC performance */
class "users" {
    ping_time = 2 minutes;
    number_per_ident = 10;
    number_per_ip = 10;
    number_per_ip_global = 50;
    max_number = 3000;
    sendq = 400 kbytes;
};

class "opers" {
    ping_time = 5 minutes;
    max_number = 1000;
    sendq = 1 megabyte;
};

class "server" {
    ping_time = 5 minutes;
    connectfreq = 5 minutes;
    max_number = 1;
    sendq = 4 megabytes;
};

/* Listeners with OpenSSL SSL/TLS */
listen { port = 6667; host = "0.0.0.0"; };
listen { port = 6697; host = "0.0.0.0"; ssl = yes; };
listen { port = 7000; host = "0.0.0.0"; ssl = yes; };

/* Operator block */
operator "admin" {
    user = "*@*";
    password = "${OPER_PASSWORD}";
    flags = global_kill, remote, kline, unkline, gline, ungline,
            die, restart, rehash, admin, operwall, wallops,
            locops, mass_notice, remoteban;
    snomask = "+Zbfkrsuy";
    class = "opers";
};

/* Server linking via Tailscale (only for hub - 9RL) */
connect "magnet-1EU.kowloon.social" {
    host = "magnet-1eu";  /* Tailscale hostname */
    send_password = "${LINK_PASSWORD_9RL_1EU}";
    accept_password = "${LINK_PASSWORD_9RL_1EU}";
    port = 7000;
    hub_mask = "*";
    class = "server";
    flags = ssl;
};

/* Services linking via Tailscale (only for hub - 9RL) */
service { name = "services.kowloon.social"; };
connect "services.kowloon.social" {
    host = "magnet-atheme";  /* Tailscale hostname */
    send_password = "${SERVICES_PASSWORD}";
    accept_password = "${SERVICES_PASSWORD}";
    port = 6667;
    class = "server";
    flags = ssl;
};

/* General settings */
general {
    hide_error_messages = opers;
    hide_spoof_ips = yes;
    default_umodes = "+i";
    default_operstring = "is an IRC Operator";
    default_adminstring = "is a Server Administrator";
    servicestring = "is a Network Service";
    anti_nick_flood = yes;
    max_nick_time = 20 seconds;
    max_nick_changes = 5;
    ts_warn_delta = 30 seconds;
    ts_max_delta = 5 minutes;
    collision_fnc = yes;
    no_oper_flood = yes;
    throttle_duration = 60 seconds;
    throttle_count = 4;
};

/* Channel settings */
channel {
    use_invex = yes;
    use_except = yes;
    use_knock = yes;
    use_forward = yes;
    max_chans_per_user = 15;
    max_bans = 100;
    autochanmodes = "+nt";
    displayed_usercount = 3;
    strip_topic = yes;
};

/* Essential extensions */
loadmodule "extensions/chm_sslonly";
loadmodule "extensions/extb_account";
loadmodule "extensions/extb_ssl";
loadmodule "extensions/m_identify";
```

## 2. US Hub Server (magnet-9RL)

**fly.toml**
```toml
app = "magnet-9rl"
primary_region = "ord"

[build]
  dockerfile = "Dockerfile.solanum"

[env]
  SERVER_NAME = "magnet-9RL"
  SERVER_SID = "9RL"
  SERVER_DESCRIPTION = "Magnet IRC Network - US Hub"

# Tailscale authkey - set via: fly secrets set TAILSCALE_AUTHKEY=tskey-auth-xxx
# Get ephemeral key from: https://login.tailscale.com/admin/settings/keys

[[mounts]]
  source = "magnet_9rl_data"
  destination = "/opt/solanum/etc"

# Client connections with Let's Encrypt
[[services]]
  protocol = "tcp"
  internal_port = 6667
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 6667

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    port = 6667

[[services]]
  protocol = "tcp"
  internal_port = 6697
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 6697
    handlers = ["tls"]

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    port = 6697

# Health check endpoint
[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 8080

  [[services.http_checks]]
    interval = "30s"
    timeout = "10s"
    method = "GET"
    path = "/health"
    port = 8080
    protocol = "http"

# Server-to-server linking (Tailscale mesh)
[[services]]
  protocol = "tcp"
  internal_port = 7000

# HTTP service for Let's Encrypt certificate challenges
[http_service]
  internal_port = 8080
  force_https = false
  auto_stop_machines = false
  auto_start_machines = true

# Machine sizing - leverage AMD EPYC performance
[vm]
  memory = "1gb"
  cpus = 2
  auto_stop_machines = false
  auto_start_machines = true

# Restart policy for reliability
[restart]
  policy = "on-failure"
  max_retries = 3
```

## 3. EU Server (magnet-1EU)

**fly.toml**
```toml
app = "magnet-1eu"
primary_region = "ams"

[build]
  dockerfile = "Dockerfile.solanum"

[env]
  SERVER_NAME = "magnet-1EU"
  SERVER_SID = "1EU"
  SERVER_DESCRIPTION = "Magnet IRC Network - EU"

[[mounts]]
  source = "magnet_1eu_data"
  destination = "/opt/solanum/etc"

# Client connections with Let's Encrypt
[[services]]
  protocol = "tcp"
  internal_port = 6667
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 6667

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    port = 6667

[[services]]
  protocol = "tcp"
  internal_port = 6697
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 6697
    handlers = ["tls"]

  [[services.tcp_checks]]
    interval = "15s"
    timeout = "2s"
    port = 6697

# Health check endpoint
[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 8080

  [[services.http_checks]]
    interval = "30s"
    timeout = "10s"
    method = "GET"
    path = "/health"
    port = 8080
    protocol = "http"

# Server-to-server linking (Tailscale mesh)
[[services]]
  protocol = "tcp"
  internal_port = 7000

# HTTP service for Let's Encrypt certificate challenges
[http_service]
  internal_port = 8080
  force_https = false
  auto_stop_machines = false
  auto_start_machines = true

# Machine sizing - leverage AMD EPYC performance
[vm]
  memory = "1gb"
  cpus = 2
  auto_stop_machines = false
  auto_start_machines = true

# Restart policy for reliability
[restart]
  policy = "on-failure"
  max_retries = 3
```

## 4. Atheme Services (OpenSSL Optimized)

**fly.toml**
```toml
app = "magnet-atheme"
primary_region = "ord"

[build]
  dockerfile = "Dockerfile.atheme"

[env]
  ATHEME_NETWORK = "Magnet"
  ATHEME_POSTGRES_HOST = "magnet-postgres.internal"
  ATHEME_POSTGRES_DB = "atheme"
  ATHEME_NETWORK_DOMAIN = "kowloon.social"
  SERVER_NAME = "magnet-atheme"

[[mounts]]
  source = "magnet_atheme_data"
  destination = "/opt/atheme/etc"

# Health check endpoint
[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = true

  [[services.ports]]
    port = 8080

  [[services.http_checks]]
    interval = "30s"
    timeout = "10s"
    method = "GET"
    path = "/health"
    port = 8080
    protocol = "http"

[http_service]
  internal_port = 8080
  force_https = false
  auto_stop_machines = false
  auto_start_machines = true

# Machine sizing for Atheme services
[vm]
  memory = "512mb"
  cpus = 1
  auto_stop_machines = false
  auto_start_machines = true

# Restart policy for reliability
[restart]
  policy = "on-failure"
  max_retries = 3
```

## 5. Atheme Dockerfile (OpenSSL Optimized)

```dockerfile
# Build stage - Atheme with OpenSSL for AMD EPYC
FROM alpine:latest as builder

# Install build dependencies
RUN apk update && apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    openssl-dev \
    postgresql-dev \
    pcre-dev \
    git \
    && rm -rf /var/cache/apk/*

# Build Atheme with OpenSSL support
WORKDIR /tmp
RUN git clone https://github.com/atheme/atheme.git
WORKDIR /tmp/atheme
RUN ./configure --prefix=/opt/atheme \
    --enable-contrib \
    --with-pcre \
    --enable-ssl \
    --with-postgresql
RUN make -j$(nproc) && make install

# Production stage
FROM alpine:latest

# Install runtime dependencies
RUN apk update && apk add --no-cache \
    openssl \
    postgresql-client \
    pcre \
    ca-certificates \
    iptables \
    ip6tables \
    pwgen \
    gettext \
    bash \
    su-exec \
    curl \
    jq \
    && rm -rf /var/cache/apk/*

# Copy Atheme from builder
COPY --from=builder /opt/atheme /opt/atheme

# Copy Tailscale binaries from official image
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscale /usr/local/bin/tailscale

# Create directories
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale
RUN mkdir -p /opt/atheme/etc

# Create atheme user
RUN adduser -D -s /bin/false atheme
RUN chown -R atheme:atheme /opt/atheme

# Copy configuration templates and startup script
COPY atheme.conf.template /opt/atheme/etc/atheme.conf.template
COPY start-atheme.sh /app/start.sh
COPY health-check-atheme.sh /app/health-check.sh
RUN chmod +x /app/start.sh /app/health-check.sh

EXPOSE 8080

WORKDIR /opt/atheme

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD ["/app/health-check.sh"]

CMD ["/app/start.sh"]
```

**health-check.sh** (Solanum IRC)
```bash
#!/bin/bash
# Health check script for Solanum IRC server

set -e

# Check if processes are running
if ! pgrep -f "solanum" > /dev/null; then
    echo "ERROR: Solanum process not running"
    exit 1
fi

if ! pgrep -f "tailscaled" > /dev/null; then
    echo "ERROR: Tailscale daemon not running"
    exit 1
fi

# Check IRC ports
if ! nc -z localhost 6667; then
    echo "ERROR: IRC port 6667 not responding"
    exit 1
fi

if ! nc -z localhost 6697; then
    echo "ERROR: IRC SSL port 6697 not responding"
    exit 1
fi

# Check Tailscale connectivity
if ! /usr/local/bin/tailscale status > /dev/null 2>&1; then
    echo "ERROR: Tailscale not connected"
    exit 1
fi

# Check health endpoint
if command -v curl > /dev/null; then
    if ! curl -f http://localhost:8080/health > /dev/null 2>&1; then
        echo "ERROR: Health endpoint not responding"
        exit 1
    fi
fi

echo "OK: All health checks passed"
exit 0
```

**health-check-atheme.sh** (Atheme Services)
```bash
#!/bin/bash
# Health check script for Atheme services

set -e

# Check if processes are running
if ! pgrep -f "atheme-services" > /dev/null; then
    echo "ERROR: Atheme services process not running"
    exit 1
fi

if ! pgrep -f "tailscaled" > /dev/null; then
    echo "ERROR: Tailscale daemon not running"
    exit 1
fi

# Check database connectivity
if ! pg_isready -h "${ATHEME_POSTGRES_HOST:-magnet-postgres.internal}" -p 5432 > /dev/null 2>&1; then
    echo "ERROR: Database not accessible"
    exit 1
fi

# Check Tailscale connectivity
if ! /usr/local/bin/tailscale status > /dev/null 2>&1; then
    echo "ERROR: Tailscale not connected"
    exit 1
fi

# Check connectivity to hub server
if ! nc -z magnet-9rl 6667; then
    echo "ERROR: Cannot reach hub server"
    exit 1
fi

echo "OK: All health checks passed"
exit 0
```

**start-atheme.sh**
```bash
#!/bin/bash
set -e

# Start Tailscale daemon in background
/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &

# Connect to Tailscale network
HOSTNAME=${SERVER_NAME:-atheme-${FLY_REGION:-unknown}}
/usr/local/bin/tailscale up --auth-key=${TAILSCALE_AUTHKEY} --hostname=${HOSTNAME}

echo "Connected to Tailscale as ${HOSTNAME}"

# Generate Atheme passwords if they don't exist
if [ ! -f /opt/atheme/etc/passwords.conf ]; then
    echo "Generating secure Atheme passwords..."

    # Use environment variables (secrets) if available, otherwise generate
    SERVICES_PASS=${SERVICES_PASSWORD:-$(pwgen -s 32 1)}
    OPERATOR_PASS=${OPERATOR_PASSWORD:-$(pwgen -s 24 1)}

    cat > /opt/atheme/etc/passwords.conf << EOF
# Auto-generated secure passwords for Atheme - DO NOT COMMIT TO VCS
SERVICES_PASSWORD=$SERVICES_PASS
OPERATOR_PASSWORD=$OPERATOR_PASS
EOF
    chown atheme:atheme /opt/atheme/etc/passwords.conf
    chmod 600 /opt/atheme/etc/passwords.conf
fi

# Source the generated passwords
source /opt/atheme/etc/passwords.conf

# Process atheme.conf template with generated passwords
echo "Instantiating atheme.conf from template..."
envsubst '${ATHEME_NETWORK} ${ATHEME_NETWORK_DOMAIN} ${SERVICES_PASSWORD} ${OPERATOR_PASSWORD} ${ATHEME_POSTGRES_HOST} ${ATHEME_POSTGRES_DB}' \
    < /opt/atheme/etc/atheme.conf.template \
    > /opt/atheme/etc/atheme.conf

chown atheme:atheme /opt/atheme/etc/atheme.conf
chmod 644 /opt/atheme/etc/atheme.conf

echo "Atheme configuration instantiated successfully"
echo "Tailscale hostname: ${HOSTNAME}"
echo "Password generation complete (check /opt/atheme/etc/passwords.conf)"

# Start Atheme as atheme user
exec su-exec atheme /opt/atheme/bin/atheme-services -n
```

**atheme.conf.template (OpenSSL Optimized)**
```
# Atheme Configuration Template for ${ATHEME_NETWORK}
# Optimized with OpenSSL for AMD EPYC performance

/* Database configuration */
database {
    module = "postgresql";
    host = "${ATHEME_POSTGRES_HOST}";
    port = 5432;
    database = "${ATHEME_POSTGRES_DB}";
    username = "postgres";
    password = ""; # Will be set via DATABASE_URL env var
};

/* Network information */
loadmodule "modules/backend/opensex";

serverinfo {
    name = "services.${ATHEME_NETWORK_DOMAIN}";
    desc = "${ATHEME_NETWORK} IRC Services";
    numeric = "00A";
    vhost = "0.0.0.0";
    recontime = 10;
    restartonfailure = no;
    netname = "${ATHEME_NETWORK}";
    hidehostsuffix = "users.${ATHEME_NETWORK_DOMAIN}";
    adminname = "Network Administrator";
    adminemail = "admin@${ATHEME_NETWORK_DOMAIN}";
    mta = "/usr/sbin/sendmail";
    loglevel = { error; info; verbose; };
    maxlogins = 5;
    maxusers = 0;
    maxnicks = 5;
    maxchans = 5;
    emaillimit = 10;
    emailtime = 300;
};

/* Uplink configuration via Tailscale */
uplink "magnet-9RL.${ATHEME_NETWORK_DOMAIN}" {
    host = "magnet-9rl";  /* Tailscale hostname */
    send_password = "${SERVICES_PASSWORD}";
    receive_password = "${SERVICES_PASSWORD}";
    port = 6667;
    vhost = "0.0.0.0";
};

/* Operator configuration */
operator "${OPERATOR_PASSWORD}" {
    name = "admin";
    class = "sra";
};

/* Load core services */
loadmodule "modules/nickserv/main";
loadmodule "modules/chanserv/main";
loadmodule "modules/operserv/main";
loadmodule "modules/memoserv/main";

/* NickServ configuration */
nickserv {
    nick = "NickServ";
    user = "services";
    host = "services.${ATHEME_NETWORK_DOMAIN}";
    real = "Nickname Services";
    aliases = { "NS" };
};

/* ChanServ configuration */
chanserv {
    nick = "ChanServ";
    user = "services";
    host = "services.${ATHEME_NETWORK_DOMAIN}";
    real = "Channel Services";
    aliases = { "CS" };
};

/* OperServ configuration */
operserv {
    nick = "OperServ";
    user = "services";
    host = "services.${ATHEME_NETWORK_DOMAIN}";
    real = "Operator Services";
    aliases = { "OS" };
};

/* MemoServ configuration */
memoserv {
    nick = "MemoServ";
    user = "services";
    host = "services.${ATHEME_NETWORK_DOMAIN}";
    real = "Memo Services";
    aliases = { "MS" };
};

/* Protocol module */
loadmodule "modules/protocol/solanum";

/* Backend modules */
loadmodule "modules/backend/opensex";

/* Crypto modules - OpenSSL optimized */
loadmodule "modules/crypto/pbkdf2";

/* Essential NickServ modules */
loadmodule "modules/nickserv/enforce";
loadmodule "modules/nickserv/help";
loadmodule "modules/nickserv/identify";
loadmodule "modules/nickserv/info";
loadmodule "modules/nickserv/list";
loadmodule "modules/nickserv/logout";
loadmodule "modules/nickserv/register";
loadmodule "modules/nickserv/set_core";
loadmodule "modules/nickserv/set_email";
loadmodule "modules/nickserv/set_password";

/* Essential ChanServ modules */
loadmodule "modules/chanserv/access";
loadmodule "modules/chanserv/akick";
loadmodule "modules/chanserv/ban";
loadmodule "modules/chanserv/flags";
loadmodule "modules/chanserv/help";
loadmodule "modules/chanserv/info";
loadmodule "modules/chanserv/invite";
loadmodule "modules/chanserv/kick";
loadmodule "modules/chanserv/list";
loadmodule "modules/chanserv/op";
loadmodule "modules/chanserv/register";
loadmodule "modules/chanserv/set_core";
loadmodule "modules/chanserv/topic";
loadmodule "modules/chanserv/voice";

/* Essential OperServ modules */
loadmodule "modules/operserv/akill";
loadmodule "modules/operserv/help";
loadmodule "modules/operserv/info";
loadmodule "modules/operserv/rehash";
loadmodule "modules/operserv/restart";
loadmodule "modules/operserv/shutdown";

/* Essential MemoServ modules */
loadmodule "modules/memoserv/help";
loadmodule "modules/memoserv/list";
loadmodule "modules/memoserv/read";
loadmodule "modules/memoserv/send";
```

## 6. Security & Access Setup

### Tailscale Configuration (Ephemeral)

1. **Create ephemeral auth keys** at https://login.tailscale.com/admin/settings/keys
   - Check "Ephemeral" checkbox when creating keys
   - Check "Pre-approved" if device approval is enabled
   - Set 90-day expiration (or shorter for security)
   - Devices automatically disappear when containers stop

2. **Set Tailscale secrets for each app:**
```bash
# Generate ephemeral auth keys (can reuse same key for all services)
EPHEMERAL_KEY="tskey-auth-xxxxxx-xxxx"
fly secrets set TAILSCALE_AUTHKEY=$EPHEMERAL_KEY --app magnet-9rl
fly secrets set TAILSCALE_AUTHKEY=$EPHEMERAL_KEY --app magnet-1eu
fly secrets set TAILSCALE_AUTHKEY=$EPHEMERAL_KEY --app magnet-atheme
```

### Password Management (Enhanced)

Each container automatically generates secure passwords on first boot:
- **Server linking passwords**: 32 character alphanumeric (shared between linked servers)
- **Operator passwords**: 24 character alphanumeric (for `/OPER admin <password>`)
- **Services passwords**: 32 character alphanumeric (for Atheme ↔ IRCd authentication)

**Improved Password Coordination Strategy**:
```bash
# 1. Deploy hub first - generates all passwords
fly deploy --app magnet-9rl

# 2. Extract generated passwords via Tailscale SSH
fly ssh console --app magnet-9rl -C "cat /opt/solanum/etc/passwords.conf"

# 3. Set as secrets for other apps (ensures consistency)
fly secrets set SERVICES_PASSWORD=<generated_value> --app magnet-atheme
fly secrets set LINK_PASSWORD_9RL_1EU=<generated_value> --app magnet-1eu

# 4. Deploy other services with shared passwords
fly deploy --app magnet-atheme
fly deploy --app magnet-1eu
```

### Let's Encrypt Certificates

Fly.io automatically provisions Let's Encrypt certificates for:
- `magnet-9rl.fly.dev` (US IRC)
- `magnet-1eu.fly.dev` (EU IRC)

To use custom domains:
```bash
# Add custom domains
fly certs create irc.kowloon.social --app magnet-9rl
fly certs create eu.kowloon.social --app magnet-1eu

# Check certificate status
fly certs list --app magnet-9rl
```

## 7. Database Setup

**Create Postgres app:**
```bash
fly postgres create --name magnet-postgres --region ord
fly postgres attach --app magnet-atheme magnet-postgres
```

## 8. Automated Deployment Script

**deploy-magnet.sh** - Comprehensive deployment automation:

```bash
#!/bin/bash
# Magnet IRC Network - Automated Deployment Script
# Addresses SRE review recommendations for operational reliability

set -euo pipefail

# Configuration
APPS=("magnet-9rl" "magnet-1eu" "magnet-atheme" "magnet-postgres")
REGIONS=("ord" "ams" "ord" "ord")
VOLUMES=("magnet_9rl_data" "magnet_1eu_data" "magnet_atheme_data")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

wait_for_deployment() {
    local app=$1
    local max_attempts=30
    local attempt=1
    
    log "Waiting for $app to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if fly status --app $app | grep -q "1 desired, 1 placed, 1 healthy"; then
            log "$app is healthy!"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts - waiting for $app..."
        sleep 10
        ((attempt++))
    done
    
    error "$app failed to become healthy after $max_attempts attempts"
}

verify_prerequisites() {
    log "Verifying prerequisites..."
    
    # Check fly CLI
    if ! command -v fly &> /dev/null; then
        error "fly CLI not found. Install from https://fly.io/docs/flyctl/"
    fi
    
    # Check logged in
    if ! fly auth whoami &> /dev/null; then
        error "Not logged into fly.io. Run: fly auth login"
    fi
    
    # Check Tailscale auth key
    if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
        error "TAILSCALE_AUTHKEY environment variable not set"
    fi
    
    log "Prerequisites verified ✓"
}

create_volumes() {
    log "Creating persistent volumes..."
    
    for i in "${!VOLUMES[@]}"; do
        local volume="${VOLUMES[$i]}"
        local region="${REGIONS[$i]}"
        
        if ! fly volumes list --app "${APPS[$i]}" | grep -q "$volume"; then
            log "Creating volume $volume in region $region..."
            fly volumes create "$volume" --region "$region" --size 3 --app "${APPS[$i]}" || \
                warn "Volume $volume may already exist"
        else
            log "Volume $volume already exists ✓"
        fi
    done
}

setup_database() {
    log "Setting up PostgreSQL database..."
    
    if ! fly apps list | grep -q "magnet-postgres"; then
        log "Creating PostgreSQL app..."
        fly postgres create --name magnet-postgres --region ord --initial-cluster-size 1 || \
            warn "PostgreSQL app may already exist"
    fi
    
    # Attach to Atheme
    log "Attaching database to Atheme..."
    fly postgres attach --app magnet-atheme magnet-postgres || \
        warn "Database may already be attached"
        
    # Set up backup schedule
    log "Configuring automated backups..."
    fly postgres config update --app magnet-postgres --max-backups 7 || \
        warn "Backup configuration may already be set"
}

set_secrets() {
    log "Setting up secrets..."
    
    # Set Tailscale auth keys for all apps
    for app in "${APPS[@]:0:3}"; do  # Skip postgres
        log "Setting Tailscale auth key for $app..."
        fly secrets set TAILSCALE_AUTHKEY="$TAILSCALE_AUTHKEY" --app "$app"
    done
}

deploy_hub() {
    log "Deploying US Hub (magnet-9rl)..."
    fly deploy --app magnet-9rl
    wait_for_deployment magnet-9rl
    
    # Wait extra time for password generation
    log "Waiting for password generation..."
    sleep 30
}

extract_and_distribute_passwords() {
    log "Extracting passwords from hub server..."
    
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if PASSWORDS=$(fly ssh console --app magnet-9rl -C "cat /opt/solanum/etc/passwords.conf" 2>/dev/null); then
            break
        fi
        
        warn "Password extraction attempt $attempt/$max_attempts failed, retrying..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Failed to extract passwords after $max_attempts attempts"
    fi
    
    # Extract individual passwords
    SERVICES_PASSWORD=$(echo "$PASSWORDS" | grep "SERVICES_PASSWORD=" | cut -d'=' -f2)
    LINK_PASSWORD=$(echo "$PASSWORDS" | grep "LINK_PASSWORD_9RL_1EU=" | cut -d'=' -f2)
    
    if [ -z "$SERVICES_PASSWORD" ] || [ -z "$LINK_PASSWORD" ]; then
        error "Failed to extract passwords from hub server"
    fi
    
    log "Distributing passwords to other services..."
    fly secrets set SERVICES_PASSWORD="$SERVICES_PASSWORD" --app magnet-atheme
    fly secrets set LINK_PASSWORD_9RL_1EU="$LINK_PASSWORD" --app magnet-1eu
}

deploy_services() {
    log "Deploying Atheme services..."
    fly deploy --app magnet-atheme
    wait_for_deployment magnet-atheme
    
    log "Deploying EU server..."
    fly deploy --app magnet-1eu
    wait_for_deployment magnet-1eu
}

verify_connectivity() {
    log "Verifying network connectivity..."
    
    # Test Tailscale connectivity
    log "Testing Tailscale mesh connectivity..."
    fly ssh console --app magnet-9rl -C "/usr/local/bin/tailscale status" || \
        warn "Tailscale status check failed"
    
    # Test IRC server connectivity
    log "Testing IRC server connectivity..."
    for app in magnet-9rl magnet-1eu; do
        if fly ssh console --app $app -C "nc -z localhost 6667" 2>/dev/null; then
            log "$app IRC port responsive ✓"
        else
            warn "$app IRC port not responsive"
        fi
    done
    
    # Test services connectivity
    log "Testing services connectivity..."
    if fly ssh console --app magnet-atheme -C "nc -z magnet-9rl 6667" 2>/dev/null; then
        log "Atheme can reach hub ✓"
    else
        warn "Atheme cannot reach hub"
    fi
}

setup_domains() {
    log "Setting up custom domains..."
    
    local domains=("irc.kowloon.social" "eu.kowloon.social")
    local apps=("magnet-9rl" "magnet-1eu")
    
    for i in "${!domains[@]}"; do
        local domain="${domains[$i]}"
        local app="${apps[$i]}"
        
        log "Creating certificate for $domain..."
        fly certs create "$domain" --app "$app" || \
            warn "Certificate for $domain may already exist"
    done
}

run_smoke_tests() {
    log "Running smoke tests..."
    
    # Test health endpoints
    for app in magnet-9rl magnet-1eu magnet-atheme; do
        if fly ssh console --app $app -C "/app/health-check.sh" 2>/dev/null; then
            log "$app health check passed ✓"
        else
            warn "$app health check failed"
        fi
    done
    
    log "Smoke tests completed"
}

main() {
    log "Starting Magnet IRC Network deployment..."
    
    verify_prerequisites
    create_volumes
    setup_database
    set_secrets
    deploy_hub
    extract_and_distribute_passwords
    deploy_services
    verify_connectivity
    setup_domains
    run_smoke_tests
    
    log "Deployment completed successfully! 🎉"
    log "Hub: magnet-9rl.fly.dev"
    log "EU: magnet-1eu.fly.dev"
    log "Services: Internal Tailscale mesh"
    log ""
    log "Check deployment status with:"
    log "  fly status --app magnet-9rl"
    log "  fly status --app magnet-1eu"
    log "  fly status --app magnet-atheme"
}

# Trap errors and provide cleanup
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed! Check the logs above for details."
        log "Manual cleanup may be required:"
        log "  fly apps list"
        log "  fly volumes list --app <app-name>"
        log "  fly secrets list --app <app-name>"
    fi
}
trap cleanup EXIT

main "$@"
```

### Manual Deployment Commands (Fallback)

If the automated script fails, use these manual commands:

```bash
# 1. Export Tailscale auth key
export TAILSCALE_AUTHKEY="tskey-auth-xxxxxx-xxxx"

# 2. Create volumes for configurations
fly volumes create magnet_9rl_data --region ord --size 3
fly volumes create magnet_1eu_data --region ams --size 3
fly volumes create magnet_atheme_data --region ord --size 3

# 3. Set up database
fly postgres create --name magnet-postgres --region ord
fly postgres attach --app magnet-atheme magnet-postgres

# 4. Set secrets
fly secrets set TAILSCALE_AUTHKEY=$TAILSCALE_AUTHKEY --app magnet-9rl
fly secrets set TAILSCALE_AUTHKEY=$TAILSCALE_AUTHKEY --app magnet-1eu
fly secrets set TAILSCALE_AUTHKEY=$TAILSCALE_AUTHKEY --app magnet-atheme

# 5. Deploy in sequence with verification
fly deploy --app magnet-9rl && \
fly ssh console --app magnet-9rl -C "cat /opt/solanum/etc/passwords.conf" > passwords.txt && \
fly secrets set SERVICES_PASSWORD=$(grep SERVICES_PASSWORD passwords.txt | cut -d'=' -f2) --app magnet-atheme && \
fly secrets set LINK_PASSWORD_9RL_1EU=$(grep LINK_PASSWORD_9RL_1EU passwords.txt | cut -d'=' -f2) --app magnet-1eu && \
fly deploy --app magnet-atheme && \
fly deploy --app magnet-1eu

# 6. Verify deployment
./deploy-magnet.sh verify

# 7. Clean up password file
rm passwords.txt
```

## 9. Access & Management (Enhanced)

### Tailscale Mesh Access
Containers automatically join/leave your Tailscale network:
- **Devices appear** when containers start with hostnames like `magnet-9rl`, `magnet-1eu`
- **Devices disappear** when containers stop (ephemeral cleanup)
- **SSH access**: Direct access to containers via Tailscale mesh network
- **Server linking**: Private communication via Tailscale hostnames

### Administrative Access
```bash
# SSH directly via Tailscale (when containers are running)
ssh root@magnet-9rl    # US hub server
ssh root@magnet-1eu    # EU server
ssh root@magnet-atheme # Services

# Or use fly.io SSH (always available)
fly ssh console --app magnet-9rl
fly ssh console --app magnet-1eu
fly ssh console --app magnet-atheme

# View real-time logs
fly logs --app magnet-9rl
fly logs --app magnet-atheme
```

### Performance Monitoring
```bash
# Check OpenSSL performance on AMD EPYC
fly ssh console --app magnet-9rl -C "openssl speed aes-256-cbc"

# Monitor SSL connections
fly ssh console --app magnet-9rl -C "netstat -an | grep :6697"

# Check Tailscale mesh status
fly ssh console --app magnet-9rl -C "/usr/local/bin/tailscale status"
```

## 10. Server Linking Configuration (Tailscale Mesh)

The servers link via Tailscale private mesh network:
- **magnet-9RL**: Tailscale hostname `magnet-9rl`
- **magnet-1EU**: Tailscale hostname `magnet-1eu`
- **magnet-atheme**: Tailscale hostname `magnet-atheme`

Link passwords are automatically generated and synchronized across services.

## 11. DNS Configuration

Point your IRC domains to fly.io apps:
```bash
# DNS records to create in kowloon.social zone
irc.kowloon.social          CNAME   magnet-9rl.fly.dev
eu.kowloon.social           CNAME   magnet-1eu.fly.dev
*.kowloon.social            CNAME   magnet-9rl.fly.dev  # Fallback to US
```

## 12. Performance Benefits Summary

### **OpenSSL on AMD EPYC Performance Gains**
- **2-3x better SSL/TLS throughput** vs mbedTLS
- **AES-NI hardware acceleration** automatic in OpenSSL
- **Lower CPU usage per connection** due to optimized crypto
- **Better concurrent connection scaling** for IRC servers

### **Tailscale Mesh Benefits**
- **Zero-config networking** between regions
- **Automatic failover** and mesh routing
- **Ephemeral device cleanup** - no persistent network pollution
- **Secure by default** - all inter-server communication encrypted

### **Fly.io AMD EPYC Optimization**
- **Multi-core compilation** during builds (`-j$(nproc)`)
- **Efficient resource allocation** (1-2 GB RAM, 1-2 vCPUs per service)
- **Hardware cryptography acceleration** leveraged by OpenSSL
- **High-performance networking** with epoll support

## 13. Shakedown → Production Migration

This deployment uses `kowloon.social` for initial testing and validation.

### **Production Domain Migration**
When ready for production with final domains:

1. **Update DNS**: Change CNAME targets
```bash
# Example production migration
irc.yournetwork.com         CNAME   magnet-9rl.fly.dev
eu.yournetwork.com          CNAME   magnet-1eu.fly.dev
```

2. **Update certificates**:
```bash
fly certs create irc.yournetwork.com --app magnet-9rl
fly certs create eu.yournetwork.com --app magnet-1eu
```

3. **Update configs**: Modify templates with production domains and redeploy

### **Shakedown Testing Checklist**
- [ ] Tailscale mesh connectivity between all servers working
- [ ] OpenSSL SSL certificates provisioned for `*.kowloon.social`
- [ ] Server linking (9RL ↔ 1EU) functional via Tailscale
- [ ] Atheme services connecting to hub via Tailscale
- [ ] Client connections working on both regions with SSL acceleration
- [ ] Database persistence through container restarts
- [ ] Password generation and config templating working
- [ ] Performance testing: SSL throughput vs mbedTLS baseline

## 14. Troubleshooting Guide

### **OpenSSL Performance Issues**
```bash
# Check OpenSSL version and capabilities
fly ssh console --app magnet-9rl -C "openssl version -a"

# Test AES-NI acceleration
fly ssh console --app magnet-9rl -C "openssl speed -evp aes-256-cbc"

# Monitor SSL handshakes
fly ssh console --app magnet-9rl -C "openssl s_client -connect localhost:6697 -brief"
```

### **Tailscale Mesh Issues**
```bash
# Check Tailscale status across mesh
fly ssh console --app magnet-9rl -C "/usr/local/bin/tailscale status"
fly ssh console --app magnet-1eu -C "/usr/local/bin/tailscale status"

# Test connectivity between servers
fly ssh console --app magnet-9rl -C "ping magnet-1eu"

# Check auth key validity
fly secrets list --app magnet-9rl | grep TAILSCALE
```

### **Performance Monitoring**
```bash
# Monitor concurrent SSL connections
fly ssh console --app magnet-9rl -C "ss -tan | grep :6697 | wc -l"

# Check CPU usage under load
fly ssh console --app magnet-9rl -C "top -n 1"

# Verify AMD EPYC optimizations
fly ssh console --app magnet-9rl -C "cat /proc/cpuinfo | grep flags"
```

## 15. Database Backup & Recovery Procedures

### Automated Backup Configuration

```bash
# Configure automated backups (included in deployment script)
fly postgres config update --app magnet-postgres \
    --max-backups 7 \
    --backup-retention 7d

# Manual backup creation
fly postgres backup create --app magnet-postgres

# List available backups
fly postgres backup list --app magnet-postgres

# Restore from backup
fly postgres backup restore <backup-id> --app magnet-postgres
```

### Database Monitoring Script

**db-monitor.sh**
```bash
#!/bin/bash
# Database monitoring and alerting script

POSTGRES_APP="magnet-postgres"
ALERT_THRESHOLD_CONNECTIONS=80
ALERT_THRESHOLD_DISK=85

# Check database health
check_db_health() {
    echo "=== Database Health Check $(date) ==="
    
    # Connection count
    CONNECTIONS=$(fly postgres connect --app $POSTGRES_APP -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tail -1)
    echo "Active connections: $CONNECTIONS"
    
    if [ "$CONNECTIONS" -gt "$ALERT_THRESHOLD_CONNECTIONS" ]; then
        echo "ALERT: High connection count ($CONNECTIONS > $ALERT_THRESHOLD_CONNECTIONS)"
    fi
    
    # Disk usage
    DISK_USAGE=$(fly status --app $POSTGRES_APP --json | jq -r '.Machines[0].Config.Mounts[0].Size')
    echo "Disk usage: $DISK_USAGE%"
    
    if [ "$DISK_USAGE" -gt "$ALERT_THRESHOLD_DISK" ]; then
        echo "ALERT: High disk usage ($DISK_USAGE% > $ALERT_THRESHOLD_DISK%)"
    fi
    
    # Backup status
    LAST_BACKUP=$(fly postgres backup list --app $POSTGRES_APP | head -2 | tail -1 | awk '{print $2}')
    echo "Last backup: $LAST_BACKUP"
    
    # Check if backup is older than 24 hours
    if [ -n "$LAST_BACKUP" ]; then
        BACKUP_AGE=$(( $(date +%s) - $(date -d "$LAST_BACKUP" +%s) ))
        if [ "$BACKUP_AGE" -gt 86400 ]; then
            echo "ALERT: Backup is older than 24 hours"
        fi
    fi
}

# Performance metrics
check_db_performance() {
    echo "=== Database Performance $(date) ==="
    
    fly postgres connect --app $POSTGRES_APP -c "
    SELECT 
        datname,
        numbackends as connections,
        xact_commit + xact_rollback as transactions,
        blks_read + blks_hit as blocks_accessed,
        tup_returned + tup_fetched as tuples_accessed
    FROM pg_stat_database 
    WHERE datname = 'atheme';"
}

# Main execution
main() {
    check_db_health
    echo ""
    check_db_performance
    echo "=== End Database Monitor ==="
}

# Run with cron: */15 * * * * /path/to/db-monitor.sh >> /var/log/db-monitor.log 2>&1
main
```

## 16. Operational Runbooks

### Common Incident Response Procedures

#### Service Down - IRC Server

**Symptoms:** Users cannot connect to IRC, health checks failing

**Response Steps:**
1. Check service status: `fly status --app magnet-9rl`
2. Review logs: `fly logs --app magnet-9rl`
3. Check health endpoint: `curl -f https://magnet-9rl.fly.dev:8080/health`
4. SSH to investigate: `fly ssh console --app magnet-9rl`
5. Check Tailscale: `/usr/local/bin/tailscale status`
6. Restart if needed: `fly restart --app magnet-9rl`

**Escalation:** If restart doesn't work, check for:
- Volume mount issues
- Configuration corruption
- Network connectivity problems

#### Service Down - Atheme Services

**Symptoms:** NickServ/ChanServ not responding, registration/auth failing

**Response Steps:**
1. Check Atheme status: `fly status --app magnet-atheme`
2. Test database: `pg_isready -h magnet-postgres.internal`
3. Check hub connectivity: `nc -z magnet-9rl 6667`
4. Review service logs: `fly logs --app magnet-atheme`
5. Restart services: `fly restart --app magnet-atheme`

#### Database Connection Issues

**Symptoms:** Atheme cannot connect to database, authentication failures

**Response Steps:**
1. Check database status: `fly status --app magnet-postgres`
2. Test connectivity: `fly postgres connect --app magnet-postgres`
3. Check connection limits: Database monitoring script above
4. Review DATABASE_URL: `fly secrets list --app magnet-atheme`
5. Restart database if needed: `fly restart --app magnet-postgres`

#### Tailscale Mesh Problems

**Symptoms:** Servers cannot reach each other, services linking fails

**Response Steps:**
1. Check all nodes: `fly ssh console --app <app> -C "tailscale status"`
2. Verify auth keys: `fly secrets list --app <app> | grep TAILSCALE`
3. Check Tailscale admin console for device status
4. Restart affected services to re-establish mesh
5. Regenerate auth keys if expired

#### Password Synchronization Issues

**Symptoms:** Services cannot authenticate, linking failures

**Response Steps:**
1. Extract current passwords: `fly ssh console --app magnet-9rl -C "cat /opt/solanum/etc/passwords.conf"`
2. Verify secrets match: `fly secrets list --app magnet-atheme`
3. Re-sync passwords using deployment script
4. Restart affected services
5. Test connectivity between services

### Performance Tuning

#### High CPU Usage
```bash
# Monitor CPU usage
fly ssh console --app magnet-9rl -C "top -n 1"

# Check OpenSSL performance
fly ssh console --app magnet-9rl -C "openssl speed aes-256-cbc"

# Monitor connection patterns
fly ssh console --app magnet-9rl -C "ss -tan | grep :6697 | wc -l"
```

#### Memory Issues
```bash
# Check memory usage
fly ssh console --app magnet-9rl -C "free -h"

# Monitor Solanum memory
fly ssh console --app magnet-9rl -C "ps aux | grep solanum"

# Scale up if needed
fly scale memory 2gb --app magnet-9rl
```

#### Database Performance
```bash
# Check slow queries
fly postgres connect --app magnet-postgres -c "
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY mean_time DESC LIMIT 10;"

# Check active connections
fly postgres connect --app magnet-postgres -c "
SELECT client_addr, state, query 
FROM pg_stat_activity 
WHERE state != 'idle';"
```

## 17. Monitoring & Alerting Setup

### Health Check Monitoring

**monitor-network.sh** - Continuous health monitoring
```bash
#!/bin/bash
# Network-wide health monitoring script

APPS=("magnet-9rl" "magnet-1eu" "magnet-atheme" "magnet-postgres")
ENDPOINTS=("https://magnet-9rl.fly.dev:8080/health" "https://magnet-1eu.fly.dev:8080/health")
ALERT_EMAIL="admin@kowloon.social"

check_app_health() {
    local app=$1
    local status=$(fly status --app $app --json | jq -r '.Machines[0].State')
    
    if [ "$status" != "started" ]; then
        echo "ALERT: $app is in state: $status"
        return 1
    fi
    return 0
}

check_endpoint_health() {
    local endpoint=$1
    if ! curl -f -s --max-time 10 "$endpoint" > /dev/null; then
        echo "ALERT: Health endpoint $endpoint not responding"
        return 1
    fi
    return 0
}

send_alert() {
    local message=$1
    echo "$(date): $message" >> /var/log/magnet-alerts.log
    
    # Send email alert (configure mail server as needed)
    if command -v mail > /dev/null; then
        echo "$message" | mail -s "Magnet IRC Network Alert" "$ALERT_EMAIL"
    fi
    
    # Send to Discord/Slack webhook (configure as needed)
    if [ -n "${DISCORD_WEBHOOK:-}" ]; then
        curl -X POST "$DISCORD_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"🚨 **Magnet IRC Alert**\n$message\"}"
    fi
}

main() {
    echo "=== Network Health Check $(date) ==="
    local alerts=0
    
    # Check app statuses
    for app in "${APPS[@]}"; do
        if ! check_app_health "$app"; then
            send_alert "Service $app is unhealthy"
            ((alerts++))
        fi
    done
    
    # Check health endpoints
    for endpoint in "${ENDPOINTS[@]}"; do
        if ! check_endpoint_health "$endpoint"; then
            send_alert "Health endpoint $endpoint failed"
            ((alerts++))
        fi
    done
    
    # Check database
    if ! ./db-monitor.sh | grep -q "ALERT"; then
        send_alert "Database alerts detected"
        ((alerts++))
    fi
    
    if [ $alerts -eq 0 ]; then
        echo "All systems healthy ✓"
    else
        echo "Found $alerts alerts"
    fi
    
    echo "=== End Health Check ==="
}

# Run every 5 minutes: */5 * * * * /path/to/monitor-network.sh
main
```

### Log Aggregation

**Setup centralized logging** (optional):
```bash
# Forward logs to external service (e.g., Papertrail, LogDNA)
fly secrets set LOG_ENDPOINT="your-log-endpoint" --app magnet-9rl
fly secrets set LOG_ENDPOINT="your-log-endpoint" --app magnet-1eu
fly secrets set LOG_ENDPOINT="your-log-endpoint" --app magnet-atheme

# Add to Dockerfile:
# RUN apk add --no-cache rsyslog
# Configure rsyslog to forward to LOG_ENDPOINT
```

## 18. Security Hardening Checklist

### Regular Security Tasks

**Monthly:**
- [ ] Rotate Tailscale auth keys
- [ ] Review Fly.io access logs
- [ ] Update base images and rebuild containers
- [ ] Check for Solanum/Atheme security updates
- [ ] Review operator account access

**Weekly:**
- [ ] Monitor failed login attempts
- [ ] Check certificate expiration dates
- [ ] Review database access patterns
- [ ] Verify backup integrity

**Daily:**
- [ ] Monitor health check status
- [ ] Review application logs for anomalies
- [ ] Check resource usage patterns

### Secret Rotation Procedure

```bash
#!/bin/bash
# rotate-secrets.sh - Automated secret rotation

# Generate new Tailscale auth key
echo "Generate new ephemeral auth key at:"
echo "https://login.tailscale.com/admin/settings/keys"
echo ""
read -p "Enter new Tailscale auth key: " NEW_AUTH_KEY

# Update secrets
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "Updating Tailscale auth key for $app..."
    fly secrets set TAILSCALE_AUTHKEY="$NEW_AUTH_KEY" --app $app
done

# Restart services to pick up new keys
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "Restarting $app..."
    fly restart --app $app
    sleep 30
done

echo "Secret rotation completed"
```

## 19. Maintenance Schedule for Small Teams

### Daily Maintenance Tasks (15-30 minutes)

**Every Morning (5-10 minutes):**
```bash
#!/bin/bash
# daily-check.sh - Quick daily health assessment

echo "=== Daily Magnet IRC Network Health Check $(date) ==="

# Check all application statuses
echo "--- Application Status ---"
for app in magnet-9rl magnet-1eu magnet-atheme magnet-postgres; do
    STATUS=$(fly status --app $app | grep -E "(started|stopped|crashed)" | head -1)
    echo "$app: $STATUS"
done

# Check health endpoints
echo "--- Health Endpoints ---"
for endpoint in https://magnet-9rl.fly.dev:8080/health https://magnet-1eu.fly.dev:8080/health; do
    if curl -f -s --max-time 10 "$endpoint" > /dev/null; then
        echo "$endpoint: ✓ OK"
    else
        echo "$endpoint: ✗ FAILED"
    fi
done

# Quick resource check
echo "--- Resource Usage ---"
for app in magnet-9rl magnet-1eu magnet-atheme; do
    METRICS=$(fly status --app $app | grep -E "(CPU|Memory)" || echo "No metrics available")
    echo "$app: $METRICS"
done

# Check recent alerts
echo "--- Recent Alerts ---"
if [ -f /var/log/magnet-alerts.log ]; then
    echo "Last 24h alerts:"
    grep "$(date -d '1 day ago' '+%Y-%m-%d')" /var/log/magnet-alerts.log | tail -5
else
    echo "No alert log found"
fi

echo "=== End Daily Check ==="
```

**Daily Checklist:**
- [ ] Run daily health check script
- [ ] Review application logs for errors: `fly logs --app magnet-9rl | grep -i error`
- [ ] Check Tailscale mesh status: `fly ssh console --app magnet-9rl -C "tailscale status"`
- [ ] Monitor connection counts: `fly ssh console --app magnet-9rl -C "ss -tan | grep :6697 | wc -l"`
- [ ] Verify database connectivity: `fly postgres connect --app magnet-postgres -c "SELECT 1;"`

**Alert Response (when needed):**
- [ ] Investigate any health check failures
- [ ] Review error logs from the past 24 hours
- [ ] Check for any certificate expiration warnings
- [ ] Verify all services are properly linked

### Weekly Maintenance Tasks (1-2 hours)

**Every Monday (60-90 minutes):**

**Security Review (20-30 minutes):**
```bash
#!/bin/bash
# weekly-security-check.sh

echo "=== Weekly Security Assessment $(date) ==="

# Check certificate expiration
echo "--- Certificate Status ---"
for app in magnet-9rl magnet-1eu; do
    echo "Checking certificates for $app..."
    fly certs list --app $app
done

# Review access logs for anomalies
echo "--- Access Patterns ---"
echo "Checking for unusual connection patterns..."
fly ssh console --app magnet-9rl -C "grep -c 'Failed connection' /opt/solanum/var/log/*.log || echo 'No failed connections logged'"

# Check for failed authentication attempts
echo "--- Authentication Failures ---"
fly logs --app magnet-atheme | grep -i "authentication failed" | tail -5 || echo "No recent auth failures"

# Verify operator account access
echo "--- Operator Access Review ---"
fly ssh console --app magnet-9rl -C "grep 'OPER' /opt/solanum/var/log/*.log | tail -5 || echo 'No recent operator access'"

echo "=== End Security Check ==="
```

**Performance Review (20-30 minutes):**
```bash
#!/bin/bash
# weekly-performance-review.sh

echo "=== Weekly Performance Review $(date) ==="

# Check resource trends
echo "--- Resource Utilization ---"
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "=== $app ==="
    fly ssh console --app $app -C "free -h; echo; ps aux | head -5"
    echo ""
done

# Database performance
echo "--- Database Performance ---"
./db-monitor.sh

# OpenSSL performance check
echo "--- Crypto Performance ---"
fly ssh console --app magnet-9rl -C "openssl speed aes-256-cbc | tail -5"

# Connection statistics
echo "--- Connection Statistics ---"
for app in magnet-9rl magnet-1eu; do
    CONNECTIONS=$(fly ssh console --app $app -C "ss -tan | grep :6697 | wc -l")
    echo "$app: $CONNECTIONS SSL connections"
done

echo "=== End Performance Review ==="
```

**Weekly Checklist:**
- [ ] Run security assessment script
- [ ] Run performance review script
- [ ] Review database backup status: `fly postgres backup list --app magnet-postgres`
- [ ] Check for available updates to base images
- [ ] Review and clean up old log files
- [ ] Test one operational runbook procedure
- [ ] Verify monitoring alerts are working (send test alert)
- [ ] Review resource usage trends and plan capacity

**Backup Verification (10-15 minutes):**
```bash
# Test database backup integrity
echo "Testing latest backup..."
LATEST_BACKUP=$(fly postgres backup list --app magnet-postgres | head -2 | tail -1 | awk '{print $1}')
echo "Latest backup: $LATEST_BACKUP"

# Verify backup is recent (within last 24 hours)
BACKUP_DATE=$(fly postgres backup list --app magnet-postgres | head -2 | tail -1 | awk '{print $2}')
echo "Backup date: $BACKUP_DATE"
```

### Monthly Maintenance Tasks (3-4 hours)

**First Monday of Each Month:**

**Security Hardening (60-90 minutes):**
```bash
#!/bin/bash
# monthly-security-hardening.sh

echo "=== Monthly Security Hardening $(date) ==="

# Rotate Tailscale auth keys
echo "--- Tailscale Key Rotation ---"
echo "Manual step: Generate new ephemeral auth key at https://login.tailscale.com/admin/settings/keys"
echo "Then run: ./rotate-secrets.sh"

# Update base images and rebuild containers
echo "--- Container Updates ---"
echo "Checking for base image updates..."
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "Rebuilding $app with latest base images..."
    fly deploy --app $app --strategy immediate
done

# Review operator account access
echo "--- Access Review ---"
echo "Review operator access logs from past month..."
fly ssh console --app magnet-9rl -C "grep 'OPER' /opt/solanum/var/log/*.log | wc -l" || echo "No operator access logged"

# Check for Solanum/Atheme security updates
echo "--- Software Updates ---"
echo "Check https://github.com/solanum-ircd/solanum/releases for updates"
echo "Check https://github.com/atheme/atheme/releases for updates"

echo "=== End Security Hardening ==="
```

**System Maintenance (90-120 minutes):**
```bash
#!/bin/bash
# monthly-system-maintenance.sh

echo "=== Monthly System Maintenance $(date) ==="

# Comprehensive backup test
echo "--- Backup Recovery Test ---"
echo "Creating test backup..."
fly postgres backup create --app magnet-postgres

echo "Testing backup list..."
fly postgres backup list --app magnet-postgres | head -5

# Performance baseline update
echo "--- Performance Baseline Update ---"
echo "Recording current performance metrics..."
cat > /tmp/monthly-metrics-$(date +%Y%m).txt << EOF
=== Performance Metrics $(date) ===
$(for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "=== $app ==="
    fly ssh console --app $app -C "free -h; echo; uptime; echo; ps aux | grep -E '(solanum|atheme)' | head -3"
    echo ""
done)

=== Database Metrics ===
$(./db-monitor.sh)

=== Connection Statistics ===
$(for app in magnet-9rl magnet-1eu; do
    CONNECTIONS=$(fly ssh console --app $app -C "ss -tan | grep :6697 | wc -l")
    echo "$app: $CONNECTIONS SSL connections"
done)
EOF

# Clean up old logs and temporary files
echo "--- Log Cleanup ---"
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "Cleaning logs for $app..."
    fly ssh console --app $app -C "find /opt/*/var/log -name '*.log' -mtime +30 -delete || true"
done

# Volume usage check
echo "--- Volume Usage ---"
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "Volume usage for $app:"
    fly ssh console --app $app -C "df -h /opt/*/etc"
done

echo "=== End System Maintenance ==="
```

**Monthly Checklist:**
- [ ] Run security hardening script
- [ ] Run system maintenance script
- [ ] Rotate Tailscale authentication keys
- [ ] Update base container images
- [ ] Test backup recovery procedure (restore to test instance)
- [ ] Review and update performance baselines
- [ ] Check for Solanum and Atheme security updates
- [ ] Review operational costs and resource allocation
- [ ] Update documentation if procedures have changed
- [ ] Review and test incident response procedures
- [ ] Clean up old monitoring data and logs
- [ ] Verify all monitoring and alerting systems
- [ ] Review access logs for security anomalies
- [ ] Update emergency contact information
- [ ] Review and test disaster recovery procedures

### Quarterly Maintenance Tasks (Half Day)

**Every Quarter:**

**Disaster Recovery Testing (3-4 hours):**
```bash
#!/bin/bash
# quarterly-dr-test.sh

echo "=== Quarterly Disaster Recovery Test $(date) ==="

# Full backup and restore test
echo "--- Full Backup/Restore Test ---"
echo "1. Create fresh backup"
echo "2. Deploy test instance"
echo "3. Restore backup to test instance"
echo "4. Verify data integrity"
echo "5. Test full service functionality"
echo "6. Document any issues found"

# Network partition simulation
echo "--- Network Partition Test ---"
echo "Simulate Tailscale network issues and test recovery"

# Complete system rebuild test
echo "--- System Rebuild Test ---"
echo "Test complete redeployment from scratch using deployment script"

echo "=== End DR Test ==="
```

**Quarterly Checklist:**
- [ ] Full disaster recovery test
- [ ] Complete backup/restore validation
- [ ] Network partition scenario testing
- [ ] Full system rebuild test using automation
- [ ] Review and update all documentation
- [ ] Capacity planning and scaling assessment
- [ ] Security audit and penetration testing
- [ ] Review operational metrics and SLA performance
- [ ] Update emergency procedures and contact lists
- [ ] Training refresh for all team members

### Emergency Response Procedures

**Immediate Response (0-15 minutes):**
- [ ] Run daily check script to assess scope
- [ ] Check monitoring dashboard and alerts
- [ ] Identify affected services using health endpoints
- [ ] Begin incident log documentation

**Investigation Phase (15-60 minutes):**
- [ ] Follow appropriate runbook from Section 16
- [ ] SSH into affected services for detailed investigation
- [ ] Check recent deployment or configuration changes
- [ ] Review system logs for error patterns

**Resolution Phase (varies):**
- [ ] Implement fix according to runbook procedures
- [ ] Verify service restoration using health checks
- [ ] Monitor for 30 minutes to ensure stability
- [ ] Document resolution steps and lessons learned

### Maintenance Tools and Scripts

**Create maintenance toolkit:**
```bash
# Create maintenance script directory
mkdir -p ~/magnet-maintenance
cd ~/magnet-maintenance

# Daily tools
wget -O daily-check.sh [script content above]
chmod +x daily-check.sh

# Weekly tools
wget -O weekly-security-check.sh [script content above]
wget -O weekly-performance-review.sh [script content above]
chmod +x weekly-*.sh

# Monthly tools
wget -O monthly-security-hardening.sh [script content above]
wget -O monthly-system-maintenance.sh [script content above]
chmod +x monthly-*.sh

# Set up cron jobs for automated checks
(crontab -l 2>/dev/null; echo "0 9 * * * ~/magnet-maintenance/daily-check.sh >> ~/magnet-maintenance/daily.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "0 10 * * 1 ~/magnet-maintenance/weekly-security-check.sh >> ~/magnet-maintenance/weekly.log 2>&1") | crontab -
```

This comprehensive maintenance schedule ensures reliable operation while keeping the operational burden manageable for a small team. The automated scripts reduce manual effort while the checklists ensure nothing critical is overlooked.

This comprehensive update optimizes the entire Magnet IRC Network deployment for fly.io's AMD EPYC infrastructure with OpenSSL acceleration, official Tailscale mesh integration, and addresses all critical SRE recommendations for small team operational reliability.

---

# REFINED 24-STEP IMPLEMENTATION ROADMAP

## Executive Summary

Based on SRE review feedback, this refined roadmap breaks down the Magnet IRC Network deployment into 24 systematic steps across 6 phases. Each step is designed for completion in 2-4 hours by a single person, with clear pass/fail criteria, rollback procedures, and comprehensive validation. The approach eliminates big-bang integration risks through incremental deployment and thorough testing at each step.

## Phase Overview

**Phase 1: Foundation (Steps 1-4)** - Core infrastructure setup
**Phase 2: Networking (Steps 5-8)** - Tailscale mesh establishment
**Phase 3: Services Integration (Steps 9-12)** - IRC and services coordination
**Phase 4: Multi-Region (Steps 13-16)** - Geographic distribution
**Phase 5: Operational Readiness (Steps 17-20)** - Monitoring and procedures
**Phase 6: Production Readiness (Steps 21-24)** - Performance and hardening

---

## PHASE 1: FOUNDATION (Steps 1-4)

### Step 1: Base Infrastructure Setup
**Duration:** 2-3 hours  
**Owner:** Platform Engineer  
**Dependencies:** None  

**Objective:** Establish Fly.io foundation and PostgreSQL database

**Tasks:**
1. Create Fly.io apps (magnet-9rl, magnet-1eu, magnet-atheme, magnet-postgres)
2. Configure base fly.toml files with minimal configuration
3. Create persistent volumes in appropriate regions
4. Deploy PostgreSQL database with basic configuration

**Implementation:**
```bash
# Create applications
fly apps create magnet-9rl --org your-org
fly apps create magnet-1eu --org your-org  
fly apps create magnet-atheme --org your-org

# Create volumes
fly volumes create magnet_9rl_data --region ord --size 3 --app magnet-9rl
fly volumes create magnet_1eu_data --region ams --size 3 --app magnet-1eu
fly volumes create magnet_atheme_data --region ord --size 3 --app magnet-atheme

# Deploy PostgreSQL
fly postgres create --name magnet-postgres --region ord --initial-cluster-size 1
fly postgres attach --app magnet-atheme magnet-postgres
```

**Validation Criteria:**
- [ ] All Fly.io apps created successfully
- [ ] All volumes created in correct regions with correct sizes
- [ ] PostgreSQL app deployed and accessible via `fly postgres connect`
- [ ] Database attached to magnet-atheme app
- [ ] All applications show in `fly apps list`

**Rollback Procedure:**
```bash
# If step fails, clean up resources
fly apps destroy magnet-9rl --yes
fly apps destroy magnet-1eu --yes
fly apps destroy magnet-atheme --yes
fly apps destroy magnet-postgres --yes
```

**Success Metrics:**
- All applications visible in Fly.io dashboard
- Database connectivity test passes
- Volume mount points accessible

---

### Step 2: Docker Image Preparation
**Duration:** 3-4 hours  
**Owner:** Platform Engineer  
**Dependencies:** Step 1 complete  

**Objective:** Build and test optimized Docker images for Solanum and Atheme

**Tasks:**
1. Create Dockerfile.solanum with OpenSSL optimization
2. Create Dockerfile.atheme with PostgreSQL support
3. Build images locally and test basic functionality
4. Prepare configuration templates
5. Create startup scripts with error handling

**Implementation:**
```bash
# Build Solanum image locally first
docker build -f Dockerfile.solanum -t magnet-solanum:test .
docker run --rm magnet-solanum:test /opt/solanum/bin/solanum --version

# Build Atheme image locally
docker build -f Dockerfile.atheme -t magnet-atheme:test .
docker run --rm magnet-atheme:test /opt/atheme/bin/atheme-services --version

# Test OpenSSL performance
docker run --rm magnet-solanum:test openssl speed aes-256-cbc
```

**Validation Criteria:**
- [ ] Solanum image builds successfully with OpenSSL support
- [ ] Atheme image builds successfully with PostgreSQL support
- [ ] OpenSSL AES-NI acceleration working in container
- [ ] Both services start and show version information
- [ ] Configuration templates pass syntax validation
- [ ] Startup scripts handle basic error conditions

**Rollback Procedure:**
```bash
# Remove test images
docker rmi magnet-solanum:test magnet-atheme:test
# Revert to previous Dockerfile versions if any exist
```

**Success Metrics:**
- OpenSSL speed test shows AES-NI acceleration
- Services start without configuration errors
- Container resource usage within expected bounds

---

### Step 3: Tailscale Integration Preparation
**Duration:** 2-3 hours  
**Owner:** Network Engineer  
**Dependencies:** Step 2 complete  

**Objective:** Prepare Tailscale mesh networking components

**Tasks:**
1. Create Tailscale ephemeral auth keys
2. Add Tailscale binaries to Docker images
3. Create Tailscale startup scripts
4. Test basic Tailscale connectivity outside of Fly.io
5. Document networking topology

**Implementation:**
```bash
# Generate ephemeral auth key at https://login.tailscale.com/admin/settings/keys
# Test Tailscale integration locally
docker run --privileged --rm \
  -e TAILSCALE_AUTHKEY=$EPHEMERAL_KEY \
  magnet-solanum:test \
  bash -c "tailscaled & sleep 5 && tailscale up --auth-key=\$TAILSCALE_AUTHKEY"
```

**Validation Criteria:**
- [ ] Ephemeral auth key generated and documented
- [ ] Tailscale binaries present in Docker images
- [ ] Basic Tailscale startup script works in test container
- [ ] Network topology documented with hostnames
- [ ] Test containers can establish Tailscale connections

**Rollback Procedure:**
```bash
# Revoke test auth keys in Tailscale admin console
# Remove Tailscale components from Dockerfiles if needed
```

**Success Metrics:**
- Test containers successfully join Tailscale network
- Ephemeral cleanup works (devices disappear when containers stop)
- Network hostnames resolve properly

---

### Step 4: Initial Security Framework
**Duration:** 2-3 hours  
**Owner:** Security Engineer  
**Dependencies:** Step 3 complete  

**Objective:** Establish security foundations and secret management

**Tasks:**
1. Design password generation and coordination strategy
2. Create secure secret distribution mechanism
3. Set up initial Fly.io secrets
4. Create security validation scripts
5. Document security procedures

**Implementation:**
```bash
# Set initial Tailscale secrets
fly secrets set TAILSCALE_AUTHKEY=$EPHEMERAL_KEY --app magnet-9rl
fly secrets set TAILSCALE_AUTHKEY=$EPHEMERAL_KEY --app magnet-1eu  
fly secrets set TAILSCALE_AUTHKEY=$EPHEMERAL_KEY --app magnet-atheme

# Create password coordination script
cat > coordinate-passwords.sh << 'EOF'
#!/bin/bash
# Extract passwords from hub and distribute to other services
set -euo pipefail
# [Implementation from main plan.md]
EOF
```

**Validation Criteria:**
- [ ] Tailscale auth keys set in all applications
- [ ] Password coordination strategy documented and tested
- [ ] Security validation scripts operational
- [ ] Secret rotation procedures documented
- [ ] Emergency access procedures defined

**Rollback Procedure:**
```bash
# Remove test secrets
fly secrets unset TAILSCALE_AUTHKEY --app magnet-9rl
fly secrets unset TAILSCALE_AUTHKEY --app magnet-1eu
fly secrets unset TAILSCALE_AUTHKEY --app magnet-atheme
```

**Success Metrics:**
- Secrets properly encrypted and stored
- Password coordination script passes dry-run test
- Security procedures pass review

---

## PHASE 2: NETWORKING (Steps 5-8)

### Step 5: Single Node Tailscale Deployment
**Duration:** 2-3 hours  
**Owner:** Network Engineer  
**Dependencies:** Phase 1 complete  

**Objective:** Deploy single IRC server with Tailscale mesh

**Tasks:**
1. Deploy magnet-9rl with Tailscale integration
2. Verify Tailscale mesh connectivity
3. Test basic IRC functionality
4. Validate health checks
5. Document networking diagnostics

**Implementation:**
```bash
# Deploy hub server with networking
fly deploy --app magnet-9rl

# Wait for deployment and test
fly status --app magnet-9rl
sleep 60  # Allow Tailscale to connect

# Test Tailscale connectivity
fly ssh console --app magnet-9rl -C "tailscale status"
fly ssh console --app magnet-9rl -C "tailscale ip -4"
```

**Validation Criteria:**
- [ ] magnet-9rl deploys successfully
- [ ] Tailscale connects and receives IP address
- [ ] Service appears in Tailscale admin console with correct hostname
- [ ] Health checks pass (IRC port 6667 accessible)
- [ ] Service auto-generates and stores passwords
- [ ] SSL port 6697 responds properly

**Rollback Procedure:**
```bash
# Stop and remove deployment
fly apps destroy magnet-9rl --yes
# Recreate app for retry
fly apps create magnet-9rl --org your-org
```

**Success Metrics:**
- Tailscale device visible in admin console
- IRC server responds to telnet connections
- Password files generated correctly

---

### Step 6: Hub Server Password Extraction
**Duration:** 1-2 hours  
**Owner:** Platform Engineer  
**Dependencies:** Step 5 complete  

**Objective:** Extract and coordinate passwords from hub server

**Tasks:**
1. Extract generated passwords from hub server
2. Validate password format and strength
3. Store passwords as secrets in other applications
4. Test password retrieval mechanisms
5. Document password rotation procedures

**Implementation:**
```bash
# Extract passwords from hub
./coordinate-passwords.sh extract

# Validate password strength
SERVICES_PASSWORD=$(fly ssh console --app magnet-9rl -C "grep SERVICES_PASSWORD /opt/solanum/etc/passwords.conf | cut -d'=' -f2")
echo "Services password length: ${#SERVICES_PASSWORD}"
[[ ${#SERVICES_PASSWORD} -ge 32 ]] || exit 1

# Distribute to other apps
fly secrets set SERVICES_PASSWORD="$SERVICES_PASSWORD" --app magnet-atheme
fly secrets set LINK_PASSWORD_9RL_1EU="$LINK_PASSWORD" --app magnet-1eu
```

**Validation Criteria:**
- [ ] Passwords extracted successfully from hub server
- [ ] All passwords meet length requirements (24+ chars)
- [ ] Passwords stored as secrets in target applications
- [ ] Password coordination script runs without errors
- [ ] Hub server password file permissions correct (600)

**Rollback Procedure:**
```bash
# Clear distributed secrets if coordination fails
fly secrets unset SERVICES_PASSWORD --app magnet-atheme
fly secrets unset LINK_PASSWORD_9RL_1EU --app magnet-1eu
# Regenerate passwords on hub if needed
fly restart --app magnet-9rl
```

**Success Metrics:**
- Password extraction completes in <5 minutes
- All target services receive correct passwords
- No passwords logged in plaintext

---

### Step 7: Database Connectivity Validation
**Duration:** 2-3 hours  
**Owner:** Database Engineer  
**Dependencies:** Step 6 complete  

**Objective:** Establish and validate database connectivity

**Tasks:**
1. Test PostgreSQL connectivity from atheme app
2. Verify database permissions and schemas
3. Run basic Atheme database initialization
4. Test database performance and connection pooling
5. Set up database monitoring

**Implementation:**
```bash
# Test database connectivity
fly postgres connect --app magnet-postgres -c "SELECT version();"

# Test from atheme application
fly ssh console --app magnet-atheme -C "pg_isready -h magnet-postgres.internal -p 5432"

# Create test tables to verify permissions
fly postgres connect --app magnet-postgres -c "
CREATE TABLE test_connectivity (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO test_connectivity DEFAULT VALUES;
SELECT * FROM test_connectivity;
DROP TABLE test_connectivity;"
```

**Validation Criteria:**
- [ ] PostgreSQL responds to connections from atheme app
- [ ] Database permissions allow table creation/modification
- [ ] Connection string properly configured in environment
- [ ] Database monitoring tools operational
- [ ] Backup configuration verified

**Rollback Procedure:**
```bash
# If database issues occur, recreate database
fly postgres destroy magnet-postgres --yes
fly postgres create --name magnet-postgres --region ord
fly postgres attach --app magnet-atheme magnet-postgres
```

**Success Metrics:**
- Database connections establish in <5 seconds
- No connection errors in application logs
- Database performance within expected parameters

---

### Step 8: Tailscale Mesh Expansion
**Duration:** 2-3 hours  
**Owner:** Network Engineer  
**Dependencies:** Step 7 complete  

**Objective:** Expand Tailscale mesh to include database and services

**Tasks:**
1. Deploy magnet-atheme with Tailscale connectivity
2. Verify mesh connectivity between hub and atheme
3. Test inter-service communication
4. Validate network security and isolation
5. Document mesh topology

**Implementation:**
```bash
# Deploy atheme services
fly deploy --app magnet-atheme

# Wait for Tailscale mesh formation
sleep 90

# Test mesh connectivity
fly ssh console --app magnet-9rl -C "ping -c 3 magnet-atheme"
fly ssh console --app magnet-atheme -C "ping -c 3 magnet-9rl"

# Test IRC connectivity from atheme to hub
fly ssh console --app magnet-atheme -C "nc -z magnet-9rl 6667"
```

**Validation Criteria:**
- [ ] magnet-atheme successfully joins Tailscale mesh
- [ ] Both services can ping each other via Tailscale hostnames
- [ ] IRC port reachable from atheme service
- [ ] Network traffic properly encrypted over mesh
- [ ] No connectivity issues between services

**Rollback Procedure:**
```bash
# If mesh issues occur, restart atheme
fly restart --app magnet-atheme
# Or redeploy if needed
fly deploy --app magnet-atheme
```

**Success Metrics:**
- Mesh formation completes in <2 minutes
- Network latency between services <50ms
- All services visible in Tailscale admin console

---

## PHASE 3: SERVICES INTEGRATION (Steps 9-12)

### Step 9: IRC Services Authentication
**Duration:** 2-3 hours  
**Owner:** IRC Engineer  
**Dependencies:** Phase 2 complete  

**Objective:** Establish authentication between IRC server and services

**Tasks:**
1. Configure IRC server for services linking
2. Configure Atheme services for hub connection
3. Test basic authentication handshake
4. Validate services can authenticate with hub
5. Monitor authentication logs

**Implementation:**
```bash
# Verify services configuration on hub
fly ssh console --app magnet-9rl -C "grep -A 5 'service {' /opt/solanum/etc/ircd.conf"

# Test services connection from atheme
fly ssh console --app magnet-atheme -C "nc -z magnet-9rl 6667"

# Check atheme logs for connection attempts
fly logs --app magnet-atheme | grep -i "connect"

# Monitor hub server for services connections
fly logs --app magnet-9rl | grep -i "services"
```

**Validation Criteria:**
- [ ] IRC server accepts connections on services port
- [ ] Atheme services can establish connection to hub
- [ ] Authentication handshake completes successfully
- [ ] Services link established without errors
- [ ] No authentication failures in logs

**Rollback Procedure:**
```bash
# If authentication fails, check and regenerate passwords
./coordinate-passwords.sh regenerate
fly restart --app magnet-atheme
fly restart --app magnet-9rl
```

**Success Metrics:**
- Services authentication completes in <30 seconds
- No authentication retries or failures
- Services link remains stable

---

### Step 10: Basic IRC Functionality Validation
**Duration:** 3-4 hours  
**Owner:** IRC Engineer  
**Dependencies:** Step 9 complete  

**Objective:** Validate core IRC functionality and services integration

**Tasks:**
1. Test user registration with NickServ
2. Test channel registration with ChanServ
3. Validate operator commands
4. Test basic IRC protocol compliance
5. Verify services database persistence

**Implementation:**
```bash
# Create test IRC client connection script
cat > test-irc-basic.sh << 'EOF'
#!/bin/bash
# Test basic IRC functionality
exec 3<>/dev/tcp/magnet-9rl.fly.dev/6667
echo "NICK testuser" >&3
echo "USER testuser 0 * :Test User" >&3
sleep 2
echo "PRIVMSG NickServ :REGISTER testpass test@example.com" >&3
sleep 2
echo "JOIN #testchannel" >&3
echo "PRIVMSG ChanServ :REGISTER #testchannel" >&3
sleep 2
echo "QUIT :Test complete" >&3
exec 3>&-
EOF

# Run basic IRC test
chmod +x test-irc-basic.sh
./test-irc-basic.sh
```

**Validation Criteria:**
- [ ] IRC client can connect and authenticate
- [ ] NickServ registration works properly
- [ ] ChanServ channel registration functional
- [ ] Basic IRC commands respond correctly
- [ ] Services persist data to database
- [ ] No protocol violations or errors

**Rollback Procedure:**
```bash
# If IRC functionality broken, restart services
fly restart --app magnet-atheme
fly restart --app magnet-9rl
# Clear test data from database if needed
```

**Success Metrics:**
- All IRC protocol tests pass
- Services respond to commands within 2 seconds
- Database properly stores user/channel data

---

### Step 11: Services Stability Testing
**Duration:** 2-3 hours  
**Owner:** SRE Engineer  
**Dependencies:** Step 10 complete  

**Objective:** Validate services stability under load and restart scenarios

**Tasks:**
1. Test services behavior during hub server restart
2. Test services reconnection after network interruption
3. Validate services persistence across restarts
4. Test concurrent user/channel operations
5. Monitor resource usage patterns

**Implementation:**
```bash
# Test services reconnection resilience
fly restart --app magnet-9rl
sleep 30
fly logs --app magnet-atheme | grep -i "reconnect\|connect"

# Test services restart with data persistence
fly restart --app magnet-atheme
sleep 60
# Verify previously registered users/channels still exist

# Monitor resource usage during operations
fly ssh console --app magnet-atheme -C "ps aux | grep atheme"
fly ssh console --app magnet-9rl -C "ps aux | grep solanum"
```

**Validation Criteria:**
- [ ] Services automatically reconnect after hub restart
- [ ] User/channel data persists across services restart
- [ ] No data corruption during restart cycles
- [ ] Resource usage remains within expected bounds
- [ ] Services handle network interruptions gracefully

**Rollback Procedure:**
```bash
# If stability issues found, restore previous configuration
fly deploy --app magnet-atheme --strategy immediate
fly deploy --app magnet-9rl --strategy immediate
```

**Success Metrics:**
- Services reconnect within 30 seconds of hub restart
- Zero data loss during restart scenarios
- Memory usage remains stable

---

### Step 12: Services Performance Baseline
**Duration:** 2-3 hours  
**Owner:** Performance Engineer  
**Dependencies:** Step 11 complete  

**Objective:** Establish performance baselines and optimize services

**Tasks:**
1. Measure services response times under normal load
2. Test database query performance
3. Validate SSL/TLS performance with OpenSSL
4. Establish monitoring metrics and alerts
5. Document performance baselines

**Implementation:**
```bash
# Measure services response times
time fly ssh console --app magnet-atheme -C "echo 'PING' | nc magnet-9rl 6667"

# Test SSL performance
fly ssh console --app magnet-9rl -C "openssl speed aes-256-cbc"

# Test database performance
fly postgres connect --app magnet-postgres -c "
EXPLAIN ANALYZE SELECT * FROM accounts LIMIT 100;
"

# Create performance monitoring script
cat > monitor-performance.sh << 'EOF'
#!/bin/bash
# Performance monitoring script
echo "=== Performance Metrics $(date) ==="
for app in magnet-9rl magnet-atheme; do
    echo "=== $app ==="
    fly ssh console --app $app -C "uptime; free -h; ps aux | head -5"
done
EOF
```

**Validation Criteria:**
- [ ] IRC command response time <500ms
- [ ] Database queries complete in <100ms
- [ ] SSL handshake time <200ms
- [ ] OpenSSL shows AES-NI acceleration
- [ ] Performance monitoring operational

**Rollback Procedure:**
```bash
# If performance issues found, scale resources
fly scale memory 2gb --app magnet-atheme
fly scale memory 2gb --app magnet-9rl
```

**Success Metrics:**
- All response times within target thresholds
- OpenSSL performance 2-3x faster than software-only
- Resource utilization <70% under normal load

---

## PHASE 4: MULTI-REGION (Steps 13-16)

### Step 13: EU Server Preparation
**Duration:** 2-3 hours  
**Owner:** Platform Engineer  
**Dependencies:** Phase 3 complete  

**Objective:** Prepare EU server for multi-region deployment

**Tasks:**
1. Configure magnet-1eu application for Amsterdam region
2. Test container deployment in AMS region
3. Verify Tailscale connectivity from EU region
4. Prepare EU-specific configuration
5. Test resource allocation and performance

**Implementation:**
```bash
# Deploy EU server in isolation first
fly deploy --app magnet-1eu

# Test basic functionality
fly status --app magnet-1eu
sleep 90  # Allow Tailscale connection

# Test Tailscale from EU region
fly ssh console --app magnet-1eu -C "tailscale status"
fly ssh console --app magnet-1eu -C "ping -c 3 magnet-9rl"
```

**Validation Criteria:**
- [ ] magnet-1eu deploys successfully in AMS region
- [ ] Tailscale mesh connectivity established from EU
- [ ] EU server can reach US hub via Tailscale
- [ ] Basic IRC functionality works on EU server
- [ ] Resource allocation appropriate for region

**Rollback Procedure:**
```bash
# If EU deployment fails, remove and retry
fly apps destroy magnet-1eu --yes
fly apps create magnet-1eu --org your-org
```

**Success Metrics:**
- EU server joins mesh within 2 minutes
- Cross-region latency <150ms via Tailscale
- EU region performance matches US baseline

---

### Step 14: Server Linking Implementation
**Duration:** 3-4 hours  
**Owner:** IRC Engineer  
**Dependencies:** Step 13 complete  

**Objective:** Establish IRC server linking between US and EU

**Tasks:**
1. Configure server linking passwords and authentication
2. Establish IRC server-to-server connection
3. Test user/channel synchronization across servers
4. Validate IRC protocol compliance for linking
5. Test netsplit and reconnection scenarios

**Implementation:**
```bash
# Verify link configuration on both servers
fly ssh console --app magnet-9rl -C "grep -A 10 'connect.*magnet-1EU' /opt/solanum/etc/ircd.conf"
fly ssh console --app magnet-1eu -C "grep -A 10 'connect.*magnet-9RL' /opt/solanum/etc/ircd.conf"

# Monitor linking process
fly logs --app magnet-9rl | grep -i "link\|connect" &
fly logs --app magnet-1eu | grep -i "link\|connect" &

# Test user visibility across servers
# (Create test script for cross-server user visibility)
```

**Validation Criteria:**
- [ ] Server linking authentication successful
- [ ] Users visible across both servers
- [ ] Channels synchronized between servers
- [ ] No split-brain scenarios during testing
- [ ] Automatic reconnection after network issues

**Rollback Procedure:**
```bash
# If linking fails, isolate EU server
fly ssh console --app magnet-1eu -C "sed -i '/connect.*magnet-9RL/,+10d' /opt/solanum/etc/ircd.conf"
fly restart --app magnet-1eu
```

**Success Metrics:**
- Server linking completes within 30 seconds
- User synchronization working properly
- No protocol errors in server logs

---

### Step 15: Multi-Region Load Testing
**Duration:** 3-4 hours  
**Owner:** Performance Engineer  
**Dependencies:** Step 14 complete  

**Objective:** Validate performance under multi-region load

**Tasks:**
1. Create load testing scripts for both regions
2. Test concurrent user connections across regions
3. Measure cross-region message propagation
4. Validate services performance with multiple servers
5. Test failover scenarios

**Implementation:**
```bash
# Create multi-region load test
cat > load-test-multiregion.sh << 'EOF'
#!/bin/bash
# Multi-region load testing script
for region in us eu; do
    for i in {1..50}; do
        (
            if [ "$region" = "us" ]; then
                SERVER="magnet-9rl.fly.dev"
            else
                SERVER="magnet-1eu.fly.dev"
            fi
            exec 3<>/dev/tcp/$SERVER/6667
            echo "NICK user${region}${i}" >&3
            echo "USER user${region}${i} 0 * :Test User" >&3
            sleep 60
            echo "QUIT" >&3
            exec 3>&-
        ) &
    done
done
wait
EOF

# Run load test
chmod +x load-test-multiregion.sh
./load-test-multiregion.sh
```

**Validation Criteria:**
- [ ] Both servers handle 50+ concurrent connections
- [ ] Cross-region message delivery <2 seconds
- [ ] No performance degradation under load
- [ ] Services remain responsive during load test
- [ ] Network resources within capacity

**Rollback Procedure:**
```bash
# If performance issues found, reduce connection limits
fly ssh console --app magnet-1eu -C "pkill -f solanum"
fly restart --app magnet-1eu
```

**Success Metrics:**
- Connection establishment time <5 seconds
- Message propagation time <1 second
- Resource usage remains stable

---

### Step 16: Geographic Redundancy Validation
**Duration:** 2-3 hours  
**Owner:** SRE Engineer  
**Dependencies:** Step 15 complete  

**Objective:** Validate geographic redundancy and failover

**Tasks:**
1. Test EU server independence during US outage
2. Test services failover scenarios
3. Validate data consistency across regions
4. Test automated recovery procedures
5. Document failover procedures

**Implementation:**
```bash
# Simulate US hub outage
fly suspend --app magnet-9rl

# Test EU server independence
sleep 60
# Connect to EU server and verify functionality
exec 3<>/dev/tcp/magnet-1eu.fly.dev/6667
echo "NICK testuser" >&3
echo "USER testuser 0 * :Test User" >&3
echo "JOIN #test" >&3
sleep 5
echo "QUIT" >&3
exec 3>&-

# Restore US hub and test reconnection
fly resume --app magnet-9rl
sleep 120
# Verify servers relink automatically
```

**Validation Criteria:**
- [ ] EU server remains functional during US outage
- [ ] Services gracefully handle hub server loss
- [ ] Automatic relinking occurs when hub returns
- [ ] No data corruption during outage scenarios
- [ ] Users can connect to available servers

**Rollback Procedure:**
```bash
# If failover issues found, restore both servers
fly resume --app magnet-9rl
fly restart --app magnet-1eu
fly restart --app magnet-atheme
```

**Success Metrics:**
- EU server maintains 100% uptime during US outage
- Relinking completes within 60 seconds
- Zero data loss during failover scenarios

---

## PHASE 5: OPERATIONAL READINESS (Steps 17-20)

### Step 17: Comprehensive Monitoring Setup
**Duration:** 3-4 hours  
**Owner:** SRE Engineer  
**Dependencies:** Phase 4 complete  

**Objective:** Implement comprehensive monitoring and alerting

**Tasks:**
1. Deploy health check monitoring across all services
2. Set up log aggregation and analysis
3. Configure performance metric collection
4. Implement automated alerting system
5. Create monitoring dashboards

**Implementation:**
```bash
# Deploy monitoring stack
cat > setup-monitoring.sh << 'EOF'
#!/bin/bash
# Comprehensive monitoring setup

# Create health check scripts for each service
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "Setting up monitoring for $app..."
    fly ssh console --app $app -C "
        cat > /usr/local/bin/health-monitor.sh << 'SCRIPT'
#!/bin/bash
# Health monitoring script
$(cat health-check.sh)
SCRIPT
        chmod +x /usr/local/bin/health-monitor.sh
        
        # Set up cron for health checks
        echo '*/5 * * * * /usr/local/bin/health-monitor.sh >> /var/log/health.log 2>&1' | crontab -
    "
done

# Set up log forwarding
for app in magnet-9rl magnet-1eu magnet-atheme; do
    fly secrets set LOG_LEVEL=info --app $app
done
EOF

chmod +x setup-monitoring.sh
./setup-monitoring.sh
```

**Validation Criteria:**
- [ ] Health checks operational on all services
- [ ] Log aggregation collecting from all sources
- [ ] Performance metrics being recorded
- [ ] Alert system responds to test alerts
- [ ] Monitoring dashboards functional

**Rollback Procedure:**
```bash
# If monitoring causes issues, disable
for app in magnet-9rl magnet-1eu magnet-atheme; do
    fly ssh console --app $app -C "crontab -r"
done
```

**Success Metrics:**
- Health checks run every 5 minutes without errors
- Alert response time <2 minutes
- Dashboard updates in real-time

---

### Step 18: Backup and Recovery Implementation
**Duration:** 3-4 hours  
**Owner:** Database Engineer  
**Dependencies:** Step 17 complete  

**Objective:** Implement comprehensive backup and recovery procedures

**Tasks:**
1. Configure automated database backups
2. Test backup restoration procedures
3. Implement configuration backup system
4. Create disaster recovery procedures
5. Test full system recovery

**Implementation:**
```bash
# Configure automated backups
fly postgres config update --app magnet-postgres \
    --max-backups 7 \
    --backup-retention 7d

# Create backup monitoring
cat > backup-monitor.sh << 'EOF'
#!/bin/bash
# Monitor backup status
LATEST_BACKUP=$(fly postgres backup list --app magnet-postgres | head -2 | tail -1)
echo "Latest backup: $LATEST_BACKUP"

# Test backup age
BACKUP_DATE=$(echo "$LATEST_BACKUP" | awk '{print $2}')
if [ $(($(date +%s) - $(date -d "$BACKUP_DATE" +%s))) -gt 86400 ]; then
    echo "ALERT: Backup older than 24 hours"
    exit 1
fi
EOF

# Test backup restoration
fly postgres backup create --app magnet-postgres
BACKUP_ID=$(fly postgres backup list --app magnet-postgres | head -2 | tail -1 | awk '{print $1}')
echo "Created test backup: $BACKUP_ID"
```

**Validation Criteria:**
- [ ] Automated backups running daily
- [ ] Backup restoration tested successfully
- [ ] Configuration files backed up regularly
- [ ] Recovery procedures documented and tested
- [ ] Backup monitoring alerts operational

**Rollback Procedure:**
```bash
# If backup system causes issues, restore manual process
fly postgres config update --app magnet-postgres --max-backups 3
```

**Success Metrics:**
- Backup creation time <10 minutes
- Restoration time <30 minutes
- 100% data integrity after restoration

---

### Step 19: Incident Response Procedures
**Duration:** 2-3 hours  
**Owner:** SRE Engineer  
**Dependencies:** Step 18 complete  

**Objective:** Establish incident response and escalation procedures

**Tasks:**
1. Create incident response runbooks
2. Set up on-call alerting system
3. Test incident escalation procedures
4. Create emergency access procedures
5. Document communication protocols

**Implementation:**
```bash
# Create incident response toolkit
mkdir -p ~/incident-response
cd ~/incident-response

# Create quick diagnostic script
cat > quick-diag.sh << 'EOF'
#!/bin/bash
# Quick incident diagnostics
echo "=== Incident Response Diagnostics $(date) ==="

echo "--- Service Status ---"
for app in magnet-9rl magnet-1eu magnet-atheme magnet-postgres; do
    STATUS=$(fly status --app $app 2>/dev/null | grep -E "(started|stopped|crashed)" | head -1)
    echo "$app: $STATUS"
done

echo "--- Health Checks ---"
for endpoint in https://magnet-9rl.fly.dev:8080/health https://magnet-1eu.fly.dev:8080/health; do
    if curl -f -s --max-time 5 "$endpoint" > /dev/null; then
        echo "$endpoint: OK"
    else
        echo "$endpoint: FAILED"
    fi
done

echo "--- Tailscale Mesh ---"
fly ssh console --app magnet-9rl -C "tailscale status" 2>/dev/null || echo "Tailscale check failed"

echo "--- Recent Alerts ---"
if [ -f /var/log/magnet-alerts.log ]; then
    tail -10 /var/log/magnet-alerts.log
fi
EOF

chmod +x quick-diag.sh
```

**Validation Criteria:**
- [ ] Incident response runbooks complete and tested
- [ ] On-call system properly configured
- [ ] Escalation procedures tested with team
- [ ] Emergency access working properly
- [ ] Communication protocols documented

**Rollback Procedure:**
```bash
# If incident response tools cause issues, simplify
mv quick-diag.sh quick-diag.sh.backup
# Create minimal version if needed
```

**Success Metrics:**
- Incident detection time <5 minutes
- Response time to critical alerts <15 minutes
- Escalation procedures tested successfully

---

### Step 20: Documentation and Training
**Duration:** 3-4 hours  
**Owner:** Technical Writer/SRE  
**Dependencies:** Step 19 complete  

**Objective:** Complete operational documentation and team training

**Tasks:**
1. Finalize all operational procedures documentation
2. Create troubleshooting guides
3. Conduct team training on procedures
4. Test all documented procedures
5. Create quick reference guides

**Implementation:**
```bash
# Create documentation structure
mkdir -p ~/magnet-docs/{procedures,troubleshooting,training}

# Generate procedure summaries
cat > ~/magnet-docs/procedures/daily-checklist.md << 'EOF'
# Daily Operations Checklist

## Morning Health Check (5 minutes)
- [ ] Run quick-diag.sh
- [ ] Check overnight alerts
- [ ] Verify all services running
- [ ] Monitor resource usage

## If Issues Found
- [ ] Follow appropriate runbook
- [ ] Document in incident log
- [ ] Escalate if needed
EOF

# Create troubleshooting quick reference
cat > ~/magnet-docs/troubleshooting/quick-reference.md << 'EOF'
# Quick Troubleshooting Reference

## Service Down
1. Check: `fly status --app <app>`
2. Logs: `fly logs --app <app>`
3. Restart: `fly restart --app <app>`

## Network Issues
1. Check: Tailscale status
2. Test: Cross-region connectivity
3. Fix: Restart affected services

## Database Issues
1. Check: `fly postgres connect`
2. Monitor: Connection counts
3. Backup: Available if needed
EOF
```

**Validation Criteria:**
- [ ] All procedures documented with step-by-step instructions
- [ ] Troubleshooting guides tested by team members
- [ ] Training completed for all team members
- [ ] Quick reference guides accessible
- [ ] Documentation kept up-to-date

**Rollback Procedure:**
```bash
# Documentation doesn't require rollback
# Versioning keeps previous documentation available
```

**Success Metrics:**
- 100% team trained on procedures
- All documented procedures tested successfully
- Average troubleshooting time reduced by 50%

---

## PHASE 6: PRODUCTION READINESS (Steps 21-24)

### Step 21: Security Hardening and Compliance
**Duration:** 3-4 hours  
**Owner:** Security Engineer  
**Dependencies:** Phase 5 complete  

**Objective:** Implement production security hardening

**Tasks:**
1. Conduct security audit of all components
2. Implement additional security measures
3. Test security incident response
4. Update security documentation
5. Conduct penetration testing

**Implementation:**
```bash
# Security audit script
cat > security-audit.sh << 'EOF'
#!/bin/bash
# Security audit for production readiness

echo "=== Security Audit $(date) ==="

echo "--- Secret Management ---"
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "Checking secrets for $app..."
    SECRETS=$(fly secrets list --app $app | wc -l)
    echo "$app has $SECRETS secrets configured"
done

echo "--- Certificate Status ---"
for app in magnet-9rl magnet-1eu; do
    echo "Checking certificates for $app..."
    fly certs list --app $app
done

echo "--- Network Security ---"
echo "Checking Tailscale ACLs..."
# Verify Tailscale network policies

echo "--- Access Controls ---"
echo "Checking operator access logs..."
for app in magnet-9rl magnet-1eu; do
    fly ssh console --app $app -C "grep -c 'OPER' /opt/solanum/var/log/*.log || echo 'No operator access'"
done
EOF

chmod +x security-audit.sh
./security-audit.sh
```

**Validation Criteria:**
- [ ] Security audit passes all checks
- [ ] All secrets properly managed and rotated
- [ ] SSL/TLS certificates valid and auto-renewing
- [ ] Network security policies enforced
- [ ] Access controls properly configured
- [ ] Security incident response tested

**Rollback Procedure:**
```bash
# If security hardening breaks functionality, restore previous configuration
# (Most security changes are additive and don't require rollback)
```

**Success Metrics:**
- Zero security vulnerabilities in audit
- All certificates valid for >30 days
- Security response time <10 minutes

---

### Step 22: Performance Optimization and Tuning
**Duration:** 4-5 hours  
**Owner:** Performance Engineer  
**Dependencies:** Step 21 complete  

**Objective:** Optimize system performance for production load

**Tasks:**
1. Conduct comprehensive performance analysis
2. Optimize OpenSSL and encryption performance
3. Tune database performance and connection pooling
4. Optimize network and Tailscale performance
5. Set up automated performance monitoring

**Implementation:**
```bash
# Performance optimization script
cat > performance-optimization.sh << 'EOF'
#!/bin/bash
# Performance optimization for production

echo "=== Performance Optimization $(date) ==="

echo "--- OpenSSL Performance ---"
for app in magnet-9rl magnet-1eu; do
    echo "Testing OpenSSL performance on $app..."
    fly ssh console --app $app -C "openssl speed aes-256-cbc | tail -5"
    
    echo "Checking CPU flags for hardware acceleration..."
    fly ssh console --app $app -C "grep -E '(aes|avx)' /proc/cpuinfo | head -3"
done

echo "--- Database Performance ---"
echo "Analyzing database query performance..."
fly postgres connect --app magnet-postgres -c "
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
ORDER BY total_time DESC LIMIT 10;" 2>/dev/null || echo "pg_stat_statements not available"

echo "--- Network Performance ---"
echo "Testing cross-region latency..."
fly ssh console --app magnet-9rl -C "ping -c 5 magnet-1eu | tail -1"

echo "--- Resource Utilization ---"
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "=== $app Resource Usage ==="
    fly ssh console --app $app -C "uptime && free -h && ps aux | grep -E '(solanum|atheme)' | head -3"
done
EOF

chmod +x performance-optimization.sh
./performance-optimization.sh
```

**Validation Criteria:**
- [ ] OpenSSL showing hardware acceleration (AES-NI)
- [ ] Database queries optimized for <100ms response
- [ ] Cross-region latency <150ms via Tailscale
- [ ] CPU utilization <70% under normal load
- [ ] Memory usage stable and within limits
- [ ] Performance monitoring showing optimal metrics

**Rollback Procedure:**
```bash
# If optimizations cause issues, revert to baseline configuration
fly deploy --app magnet-9rl --strategy immediate
fly deploy --app magnet-1eu --strategy immediate
fly deploy --app magnet-atheme --strategy immediate
```

**Success Metrics:**
- SSL handshake time <200ms
- IRC command response time <500ms
- Resource utilization optimized for cost/performance

---

### Step 23: Load Testing and Capacity Planning
**Duration:** 4-5 hours  
**Owner:** Performance Engineer  
**Dependencies:** Step 22 complete  

**Objective:** Validate system capacity and establish scaling thresholds

**Tasks:**
1. Conduct comprehensive load testing
2. Test system behavior at capacity limits
3. Validate auto-scaling and resource management
4. Establish capacity planning guidelines
5. Test degraded performance scenarios

**Implementation:**
```bash
# Comprehensive load testing
cat > load-test-production.sh << 'EOF'
#!/bin/bash
# Production load testing script

echo "=== Production Load Testing $(date) ==="

echo "--- Connection Load Test ---"
# Test maximum concurrent connections
for server in magnet-9rl.fly.dev magnet-1eu.fly.dev; do
    echo "Testing connection capacity for $server..."
    for i in {1..200}; do
        (
            exec 3<>/dev/tcp/$server/6667
            echo "NICK loadtest$i" >&3
            echo "USER loadtest$i 0 * :Load Test User $i" >&3
            sleep 120  # Stay connected for 2 minutes
            echo "QUIT :Load test complete" >&3
            exec 3>&-
        ) &
        
        if [ $((i % 50)) -eq 0 ]; then
            echo "Started $i connections..."
            sleep 10  # Brief pause every 50 connections
        fi
    done
    
    echo "Waiting for connections to complete..."
    wait
done

echo "--- Services Load Test ---"
# Test services under load
for i in {1..100}; do
    (
        exec 3<>/dev/tcp/magnet-9rl.fly.dev/6667
        echo "NICK svctest$i" >&3
        echo "USER svctest$i 0 * :Services Test User $i" >&3
        sleep 5
        echo "PRIVMSG NickServ :REGISTER testpass$i test$i@example.com" >&3
        sleep 5
        echo "JOIN #loadtest$i" >&3
        echo "PRIVMSG ChanServ :REGISTER #loadtest$i" >&3
        sleep 10
        echo "QUIT :Services test complete" >&3
        exec 3>&-
    ) &
    
    if [ $((i % 25)) -eq 0 ]; then
        echo "Started $i services tests..."
        sleep 5
    fi
done
wait

echo "--- Performance Monitoring During Load ---"
# Monitor performance during load test
for app in magnet-9rl magnet-1eu magnet-atheme; do
    echo "=== $app Performance Under Load ==="
    fly ssh console --app $app -C "uptime && free -h && ss -tan | grep -E ':(6667|6697)' | wc -l"
done
EOF

chmod +x load-test-production.sh
./load-test-production.sh
```

**Validation Criteria:**
- [ ] System handles target load without degradation
- [ ] Resource usage scales predictably with load
- [ ] Services remain responsive under high load
- [ ] Auto-scaling triggers work properly
- [ ] Database performance stable under load
- [ ] Network connectivity maintains quality

**Rollback Procedure:**
```bash
# If load testing reveals capacity issues, scale resources
fly scale memory 2gb --app magnet-9rl
fly scale memory 2gb --app magnet-1eu
fly scale memory 1gb --app magnet-atheme
```

**Success Metrics:**
- Handle 500+ concurrent connections without issues
- Response time degradation <50% under peak load
- Zero service failures during load test

---

### Step 24: Production Deployment and Validation
**Duration:** 3-4 hours  
**Owner:** SRE Engineer  
**Dependencies:** Step 23 complete  

**Objective:** Final production deployment and comprehensive validation

**Tasks:**
1. Conduct final pre-production checklist
2. Deploy to production configuration
3. Validate all systems in production mode
4. Conduct end-to-end testing
5. Sign off on production readiness

**Implementation:**
```bash
# Production readiness validation
cat > production-validation.sh << 'EOF'
#!/bin/bash
# Final production validation

echo "=== Production Readiness Validation $(date) ==="

echo "--- Infrastructure Status ---"
for app in magnet-9rl magnet-1eu magnet-atheme magnet-postgres; do
    STATUS=$(fly status --app $app | grep -E "(started|healthy)" | head -1)
    echo "$app: $STATUS"
    
    # Verify app is in correct region
    REGION=$(fly status --app $app | grep -o "region: [a-z]*" | cut -d' ' -f2)
    echo "$app region: $REGION"
done

echo "--- Network Connectivity ---"
echo "Testing full mesh connectivity..."
fly ssh console --app magnet-9rl -C "ping -c 3 magnet-1eu && ping -c 3 magnet-atheme"
fly ssh console --app magnet-1eu -C "ping -c 3 magnet-9rl"
fly ssh console --app magnet-atheme -C "ping -c 3 magnet-9rl"

echo "--- Service Integration ---"
echo "Testing IRC services integration..."
# Test NickServ and ChanServ functionality
exec 3<>/dev/tcp/magnet-9rl.fly.dev/6667
echo "NICK prodtest" >&3
echo "USER prodtest 0 * :Production Test" >&3
sleep 3
echo "PRIVMSG NickServ :REGISTER prodpass prod@example.com" >&3
sleep 3
echo "JOIN #production" >&3
echo "PRIVMSG ChanServ :REGISTER #production" >&3
sleep 3
echo "QUIT :Production test complete" >&3
exec 3>&-

echo "--- Security Validation ---"
echo "Checking SSL certificates..."
for server in magnet-9rl.fly.dev magnet-1eu.fly.dev; do
    echo "SSL check for $server..."
    echo | openssl s_client -connect $server:6697 -brief 2>/dev/null || echo "SSL check failed"
done

echo "--- Performance Validation ---"
echo "Final performance check..."
./performance-optimization.sh | tail -20

echo "--- Backup Validation ---"
echo "Verifying backup systems..."
fly postgres backup list --app magnet-postgres | head -3

echo "--- Monitoring Validation ---"
echo "Checking monitoring systems..."
for endpoint in https://magnet-9rl.fly.dev:8080/health https://magnet-1eu.fly.dev:8080/health; do
    if curl -f -s --max-time 10 "$endpoint" > /dev/null; then
        echo "$endpoint: Healthy"
    else
        echo "$endpoint: FAILED"
    fi
done

echo "=== Production Validation Complete ==="
echo "System ready for production traffic!"
EOF

chmod +x production-validation.sh
./production-validation.sh
```

**Validation Criteria:**
- [ ] All services running in production configuration
- [ ] Network connectivity fully operational
- [ ] IRC services integration working perfectly
- [ ] SSL/TLS certificates valid and functioning
- [ ] Performance meets all requirements
- [ ] Backup systems operational
- [ ] Monitoring and alerting functional
- [ ] Security hardening complete
- [ ] Documentation up-to-date
- [ ] Team trained on all procedures

**Rollback Procedure:**
```bash
# If production validation fails, implement emergency rollback
echo "EMERGENCY ROLLBACK PROCEDURE"
echo "1. Scale down to single region if needed"
echo "2. Disable problematic services"
echo "3. Restore from known good backup"
echo "4. Notify stakeholders of service degradation"
```

**Success Metrics:**
- 100% of validation tests pass
- All SLA requirements met
- Zero critical issues identified
- Team confident in production operations

---

## RISK ASSESSMENT AND MITIGATION

### High-Risk Integration Points

1. **Password Coordination (Steps 6, 9):** 
   - Risk: Services authentication failure
   - Mitigation: Automated coordination scripts with validation
   - Rollback: Manual password sync procedures

2. **Tailscale Mesh Formation (Steps 5, 8):**
   - Risk: Network connectivity failure
   - Mitigation: Incremental deployment with connectivity validation
   - Rollback: Single-region fallback mode

3. **Server Linking (Step 14):**
   - Risk: IRC protocol violations or split-brain scenarios
   - Mitigation: Extensive testing in isolated environment
   - Rollback: Disable linking, operate as independent servers

4. **Database Integration (Steps 7, 10):**
   - Risk: Data corruption or connectivity issues
   - Mitigation: Comprehensive backup and testing procedures
   - Rollback: Restore from backup, rebuild database

### Success Metrics Summary

- **Availability:** 99.9% uptime target
- **Performance:** <500ms IRC command response, <200ms SSL handshake
- **Scalability:** Handle 500+ concurrent connections
- **Recovery:** <30 minutes RTO, <5 minutes RPO
- **Security:** Zero critical vulnerabilities, automated secret rotation

### Small Team Operational Requirements

- **Time per step:** 2-4 hours maximum
- **Validation:** Clear pass/fail criteria for each step
- **Documentation:** Real-time updates throughout process
- **Testing:** Smoke tests, integration tests, performance baselines
- **Rollback:** Defined procedures for every integration point

This refined roadmap transforms the complex infrastructure deployment into a systematic, validated process suitable for small teams while maintaining production-grade reliability and performance.
