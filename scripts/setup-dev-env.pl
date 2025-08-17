#!/usr/bin/env perl
# ABOUTME: Development environment setup for Magnet IRC Network
# ABOUTME: Manages per-user dev environments with volume provisioning and secrets

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;

sub get_username {
    my $username = $ENV{USER} || $ENV{USERNAME} || `whoami`;
    chomp $username if $username;
    $username =~ s/[^a-z0-9\-]//gi;  # Sanitize for Fly.io app names
    return lc($username);
}

# Dev environment apps (simplified single-region)
my @DEV_APPS = qw(magnet-hub magnet-services);

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

sub get_dev_app_name {
    my ($base_name, $username) = @_;
    return "$base_name-$username";
}

sub app_exists {
    my ($app_name) = @_;
    
    my $output = `flyctl status --app $app_name 2>&1`;
    return $? == 0;
}

sub volume_exists {
    my ($app_name, $volume_name) = @_;
    
    my $output = `flyctl volumes list --app $app_name --json 2>/dev/null`;
    return 0 if $? != 0;
    
    # Simple JSON parsing for volume names
    return $output =~ /"name":\s*"$volume_name"/;
}

sub create_dev_app {
    my ($base_name, $username) = @_;
    
    my $app_name = get_dev_app_name($base_name, $username);
    
    if (app_exists($app_name)) {
        print "✅ Dev app $app_name already exists\n";
        return 1;
    }
    
    print "🏗️  Creating dev app $app_name...\n";
    
    my $create_cmd = "flyctl apps create $app_name --org personal";
    my $output = `$create_cmd 2>&1`;
    
    if ($? == 0) {
        print "✅ Created dev app $app_name\n";
        return 1;
    } else {
        print "❌ Failed to create dev app $app_name:\n$output\n";
        return 0;
    }
}

sub create_dev_volume {
    my ($base_name, $username) = @_;
    
    my $app_name = get_dev_app_name($base_name, $username);
    # Create shorter volume name (max 30 chars, only lowercase alphanumeric and underscores)
    my $short_base = $base_name;
    $short_base =~ s/magnet-//;  # Remove magnet- prefix to save space
    my $volume_name = "${short_base}_${username}_vol";
    
    # Ensure volume name is under 30 characters
    if (length($volume_name) > 30) {
        $volume_name = substr($volume_name, 0, 30);
    }
    
    if (volume_exists($app_name, $volume_name)) {
        print "✅ Volume $volume_name already exists for $app_name\n";
        return 1;
    }
    
    print "📦 Creating volume $volume_name for $app_name...\n";
    
    my $cmd = "flyctl volumes create $volume_name --region ord --size 1 --app $app_name --yes";
    my $output = `$cmd 2>&1`;
    
    if ($? == 0) {
        print "✅ Created volume $volume_name for $app_name\n";
        return 1;
    } else {
        print "❌ Failed to create volume $volume_name for $app_name:\n$output\n";
        return 0;
    }
}

sub setup_dev_secrets {
    my ($base_name, $username) = @_;
    
    my $app_name = get_dev_app_name($base_name, $username);
    
    print "🔐 Setting up development secrets for $app_name...\n";
    
    # Generate development-specific secrets
    my $tailscale_key = "tskey-auth-DEV-PLACEHOLDER";  # User must replace
    my $services_pass = generate_password(24);
    my $oper_pass = generate_password(24);
    
    my @secret_commands = (
        "flyctl secrets set TAILSCALE_AUTHKEY='$tailscale_key' --app $app_name",
        "flyctl secrets set SERVICES_PASSWORD='$services_pass' --app $app_name",
        "flyctl secrets set OPER_PASSWORD='$oper_pass' --app $app_name",
    );
    
    my $success_count = 0;
    foreach my $cmd (@secret_commands) {
        my $output = `$cmd 2>&1`;
        if ($? == 0) {
            $success_count++;
        } else {
            print "⚠️  Failed to set secret: $output\n";
        }
    }
    
    if ($success_count == @secret_commands) {
        print "✅ Development secrets configured for $app_name\n";
        
        if ($tailscale_key =~ /PLACEHOLDER/) {
            print "⚠️  Remember to update TAILSCALE_AUTHKEY with a real ephemeral key\n";
        }
        
        return 1;
    } else {
        print "❌ Some secrets failed to configure for $app_name\n";
        return 0;
    }
}

sub generate_password {
    my ($length) = @_;
    my @chars = ('a'..'z', 'A'..'Z', '0'..'9');
    my $password = '';
    for (1..$length) {
        $password .= $chars[rand @chars];
    }
    return $password;
}

