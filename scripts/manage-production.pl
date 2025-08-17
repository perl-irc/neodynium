#!/usr/bin/env perl
# ABOUTME: Production machine management for Magnet IRC Network
# ABOUTME: Start, stop, restart, and destroy production infrastructure with safety checks

use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Getopt::Long;

# Production applications (magnet-postgres removed - atheme uses opensex backend)
my @PRODUCTION_APPS = qw(magnet-9rl magnet-1eu magnet-atheme);

sub check_prerequisites {
    print "🔍 Checking prerequisites...\n";
    
    # Check flyctl availability
    my $fly_version = `flyctl version 2>&1`;
    if ($? != 0) {
        die "❌ flyctl not available. Please install Fly.io CLI first.\n";
    }
    
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

sub get_app_status {
    my ($app_name) = @_;
    
    unless (app_exists($app_name)) {
        return "NOT_FOUND";
    }
    
    my $output = `flyctl status --app $app_name 2>&1`;
    if ($? != 0) {
        return "ERROR";
    }
    
    # Parse status from output
    if ($output =~ /Machines.*?running/is) {
        return "RUNNING";
    } elsif ($output =~ /Machines.*?stopped/is) {
        return "STOPPED";
    } elsif ($output =~ /No machines/is) {
        return "NO_MACHINES";
    } else {
        return "UNKNOWN";
    }
}

sub list_production_status {
    print "Production Infrastructure Status:\n";
    print "=" x 40 . "\n";
    
    foreach my $app (@PRODUCTION_APPS) {
        my $status = get_app_status($app);
        my $emoji = $status eq "RUNNING" ? "🟢" : 
                   $status eq "STOPPED" ? "🟡" : 
                   $status eq "NOT_FOUND" ? "❌" : "❓";
        
        printf "%-20s %s %s\n", $app, $emoji, $status;
    }
    print "\n";
}

sub stop_machines {
    my (@apps) = @_;
    @apps = @PRODUCTION_APPS unless @apps;
    
    print "🛑 Stopping machines...\n";
    
    my $success_count = 0;
    foreach my $app (@apps) {
        unless (app_exists($app)) {
            print "⚠️  App $app does not exist, skipping\n";
            next;
        }
        
        print "Stopping machines for $app...\n";
        my $cmd = "flyctl machine stop --app $app";
        my $output = `$cmd 2>&1`;
        
        if ($? == 0) {
            print "✅ Stopped machines for $app\n";
            $success_count++;
        } else {
            print "❌ Failed to stop machines for $app:\n$output\n";
        }
    }
    
    return $success_count;
}

sub start_machines {
    my (@apps) = @_;
    @apps = @PRODUCTION_APPS unless @apps;
    
    print "🚀 Starting machines...\n";
    
    my $success_count = 0;
    foreach my $app (@apps) {
        unless (app_exists($app)) {
            print "⚠️  App $app does not exist, skipping\n";
            next;
        }
        
        print "Starting machines for $app...\n";
        my $cmd = "flyctl machine start --app $app";
        my $output = `$cmd 2>&1`;
        
        if ($? == 0) {
            print "✅ Started machines for $app\n";
            $success_count++;
        } else {
            print "❌ Failed to start machines for $app:\n$output\n";
        }
    }
    
    return $success_count;
}

sub restart_machines {
    my (@apps) = @_;
    @apps = @PRODUCTION_APPS unless @apps;
    
    print "🔄 Restarting machines...\n";
    
    my $success_count = 0;
    foreach my $app (@apps) {
        unless (app_exists($app)) {
            print "⚠️  App $app does not exist, skipping\n";
            next;
        }
        
        print "Restarting machines for $app...\n";
        my $cmd = "flyctl machine restart --app $app";
        my $output = `$cmd 2>&1`;
        
        if ($? == 0) {
            print "✅ Restarted machines for $app\n";
            $success_count++;
        } else {
            print "❌ Failed to restart machines for $app:\n$output\n";
        }
    }
    
    return $success_count;
}

sub confirm_destruction {
    my (@apps) = @_;
    
    print "⚠️  DANGER: This will permanently DELETE the following production apps:\n\n";
    foreach my $app (@apps) {
        print "   💥 $app (including ALL data, volumes, and configurations)\n";
    }
    print "\n";
    print "🚨 THIS WILL DESTROY THE ENTIRE MAGNET IRC NETWORK!\n";
    print "🚨 ALL USER DATA, CHANNELS, AND SERVICES WILL BE LOST!\n";
    print "🚨 THIS ACTION CANNOT BE UNDONE!\n\n";
    print "Type 'BURN IT ALL DOWN' to confirm: ";
    
    my $confirmation = <STDIN>;
    chomp $confirmation;
    
    return $confirmation eq 'BURN IT ALL DOWN';
}

sub destroy_production {
    my (@apps) = @_;
    @apps = @PRODUCTION_APPS unless @apps;
    
    # Filter to only existing apps
    my @existing_apps = grep { app_exists($_) } @apps;
    
    if (@existing_apps == 0) {
        print "ℹ️  No production apps found to destroy\n";
        return 0;
    }
    
    unless (confirm_destruction(@existing_apps)) {
        print "❌ Destruction cancelled by user\n";
        return 0;
    }
    
    print "\n💥 DESTROYING PRODUCTION INFRASTRUCTURE...\n\n";
    
    my $success_count = 0;
    foreach my $app (@existing_apps) {
        print "Destroying $app...\n";
        my $cmd = "flyctl apps destroy $app --yes";
        my $output = `$cmd 2>&1`;
        
        if ($? == 0) {
            print "✅ Destroyed $app\n";
            $success_count++;
        } else {
            print "❌ Failed to destroy $app:\n$output\n";
        }
        print "\n";
    }
    
    print "=" x 50 . "\n";
    printf "Destruction Summary: %d/%d apps destroyed\n", $success_count, scalar(@existing_apps);
    
    return $success_count;
}

sub main {
    my $action = '';
    my $apps_arg = '';
    my $list = 0;
    my $help = 0;
    
    GetOptions(
        'action=s' => \$action,
        'apps=s' => \$apps_arg,
        'list' => \$list,
        'help|h' => \$help,
    ) or die "Error in command line arguments\n";
    
    if ($help) {
        print <<EOF;
Usage: $0 --action ACTION [options]

Manages Magnet IRC Network production infrastructure machines.

Actions:
    start        Start machines for specified apps
    stop         Stop machines for specified apps  
    restart      Restart machines for specified apps
    destroy      Permanently destroy apps and all data
    status       Show current status of all apps

Options:
    --apps LIST  Comma-separated list of apps (default: all production apps)
    --list       Same as --action status
    --help       Show this help message

Production Apps:
    magnet-9rl       US Hub IRC server
    magnet-1eu       EU IRC server
    magnet-atheme    IRC services (uses opensex flat file backend)

Examples:
    $0 --action status                    # Show status of all apps
    $0 --action stop                      # Stop all machines
    $0 --action start --apps magnet-9rl   # Start only US hub
    $0 --action restart                   # Restart all machines
    $0 --action destroy                   # DESTROY EVERYTHING (requires confirmation)

⚠️  WARNING: 
- The 'destroy' action permanently deletes apps and ALL data
- This includes user accounts, channels, and network history  
- Use with extreme caution in production environments
EOF
        exit 0;
    }
    
    if ($list) {
        $action = 'status';
    }
    
    unless ($action) {
        die "❌ No action specified. Use --action or --help for usage.\n";
    }
    
    # Parse apps argument
    my @target_apps;
    if ($apps_arg) {
        @target_apps = split /,/, $apps_arg;
        @target_apps = map { s/^\s+|\s+$//g; $_ } @target_apps;  # trim
        
        # Validate app names
        foreach my $app (@target_apps) {
            unless (grep { $_ eq $app } @PRODUCTION_APPS) {
                die "❌ Invalid app name: $app\n";
            }
        }
    } else {
        @target_apps = @PRODUCTION_APPS;
    }
    
    print "Magnet IRC Network - Production Management\n";
    print "=" x 45 . "\n\n";
    
    check_prerequisites();
    print "\n";
    
    if ($action eq 'status') {
        list_production_status();
    } elsif ($action eq 'start') {
        start_machines(@target_apps);
    } elsif ($action eq 'stop') {
        stop_machines(@target_apps);
    } elsif ($action eq 'restart') {
        restart_machines(@target_apps);
    } elsif ($action eq 'destroy') {
        destroy_production(@target_apps);
    } else {
        die "❌ Unknown action: $action\n";
    }
}

main() unless caller;