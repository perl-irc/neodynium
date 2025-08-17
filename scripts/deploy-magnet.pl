#!/usr/bin/env perl
# ABOUTME: Comprehensive deployment automation for Magnet IRC Network
# ABOUTME: Implements Fly.io best practices for multi-app infrastructure deployment

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;

# Application deployment configuration
my %DEPLOY_CONFIG = (
    'magnet-9rl' => {
        config => 'servers/magnet-9rl/fly.toml',
        region => 'ord',
        description => 'US Hub IRC Server',
        health_check => '/health',
        required_secrets => ['TAILSCALE_AUTHKEY', 'SERVICES_PASSWORD', 'LINK_PASSWORD_9RL_1EU', 'OPER_PASSWORD'],
    },
    'magnet-1eu' => {
        config => 'servers/magnet-1eu/fly.toml',
        region => 'ams', 
        description => 'EU IRC Server',
        health_check => '/health',
        required_secrets => ['TAILSCALE_AUTHKEY', 'SERVICES_PASSWORD', 'LINK_PASSWORD_9RL_1EU', 'OPER_PASSWORD'],
    },
    'magnet-atheme' => {
        config => 'servers/magnet-atheme/fly.toml',
        region => 'ord',
        description => 'Atheme IRC Services',
        health_check => '/health',
        required_secrets => ['TAILSCALE_AUTHKEY', 'SERVICES_PASSWORD'],
    },
);

sub check_prerequisites {
    print "🔍 Checking deployment prerequisites...\n";
    
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
    
    # Check configuration files exist
    foreach my $app (keys %DEPLOY_CONFIG) {
        my $config_path = $DEPLOY_CONFIG{$app}->{config};
        unless (-f $config_path) {
            die "❌ Configuration file missing: $config_path\n";
        }
    }
    print "✅ All configuration files present\n";
    
    return 1;
}

sub app_exists {
    my ($app_name) = @_;
    
    my $output = `flyctl status --app $app_name 2>&1`;
    return $? == 0;
}

sub verify_secrets {
    my ($app_name) = @_;
    
    print "🔐 Verifying secrets for $app_name...\n";
    
    my $secrets_output = `flyctl secrets list --app $app_name 2>/dev/null`;
    if ($? != 0) {
        print "⚠️  Could not verify secrets for $app_name\n";
        return 0;
    }
    
    my $missing_secrets = 0;
    foreach my $secret (@{$DEPLOY_CONFIG{$app_name}->{required_secrets}}) {
        unless ($secrets_output =~ /^$secret\s+/m) {
            print "⚠️  Missing secret: $secret for $app_name\n";
            $missing_secrets++;
        }
    }
    
    if ($missing_secrets == 0) {
        print "✅ All required secrets configured for $app_name\n";
        return 1;
    } else {
        print "❌ $missing_secrets missing secrets for $app_name\n";
        return 0;
    }
}

