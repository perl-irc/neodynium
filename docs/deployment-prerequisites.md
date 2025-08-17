# Deployment Prerequisites

This document outlines the requirements and setup procedures for deploying the Magnet IRC Network infrastructure on Fly.io.

## Fly.io CLI Requirements

### Installation

Install the Fly.io CLI following the official instructions:

```bash
# macOS
brew install flyctl

# Linux/WSL
curl -L https://fly.io/install.sh | sh

# Windows PowerShell
iwr https://fly.io/install.ps1 -useb | iex
```

### Verification

Verify your installation:

```bash
fly version
```

Expected output should show a version number (e.g., `flyctl v0.1.xxx`).

## Authentication Setup

### Initial Authentication

1. Create a Fly.io account at https://fly.io if you don't have one
2. Authenticate your CLI:

```bash
fly auth login
```

3. Verify authentication:

```bash
fly auth whoami
```

### Organization Setup (Optional)

If deploying for an organization:

```bash
# List available organizations
fly orgs list

# Switch to organization context
fly auth login --org <org-name>
```

## Required Environment Variables

The following secrets must be configured for each application:

### Tailscale Integration

```bash
# Generate ephemeral auth keys from Tailscale admin console
fly secrets set TAILSCALE_AUTHKEY=tskey-auth-PLACEHOLDER --app magnet-9rl
fly secrets set TAILSCALE_AUTHKEY=tskey-auth-PLACEHOLDER --app magnet-1eu  
fly secrets set TAILSCALE_AUTHKEY=tskey-auth-PLACEHOLDER --app magnet-atheme
```

### IRC Server Passwords

```bash
# Generate secure passwords (24-32 characters recommended)
fly secrets set SERVICES_PASSWORD=$(openssl rand -base64 24) --app magnet-9rl
fly secrets set SERVICES_PASSWORD=$(openssl rand -base64 24) --app magnet-1eu
fly secrets set SERVICES_PASSWORD=$(openssl rand -base64 24) --app magnet-atheme

# Link passwords between IRC servers
LINK_PASS=$(openssl rand -base64 32)
fly secrets set LINK_PASSWORD_9RL_1EU="$LINK_PASS" --app magnet-9rl
fly secrets set LINK_PASSWORD_9RL_1EU="$LINK_PASS" --app magnet-1eu
```

### Operator Passwords

```bash
fly secrets set OPER_PASSWORD=$(openssl rand -base64 24) --app magnet-9rl
fly secrets set OPER_PASSWORD=$(openssl rand -base64 24) --app magnet-1eu
```

## App Creation

Create the Fly.io applications before deploying:

```bash
# Create apps in respective regions
fly apps create magnet-9rl --org <your-org>
fly apps create magnet-1eu --org <your-org>
fly apps create magnet-atheme --org <your-org>
```

## Volume Provisioning

Use the provided script to create persistent volumes:

```bash
# Preview what will be created
scripts/create-volumes.pl --dry-run

# Create volumes
scripts/create-volumes.pl
```

Manual volume creation (if script fails):

```bash
fly volumes create magnet_9rl_data --region ord --size 3 --app magnet-9rl
fly volumes create magnet_1eu_data --region ams --size 3 --app magnet-1eu
fly volumes create magnet_atheme_data --region ord --size 3 --app magnet-atheme
```

## Database Setup

Create and attach PostgreSQL database for Atheme services:

```bash
# Create PostgreSQL cluster
fly postgres create --name magnet-postgres --region ord --vm-size shared-cpu-1x --volume-size 10

# Attach to Atheme services
fly postgres attach --app magnet-atheme magnet-postgres
```

## Deployment Process

### Automated Deployment (Recommended)

The project includes GitHub Actions workflow for automated deployment following Fly.io best practices:

1. **Setup Deploy Token** (one-time setup):

```bash
# Generate deploy token for each app
fly tokens create deploy --app magnet-9rl
fly tokens create deploy --app magnet-1eu  
fly tokens create deploy --app magnet-atheme

# Add to GitHub repository secrets as FLY_API_TOKEN
# Go to GitHub repo → Settings → Secrets → Actions
# Create new secret: FLY_API_TOKEN = <your-deploy-token>
```

2. **Automatic Deployment**:
   - Push to `main` branch triggers automatic deployment
   - Workflow runs infrastructure tests first
   - Deploys all applications with remote builders
   - Provisions volumes automatically
   - Generates deployment reports

3. **Manual Deployment Trigger**:
   - Go to GitHub → Actions → "Deploy to Fly.io"
   - Click "Run workflow" for manual deployment

### Manual Deployment

For development or troubleshooting, use the deployment automation script:

