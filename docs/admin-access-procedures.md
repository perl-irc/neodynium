# Magnet IRC Network - Admin Access Procedures

This document outlines the administrative access procedures for the Magnet IRC Network infrastructure using Tailscale mesh networking.

## Overview

The Magnet IRC Network uses Tailscale for secure administrative access to IRC servers and services. All containers automatically join the Tailscale mesh network with ephemeral devices that are automatically cleaned up when containers terminate.

## Tailscale Mesh Architecture

### Device Hostnames
- **magnet-9rl**: US Hub IRC server (Chicago)
- **magnet-1eu**: EU IRC server (Amsterdam) 
- **magnet-atheme**: IRC services (Chicago)

### Network Design
- **Ephemeral devices**: Automatically removed when containers stop
- **Pre-approved access**: Devices join without manual approval (if configured)
- **SSH access enabled**: Direct SSH access through Tailscale mesh
- **Network isolation**: Admin traffic separated from service-to-service communication

## Prerequisites

### Tailscale Account Setup
1. Create a Tailscale account at https://tailscale.com
2. Generate ephemeral auth keys at https://login.tailscale.com/admin/settings/keys
3. Configure auth key settings:
   - ✅ **Ephemeral**: Devices automatically removed when offline
   - ✅ **Pre-approved**: Skip manual device approval (optional)
   - ⏱️ **90-day expiration**: Set reasonable expiration time

### GitHub Repository Secrets Configuration
Set both Fly.io API token and Tailscale auth key as GitHub repository secrets for CI/CD deployment:

```bash
# Generate ephemeral Tailscale auth key
EPHEMERAL_KEY="tskey-auth-xxxxxx-xxxx"

# Generate Fly.io deploy token  
FLY_TOKEN="fo1_xxxxxxxxxxxxxxxxxxxxxx"

# Add to GitHub repository secrets at:
# https://github.com/your-org/your-repo/settings/secrets/actions
# 
# Required secrets:
# Name: FLY_API_TOKEN
# Value: fo1_xxxxxxxxxxxxxxxxxxxxxx
#
# Name: TAILSCALE_AUTHKEY  
# Value: tskey-auth-xxxxxx-xxxx
```

**Note**: The GitHub Actions workflow will automatically set these as Fly.io secrets during deployment.

## Administrative Access Methods

### Method 1: Direct SSH via Tailscale (Recommended)

Once containers are running and connected to Tailscale:

```bash
# SSH directly to containers via Tailscale hostnames
ssh root@magnet-9rl      # US Hub IRC server
ssh root@magnet-1eu      # EU IRC server  
ssh root@magnet-atheme   # IRC services

# Alternative: Use full Tailscale hostnames
ssh root@magnet-9rl.tail[suffix].ts.net
```

### Method 2: Fly.io SSH (Always Available)

Traditional access through Fly.io platform:

```bash
# SSH via Fly.io (works regardless of Tailscale status)
fly ssh console --app magnet-9rl
fly ssh console --app magnet-1eu
fly ssh console --app magnet-atheme
```

### Method 3: SSH with Port Forwarding

For accessing services through SSH tunnels:

```bash
# Forward IRC ports through SSH
ssh -L 6667:localhost:6667 root@magnet-9rl
ssh -L 6697:localhost:6697 root@magnet-9rl

# Forward HTTP health endpoints
ssh -L 8080:localhost:8080 root@magnet-atheme
```

## Common Administrative Tasks

### Container Management

```bash
# View real-time logs
fly logs --app magnet-9rl
fly logs --app magnet-atheme

# Restart containers
fly machines restart --app magnet-9rl
fly machines restart --app magnet-atheme

# Deploy updates
fly deploy --app magnet-9rl
fly deploy --app magnet-atheme
```

### Configuration Management

```bash
# View current IRC configuration
ssh root@magnet-9rl cat /opt/solanum/etc/ircd.conf

# View generated passwords (sensitive!)
ssh root@magnet-9rl cat /opt/solanum/etc/passwords.conf

# View Atheme configuration
ssh root@magnet-atheme cat /opt/atheme/etc/atheme.conf
```

### Network Diagnostics

```bash
# Check Tailscale mesh status
ssh root@magnet-9rl '/usr/local/bin/tailscale status'
ssh root@magnet-1eu '/usr/local/bin/tailscale status'

# Test connectivity between servers
ssh root@magnet-9rl ping magnet-1eu
ssh root@magnet-9rl ping magnet-atheme

# Monitor IRC connections
ssh root@magnet-9rl 'netstat -an | grep :6697'

# Check SSL certificate status
ssh root@magnet-9rl 'openssl s_client -connect localhost:6697 -brief'
```

### Performance Monitoring

```bash
# Check OpenSSL performance on AMD EPYC
ssh root@magnet-9rl 'openssl speed aes-256-cbc'

# Monitor concurrent connections
ssh root@magnet-9rl 'ss -tan | grep :6697 | wc -l'

# Check CPU and memory usage
ssh root@magnet-9rl top -n 1
ssh root@magnet-atheme top -n 1

# Verify AMD EPYC optimizations
ssh root@magnet-9rl 'cat /proc/cpuinfo | grep flags'
```

## Security Procedures

### Auth Key Management