sub deploy_app {
    my ($app_name, $remote_only) = @_;
    
    my $config = $DEPLOY_CONFIG{$app_name};
    print "🚀 Deploying $app_name ($config->{description})...\n";
    
    # Construct deploy command
    my $deploy_cmd = "flyctl deploy --config $config->{config} --app $app_name";
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

sub verify_deployment {
    my ($app_name) = @_;
    
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
        my $health_url = "https://$hostname$DEPLOY_CONFIG{$app_name}->{health_check}";
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

sub create_apps_if_needed {
    my ($organization) = @_;
    
    print "🏗️  Checking application existence...\n";
    
    foreach my $app_name (sort keys %DEPLOY_CONFIG) {
        if (app_exists($app_name)) {
            print "✅ App $app_name already exists\n";
        } else {
            print "Creating app $app_name...\n";
            
            my $create_cmd = "flyctl apps create $app_name";
            $create_cmd .= " --org $organization" if $organization;
            
            my $output = `$create_cmd 2>&1`;
            if ($? == 0) {
                print "✅ Created app $app_name\n";
            } else {
                die "❌ Failed to create app $app_name:\n$output\n";
            }
        }
    }
}

sub generate_deployment_report {
    my ($deployment_results) = @_;
    
    print "\n" . "="x50 . "\n";
    print "DEPLOYMENT REPORT\n";
    print "="x50 . "\n";
    printf "Date: %s\n", scalar localtime;
    print "\n";
    
    foreach my $app_name (sort keys %$deployment_results) {
        my $result = $deployment_results->{$app_name};
        my $status_icon = $result->{success} ? "✅" : "❌";
        
        printf "%s %s (%s)\n", $status_icon, $app_name, $DEPLOY_CONFIG{$app_name}->{description};
        printf "   Region: %s\n", $DEPLOY_CONFIG{$app_name}->{region};
        printf "   Status: %s\n", $result->{status} || 'unknown';
        
        if ($result->{health_check}) {
            printf "   Health: %s\n", $result->{health_check} ? "✅ Passed" : "❌ Failed";
        }
        print "\n";
    }
}

sub main {
    my $dry_run = 0;
    my $remote_only = 1;  # Default to remote builds per Fly.io best practices
    my $skip_secrets_check = 0;
    my $organization = '';
    my $help = 0;
    
    GetOptions(
        'dry-run' => \$dry_run,
        'local-build' => sub { $remote_only = 0 },
        'skip-secrets' => \$skip_secrets_check,
        'org=s' => \$organization,
        'help|h' => \$help,
    ) or die "Error in command line arguments\n";
    
    if ($help) {
        print <<EOF;
Usage: $0 [options]

Deploys Magnet IRC Network infrastructure to Fly.io following best practices.

Options:
    --dry-run        Show what would be done without making changes
    --local-build    Use local Docker builds instead of remote builders
    --skip-secrets   Skip secrets verification (not recommended)
    --org ORG        Specify organization for app creation
    --help           Show this help message

Applications Deployed:
    magnet-9rl:    US Hub IRC server (Chicago)
    magnet-1eu:    EU IRC server (Amsterdam)  
    magnet-atheme: Atheme services (Chicago)

Prerequisites:
    - Fly.io CLI installed and authenticated
    - All configuration files present in servers/ directory
    - Required secrets configured for each application

Examples:
    $0                    # Full deployment with remote builds
    $0 --dry-run          # Preview deployment without changes
    $0 --local-build      # Use local Docker builds
    $0 --org my-org       # Create apps under specific organization
EOF
        exit 0;
    }
    
    print "Magnet IRC Network - Fly.io Deployment\n";
    print "=" x 45 . "\n\n";
    
    # Prerequisites check
    check_prerequisites();
    
    if ($dry_run) {
        print "\n🔍 DRY RUN MODE - No changes will be made\n\n";
        
        foreach my $app_name (sort keys %DEPLOY_CONFIG) {
            my $config = $DEPLOY_CONFIG{$app_name};
            printf "Would deploy: %-15s (%s)\n", $app_name, $config->{description};
            printf "   Config: %s\n", $config->{config};
            printf "   Region: %s\n", $config->{region};
            print "\n";
        }
        exit 0;
    }
    
    # Create apps if needed
    create_apps_if_needed($organization);
    
    # Verify secrets unless skipped
    unless ($skip_secrets_check) {
        print "\n🔐 Verifying secrets configuration...\n";
        my $secrets_ok = 1;
        
        foreach my $app_name (sort keys %DEPLOY_CONFIG) {
            unless (verify_secrets($app_name)) {
                $secrets_ok = 0;
            }
        }
        
        unless ($secrets_ok) {
            print "\n❌ Secrets verification failed. Please configure missing secrets.\n";
            print "See docs/deployment-prerequisites.md for setup instructions.\n";
            exit 1;
        }
    }
    
    # Deploy applications
    print "\n🚀 Starting deployment...\n";
    my %deployment_results;
    
    foreach my $app_name (sort keys %DEPLOY_CONFIG) {
        my $success = deploy_app($app_name, $remote_only);
        $deployment_results{$app_name} = { success => $success };
        
        if ($success) {
            my $verification = verify_deployment($app_name);
            $deployment_results{$app_name}->{health_check} = $verification;
        }
        
        print "\n";
    }
    
    # Generate final report
    generate_deployment_report(\%deployment_results);
    
    # Exit with appropriate code
    my $failed_deployments = grep { !$_->{success} } values %deployment_results;
    if ($failed_deployments > 0) {
        print "❌ $failed_deployments deployment(s) failed\n";
        exit 1;
    } else {
        print "✅ All deployments completed successfully!\n";
        exit 0;
    }
}

main() unless caller;