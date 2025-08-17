#!/usr/bin/env perl
# ABOUTME: Deploy token management script for Magnet IRC Network
# ABOUTME: Automates creation and management of Fly.io deploy tokens following best practices

use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Getopt::Long;

my @APPS = qw(magnet-9rl magnet-1eu magnet-atheme);

sub check_prerequisites {
    print "🔍 Checking prerequisites...\n";
    
    # Check flyctl availability
    my $fly_version = `flyctl version 2>&1`;
    if ($? != 0) {
        die "❌ flyctl not available. Please install Fly.io CLI first.\n";
    }
    print "✅ flyctl available\n";
    
    # Check authentication
    my $auth_output = `flyctl auth whoami 2>&1`;
    if ($? != 0 || $auth_output =~ /not logged in/i) {
        die "❌ Not authenticated with Fly.io. Run 'flyctl auth login' first.\n";
    }
    chomp $auth_output;
    print "✅ Authenticated as: $auth_output\n";
    
    return 1;
}

sub app_exists {
    my ($app_name) = @_;
    
    my $output = `flyctl status --app $app_name 2>&1`;
    return $? == 0;
}

sub create_deploy_tokens {
    my ($token_name) = @_;
    $token_name ||= "GitHub Actions";
    
    print "🔑 Creating deploy tokens...\n";
    
    my @created_tokens;
    
    foreach my $app (@APPS) {
        unless (app_exists($app)) {
            print "⚠️  App $app does not exist. Please create it first.\n";
            next;
        }
        
        print "Creating deploy token for $app...\n";
        
        my $cmd = "flyctl tokens create deploy --app $app --name \"$token_name\"";
        my $output = `$cmd 2>&1`;
        
        if ($? == 0) {
            # Extract token from output
            if ($output =~ /FlyV1\s+([^\s]+)/) {
                my $token = $1;
                push @created_tokens, {
                    app => $app,
                    token => $token
                };
                print "✅ Created deploy token for $app\n";
            } else {
                print "⚠️  Could not extract token for $app\n";
            }
        } else {
            print "❌ Failed to create token for $app:\n$output\n";
        }
    }
    
    return @created_tokens;
}

sub list_existing_tokens {
    print "📋 Listing existing deploy tokens...\n";
    
    my $output = `flyctl tokens list 2>&1`;
    if ($? != 0) {
        print "❌ Could not list tokens:\n$output\n";
        return;
    }
    
    print $output;
}

sub revoke_tokens {
    my ($token_pattern) = @_;
    
    print "🗑️  Revoking tokens matching pattern: $token_pattern\n";
    
    my $list_output = `flyctl tokens list 2>&1`;
    if ($? != 0) {
        print "❌ Could not list tokens for revocation\n";
        return;
    }
    
    my @token_ids = $list_output =~ /^(\S+)\s+.*$token_pattern/gm;
    
    if (@token_ids == 0) {
        print "ℹ️  No tokens found matching pattern: $token_pattern\n";
        return;
    }
    
    foreach my $token_id (@token_ids) {
        print "Revoking token: $token_id\n";
        
        my $cmd = "flyctl tokens revoke $token_id";
        my $output = `$cmd 2>&1`;
        
        if ($? == 0) {
            print "✅ Revoked token: $token_id\n";
        } else {
            print "❌ Failed to revoke token $token_id:\n$output\n";
        }
    }
}

sub display_github_instructions {
    my (@tokens) = @_;
    
    if (@tokens == 0) {
        print "ℹ️  No tokens to configure\n";
        return;
    }
    
    print "\n" . "="x60 . "\n";
    print "GITHUB ACTIONS SETUP INSTRUCTIONS\n";
    print "="x60 . "\n\n";
    
    print "1. Go to your GitHub repository\n";
    print "2. Navigate to Settings → Secrets and variables → Actions\n";
    print "3. Create a new repository secret:\n\n";
    
    print "   Name: FLY_API_TOKEN\n";
    print "   Value: (choose one of the following)\n\n";
    
    foreach my $token_info (@tokens) {
        printf "   # For %s: %s\n", $token_info->{app}, $token_info->{token};
    }
    
    print "\n⚠️  IMPORTANT:\n";
    print "   - Use a single token that has access to all required apps\n";
    print "   - Store the token securely - it won't be shown again\n";
    print "   - Rotate tokens quarterly for security\n";
    print "   - Never commit tokens to your repository\n\n";
    
    print "4. Test the workflow by pushing to the main branch\n";
    print "5. Monitor deployment in GitHub Actions tab\n\n";
}

sub main {
    my $create = 0;
    my $list = 0;
    my $revoke_pattern = '';
    my $token_name = 'GitHub Actions';
    my $production = 0;
    my $help = 0;
    
    GetOptions(
        'create' => \$create,
        'list' => \$list,
        'revoke=s' => \$revoke_pattern,
        'name=s' => \$token_name,
        'production' => \$production,
        'help|h' => \$help,
    ) or die "Error in command line arguments\n";
    
    if ($help) {
        print <<EOF;
Usage: $0 [options]

Manages Fly.io deploy tokens for Magnet IRC Network GitHub Actions.

Options:
    --create            Create new deploy tokens for all apps
    --list              List existing deploy tokens
    --revoke PATTERN    Revoke tokens matching pattern
    --name NAME         Name for created tokens (default: "GitHub Actions")
    --production        Run in production mode (for CI/CD)
    --help              Show this help message

Examples:
    $0 --create                    # Create tokens for GitHub Actions
    $0 --list                      # Show existing tokens
    $0 --revoke "GitHub Actions"   # Revoke old GitHub Actions tokens
    $0 --create --name "CI/CD"     # Create tokens with custom name

Security Best Practices:
    - Rotate tokens quarterly
    - Use app-specific tokens when possible
    - Store tokens in GitHub Secrets, never in code
    - Revoke unused or compromised tokens immediately
EOF
        exit 0;
    }
    
    unless ($production) {
        print "Magnet IRC Network - Deploy Token Management\n";
        print "=" x 50 . "\n\n";
    }
    
    check_prerequisites();
    
    # In production mode, always create tokens without interactive output
    if ($production) {
        $create = 1;
    }
    
    if ($list) {
        list_existing_tokens();
    }
    
    if ($revoke_pattern) {
        revoke_tokens($revoke_pattern);
    }
    
    if ($create) {
        my @tokens = create_deploy_tokens($token_name);
        unless ($production) {
            display_github_instructions(@tokens);
        }
    }
    
    unless ($create || $list || $revoke_pattern) {
        print "No action specified. Use --help for options.\n";
        exit 1;
    }
}

main() unless caller;