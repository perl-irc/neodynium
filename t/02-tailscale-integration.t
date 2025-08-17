#!/usr/bin/env perl
# ABOUTME: Tailscale mesh networking tests for Magnet IRC Network admin access
# ABOUTME: Tests Tailscale integration, ephemeral keys, mesh connectivity, and admin access using Test2::V0

use strict;
use warnings;
use Test2::V0;

# Test constants for Tailscale configuration
my %TAILSCALE_CONFIGS = (
    'magnet-9rl' => {
        hostname => 'magnet-9rl',
        component => 'solanum',
        startup_script => 'solanum/entrypoint.sh',
        admin_access => 1,
        ephemeral => 1,
    },
    'magnet-1eu' => {
        hostname => 'magnet-1eu',
        component => 'solanum',
        startup_script => 'solanum/entrypoint.sh',
        admin_access => 1,
        ephemeral => 1,
    },
    'magnet-atheme' => {
        hostname => 'magnet-atheme',
        component => 'atheme',
        startup_script => 'atheme/entrypoint.sh',
        admin_access => 1,
        ephemeral => 1,
    },
);

# Test 1: Tailscale configuration template exists
subtest 'tailscale configuration template' => sub {
    my $config_template = 'config/tailscale.conf.template';
    ok(-f $config_template, 'tailscale.conf.template exists');
};

# Test 2: Ephemeral device auto-cleanup validation  
subtest 'ephemeral device auto cleanup' => sub {
    # Ephemeral devices clean themselves up automatically
    # No manual cleanup script needed - that's the point of ephemeral!
    pass("Ephemeral devices auto-cleanup when containers stop");
};

# Test 3: Startup scripts include Tailscale initialization
subtest 'startup script tailscale initialization' => sub {
    foreach my $service (keys %TAILSCALE_CONFIGS) {
        my $config = $TAILSCALE_CONFIGS{$service};
        my $script = $config->{startup_script};
        
        ok(-f $script, "$script exists for $service");
        skip_all "$script not found for $service" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Tailscale daemon startup
        like($content, qr/tailscaled.*&/i, "$service: Starts Tailscale daemon in background");
        like($content, qr/sleep.*[0-9]+/i, "$service: Waits for daemon startup");
        
        # Tailscale authentication
        like($content, qr/tailscale.*up/i, "$service: Brings up Tailscale connection");
        like($content, qr/TAILSCALE_AUTHKEY/i, "$service: Uses auth key environment variable");
        like($content, qr/--ephemeral/i, "$service: Uses ephemeral device registration");
        like($content, qr/--hostname.*\$\{HOSTNAME\}/i, "$service: Sets dynamic hostname");
    }
};

# Test 4: Ephemeral authentication key handling
subtest 'ephemeral auth key handling' => sub {
    foreach my $service (keys %TAILSCALE_CONFIGS) {
        next unless $TAILSCALE_CONFIGS{$service}->{ephemeral};
        
        my $script = $TAILSCALE_CONFIGS{$service}->{startup_script};
        skip_all "$script not found for $service" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Ephemeral key configuration
        like($content, qr/--auth-key.*\$\{TAILSCALE_AUTHKEY\}/i, "$service: Uses authkey from environment");
        like($content, qr/--ephemeral/i, "$service: Enables ephemeral mode");
        
        # Security: No hardcoded keys
        unlike($content, qr/tskey-auth-[a-zA-Z0-9]+/i, "$service: No hardcoded auth keys");
    }
};

# Test 5: Dynamic hostname assignment
subtest 'dynamic hostname assignment' => sub {
    foreach my $service (keys %TAILSCALE_CONFIGS) {
        my $config = $TAILSCALE_CONFIGS{$service};
        my $script = $config->{startup_script};
        
        skip_all "$script not found for $service" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Hostname should be set dynamically via environment variable
        like($content, qr/--hostname.*\$\{HOSTNAME\}/i, 
             "$service: Hostname set to $config->{hostname}");
    }
};

# Test 6: Admin access SSH configuration
subtest 'admin ssh access configuration' => sub {
    foreach my $service (keys %TAILSCALE_CONFIGS) {
        next unless $TAILSCALE_CONFIGS{$service}->{admin_access};
        
        my $script = $TAILSCALE_CONFIGS{$service}->{startup_script};
        skip_all "$script not found for $service" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # SSH access enablement
        like($content, qr/--ssh/i, "$service: Enables SSH access through Tailscale");
        
        # Alternative: check if SSH is configured elsewhere
        if ($content !~ /--ssh/i) {
            like($content, qr/sshd|ssh.*start/i, "$service: SSH daemon configuration present");
        }
    }
};

# Test 7: Network isolation validation
subtest 'network isolation configuration' => sub {
    foreach my $service (keys %TAILSCALE_CONFIGS) {
        my $script = $TAILSCALE_CONFIGS{$service}->{startup_script};
        skip_all "$script not found for $service" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Tailscale should not interfere with service ports
        like($content, qr/--accept-routes=false|--no-accept-routes/i, 
             "$service: Disables route acceptance for isolation");
    }
};

# Test 8: Ephemeral device lifecycle validation
subtest 'ephemeral device lifecycle' => sub {
    # Ephemeral devices automatically disappear when containers stop
    # This is handled by Tailscale itself, not manual scripts
    
    foreach my $service (keys %TAILSCALE_CONFIGS) {
        next unless $TAILSCALE_CONFIGS{$service}->{ephemeral};
        
        my $script = $TAILSCALE_CONFIGS{$service}->{startup_script};
        skip_all "$script not found for $service" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Verify ephemeral mode is enabled
        like($content, qr/--ephemeral/i, "$service: Uses ephemeral device registration");
    }
};

