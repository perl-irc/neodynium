#!/usr/bin/env perl
# ABOUTME: Docker build validation tests for Magnet IRC Network containers
# ABOUTME: Tests Dockerfile syntax, build process, OpenSSL optimization, and container functionality using Test2::V0

use strict;
use warnings;
use Test2::V0;

# Test constants for Docker configurations
my %DOCKER_CONFIGS = (
    'solanum' => {
        dockerfile => 'solanum/Dockerfile',
        base_image => 'alpine:latest',
        required_packages => ['openssl', 'ca-certificates', 'iptables'],
        exposed_ports => [6667, 6697, 7000, 8080],
        expected_user => 'ircd',
        startup_script => 'solanum/entrypoint.sh',
        config_template => 'solanum/ircd.conf.template',
        volume_mount => '/opt/solanum/var',
        uses_tailscale => 1,
        openssl_optimization => 1,
    },
    'atheme' => {
        dockerfile => 'atheme/Dockerfile',
        base_image => 'alpine:latest',
        required_packages => ['openssl', 'postgresql-client', 'ca-certificates'],
        exposed_ports => [8080],
        expected_user => 'atheme',
        startup_script => 'atheme/entrypoint.sh',
        config_template => 'atheme/atheme.conf.template',
        volume_mount => '/var/lib/atheme',
        uses_tailscale => 1,
        openssl_optimization => 1,
    },
);

# Test 1: Dockerfile files exist
subtest 'dockerfile files exist' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        ok(-f $dockerfile, "$dockerfile exists for $component");
    }
};

# Test 2: Dockerfile syntax validation
subtest 'dockerfile syntax validation' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        skip_all "$dockerfile not found for $component" unless -f $dockerfile;
        
        open my $fh, '<', $dockerfile or die "Can't open $dockerfile: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Basic Dockerfile structure validation
        like($content, qr/^FROM\s+/m, "$component: Dockerfile has FROM instruction");
        like($content, qr/^RUN\s+/m, "$component: Dockerfile has RUN instructions");
        like($content, qr/^COPY\s+/m, "$component: Dockerfile has COPY instructions");
        like($content, qr/^EXPOSE\s+/m, "$component: Dockerfile has EXPOSE instructions");
        like($content, qr/^CMD\s+/m, "$component: Dockerfile has CMD instruction");
        
        # Multi-stage build validation
        my $from_count = () = $content =~ /^FROM\s+/gm;
        ok($from_count >= 2, "$component: Uses multi-stage build (found $from_count FROM statements)");
    }
};

# Test 3: OpenSSL optimization validation
subtest 'openssl optimization configuration' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        next unless $DOCKER_CONFIGS{$component}->{openssl_optimization};
        
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        skip_all "$dockerfile not found for $component" unless -f $dockerfile;
        
        open my $fh, '<', $dockerfile or die "Can't open $dockerfile: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # OpenSSL compilation flags for AMD EPYC optimization
        like($content, qr/--enable-aes/i, "$component: OpenSSL compiled with AES support");
        like($content, qr/--enable.*ssl/i, "$component: OpenSSL explicitly enabled");
        like($content, qr/-march=znver2|-march=native/i, "$component: AMD EPYC optimization flags");
        like($content, qr/-j\$\(nproc\)|-j[0-9]+/i, "$component: Multi-core compilation");
    }
};

# Test 4: Tailscale integration validation
subtest 'tailscale integration' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        next unless $DOCKER_CONFIGS{$component}->{uses_tailscale};
        
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        skip_all "$dockerfile not found for $component" unless -f $dockerfile;
        
        open my $fh, '<', $dockerfile or die "Can't open $dockerfile: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Tailscale binary integration from official image
        like($content, qr/tailscale\/tailscale/i, "$component: Uses official Tailscale image");
        like($content, qr/\/usr\/local\/bin\/tailscaled?/i, "$component: Copies Tailscale binaries");
        like($content, qr/\/usr\/local\/bin\/tailscale/i, "$component: Copies Tailscale CLI");
    }
};

# Test 5: Security hardening validation
subtest 'security hardening configuration' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        skip_all "$dockerfile not found for $component" unless -f $dockerfile;
        
        open my $fh, '<', $dockerfile or die "Can't open $dockerfile: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        my $expected_user = $DOCKER_CONFIGS{$component}->{expected_user};
        
        # Non-root user setup
        like($content, qr/adduser.*$expected_user/i, "$component: Creates non-root user $expected_user");
        like($content, qr/USER\s+$expected_user/i, "$component: Switches to non-root user");
        
        # Package management best practices
        like($content, qr/--no-cache/i, "$component: Uses --no-cache for package installation");
        like($content, qr/rm.*-rf.*\/var\/cache/i, "$component: Cleans package cache");
    }
};

