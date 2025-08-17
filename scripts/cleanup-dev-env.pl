#!/usr/bin/env perl
# ABOUTME: Development environment cleanup for Magnet IRC Network
# ABOUTME: Safely removes per-user dev environments with confirmation prompts

use strict;
use warnings;
use utf8;
use open ':std', ':encoding(UTF-8)';
use Getopt::Long;

sub get_username {
    my $username = $ENV{USER} || $ENV{USERNAME} || `whoami`;
    chomp $username if $username;
    $username =~ s/[^a-z0-9\-]//gi;  # Sanitize for Fly.io app names
    return lc($username);
}

# Dev environment apps
my @DEV_APPS = qw(magnet-hub magnet-services);

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

sub get_dev_app_name {
    my ($base_name, $username) = @_;
    return "$base_name-$username";
}

sub app_exists {
    my ($app_name) = @_;
    
    my $output = `flyctl status --app $app_name 2>&1`;
    return $? == 0;
}

sub list_dev_apps {
    my ($username) = @_;
    
    my @existing_apps;
    
    foreach my $base_name (@DEV_APPS) {
        my $app_name = get_dev_app_name($base_name, $username);
        if (app_exists($app_name)) {
            push @existing_apps, $app_name;
        }
    }
    
    return @existing_apps;
}

sub confirm_cleanup {
    my ($username, @apps) = @_;
    
    if (@apps == 0) {
        print "ℹ️  No development apps found for $username\n";
        return 0;
    }
    
    print "⚠️  WARNING: This will permanently DELETE the following apps:\n\n";
    foreach my $app (@apps) {
        print "   🗑️  $app (including all volumes and data)\n";
    }
    print "\n";
    print "This action CANNOT be undone!\n";
    print "Type 'DELETE' to confirm: ";
    
    my $confirmation = <STDIN>;
    chomp $confirmation;
    
    return $confirmation eq 'DELETE';
}

sub cleanup_dev_app {
    my ($app_name) = @_;
    
    print "🗑️  Destroying app $app_name...\n";
    
    my $cmd = "flyctl apps destroy $app_name --yes";
    my $output = `$cmd 2>&1`;
    
    if ($? == 0) {
        print "✅ Destroyed $app_name\n";
        return 1;
    } else {
        print "❌ Failed to destroy $app_name:\n$output\n";
        return 0;
    }
}

sub main {
    my $username = get_username();
    my $force = 0;
    my $list_only = 0;
    my $help = 0;
    
    GetOptions(
        'user=s' => \$username,
        'force' => \$force,
        'list' => \$list_only,
        'help|h' => \$help,
    ) or die "Error in command line arguments\n";
    
    if ($help) {
        print <<EOF;
Usage: $0 [options]

Safely removes per-user development environments for Magnet IRC Network.

Options:
    --user USER      Specify username (default: current user)
    --force          Skip interactive confirmation (DANGEROUS!)
    --list           List apps that would be deleted (dry-run)
    --help           Show this help message

WARNING: This permanently deletes apps and all associated data including:
- Fly.io applications
- Persistent volumes 
- All stored data
- Application secrets

The cleanup cannot be undone!

Examples:
    $0                    # Interactive cleanup with confirmation
    $0 --list             # Show what would be deleted
    $0 --force            # Skip confirmation (use with caution!)
    $0 --user alice       # Cleanup specific user (admin only)

Development Apps Managed:
    magnet-hub-USER       IRC server development environment
    magnet-services-USER  Atheme services development environment
EOF
        exit 0;
    }
    
    unless ($username) {
        die "❌ Could not determine username. Use --user option.\n";
    }
    
    print "Magnet IRC Network - Development Environment Cleanup\n";
    print "=" x 55 . "\n";
    printf "Target User: %s\n\n", $username;
    
    check_prerequisites();
    
    # Find existing dev apps
    my @existing_apps = list_dev_apps($username);
    
    if ($list_only) {
        if (@existing_apps == 0) {
            print "ℹ️  No development apps found for $username\n";
        } else {
            print "Development apps that would be deleted:\n";
            foreach my $app (@existing_apps) {
                print "   🗑️  $app\n";
            }
            print "\nRun without --list to perform cleanup.\n";
        }
        exit 0;
    }
    
    # Confirm cleanup unless forced
    unless ($force) {
        unless (confirm_cleanup($username, @existing_apps)) {
            print "❌ Cleanup cancelled by user\n";
            exit 1;
        }
    }
    
    if (@existing_apps == 0) {
        exit 0;  # Nothing to do
    }
    
    # Perform cleanup
    print "\n🚀 Starting cleanup process...\n\n";
    
    my $success_count = 0;
    foreach my $app (@existing_apps) {
        if (cleanup_dev_app($app)) {
            $success_count++;
        }
        print "\n";
    }
    
    # Final report
    my $total_apps = @existing_apps;
    print "=" x 50 . "\n";
    printf "Cleanup Summary: %d/%d apps successfully removed\n", $success_count, $total_apps;
    
    if ($success_count == $total_apps) {
        print "✅ Development environment completely removed for $username\n";
        exit 0;
    } else {
        my $failed = $total_apps - $success_count;
        print "⚠️  $failed apps failed to remove. Check output above for details.\n";
        exit 1;
    }
}

main() unless caller;