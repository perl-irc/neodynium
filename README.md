# Magnet IRC Network

A modern, distributed IRC network infrastructure built for irc.perl.org with
multi-region deployment.

## Overview

The Magnet IRC Network is IRC infrastructure that provides reliable, secure,
and performant IRC services across multiple geographic regions. Built using
Solanum IRCd and Atheme services, it leverages Fly.io's global infrastructure
and Tailscale's mesh networking for secure inter-server communication.

### Key Features

- **Multi-Region Deployment**: US (Chicago) and EU (Amsterdam) regions for
  optimal global performance
- **Security-First Design**: Tailscale mesh networking, ephemeral
  authentication keys, auto-generated passwords
- **High Availability**: Geographic redundancy with automatic failover
  capabilities
- **Modern Infrastructure**: Container-based deployment with proper health
  checks and monitoring

## Architecture

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

### Components

1. **magnet-9RL** - Primary IRC server (US/Chicago)
   - Solanum IRCd with OpenSSL optimizations
   - Hub server for network coordination
   - SSL/TLS client connections on port 6697

2. **magnet-1EU** - Secondary IRC server (EU/Amsterdam)
   - Solanum IRCd with OpenSSL optimizations
   - Linked to US hub for global federation
   - Regional optimization for European users

3. **magnet-atheme** - IRC Services (US/Chicago)
   - User registration and authentication (NickServ)
   - Channel management services (ChanServ)
   - Persistent data storage via PostgreSQL

4. **magnet-postgres** - Database (US/Chicago)
   - PostgreSQL database for services persistence
   - User accounts, channel registrations, configurations
   - Automated backups and high availability

## Getting Started

### Prerequisites

- Access to the perl-irc Github organization
- [Fly.io CLI](https://fly.io/docs/hands-on/install-flyctl/) installed and authenticated
- Access to the `magnet-irc` Fly.io organization
- Tailscale account with access to the `perl-irc` organization
- Basic familiarity with IRC network administration

## Deployment

### Development Deployment

For testing and development purposes, use development-specific app names to avoid
conflicts with production:

```bash
# Create development apps with -dev suffix
fly apps create magnet-hub-dev --org magnet-irc
fly apps create magnet-atheme-dev --org magnet-irc

# Set up Tailscale authentication for dev
fly secrets set TAILSCALE_AUTHKEY=tskey-auth-xxxxx --app magnet-9rl-dev

# Deploy base infrastructure (development)
fly deploy --app magnet-hub-dev
fly deploy --app magnet-atheme-dev

# Validate mesh connectivity
fly ssh console --app magnet-hub-dev
tailscale status
```

**Important**: Always use the `-dev` suffix for development deployments to prevent
conflicts with production infrastructure.

### Production Deployment

Follow the systematic approach outlined in `github-issues.md`:

1. **Start with Issue #1** - Implement base infrastructure with proper testing
2. **Follow TDD methodology** - Write failing tests, implement minimal code to pass
3. **Validate each step** - Ensure all tests pass before proceeding
4. **Build incrementally** - Each issue adds functionality while maintaining stability

## Configuration

### Key Environment Variables

- `SERVER_NAME` - Unique server identifier (magnet-9RL, magnet-1EU)
- `SERVER_SID` - Three-character server ID for IRC protocol
- `SERVER_DESCRIPTION` - Human-readable server description
- `TAILSCALE_AUTHKEY` - Ephemeral auth key for mesh networking
- `SERVICES_PASSWORD` - Authentication between IRC server and services
- `LINK_PASSWORD_9RL_1EU` - Authentication between linked IRC servers

### Configuration Templates

The project uses environment variable substitution in configuration templates:

- `ircd.conf.template` - Solanum server configuration
- `atheme.conf.template` - Atheme services configuration
- Startup scripts handle dynamic password generation and Tailscale initialization

## Security

### Security Features

- **Ephemeral Tailscale Keys** - Devices automatically cleaned up on container termination
- **Auto-Generated Passwords** - 24-32 character secure passwords for all inter-service communication
- **SSL/TLS Everywhere** - All client and server-to-server communications encrypted
- **Private Mesh Networking** - Inter-server communication isolated via Tailscale
- **AMD EPYC Optimizations** - Hardware-accelerated cryptography with OpenSSL

### Security Best Practices

- No passwords stored in plain text or logs
- Secure credential distribution via Fly.io secrets
- Network isolation from public internet for internal communication
- Regular password rotation capabilities
- Comprehensive security audit coverage in test suite

## Performance

### Optimization Features

- **OpenSSL with AES-NI** acceleration on AMD EPYC processors
- **Multi-core compilation** during Docker builds
- **Optimized connection classes** for different user types and regions
- **Efficient resource allocation** (1-2GB RAM, 1-2 vCPUs per service)
- **Geographic distribution** for optimal user experience

### Performance Monitoring

The project includes comprehensive performance testing:
- Response time measurement and SLA establishment
- Throughput testing under load
- Resource utilization monitoring
- Capacity planning metrics
- Performance regression detection

## Troubleshooting

### Common Operations

```bash
# Check application status
fly status --app magnet-9rl

# View logs
fly logs --app magnet-9rl

# SSH into container
fly ssh console --app magnet-9rl

# Check Tailscale mesh status
tailscale status

# Monitor SSL connections
netstat -an | grep :6697

# Test OpenSSL performance
openssl speed aes-256-cbc

# Verify AMD EPYC features
cat /proc/cpuinfo | grep flags
```

### Health Checks

All components include comprehensive health checks:
- Tailscale mesh connectivity
- IRC server responsiveness
- Services authentication status
- Database connectivity
- SSL certificate validity

## Development

### Contributing

1. **Use GitHub Issues** - Follow the systematic 15-issue implementation plan
2. **Maintain Documentation** - Update relevant documentation with changes
3. **Test Thoroughly** - Ensure all tests pass before submitting changes
4. **Security Review** - Consider security implications of all changes

### Testing

The project emphasizes comprehensive testing:
- **Unit Tests** - Component-level functionality validation
- **Integration Tests** - Inter-component communication testing
- **End-to-End Tests** - Complete IRC network functionality
- **Load Tests** - Performance and stability under realistic usage
- **Security Tests** - Vulnerability and penetration testing

### Code Style

- Simple, clean, maintainable solutions preferred
- Match existing code style and formatting
- Preserve comments and documentation
- Use descriptive, evergreen naming conventions
- No mock implementations - always use real data and APIs

## Documentation

### Key Files

- **`README.md`** - This comprehensive project overview
- **`LICENSE`** - MIT License for the project

### Additional Resources

- [Fly.io Documentation](https://fly.io/docs/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Solanum IRCd Documentation](https://github.com/solanum-ircd/solanum)
- [Atheme Services Documentation](https://github.com/atheme/atheme)

## License

This project is licensed under the MIT License - see the
[LICENSE](/Users/perigrin/dev/magnet/LICENSE) file for details.

## Organizations

- **Fly.io Organization**: `magnet-irc`
- **Tailscale Organization**: `perl-irc`
- **Github Organization**: `perl-irc`

## Support

For issues, questions, or contributions:
1. Submit issues following the established format
2. Ensure all tests pass before requesting reviews

---

**Note**: This infrastructure is designed for production IRC network operation.
Follow all security best practices and test thoroughly in development
environments before production deployment.
