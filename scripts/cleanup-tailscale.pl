#!/usr/bin/env perl
# ABOUTME: Tailscale device cleanup automation for ephemeral container management
# ABOUTME: Removes devices from Tailscale network when containers terminate using Tailscale API

use strict;
use warnings;
use File::Slurp qw(read_file write_file);
use JSON::PP;

sub main {
    my $action = shift @ARGV || 'help';
    
    if ($action eq 'logout') {
        logout_device();
    } elsif ($action eq 'cleanup') {
        cleanup_ephemeral_devices();
    } elsif ($action eq 'status') {
        show_status();
    } else {
        show_help();
    }
}

sub logout_device {
    print "Logging out Tailscale device...\n";
    
    eval {
        # Logout from current device
        system('/usr/local/bin/tailscale logout');
        if ($? != 0) {
            die "Failed to logout from Tailscale: $!";
        }
        
        # Stop tailscale daemon gracefully
        system('pkill -TERM tailscaled');
        
        print "Device logged out successfully\n";
    };
    
    if ($@) {
        print STDERR "Error during logout: $@\n";
        exit 1;
    }
}

sub cleanup_ephemeral_devices {
    print "Cleaning up ephemeral Tailscale devices...\n";
    
    eval {
        # Get current device status
        my $status_output = `tailscale status --json 2>/dev/null`;
        
        if ($? == 0 && $status_output) {
            my $status = decode_json($status_output);
            my $self_id = $status->{Self}->{ID};
            
            if ($self_id) {
                print "Current device ID: $self_id\n";
                
                # Check if this is an ephemeral device (magnet-* hostname)
                my $hostname = $status->{Self}->{HostName} || '';
                if ($hostname =~ /^magnet-/) {
                    print "Ephemeral magnet device detected: $hostname\n";
                    logout_device();
                } else {
                    print "Non-ephemeral device, skipping cleanup\n";
                }
            }
        } else {
            print "Tailscale not active or accessible, skipping cleanup\n";
        }
    };
    
    if ($@) {
        print STDERR "Error during cleanup: $@\n";
        exit 1;
    }
}

sub show_status {
    print "Tailscale device status:\n";
    
    eval {
        # Show current status
        system('/usr/local/bin/tailscale status');
        
        if ($? != 0) {
            print "Tailscale not running or not authenticated\n";
        }
    };
    
    if ($@) {
        print STDERR "Error checking status: $@\n";
        exit 1;
    }
}

sub show_help {
    print <<'EOF';
cleanup-tailscale.pl - Tailscale device cleanup automation

Usage:
    cleanup-tailscale.pl logout     - Logout current device and stop daemon
    cleanup-tailscale.pl cleanup    - Cleanup ephemeral magnet devices  
    cleanup-tailscale.pl status     - Show current Tailscale status
    cleanup-tailscale.pl help       - Show this help message

This script handles automatic cleanup of Tailscale devices when
IRC network containers terminate. Ephemeral devices with magnet-*
hostnames are automatically removed from the Tailscale network.

Examples:
    # Cleanup on container shutdown
    cleanup-tailscale.pl cleanup
    
    # Force logout
    cleanup-tailscale.pl logout
    
    # Check current status
    cleanup-tailscale.pl status

EOF
}

# Error handling for signals
$SIG{INT} = $SIG{TERM} = sub {
    print "\nReceived termination signal, cleaning up...\n";
    logout_device();
    exit 0;
};

# Run main function
main() if !caller;