#!/usr/bin/env perl
# ABOUTME: Infrastructure validation tests for Magnet IRC Network Fly.io deployment
# ABOUTME: Tests fly.toml configurations, volume specs, and deployment readiness

use strict;
use warnings;
use Test::More;

# Test constants
my %EXPECTED_APPS = (
    'magnet-9rl' => {
        region => 'ord',
        memory => '1gb',
        cpus => 1,
        volume_size => 3,
        ports => [6667, 6697, 7000, 8080],
    },
    'magnet-1eu' => {
        region => 'ams',
        memory => '1gb',
        cpus => 1,
        volume_size => 3,
        ports => [6667, 6697, 7000, 8080],
    },
    'magnet-atheme' => {
        region => 'ord',
        memory => '2gb',
        cpus => 2,
        volume_size => 3,
        ports => [8080],
    },
);

# Test 1: Verify fly.toml files exist
subtest 'fly.toml files exist' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "apps/$app/fly.toml";
        ok(-f $fly_toml_path, "fly.toml exists for $app");
    }
};

# Test 2: Validate fly.toml configuration structure
subtest 'fly.toml configuration validity' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "apps/$app/fly.toml";
        SKIP: {
            skip "fly.toml not found for $app", 4 unless -f $fly_toml_path;
            
            open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
            my $content = do { local $/; <$fh> };
            close $fh;
            
            # Basic validation without TOML parser
            like($content, qr/^app\s*=\s*"$app"/m, "App name matches for $app");
            like($content, qr/^primary_region\s*=\s*"$EXPECTED_APPS{$app}->{region}"/m, 
                 "Primary region correct for $app");
            like($content, qr/\[vm\]/m, "VM configuration exists for $app");
            like($content, qr/\[mounts\]/m, "Mount configuration exists for $app");
        }
    }
};

# Test 3: Validate resource allocation
subtest 'resource allocation' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "apps/$app/fly.toml";
        SKIP: {
            skip "fly.toml not found for $app", 2 unless -f $fly_toml_path;
            
            open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
            my $content = do { local $/; <$fh> };
            close $fh;
            
            like($content, qr/memory\s*=\s*"$EXPECTED_APPS{$app}->{memory}"/m, 
                 "Memory allocation correct for $app");
            like($content, qr/cpus\s*=\s*$EXPECTED_APPS{$app}->{cpus}/m, 
                 "CPU allocation correct for $app");
        }
    }
};

# Test 4: Validate volume configuration
subtest 'volume configuration' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "apps/$app/fly.toml";
        SKIP: {
            skip "fly.toml not found for $app", 2 unless -f $fly_toml_path;
            
            open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
            my $content = do { local $/; <$fh> };
            close $fh;
            
            like($content, qr/source\s*=/m, "Volume source defined for $app");
            like($content, qr/destination\s*=/m, "Volume destination defined for $app");
        }
    }
};

# Test 5: Validate health check configuration
subtest 'health check endpoints' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "apps/$app/fly.toml";
        SKIP: {
            skip "fly.toml not found for $app", 3 unless -f $fly_toml_path;
            
            open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
            my $content = do { local $/; <$fh> };
            close $fh;
            
            like($content, qr/\[http_service\]/m, "HTTP service defined for $app");
            like($content, qr/internal_port\s*=\s*8080/m, 
                 "Health check port is 8080 for $app");
            like($content, qr/path\s*=\s*"\/health"/m, "Health check path is /health for $app");
        }
    }
};

# Test 6: Validate service ports
subtest 'service ports configuration' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "apps/$app/fly.toml";
        SKIP: {
            skip "fly.toml not found for $app", 1 unless -f $fly_toml_path;
            
            open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
            my $content = do { local $/; <$fh> };
            close $fh;
            
            if ($app eq 'magnet-9rl' || $app eq 'magnet-1eu') {
                # IRC servers need additional service ports
                like($content, qr/\[\[services\]\]/m, "Services section exists for IRC server $app");
            } else {
                pass("Service ports check for $app");
            }
        }
    }
};

# Test 7: Volume creation script exists and is executable
subtest 'volume creation script' => sub {
    my $script_path = 'scripts/create-volumes.pl';
    ok(-f $script_path, 'create-volumes.pl exists');
    SKIP: {
        skip "create-volumes.pl not found", 1 unless -f $script_path;
        ok(-x $script_path, 'create-volumes.pl is executable');
    }
};

# Test 8: Documentation exists
subtest 'deployment documentation' => sub {
    my $doc_path = 'docs/deployment-prerequisites.md';
    ok(-f $doc_path, 'deployment-prerequisites.md exists');
    SKIP: {
        skip "deployment-prerequisites.md not found", 3 unless -f $doc_path;
        
        open my $fh, '<', $doc_path or die "Can't open $doc_path: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        like($content, qr/Fly\.io CLI/i, 'Documents Fly.io CLI requirements');
        like($content, qr/Authentication/i, 'Documents authentication setup');
        like($content, qr/Rollback/i, 'Documents rollback procedures');
    }
};

# Test 9: Verify Fly.io app deployment (requires fly CLI)
subtest 'fly.io app deployment validation' => sub {
    SKIP: {
        skip "Fly CLI not available or not authenticated", 3 
            unless system('fly version >/dev/null 2>&1') == 0;
        
        foreach my $app (keys %EXPECTED_APPS) {
            my $cmd = "fly status --app $app 2>&1";
            my $output = `$cmd`;
            
            if ($? == 0 && $output !~ /Error/) {
                pass("App $app is deployed on Fly.io");
            } else {
                fail("App $app is not yet deployed on Fly.io");
            }
        }
    }
};

# Test 10: Verify volume attachments
subtest 'volume attachments' => sub {
    SKIP: {
        skip "Fly CLI not available or not authenticated", 3 
            unless system('fly version >/dev/null 2>&1') == 0;
        
        foreach my $app (keys %EXPECTED_APPS) {
            my $cmd = "fly volumes list --app $app 2>&1";
            my $output = `$cmd`;
            
            if ($? == 0 && $output !~ /Error/) {
                like($output, qr/3gb/i, "Volume size correct for $app");
            } else {
                fail("Volumes not yet created for $app");
            }
        }
    }
};

done_testing();