sub list_dev_environment {
    my ($username) = @_;
    
    print "\n📋 Development Environment Status for $username:\n";
    print "=" x 50 . "\n";
    
    foreach my $base_name (@DEV_APPS) {
        my $app_name = get_dev_app_name($base_name, $username);
        # Create shorter volume name (max 30 chars, only lowercase alphanumeric and underscores)
    my $short_base = $base_name;
    $short_base =~ s/magnet-//;  # Remove magnet- prefix to save space
    my $volume_name = "${short_base}_${username}_vol";
    
    # Ensure volume name is under 30 characters
    if (length($volume_name) > 30) {
        $volume_name = substr($volume_name, 0, 30);
    }
        
        printf "App: %-20s ", $app_name;
        if (app_exists($app_name)) {
            print "✅ Created";
            
            # Check volume
            if (volume_exists($app_name, $volume_name)) {
                print " | Volume: ✅";
            } else {
                print " | Volume: ❌";
            }
            
            # Get URL if available
            my $status_output = `flyctl status --app $app_name --json 2>/dev/null`;
            if ($? == 0) {
                my $status_data = eval { decode_json($status_output) };
                if ($status_data && $status_data->{Hostname}) {
                    print " | URL: https://$status_data->{Hostname}";
                }
            }
            print "\n";
        } else {
            print "❌ Not created\n";
        }
    }
    
    print "\nNext steps:\n";
    print "1. Update Tailscale auth keys: flyctl secrets set TAILSCALE_AUTHKEY=<real-key> --app <app-name>\n";
    print "2. Deploy your environment: scripts/deploy-dev.pl\n";
    print "3. Access via: flyctl ssh console --app " . get_dev_app_name('magnet-hub', $username) . "\n";
}

sub cleanup_dev_environment {
    my ($username, $confirm) = @_;
    
    unless ($confirm) {
        print "⚠️  This will DELETE all development apps and volumes for $username!\n";
        print "Use --confirm to proceed with cleanup.\n";
        return 0;
    }
    
    print "🗑️  Cleaning up development environment for $username...\n";
    
    my $cleanup_count = 0;
    foreach my $base_name (@DEV_APPS) {
        my $app_name = get_dev_app_name($base_name, $username);
        
        if (app_exists($app_name)) {
            print "Destroying app $app_name...\n";
            
            my $cmd = "flyctl apps destroy $app_name --yes";
            my $output = `$cmd 2>&1`;
            
            if ($? == 0) {
                print "✅ Destroyed $app_name\n";
                $cleanup_count++;
            } else {
                print "❌ Failed to destroy $app_name:\n$output\n";
            }
        }
    }
    
    print "\n✅ Cleanup complete: $cleanup_count apps destroyed\n";
    return 1;
}

sub main {
    my $username = get_username();
    my $list_only = 0;
    my $cleanup = 0;
    my $confirm = 0;
    my $help = 0;
    
    GetOptions(
        'user=s' => \$username,
        'list' => \$list_only,
        'cleanup' => \$cleanup,
        'confirm' => \$confirm,
        'help|h' => \$help,
    ) or die "Error in command line arguments\n";
    
    if ($help) {
        print <<EOF;
Usage: $0 [options]

Sets up per-user development environment for Magnet IRC Network.

Options:
    --user USER      Specify username (default: current user)
    --list           List existing dev environment status
    --cleanup        Remove all dev apps and volumes (destructive!)
    --confirm        Confirm destructive operations
    --help           Show this help message

Operations:
    Default:         Create dev apps, volumes, and secrets
    --list:          Show current dev environment status
    --cleanup:       Destroy all dev apps (requires --confirm)

Development Environment:
    magnet-hub-USER:      IRC server (ord region, 1GB volume)
    magnet-services-USER: Atheme services (ord region, 1GB volume)

Examples:
    $0                    # Set up dev environment for current user
    $0 --list             # Show current status
    $0 --cleanup --confirm # Destroy dev environment (DESTRUCTIVE!)

Security: Development secrets are auto-generated. Update TAILSCALE_AUTHKEY
manually with a real ephemeral key from the Tailscale admin console.
EOF
        exit 0;
    }
    
    unless ($username) {
        die "❌ Could not determine username. Use --user option.\n";
    }
    
    print "Magnet IRC Network - Development Environment Setup\n";
    print "=" x 50 . "\n";
    printf "Developer: %s\n\n", $username;
    
    if ($list_only) {
        list_dev_environment($username);
        exit 0;
    }
    
    if ($cleanup) {
        exit cleanup_dev_environment($username, $confirm) ? 0 : 1;
    }
    
    # Default: Set up dev environment
    check_prerequisites();
    
    print "🚀 Setting up development environment...\n\n";
    
    my $total_success = 1;
    
    foreach my $base_name (@DEV_APPS) {
        print "Setting up $base_name environment...\n";
        
        # Create app
        unless (create_dev_app($base_name, $username)) {
            $total_success = 0;
            next;
        }
        
        # Create volume
        unless (create_dev_volume($base_name, $username)) {
            $total_success = 0;
        }
        
        # Setup secrets
        unless (setup_dev_secrets($base_name, $username)) {
            $total_success = 0;
        }
        
        print "\n";
    }
    
    if ($total_success) {
        print "✅ Development environment setup complete!\n\n";
        list_dev_environment($username);
    } else {
        print "❌ Some setup steps failed. Check output above.\n";
        exit 1;
    }
}

main() unless caller;