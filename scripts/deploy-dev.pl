#!/usr/bin/env perl
# ABOUTME: Per-user development environment deployment for Magnet IRC Network
# ABOUTME: Creates isolated dev environments following Fly.io per-user dev patterns

use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Getopt::Long;
use JSON::PP;

sub get_username {
    my $username = $ENV{USER} || $ENV{USERNAME} || `whoami`;
    chomp $username if $username;
    $username =~ s/[^a-z0-9\-]//gi;  # Sanitize for Fly.io app names
    return lc($username);
}

# Single-region dev configuration (US only for simplicity)
my %DEV_CONFIG = (
    'magnet-hub' => {
        config => 'servers/magnet-9rl/fly.toml',
        region => 'ord',
        description => 'Development IRC Hub',
        health_check => '/health',
        required_secrets => ['TAILSCALE_AUTHKEY', 'SERVICES_PASSWORD', 'OPER_PASSWORD'],
    },
    'magnet-services' => {
        config => 'servers/magnet-atheme/fly.toml',
        region => 'ord',
        description => 'Development IRC Services',
        health_check => '/health',
        required_secrets => ['TAILSCALE_AUTHKEY', 'SERVICES_PASSWORD'],
    },
);

sub check_prerequisites {
    print "🔍 Checking development deployment prerequisites...\n";
    
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

sub get_dev_app_name {
    my ($base_name, $username) = @_;
    return "$base_name-$username";
}

sub app_exists {
    my ($app_name) = @_;
    
    my $output = `flyctl status --app $app_name 2>&1`;
    return $? == 0;
}

sub create_dev_app {
    my ($base_name, $username, $config) = @_;
    
    my $app_name = get_dev_app_name($base_name, $username);
    
    if (app_exists($app_name)) {
        print "✅ Dev app $app_name already exists\n";
        return 1;
    }
    
    print "🏗️  Creating dev app $app_name...\n";
    
    my $create_cmd = "flyctl apps create $app_name --org magnet-irc";
    my $output = `$create_cmd 2>&1`;
    
    if ($? == 0) {
        print "✅ Created dev app $app_name\n";
        return 1;
    } else {
        print "❌ Failed to create dev app $app_name:\n$output\n";
        return 0;
    }
}

sub deploy_dev_app {
    my ($base_name, $username, $config, $remote_only) = @_;
    
    my $app_name = get_dev_app_name($base_name, $username);
    print "🚀 Deploying $app_name ($config->{description})...\n";
    
    # Construct deploy command - deploy from project root for proper build context
    my $deploy_cmd = "flyctl deploy . --config $config->{config} --app $app_name --wait-timeout 300";
    $deploy_cmd .= " --remote-only" if $remote_only;
    
    print "Running: $deploy_cmd\n";
    my $output = `$deploy_cmd 2>&1`;
    
    if ($? == 0) {
        print "✅ Successfully deployed $app_name\n";
        return 1;
    } else {
        print "❌ Failed to deploy $app_name:\n$output\n";
        return 0;
    }
}

sub verify_dev_deployment {
    my ($base_name, $username, $config) = @_;
    
    my $app_name = get_dev_app_name($base_name, $username);
    print "🔍 Verifying deployment of $app_name...\n";
    
    # Allow time for deployment to stabilize
    sleep 10;
    
    # Check app status
    my $status_output = `flyctl status --app $app_name --json 2>/dev/null`;
    if ($? != 0) {
        print "❌ Could not get status for $app_name\n";
        return 0;
    }
    
    my $status_data = eval { decode_json($status_output) };
    if (!$status_data) {
        print "❌ Could not parse status JSON for $app_name\n";
        return 0;
    }
    
    my $app_status = $status_data->{Status} || 'unknown';
    print "App status: $app_status\n";
    
    # Test health endpoint if available
    my $hostname = $status_data->{Hostname};
    if ($hostname && $hostname =~ /fly\.dev$/) {
        my $health_url = "https://$hostname$config->{health_check}";
        print "Testing health endpoint: $health_url\n";
        
        my $health_response = `curl -f -s "$health_url" 2>&1`;
        if ($? == 0) {
            print "✅ Health check passed for $app_name\n";
            return 1;
        } else {
            print "⚠️  Health check failed for $app_name\n";
            return 0;
        }
    }
    
    # If no health endpoint, just check if app is running
    if ($app_status eq 'running') {
        print "✅ $app_name is running\n";
        return 1;
    } else {
        print "⚠️  $app_name status is $app_status\n";
        return 0;
    }
}

sub list_dev_apps {
    my ($username) = @_;
    
    print "📋 Development apps for $username:\n";
    
    foreach my $base_name (sort keys %DEV_CONFIG) {
        my $app_name = get_dev_app_name($base_name, $username);
        my $config = $DEV_CONFIG{$base_name};
        
        if (app_exists($app_name)) {
            print "✅ $app_name ($config->{description})\n";
            
            # Get app URL
            my $status_output = `flyctl status --app $app_name --json 2>/dev/null`;
            if ($? == 0) {
                my $status_data = eval { decode_json($status_output) };
                if ($status_data && $status_data->{Hostname}) {
                    print "   URL: https://$status_data->{Hostname}\n";
                }
            }
        } else {
            print "❌ $app_name (not created)\n";
        }
    }
}

sub generate_dev_report {
    my ($username, $deployment_results) = @_;
    
    print "\n" . "="x50 . "\n";
    print "DEVELOPMENT DEPLOYMENT REPORT\n";
    print "="x50 . "\n";
    printf "Developer: %s\n", $username;
    printf "Date: %s\n", scalar localtime;
    print "\n";
    
    foreach my $base_name (sort keys %$deployment_results) {
        my $app_name = get_dev_app_name($base_name, $username);
        my $result = $deployment_results->{$base_name};
        my $status_icon = $result->{success} ? "✅" : "❌";
        
        printf "%s %s (%s)\n", $status_icon, $app_name, $DEV_CONFIG{$base_name}->{description};
        printf "   Region: %s\n", $DEV_CONFIG{$base_name}->{region};
        printf "   Status: %s\n", $result->{status} || 'unknown';
        
        if ($result->{health_check}) {
            printf "   Health: %s\n", $result->{health_check} ? "✅ Passed" : "❌ Failed";
        }
        print "\n";
    }
    
    print "💡 Access your development environment:\n";
    print "   flyctl ssh console --app " . get_dev_app_name('magnet-hub', $username) . "\n";
    print "   flyctl logs --app " . get_dev_app_name('magnet-hub', $username) . "\n";
}

sub main {
    my $username = get_username();
    my $dry_run = 0;
    my $remote_only = 1;  # Default to remote builds
    my $list_only = 0;
    my $help = 0;
    
    GetOptions(
        'user=s' => \$username,
        'dry-run' => \$dry_run,
        'local-build' => sub { $remote_only = 0 },
        'list' => \$list_only,
        'help|h' => \$help,
    ) or die "Error in command line arguments\n";
    
    if ($help) {
        print <<EOF;
Usage: $0 [options]

Deploys per-user development environment for Magnet IRC Network.

Options:
    --user USER      Specify username (default: current user)
    --dry-run        Show what would be done without making changes
    --local-build    Use local Docker builds instead of remote builders
    --list           List existing dev apps for user
    --help           Show this help message

Development Apps Created:
    magnet-hub-USER:      IRC server (single region for dev)
    magnet-services-USER: Atheme services

Examples:
    $0                    # Deploy dev environment for current user
    $0 --dry-run          # Preview deployment
    $0 --list             # List existing dev apps
    $0 --user alice       # Deploy for specific user (admin only)

Note: This creates DEVELOPMENT apps only. Production deployment
is handled automatically via GitHub Actions on push to main.
EOF
        exit 0;
    }
    
    unless ($username) {
        die "❌ Could not determine username. Use --user option.\n";
    }
    
    print "Magnet IRC Network - Development Deployment\n";
    print "=" x 45 . "\n";
    printf "Developer: %s\n\n", $username;
    
    if ($list_only) {
        list_dev_apps($username);
        exit 0;
    }
    
    # Prerequisites check
    check_prerequisites();
    
    if ($dry_run) {
        print "\n🔍 DRY RUN MODE - No changes will be made\n\n";
        
        foreach my $base_name (sort keys %DEV_CONFIG) {
            my $app_name = get_dev_app_name($base_name, $username);
            my $config = $DEV_CONFIG{$base_name};
            printf "Would deploy: %-20s (%s)\n", $app_name, $config->{description};
            printf "   Config: %s\n", $config->{config};
            printf "   Region: %s\n", $config->{region};
            print "\n";
        }
        exit 0;
    }
    
    # Create and deploy dev apps
    print "🚀 Setting up development environment...\n";
    my %deployment_results;
    
    foreach my $base_name (sort keys %DEV_CONFIG) {
        my $config = $DEV_CONFIG{$base_name};
        
        # Create app if needed
        unless (create_dev_app($base_name, $username, $config)) {
            $deployment_results{$base_name} = { success => 0 };
            next;
        }
        
        # Deploy app
        my $success = deploy_dev_app($base_name, $username, $config, $remote_only);
        $deployment_results{$base_name} = { success => $success };
        
        if ($success) {
            my $verification = verify_dev_deployment($base_name, $username, $config);
            $deployment_results{$base_name}->{health_check} = $verification;
        }
        
        print "\n";
    }
    
    # Generate final report
    generate_dev_report($username, \%deployment_results);
    
    # Exit with appropriate code
    my $failed_deployments = grep { !$_->{success} } values %deployment_results;
    if ($failed_deployments > 0) {
        print "❌ $failed_deployments deployment(s) failed\n";
        exit 1;
    } else {
        print "✅ Development environment ready!\n";
        exit 0;
    }
}

main() unless caller;