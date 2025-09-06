#!/bin/bash
# ABOUTME: Remove Tailscale auth keys from git repository history using git-filter-repo
# ABOUTME: Modern, safe approach to scrub sensitive data from all commits

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

# Create expressions file for git-filter-repo
cat > /tmp/secret-expressions.txt << 'EOF'
# Replace all Tailscale auth keys with placeholder
regex:tskey-auth-k[A-Za-z0-9_-]*==><TAILSCALE_AUTH_KEY>
EOF

echo "Removing Tailscale auth keys from repository history using git-filter-repo..."
git filter-repo --replace-text /tmp/secret-expressions.txt --force

# Clean up temp file
rm -f /tmp/secret-expressions.txt

echo "Git history has been rewritten!"
echo "All Tailscale auth keys have been replaced with <TAILSCALE_AUTH_KEY>"
echo ""
echo "Verification:"
git log --all --oneline | head -5
echo ""
echo "Next steps:"
echo "1. Verify the keys are gone: git log --all -S 'tskey-auth-k' --source --all"
echo "2. Add origin remote back: git remote add origin <your-repo-url>"
echo "3. Force push to remote: git push --force-with-lease --all"
echo "4. IMMEDIATELY revoke the exposed keys in Tailscale admin panel"
echo "5. Generate new auth keys"
echo "6. Update deployment scripts with new keys from environment variables"
echo ""
echo "Backup branch created: backup-before-secret-cleanup"