# Magnet IRC Network - Container Architecture

This document provides a comprehensive overview of the Docker container architecture for the Magnet IRC Network, including design decisions, optimization strategies, and deployment patterns.

## Architecture Overview

The Magnet IRC Network consists of two primary container types, each optimized for specific roles in the IRC infrastructure:

### Container Types

1. **Solanum IRCd Container** (`Dockerfile.solanum`)
   - **Purpose**: IRC server daemon for client connections and server linking
   - **Applications**: magnet-9rl (US Hub), magnet-1eu (EU Server)
   - **Base**: Alpine Linux with OpenSSL optimization

2. **Atheme Services Container** (`Dockerfile.atheme`)
   - **Purpose**: IRC services (NickServ, ChanServ, etc.) with database backend
   - **Application**: magnet-atheme (US Services)
   - **Base**: Alpine Linux with PostgreSQL client support

## Design Principles

### Multi-Stage Build Architecture
Both containers use multi-stage builds to optimize for:
- **Build Stage**: Full development environment with build tools
- **Production Stage**: Minimal runtime environment with only required binaries
- **Tailscale Integration Stage**: Official Tailscale binaries from upstream image

### AMD EPYC Optimization
Optimized specifically for Fly.io's AMD EPYC infrastructure:
- **Compile Flags**: `-march=znver2 -O3` for AMD EPYC specific optimizations
- **OpenSSL AES-NI**: Hardware-accelerated cryptography for SSL/TLS performance
- **Multi-core Compilation**: `make -j$(nproc)` for parallel builds

### Security Hardening
- **Non-root Execution**: All services run as dedicated users (`ircd`, `atheme`)
- **Ephemeral Auth Keys**: Tailscale devices automatically cleaned up
- **Minimal Attack Surface**: Alpine Linux base with only required packages
- **Secure Defaults**: Configuration templates with secure parameter sets

## Container Specifications

### Solanum IRCd Container

#### Build Stage Components
```dockerfile
FROM alpine:latest as builder
# Development tools: build-base, autoconf, git, etc.
# OpenSSL development headers
# Source compilation with AMD EPYC flags
```

#### Production Stage Components
```dockerfile
FROM alpine:latest
# Runtime: openssl, ca-certificates, iptables
# Tailscale binaries from official image
# User management and permissions
```

#### Key Features
- **OpenSSL Integration**: Compiled with `--enable-openssl` for SSL/TLS support
- **AMD EPYC Flags**: `CFLAGS="-march=znver2 -O3"` for processor-specific optimization
- **Tailscale Mesh**: Official binaries for secure admin access
- **Configuration Templating**: Environment variable substitution with `envsubst`
- **Health Endpoints**: HTTP service on port 8080 for Fly.io health checks

#### Port Configuration
- **6667**: IRC plaintext connections
- **6697**: IRC SSL/TLS connections  
- **7000**: Server-to-server linking (SSL/TLS)
- **8080**: HTTP health endpoint

#### Volume Mounts
- **Source**: Fly.io persistent volume (`magnet_*_data`)
- **Destination**: `/opt/solanum/var` (configurations and runtime data)
- **Purpose**: Persistent storage for generated passwords and configurations

### Atheme Services Container

#### Build Stage Components
```dockerfile
FROM alpine:latest as builder
# PostgreSQL development libraries
# PCRE development headers for pattern matching
# Atheme source compilation with database support
```

#### Production Stage Components
```dockerfile
FROM alpine:latest  
# PostgreSQL client libraries
# Runtime dependencies for services
# Tailscale integration matching IRC servers
```

#### Key Features
- **PostgreSQL Backend**: Compiled with `--with-postgresql` for database persistence
- **SSL Support**: `--enable-ssl` for encrypted connections to IRC servers
- **Contrib Modules**: `--enable-contrib` for extended functionality
- **PCRE Support**: Pattern matching for advanced service features
- **Database Connectivity**: PostgreSQL client for `magnet-postgres.internal`

#### Port Configuration
- **6667**: Connection to IRC servers via Tailscale mesh
- **8080**: HTTP health endpoint

#### Volume Mounts
- **Source**: Fly.io persistent volume (`magnet_atheme_data`)
- **Destination**: `/var/lib/atheme` (services database and configuration)
- **Purpose**: Persistent storage for services data and generated credentials

## Tailscale Integration Architecture

### Official Binary Integration
Both containers integrate Tailscale using the official approach:

```dockerfile
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale/tailscale:latest /usr/local/bin/tailscale /usr/local/bin/tailscale
```

### Ephemeral Device Strategy
- **Automatic Registration**: Devices join mesh using ephemeral auth keys
- **Dynamic Hostnames**: `magnet-9rl`, `magnet-1eu`, `magnet-atheme`
- **Automatic Cleanup**: Devices removed when containers terminate
- **Admin SSH Access**: Direct SSH through Tailscale mesh network

### Network Isolation
- **Service Communication**: Fly.io private internal network for IRC traffic
- **Admin Access**: Tailscale mesh for secure administrative operations
- **Route Management**: `--accept-routes=false` to prevent route conflicts

## Configuration Management

### Template System
Both containers use configuration templates with environment variable substitution:

#### Solanum Template Variables
- `${SERVER_NAME}`: Unique server identifier (magnet-9rl, magnet-1eu)
- `${SERVER_SID}`: Three-character server ID (9RL, 1EU)  
- `${SERVER_DESCRIPTION}`: Human-readable server description
- `${LINK_PASSWORD_9RL_1EU}`: Server-to-server linking authentication
- `${OPER_PASSWORD}`: IRC operator authentication
- `${SERVICES_PASSWORD}`: IRC services authentication

