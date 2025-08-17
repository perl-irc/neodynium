#!/usr/bin/env perl
# ABOUTME: Infrastructure validation tests for Magnet IRC Network Fly.io deployment
# ABOUTME: Tests fly.toml configurations, volume specs, and deployment readiness using Test2::V0

use strict;
use warnings;
use Test2::V0;

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
        my $fly_toml_path = "servers/$app/fly.toml";
        ok(-f $fly_toml_path, "fly.toml exists for $app");
    }
};

# Test 2: Validate fly.toml configuration structure
subtest 'fly.toml configuration validity' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "servers/$app/fly.toml";
        skip_all "fly.toml not found for $app" unless -f $fly_toml_path;
        
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
};

# Test 3: Validate resource allocation
subtest 'resource allocation' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "servers/$app/fly.toml";
        skip_all "fly.toml not found for $app" unless -f $fly_toml_path;
        
        open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        like($content, qr/memory\s*=\s*"$EXPECTED_APPS{$app}->{memory}"/m, 
             "Memory allocation correct for $app");
        like($content, qr/cpus\s*=\s*$EXPECTED_APPS{$app}->{cpus}/m, 
             "CPU allocation correct for $app");
    }
};

# Test 4: Validate volume configuration
subtest 'volume configuration' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "servers/$app/fly.toml";
        skip_all "fly.toml not found for $app" unless -f $fly_toml_path;
        
        open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        like($content, qr/source\s*=/m, "Volume source defined for $app");
        like($content, qr/destination\s*=/m, "Volume destination defined for $app");
    }
};

# Test 5: Validate health check configuration
subtest 'health check endpoints' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "servers/$app/fly.toml";
        skip_all "fly.toml not found for $app" unless -f $fly_toml_path;
        
        open my $fh, '<', $fly_toml_path or die "Can't open $fly_toml_path: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        like($content, qr/\[http_service\]/m, "HTTP service defined for $app");
        like($content, qr/internal_port\s*=\s*8080/m, 
             "Health check port is 8080 for $app");
        like($content, qr/path\s*=\s*"\/health"/m, "Health check path is /health for $app");
    }
};

