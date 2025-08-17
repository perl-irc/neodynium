#!/usr/bin/env perl
# ABOUTME: Volume provisioning automation for Magnet IRC Network
# ABOUTME: Creates persistent volumes for all components with proper sizing and region placement

use strict;
use warnings;
use Getopt::Long;

# Volume specifications for each app
my %VOLUMES = (
    'magnet-9rl' => {
        name => 'magnet_9rl_data',
        region => 'ord',
        size => 3,
        app => 'magnet-9rl'
    },
    'magnet-1eu' => {
        name => 'magnet_1eu_data', 
        region => 'ams',
        size => 3,
        app => 'magnet-1eu'
    },
    'magnet-atheme' => {
        name => 'magnet_atheme_data',
        region => 'ord', 
        size => 3,
        app => 'magnet-atheme'
    }
);

sub check_fly_cli {
    my $output = `fly version 2>&1`;
    if ($? != 0) {
        die "ERROR: Fly CLI not available. Please install fly CLI first.\n";
    }
    print "✓ Fly CLI available\n";
}

sub check_authentication {
    my $output = `fly auth whoami 2>&1`;
    if ($? != 0 || $output =~ /not logged in/i) {
        die "ERROR: Not authenticated with Fly.io. Run 'fly auth login' first.\n";
    }
    chomp $output;
    print "✓ Authenticated as: $output\n";
}

sub volume_exists {
    my ($app, $volume_name) = @_;
    
    my $output = `fly volumes list --app $app --json 2>/dev/null`;
    return 0 if $? != 0;
    
    # Simple JSON parsing for volume names
    return $output =~ /"name":\s*"$volume_name"/;
}

sub create_volume {
    my ($app, $volume_spec) = @_;
    
    my $name = $volume_spec->{name};
    my $region = $volume_spec->{region};
    my $size = $volume_spec->{size};
    
    if (volume_exists($app, $name)) {
        print "✓ Volume $name already exists for $app\n";
        return 1;
    }
    
    print "Creating volume $name for $app ($size GB in $region)...\n";
    
    my $cmd = "fly volumes create $name --region $region --size $size --app $app";
    my $output = `$cmd 2>&1`;
    
    if ($? == 0) {
        print "✓ Created volume $name for $app\n";
        return 1;
    } else {
        print "✗ Failed to create volume $name for $app:\n$output\n";
        return 0;
    }
}

sub verify_volumes {
    my $all_good = 1;
    
    print "\nVerifying volumes...\n";
    
    foreach my $app (sort keys %VOLUMES) {
        my $volume_spec = $VOLUMES{$app};
        my $name = $volume_spec->{name};
        
        if (volume_exists($app, $name)) {
            print "✓ Volume $name exists for $app\n";
        } else {
            print "✗ Volume $name missing for $app\n";
            $all_good = 0;
        }
    }
    
    return $all_good;
}

sub main {
    my $dry_run = 0;
    my $help = 0;
    my $production = 0;
    
    GetOptions(
        'dry-run' => \$dry_run,
        'production' => \$production,
        'help|h' => \$help,
    ) or die "Error in command line arguments\n";
    
    if ($help) {
        print <<EOF;
Usage: $0 [options]

Creates persistent volumes for Magnet IRC Network components.

Options:
    --dry-run      Show what would be done without making changes
    --production   Run in production mode (for CI/CD)
    --help         Show this help message

Volume Configuration:
    magnet-9rl:    3GB volume in ord (Chicago) region
    magnet-1eu:    3GB volume in ams (Amsterdam) region  
    magnet-atheme: 3GB volume in ord (Chicago) region

Prerequisites:
    - Fly CLI installed and authenticated
    - Apps must exist on Fly.io (use 'fly apps create' first)
EOF
        exit 0;
    }
    
    unless ($production) {
        print "Magnet IRC Network - Volume Provisioning\n";
        print "=" x 45 . "\n\n";
    }
    
    # Pre-flight checks
    check_fly_cli();
    check_authentication();
    
    if ($dry_run) {
        print "\nDRY RUN MODE - No volumes will be created\n\n";
        
        foreach my $app (sort keys %VOLUMES) {
            my $volume_spec = $VOLUMES{$app};
            printf "Would create: %-20s %-6s %dGB in %s\n", 
                   $volume_spec->{name}, "($app)", $volume_spec->{size}, $volume_spec->{region};
        }
        exit 0;
    }
    
    # Create volumes
    print "\nCreating volumes...\n";
    my $success_count = 0;
    my $total_count = scalar keys %VOLUMES;
    
    foreach my $app (sort keys %VOLUMES) {
        if (create_volume($app, $VOLUMES{$app})) {
            $success_count++;
        }
    }
    
    print "\n";
    
    # Verify all volumes
    if (verify_volumes()) {
        print "\n✓ All volumes created successfully!\n";
        exit 0;
    } else {
        print "\n✗ Some volumes failed to create properly\n";
        exit 1;
    }
}

main() unless caller;