#### Atheme Template Variables
- `${ATHEME_NETWORK}`: Network name (Magnet)
- `${ATHEME_NETWORK_DOMAIN}`: Domain suffix (kowloon.social)
- `${SERVICES_PASSWORD}`: Authentication to IRC servers
- `${OPERATOR_PASSWORD}`: Services operator authentication
- `${ATHEME_POSTGRES_HOST}`: Database host (magnet-postgres.internal)
- `${ATHEME_POSTGRES_DB}`: Database name
- `${ATHEME_HUB_SERVER}`: Configurable hub server name (default: magnet-9RL)
- `${ATHEME_HUB_HOSTNAME}`: Configurable hub Tailscale hostname (default: magnet-9rl)

### Password Generation Strategy
Secure password generation using `pwgen` with fallback to environment variables:

```bash
# Use secrets if available, otherwise generate
SERVICES_PASS=${SERVICES_PASSWORD:-$(pwgen -s 32 1)}
OPER_PASS=${OPER_PASSWORD:-$(pwgen -s 24 1)}
```

## Performance Optimizations

### Compilation Optimizations
- **AMD EPYC Targeting**: `-march=znver2` compiler flag
- **Optimization Level**: `-O3` for maximum performance
- **Parallel Compilation**: `make -j$(nproc)` for faster builds
- **Link-Time Optimization**: Enabled where supported

### Runtime Optimizations
- **OpenSSL AES-NI**: Hardware-accelerated encryption/decryption
- **Efficient Connection Handling**: `epoll` support for Linux networking
- **Memory Management**: Optimized sendq and buffer configurations
- **CPU Scaling**: Container sizing aligned with workload characteristics

### Container Sizing Strategy

#### Solanum IRCd Containers
- **Memory**: 1GB (sufficient for thousands of concurrent connections)
- **CPU**: 1-2 vCPUs (single-threaded with occasional spikes)
- **Use Case**: Client connections and occasional server linking

#### Atheme Services Container
- **Memory**: 2GB (database operations and service state)
- **CPU**: 2 vCPUs (database queries and multi-service operations)
- **Use Case**: Services registration, channel management, authentication

## Security Architecture

### User Isolation
Each container runs services under dedicated non-root users:

```dockerfile
# Solanum container
RUN adduser -D -s /bin/false ircd
USER ircd

# Atheme container  
RUN adduser -D -s /bin/false atheme
USER atheme
```

### Filesystem Security
- **Configuration Protection**: 600 permissions on password files
- **Log Isolation**: Dedicated log directories with proper ownership
- **Runtime Separation**: Services cannot access each other's data

### Network Security
- **Tailscale Mesh**: Encrypted overlay network for admin access
- **SSL/TLS**: All IRC connections encrypted (ports 6697, 7000)
- **Health Endpoints**: Minimal HTTP service for monitoring only

## Startup Process Architecture

### Initialization Sequence
1. **Tailscale Daemon**: Background process with state persistence
2. **Network Registration**: Ephemeral device with dynamic hostname
3. **Password Management**: Generate or load existing credentials
4. **Template Processing**: Environment variable substitution
5. **Service Startup**: IRC daemon or services as non-root user
6. **Health Endpoint**: Background HTTP server for monitoring

### Dependency Management
- **Tailscale First**: Network connectivity established before services
- **Configuration Before Service**: Templates processed before daemon startup
- **Graceful Degradation**: Services can start without Tailscale in emergency

## Monitoring and Observability

### Health Check Implementation
Both containers provide HTTP health endpoints:

```bash
# Simple health response
echo "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nService Health OK"
```

### Log Management
- **Structured Output**: Clear startup sequence logging
- **Security Awareness**: No credential logging to stdout/stderr
- **Performance Metrics**: Key operational parameters displayed

### Diagnostic Endpoints
- **Health Status**: `/health` endpoint for automated monitoring
- **Service Verification**: Tailscale status and IRC connectivity
- **Performance Monitoring**: OpenSSL benchmarking capabilities

## Build Process Architecture

### Automated Build Pipeline
The `scripts/build-images.sh` provides:
- **Multi-platform Support**: `linux/amd64` targeting
- **Caching Strategy**: Configurable build cache management
- **Validation Pipeline**: Pre-build file and permission verification
- **Image Tagging**: Flexible registry and tag management

### Build Optimization Strategy
- **Layer Caching**: Optimized Dockerfile layer ordering
- **Multi-stage Efficiency**: Minimal production image size
- **Parallel Processing**: `$(nproc)` compilation utilization
- **Build Time Targets**: Sub-10-minute build completion

## Deployment Integration

### Fly.io Platform Integration
- **Volume Management**: Persistent storage for configurations and data  
- **Health Monitoring**: HTTP endpoint integration with Fly.io health checks
- **Service Discovery**: Container hostnames align with Tailscale mesh
- **Resource Allocation**: Sizing optimized for AMD EPYC performance characteristics

### Regional Distribution
- **US Hub (ord)**: magnet-9rl, magnet-atheme in Chicago region
- **EU Server (ams)**: magnet-1eu in Amsterdam region
- **Latency Optimization**: Regional deployment for user proximity
- **Cross-region Linking**: Tailscale mesh for secure inter-region communication

This architecture provides a robust, secure, and performant foundation for the Magnet IRC Network, leveraging modern containerization practices with specific optimizations for the Fly.io AMD EPYC infrastructure.