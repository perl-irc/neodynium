#!/bin/bash
# ABOUTME: Remove Tailscale auth keys from git repository history
# ABOUTME: Uses git filter-branch to scrub sensitive data from all commits

set -e

echo "WARNING: This will rewrite git history and change all commit hashes!"
echo "Make sure you have a backup and coordinate with anyone else who has cloned this repo."
echo ""
echo "Found Tailscale keys in repository that need to be removed:"
echo "- tskey-auth-k7NgX72hkZ11CNTRL-*"
echo "- tskey-auth-k8QSBCo5Sj11CNTRL-*"
echo ""
read -p "Continue with history rewrite? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Create a backup branch
git branch backup-before-secret-cleanup HEAD

# Use git filter-branch to remove the secrets
echo "Removing Tailscale auth keys from repository history..."
git filter-branch --tree-filter '
    find . -type f -name "*.sh" -exec sed -i "" "s/tskey-auth-k[A-Za-z0-9_-]*/<TAILSCALE_AUTH_KEY>/g" {} \; 2>/dev/null || true
    find . -type f -name "*.md" -exec sed -i "" "s/tskey-auth-k[A-Za-z0-9_-]*/<TAILSCALE_AUTH_KEY>/g" {} \; 2>/dev/null || true
    find . -type f -name "*.yml" -exec sed -i "" "s/tskey-auth-k[A-Za-z0-9_-]*/<TAILSCALE_AUTH_KEY>/g" {} \; 2>/dev/null || true
    find . -type f -name "*.yaml" -exec sed -i "" "s/tskey-auth-k[A-Za-z0-9_-]*/<TAILSCALE_AUTH_KEY>/g" {} \; 2>/dev/null || true
' --all

# Clean up the refs
echo "Cleaning up git references..."
git for-each-ref --format='delete %(refname)' refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo "Git history has been rewritten!"
echo "All Tailscale auth keys have been replaced with <TAILSCALE_AUTH_KEY>"
echo ""
echo "Next steps:"
echo "1. Verify the keys are gone: git log --all -S 'tskey-auth-k' --source --all"
echo "2. Force push to remote: git push --force-with-lease --all"
echo "3. Revoke the exposed keys in Tailscale admin panel"
echo "4. Generate new auth keys"
echo "5. Update deployment scripts with new keys"
echo ""
echo "Backup branch created: backup-before-secret-cleanup"