```bash
# Preview deployment (dry-run)
scripts/deploy-magnet.pl --dry-run

# Full deployment with remote builders (recommended)
scripts/deploy-magnet.pl

# Deploy with local builds (if needed)
scripts/deploy-magnet.pl --local-build

# Deploy to specific organization
scripts/deploy-magnet.pl --org my-organization
```

### Traditional Manual Deployment

1. Deploy each application individually:

```bash
fly deploy --app magnet-9rl --config servers/magnet-9rl/fly.toml --remote-only
fly deploy --app magnet-1eu --config servers/magnet-1eu/fly.toml --remote-only
fly deploy --app magnet-atheme --config servers/magnet-atheme/fly.toml --remote-only
```

2. Verify deployments:

```bash
fly status --app magnet-9rl
fly status --app magnet-1eu
fly status --app magnet-atheme
```

3. Check health endpoints:

```bash
curl https://magnet-9rl.fly.dev/health
curl https://magnet-1eu.fly.dev/health
curl https://magnet-atheme.fly.dev/health
```

## CI/CD Best Practices

### Deploy Token Management

Following Fly.io recommendations for secure token management:

```bash
# Create dedicated deploy tokens (not personal auth tokens)
fly tokens create deploy --app <app-name> --name "GitHub Actions"

# Rotate tokens regularly (quarterly recommended)
fly tokens list
fly tokens revoke <token-id>
```

### Remote Builders

Always use `--remote-only` flag for deployments to leverage Fly.io's optimized build environment:

- Faster builds on AMD EPYC infrastructure
- Consistent build environment
- No local Docker daemon requirements
- Better caching and optimization

### Deployment Verification

The automated workflow includes comprehensive verification:

- Infrastructure tests before deployment
- App existence validation
- Health check verification
- Deployment status monitoring
- Automated rollback on failure

### Security Considerations

- Deploy tokens have limited scope (app-specific)
- Secrets are managed through Fly.io platform
- No sensitive data in repository
- Automated security scanning in CI/CD

## Rollback Procedures

### Application Rollback

Rollback to previous version:

```bash
# List recent releases
fly releases --app magnet-9rl

# Rollback to specific version
fly releases rollback v2 --app magnet-9rl
```

### Volume Rollback

Volume data cannot be automatically rolled back. Consider these strategies:

1. **Snapshot Strategy**: Create volume snapshots before major changes:

```bash
# Create snapshot (when feature becomes available)
fly volumes snapshot create magnet_9rl_data --app magnet-9rl
```

2. **Backup Strategy**: Export critical data before changes:

```bash
# SSH into machine and backup data
fly ssh console --app magnet-9rl
tar -czf /tmp/backup.tar.gz /opt/solanum/var
```

3. **Blue-Green Strategy**: Maintain parallel environments for critical updates.

### Secret Rotation

If secrets are compromised:

```bash
# Rotate Tailscale keys
fly secrets set TAILSCALE_AUTHKEY=tskey-auth-new-key --app magnet-9rl

# Rotate passwords (coordinate across all affected apps)
NEW_SERVICES_PASS=$(openssl rand -base64 24)
fly secrets set SERVICES_PASSWORD="$NEW_SERVICES_PASS" --app magnet-9rl
fly secrets set SERVICES_PASSWORD="$NEW_SERVICES_PASS" --app magnet-atheme
```

### Emergency Procedures

1. **Complete Service Restart**:

```bash
fly machine restart --app magnet-9rl
```

2. **Scale Down (Emergency Stop)**:

```bash
fly scale count 0 --app magnet-9rl
```

3. **Scale Up (Recovery)**:

```bash
fly scale count 1 --app magnet-9rl
```

## Monitoring and Logs

### Real-time Logs

```bash
fly logs --app magnet-9rl
```

### Health Monitoring

```bash
# Check machine status
fly machine list --app magnet-9rl

# Monitor metrics
fly machine status <machine-id> --app magnet-9rl
```

## Troubleshooting

### Common Issues

1. **Volume Mount Failures**: Ensure volumes exist and are in the correct region
2. **Health Check Failures**: Verify service is listening on port 8080
3. **Tailscale Connection Issues**: Check auth key validity and network access
4. **Database Connection Issues**: Verify PostgreSQL attachment and credentials

### Debug Commands

```bash
# SSH into running machine
fly ssh console --app magnet-9rl

# Check Tailscale status
fly ssh console --app magnet-9rl -C "tailscale status"

# View service logs
fly ssh console --app magnet-9rl -C "journalctl -f"
```

## Security Considerations

- Use ephemeral Tailscale auth keys (automatically cleaned up when containers stop)
- Rotate passwords regularly (monthly recommended)
- Monitor access logs for unusual activity
- Keep Fly.io CLI and base images updated
- Use least-privilege access for operational accounts