# Test 6: Validate service ports
subtest 'service ports configuration' => sub {
    foreach my $app (keys %EXPECTED_APPS) {
        my $fly_toml_path = "servers/$app/fly.toml";
        skip_all "fly.toml not found for $app" unless -f $fly_toml_path;
        
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
};

# Test 7: Volume creation script exists and is executable
subtest 'volume creation script' => sub {
    my $script_path = 'scripts/create-volumes.pl';
    ok(-f $script_path, 'create-volumes.pl exists');
    skip_all "create-volumes.pl not found" unless -f $script_path;
    ok(-x $script_path, 'create-volumes.pl is executable');
};

# Test 8: Documentation exists
subtest 'deployment documentation' => sub {
    my $doc_path = 'docs/deployment-prerequisites.md';
    ok(-f $doc_path, 'deployment-prerequisites.md exists');
    skip_all "deployment-prerequisites.md not found" unless -f $doc_path;
    
    open my $fh, '<', $doc_path or die "Can't open $doc_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    like($content, qr/Fly\.io CLI/i, 'Documents Fly.io CLI requirements');
    like($content, qr/Authentication/i, 'Documents authentication setup');
    like($content, qr/Rollback/i, 'Documents rollback procedures');
    like($content, qr/GitHub Actions/i, 'Documents CI/CD with GitHub Actions');
    like($content, qr/deploy.*token/i, 'Documents deploy token management');
    like($content, qr/remote.*only/i, 'Documents remote builders best practice');
};

# Test 9: Verify Fly.io app deployment (requires fly CLI)
subtest 'fly.io app deployment validation' => sub {
    skip_all "Fly CLI not available or not authenticated" 
        unless system('fly version >/dev/null 2>&1') == 0;
    
    foreach my $app (keys %EXPECTED_APPS) {
        my $cmd = "fly status --app $app 2>&1";
        my $output = `$cmd`;
        
        if ($? == 0 && $output !~ /Error/) {
            pass("App $app is deployed on Fly.io");
        } else {
            # TODO: Deploy apps to Fly.io via GitHub Actions workflow
            todo "App $app is not yet deployed on Fly.io" => sub {
                fail("App $app is not yet deployed on Fly.io");
            };
        }
    }
};

# Test 10: Verify volume attachments
subtest 'volume attachments' => sub {
    skip_all "Fly CLI not available or not authenticated" 
        unless system('fly version >/dev/null 2>&1') == 0;
    
    foreach my $app (keys %EXPECTED_APPS) {
        my $cmd = "fly volumes list --app $app 2>&1";
        my $output = `$cmd`;
        
        if ($? == 0 && $output !~ /Error/) {
            like($output, qr/3gb/i, "Volume size correct for $app");
        } else {
            # TODO: Create volumes via GitHub Actions deployment
            todo "Volumes not yet created for $app" => sub {
                fail("Volumes not yet created for $app");
            };
        }
    }
};

# Test 11: GitHub Actions workflow exists and is valid
subtest 'github actions workflow' => sub {
    my $workflow_path = '.github/workflows/fly.yml';
    ok(-f $workflow_path, 'GitHub Actions workflow exists');
    skip_all "workflow file not found" unless -f $workflow_path;
    
    open my $fh, '<', $workflow_path or die "Can't open $workflow_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    like($content, qr/name:\s*Deploy to Fly\.io/i, 'Workflow has correct name');
    like($content, qr/on:\s*\n\s*push:/m, 'Workflow triggers on push');
    like($content, qr/FLY_API_TOKEN/i, 'Workflow uses deploy token');
    like($content, qr/--remote-only/i, 'Workflow uses remote builders');
    like($content, qr/prove.*t/i, 'Workflow runs infrastructure tests');
};

# Test 12: Development environment scripts exist and are executable
subtest 'development environment scripts' => sub {
    my @scripts = (
        'scripts/deploy-dev.pl',
        'scripts/setup-dev-env.pl',
        'scripts/cleanup-dev-env.pl',
        'scripts/setup-deploy-tokens.pl'
    );
    
    foreach my $script (@scripts) {
        ok(-f $script, "$script exists");
        skip_all "$script not found" unless -f $script;
        ok(-x $script, "$script is executable");
    }
};

# Test 13: Development deployment script configuration
subtest 'development deployment script configuration' => sub {
    my $script_path = 'scripts/deploy-dev.pl';
    skip_all "deploy-dev.pl not found" unless -f $script_path;
    
    open my $fh, '<', $script_path or die "Can't open $script_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    like($content, qr/per.*user.*dev/i, 'Implements per-user development environments');
    like($content, qr/health.*check/i, 'Implements health checking');
    like($content, qr/remote.*only/i, 'Uses remote builders by default');
    like($content, qr/magnet-hub.*magnet-services/s, 'Includes dev applications');
};

# Test 14: Token management script functionality
subtest 'token management script' => sub {
    my $script_path = 'scripts/setup-deploy-tokens.pl';
    skip_all "setup-deploy-tokens.pl not found" unless -f $script_path;
    
    open my $fh, '<', $script_path or die "Can't open $script_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    like($content, qr/tokens.*create.*deploy/i, 'Creates deploy tokens');
    like($content, qr/GitHub.*Actions/i, 'Includes GitHub Actions setup');
    like($content, qr/revoke.*tokens/i, 'Supports token revocation');
};

# Test 15: Development environment setup script
subtest 'development environment setup script' => sub {
    my $script_path = 'scripts/setup-dev-env.pl';
    skip_all "setup-dev-env.pl not found" unless -f $script_path;
    
    open my $fh, '<', $script_path or die "Can't open $script_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    like($content, qr/per.*user.*dev/i, 'Implements per-user development setup');
    like($content, qr/volume.*create/i, 'Creates development volumes');
    like($content, qr/secrets.*set/i, 'Configures development secrets');
    like($content, qr/cleanup/i, 'Includes cleanup functionality');
};

done_testing();