#### Key Rotation (Recommended: 90 days)
```bash
# Generate new ephemeral key
NEW_KEY="tskey-auth-xxxxxx-yyyy"

# Update GitHub repository secret
# Go to: https://github.com/your-org/your-repo/settings/secrets/actions
# Update TAILSCALE_AUTHKEY with new value

# Redeploy to apply new key (triggers via GitHub Actions)
git commit --allow-empty -m "Rotate Tailscale auth key"
git push

# Or manually update Fly.io secrets if needed
fly secrets set TAILSCALE_AUTHKEY=$NEW_KEY --app magnet-9rl
fly secrets set TAILSCALE_AUTHKEY=$NEW_KEY --app magnet-1eu
fly secrets set TAILSCALE_AUTHKEY=$NEW_KEY --app magnet-atheme
fly machines restart --app magnet-9rl
fly machines restart --app magnet-1eu  
fly machines restart --app magnet-atheme
```

#### Emergency Key Revocation
```bash
# Revoke auth key at Tailscale admin console
# https://login.tailscale.com/admin/settings/keys

# Containers will lose Tailscale access but remain accessible via fly ssh
```

### Device Cleanup

#### Automatic Cleanup (Normal Operation)
- **Ephemeral devices are automatically removed when containers stop**
- **No manual intervention required** - this is the key benefit of ephemeral devices
- Devices reappear with same hostnames when containers restart
- Tailscale handles all lifecycle management automatically

### Access Audit

#### Device Inventory
```bash
# List all devices in Tailscale network
tailscale status

# Web interface: https://login.tailscale.com/admin/machines
```

#### Connection Monitoring
```bash
# Monitor SSH connections to containers
ssh root@magnet-9rl 'who'
ssh root@magnet-9rl 'last -10'

# Monitor Tailscale connection logs
ssh root@magnet-9rl 'journalctl -u tailscaled --since "1 hour ago"'
```

## Troubleshooting

### Tailscale Connection Issues

```bash
# Check Tailscale daemon status
ssh root@magnet-9rl 'pgrep tailscaled'

# Restart Tailscale daemon
ssh root@magnet-9rl 'pkill tailscaled && /usr/local/bin/tailscaled &'

# Re-authenticate with new connection
ssh root@magnet-9rl '/usr/local/bin/tailscale up --auth-key=$TAILSCALE_AUTHKEY --hostname=magnet-9rl --ephemeral'
```

### SSH Access Problems

```bash
# Verify SSH service is running
ssh root@magnet-9rl 'pgrep sshd'

# Check SSH configuration
ssh root@magnet-9rl 'cat /etc/ssh/sshd_config | grep -E "(PermitRoot|PasswordAuth)"'

# Restart SSH service
ssh root@magnet-9rl 'service ssh restart'
```

### Network Connectivity Issues

```bash
# Test basic network connectivity
ssh root@magnet-9rl 'ping -c 3 1.1.1.1'

# Check routing table
ssh root@magnet-9rl 'ip route show'

# Verify Tailscale interface
ssh root@magnet-9rl 'ip addr show tailscale0'
```

## Emergency Procedures

### Hub Server Failover
If the primary hub server (magnet-9rl) needs to be changed due to failure or maintenance:

```bash
# Update Atheme services to connect to backup hub
fly secrets set ATHEME_HUB_SERVER=magnet-1EU --app magnet-atheme
fly secrets set ATHEME_HUB_HOSTNAME=magnet-1eu --app magnet-atheme

# Restart Atheme to apply new hub configuration
fly machines restart --app magnet-atheme

# Verify services connection to new hub
fly ssh console --app magnet-atheme -C 'grep uplink /opt/atheme/etc/atheme.conf'
```

**Note**: Ensure the target hub server is configured to accept services connections before switching.

### Complete Network Isolation
If Tailscale access needs to be completely disabled:

```bash
# Stop Tailscale on all containers
fly ssh console --app magnet-9rl -C 'pkill tailscaled'
fly ssh console --app magnet-1eu -C 'pkill tailscaled'  
fly ssh console --app magnet-atheme -C 'pkill tailscaled'

# Access only via fly ssh from this point
```

### Restore Tailscale Access
```bash
# Restart containers to re-establish Tailscale
fly machines restart --app magnet-9rl
fly machines restart --app magnet-1eu
fly machines restart --app magnet-atheme

# Or manually restart Tailscale daemons
fly ssh console --app magnet-9rl -C '/app/start.sh &'
```

### Password Recovery
```bash
# Extract passwords from hub server
fly ssh console --app magnet-9rl -C 'cat /opt/solanum/etc/passwords.conf'

# Reset passwords by deleting password file and restarting
fly ssh console --app magnet-9rl -C 'rm /opt/solanum/etc/passwords.conf'
fly machines restart --app magnet-9rl
```

## Security Best Practices

1. **Regular key rotation**: Rotate Tailscale auth keys every 90 days
2. **Monitor device list**: Regularly review active devices in Tailscale admin
3. **Use ephemeral keys**: Never use permanent auth keys for containers
4. **Audit SSH access**: Monitor SSH login logs for unusual activity
5. **Network segmentation**: Keep admin access separate from service communication
6. **Emergency access**: Always maintain fly ssh access as backup method

## Support and Documentation

- **Tailscale Documentation**: https://tailscale.com/kb/
- **Fly.io SSH Guide**: https://fly.io/docs/flyctl/ssh/
- **Container Logs**: `fly logs --app <app-name>`
- **Status Monitoring**: `fly status --app <app-name>`

For infrastructure issues, use the development scripts in `scripts/` directory for automated troubleshooting and recovery procedures.