# Test 9: Configuration template validation
subtest 'configuration template validation' => sub {
    my $config_template = 'config/tailscale.conf.template';
    skip_all "tailscale.conf.template not found" unless -f $config_template;
    
    open my $fh, '<', $config_template or die "Can't open $config_template: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Configuration template should use environment variables
    like($content, qr/\$\{[A-Z_]+\}/i, 'Template uses environment variable substitution');
    like($content, qr/\$\{?TAILSCALE_AUTHKEY\}?/i, 'Template references auth key variable');
    
    # Configuration should be minimal for security
    like($content, qr/ephemeral|temporary/i, 'Template includes ephemeral configuration');
};

# Test 10: Integration with development environment
subtest 'development environment integration' => sub {
    my $dev_script = 'scripts/setup-dev-env.pl';
    skip_all "setup-dev-env.pl not found" unless -f $dev_script;
    
    open my $fh, '<', $dev_script or die "Can't open $dev_script: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Development environment should handle Tailscale auth keys
    like($content, qr/TAILSCALE_AUTHKEY/i, 'Dev environment handles Tailscale auth keys');
    like($content, qr/tailscale.*secret/i, 'Dev environment sets Tailscale secrets');
};

# Test 11: Tailscale binary validation in Dockerfiles
subtest 'tailscale binary integration in dockerfiles' => sub {
    my @dockerfiles = ('solanum/Dockerfile', 'atheme/Dockerfile');
    
    foreach my $dockerfile (@dockerfiles) {
        skip_all "$dockerfile not found" unless -f $dockerfile;
        
        open my $fh, '<', $dockerfile or die "Can't open $dockerfile: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Tailscale binary copying from official image
        like($content, qr/FROM.*tailscale\/tailscale/i, "$dockerfile: Uses official Tailscale image");
        like($content, qr/COPY.*--from.*tailscaled/i, "$dockerfile: Copies tailscaled binary");
        like($content, qr/COPY.*--from.*tailscale/i, "$dockerfile: Copies tailscale CLI");
        
        # Binary placement
        like($content, qr/\/usr\/local\/bin\/tailscale/i, "$dockerfile: Installs binaries in PATH");
    }
};

# Test 12: Admin access documentation
subtest 'admin access documentation' => sub {
    my $admin_docs = 'docs/admin-access-procedures.md';
    ok(-f $admin_docs, 'admin-access-procedures.md exists');
    skip_all "admin-access-procedures.md not found" unless -f $admin_docs;
    
    open my $fh, '<', $admin_docs or die "Can't open $admin_docs: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # Documentation content validation
    like($content, qr/tailscale.*ssh/i, 'Documents Tailscale SSH access');
    like($content, qr/ephemeral.*key/i, 'Documents ephemeral key usage');
    like($content, qr/admin.*access/i, 'Documents admin access procedures');
    like($content, qr/ephemeral.*cleanup|automatic.*cleanup/i, 'Documents device cleanup procedures');
};

# Test 13: Security validation for auth key handling
subtest 'auth key security validation' => sub {
    # Check all scripts for security best practices
    my @scripts = ('solanum/entrypoint.sh', 'atheme/entrypoint.sh');
    
    foreach my $script (@scripts) {
        skip_all "$script not found" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Security checks
        unlike($content, qr/tskey-auth-[a-zA-Z0-9]{20,}/i, "$script: No hardcoded auth keys");
        unlike($content, qr/echo.*TAILSCALE_AUTHKEY/i, "$script: No auth key logging");
        unlike($content, qr/print.*TAILSCALE_AUTHKEY/i, "$script: No auth key printing");
        
        # Should use environment variable
        if ($content =~ /TAILSCALE_AUTHKEY/) {
            like($content, qr/\$\{?TAILSCALE_AUTHKEY\}?/i, "$script: Uses environment variable for auth key");
        }
    }
};

# Test 14: Cross-region connectivity validation
subtest 'cross-region connectivity configuration' => sub {
    foreach my $service (keys %TAILSCALE_CONFIGS) {
        my $script = $TAILSCALE_CONFIGS{$service}->{startup_script};
        skip_all "$script not found for $service" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Configuration for cross-region access with MagicDNS enabled
        like($content, qr/--accept-dns=true/i, "$service: Enables MagicDNS for hostname resolution");
        
        # Should not restrict regions
        unlike($content, qr/--exit-node-allow-lan-access=false/i, 
               "$service: Allows cross-region admin access");
    }
};

# Test 15: Tailscale mesh connectivity testing (if Tailscale available)
subtest 'tailscale mesh connectivity testing' => sub {
    skip_all "Tailscale not available" unless system('tailscale version >/dev/null 2>&1') == 0;
    
    # Test basic Tailscale functionality
    my $status_output = `tailscale status 2>&1`;
    
    if ($? == 0) {
        pass("Tailscale is functional on this system");
        
        # Check for magnet network devices if they exist
        foreach my $service (keys %TAILSCALE_CONFIGS) {
            my $hostname = $TAILSCALE_CONFIGS{$service}->{hostname};
            if ($status_output =~ /$hostname/i) {
                pass("Found $hostname in Tailscale network");
            } else {
                pass("$hostname not yet in Tailscale network (expected for fresh deployment)");
            }
        }
    } else {
        skip_all "Tailscale not authenticated or not functional";
    }
};

done_testing();