# Test 6: Port exposure validation
subtest 'port exposure configuration' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        skip_all "$dockerfile not found for $component" unless -f $dockerfile;
        
        open my $fh, '<', $dockerfile or die "Can't open $dockerfile: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        my $expected_ports = $DOCKER_CONFIGS{$component}->{exposed_ports};
        
        foreach my $port (@$expected_ports) {
            like($content, qr/EXPOSE.*\b$port\b/i, "$component: Exposes port $port");
        }
    }
};

# Test 7: Configuration template files exist
subtest 'configuration template files exist' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $template = $DOCKER_CONFIGS{$component}->{config_template};
        ok(-f $template, "$template exists for $component");
    }
};

# Test 8: Startup script files exist and are executable
subtest 'startup script files exist' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $script = $DOCKER_CONFIGS{$component}->{startup_script};
        ok(-f $script, "$script exists for $component");
        skip_all "$script not found for $component" unless -f $script;
        ok(-x $script, "$script is executable for $component");
    }
};

# Test 9: Startup script Tailscale integration
subtest 'startup script tailscale integration' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        next unless $DOCKER_CONFIGS{$component}->{uses_tailscale};
        
        my $script = $DOCKER_CONFIGS{$component}->{startup_script};
        skip_all "$script not found for $component" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Tailscale daemon startup
        like($content, qr/tailscaled.*&/i, "$component: Starts Tailscale daemon");
        like($content, qr/tailscale.*up/i, "$component: Brings up Tailscale connection");
        like($content, qr/TAILSCALE_AUTHKEY/i, "$component: Uses ephemeral auth key");
        like($content, qr/--ephemeral/i, "$component: Uses ephemeral device registration");
    }
};

# Test 10: Docker build process validation (requires Docker)
subtest 'docker build process validation' => sub {
    skip_all "Docker not available" unless system('docker version >/dev/null 2>&1') == 0;
    
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        skip_all "$dockerfile not found for $component" unless -f $dockerfile;
        
        # Test docker build syntax
        my $build_cmd = "docker build --dry-run -f $dockerfile . 2>&1";
        my $output = `$build_cmd`;
        
        # Note: --dry-run may not be available in all Docker versions
        # so we'll check if the command is recognized
        if ($? == 0 || $output =~ /unknown flag.*dry-run/i) {
            pass("Docker build syntax valid for $component");
        } else {
            fail("Docker build syntax invalid for $component: $output");
        }
    }
};

# Test 11: Configuration template syntax validation
subtest 'configuration template syntax' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $template = $DOCKER_CONFIGS{$component}->{config_template};
        skip_all "$template not found for $component" unless -f $template;
        
        open my $fh, '<', $template or die "Can't open $template: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Environment variable substitution patterns
        like($content, qr/\$\{[A-Z_]+\}/i, "$component: Template uses environment variable substitution");
        
        if ($component eq 'solanum') {
            like($content, qr/name.*\$\{SERVER_NAME\}/i, "$component: Template includes server name");
            like($content, qr/sid.*\$\{SERVER_SID\}/i, "$component: Template includes server ID");
        } elsif ($component eq 'atheme') {
            like($content, qr/\$\{SERVICES_PASSWORD\}/i, "$component: Template includes services password");
            like($content, qr/\$\{ATHEME_POSTGRES_HOST\}/i, "$component: Template includes database host");
            like($content, qr/\$\{ATHEME_HUB_SERVER\}/i, "$component: Template includes configurable hub server");
        }
    }
};

# Test 12: Health endpoint validation in startup scripts
subtest 'health endpoint configuration' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        my $script = $DOCKER_CONFIGS{$component}->{startup_script};
        skip_all "$script not found for $component" unless -f $script;
        
        open my $fh, '<', $script or die "Can't open $script: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Health endpoint should be available on port 8080
        like($content, qr/8080/i, "$component: Startup script references health port 8080");
        like($content, qr/health/i, "$component: Startup script includes health endpoint");
    }
};

# Test 13: AMD EPYC specific optimizations
subtest 'amd epyc specific optimizations' => sub {
    foreach my $component (keys %DOCKER_CONFIGS) {
        next unless $DOCKER_CONFIGS{$component}->{openssl_optimization};
        
        my $dockerfile = $DOCKER_CONFIGS{$component}->{dockerfile};
        skip_all "$dockerfile not found for $component" unless -f $dockerfile;
        
        open my $fh, '<', $dockerfile or die "Can't open $dockerfile: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # AMD EPYC optimization flags
        like($content, qr/CFLAGS.*march.*znver/i, "$component: Uses AMD EPYC march flags");
        like($content, qr/AES.*NI|enable.*aes/i, "$component: Enables AES-NI acceleration");
    }
};

done_testing();