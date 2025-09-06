# Security Remediation: Tailscale Auth Keys

## Issue
Tailscale auth keys have been committed to the git repository history. These keys must be immediately revoked and removed from git history.

## Immediate Actions Required

### 1. Revoke Exposed Keys
**URGENT**: Log into Tailscale admin panel and revoke these keys immediately:
- `tskey-auth-k7NgX72hkZ11CNTRL-*` 
- `tskey-auth-k8QSBCo5Sj11CNTRL-*`

### 2. Clean Git History
Run the cleanup script to remove keys from all commits:

```bash
# Modern approach (recommended)
./clean-secrets-filter-repo.sh

# Alternative approach
./clean-secrets.sh
```

### 3. Force Push Changes
After cleaning, force push to remote:

```bash
git remote add origin <your-repo-url>  # if remote was removed
git push --force-with-lease --all
git push --force-with-lease --tags
```

### 4. Generate New Keys
Create new ephemeral auth keys in Tailscale admin panel.

### 5. Update Deployment Scripts
Use environment variables instead of hardcoded keys:

```bash
export TAILSCALE_AUTHKEY="tskey-auth-NEW-KEY-HERE"
./deploy-host-9rl-secure.sh
```

## Files Affected
The following files contained exposed keys:
- `deploy-9rl.sh`
- `deploy-1eu.sh`
- `deploy-sidecar-*.sh`
- `deploy-host-*.sh`

## Prevention Measures

### 1. Use Environment Variables
```bash
# Good
export TAILSCALE_AUTHKEY="tskey-auth-..."
./deploy.sh

# Bad - never hardcode in scripts
TAILSCALE_AUTHKEY=tskey-auth-... ./deploy.sh
```

### 2. Add to .gitignore
```
# Secrets and keys
*.key
*.pem
.env
.envrc
secrets/
```

### 3. Use Pre-commit Hooks
Install git hooks to detect secrets before commit:

```bash
pip install pre-commit
pre-commit install
```

### 4. Repository Secrets Scanning
Enable GitHub's secret scanning if using GitHub.

## Verification Steps

After cleanup, verify keys are gone:

```bash
# Should return no results
git log --all -S 'tskey-auth-k' --source --all

# Check current files
grep -r "tskey-auth" . --exclude-dir=.git
```

## Coordination Required

**Anyone who has cloned this repository must:**
1. Delete their local clone
2. Re-clone after the force push
3. Update any local deployment scripts

## Root Cause
Auth keys were hardcoded in deployment scripts instead of using environment variables or secrets management.

## Long-term Solution
- All secrets via environment variables
- Use ephemeral auth keys (auto-expire)
- Implement proper secrets management
- Regular key rotation