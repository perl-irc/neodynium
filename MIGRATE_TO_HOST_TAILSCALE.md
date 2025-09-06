# Migrate to Host-Level Tailscale

## Problem
The current sidecar architecture prevents proper SSH access to DigitalOcean hosts because Tailscale SSH connects to the sidecar container instead of the host.

## Solution
Install Tailscale directly on the host OS and simplify container architecture.

## Migration Steps

### 1. Deploy magnet-9rl (US Hub)
```bash
scp deploy-host-9rl.sh root@178.62.240.156:~/
ssh root@178.62.240.156
chmod +x deploy-host-9rl.sh
./deploy-host-9rl.sh
```

### 2. Deploy magnet-1eu (EU Leaf)
```bash
scp deploy-host-1eu.sh root@139.59.144.201:~/
ssh root@139.59.144.201
chmod +x deploy-host-1eu.sh
./deploy-host-1eu.sh
```

### 3. Deploy magnet-atheme (Services)
```bash
scp deploy-host-atheme.sh root@142.93.136.70:~/
ssh root@142.93.136.70
chmod +x deploy-host-atheme.sh
./deploy-host-atheme.sh
```

## Benefits of Host Tailscale

1. **Direct SSH Access**: `ssh root@magnet-9rl.camel-kanyu.ts.net` reaches the actual host
2. **Simplified Containers**: No more complex sidecar networking
3. **Better Administration**: Full Docker and system access via SSH
4. **Same Networking**: Containers still communicate via Tailscale mesh
5. **Port Exposure**: Direct port mapping without network namespace sharing

## What Changes

- **Before**: Sidecar containers + network namespace sharing
- **After**: Host Tailscale + simple container networking
- **SSH Access**: Host OS instead of container shell
- **Port Mapping**: Direct `-p 6667:6667` instead of shared networking

## Verification

After deployment, each server should be accessible:
- `ssh root@magnet-9rl.camel-kanyu.ts.net`
- `ssh root@magnet-1eu.camel-kanyu.ts.net` 
- `ssh root@magnet-atheme.camel-kanyu.ts.net`

IRC functionality should be identical, but administration is much simpler.