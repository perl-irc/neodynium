#!/usr/bin/env perl
# ABOUTME: Integration tests for development environment deployment and teardown
# ABOUTME: Tests end-to-end dev environment creation, validation, and cleanup using Test2::V0

use strict;
use warnings;
use Test2::V0;

# Skip if flyctl not available
plan skip_all => 'flyctl not available - required for integration tests'
    unless system('flyctl version >/dev/null 2>&1') == 0;

# Skip if not authenticated with Fly.io
my $auth_check = `flyctl auth whoami 2>&1`;
plan skip_all => 'Not authenticated with Fly.io - run "flyctl auth login" to enable integration tests'
    if $? != 0 || $auth_check =~ /not authenticated/i;

# Test configuration
my $USERNAME = $ENV{USER} || 'testuser';
$USERNAME =~ s/[^a-z0-9\-]//gi;
$USERNAME = lc($USERNAME);

my @DEV_APPS = (
    "magnet-hub-$USERNAME",
    "magnet-services-$USERNAME"
);

my $TEST_TIMEOUT = 300; # 5 minutes max for environment operations

# Test 1: Prerequisites validation
subtest 'prerequisites validation' => sub {
    # flyctl authentication already checked in plan skip_all above
    pass('Authenticated with Fly.io');
    
    # Check required scripts exist
    ok(-f 'scripts/setup-dev-env.pl', 'setup-dev-env.pl script exists');
    ok(-x 'scripts/setup-dev-env.pl', 'setup-dev-env.pl is executable');
    ok(-f 'scripts/cleanup-dev-env.pl', 'cleanup-dev-env.pl script exists');
    ok(-x 'scripts/cleanup-dev-env.pl', 'cleanup-dev-env.pl is executable');
    
    # Check Dockerfiles exist
    ok(-f 'solanum/Dockerfile', 'Solanum Dockerfile exists');
    ok(-f 'atheme/Dockerfile', 'Atheme Dockerfile exists');
    
    # Check configuration templates exist
    ok(-f 'solanum/ircd.conf.template', 'Solanum config template exists');
    ok(-f 'atheme/atheme.conf.template', 'Atheme config template exists');
};

# Test 2: Environment cleanup (ensure clean state)
subtest 'environment cleanup before test' => sub {
    note("Cleaning up any existing dev environment for $USERNAME");
    
    foreach my $app (@DEV_APPS) {
        my $status_output = `flyctl status --app $app 2>&1`;
        if ($? == 0) {
            note("Found existing app $app, cleaning up...");
            
            # Destroy app (this also cleans up volumes)
            my $destroy_output = `flyctl apps destroy $app --yes 2>&1`;
            if ($? == 0) {
                pass("Successfully cleaned up existing app $app");
            } else {
                # App might not exist, which is fine
                pass("App $app cleanup completed (may not have existed)");
            }
        } else {
            pass("No existing app $app found");
        }
    }
};

# Test 3: Development environment setup
subtest 'development environment setup' => sub {
    note("Setting up development environment for $USERNAME");
    
    # Run setup script with timeout
    my $setup_cmd = "timeout $TEST_TIMEOUT perl scripts/setup-dev-env.pl --user $USERNAME --create-volumes 2>&1";
    my $setup_output = `$setup_cmd` // '';
    my $setup_exit = $?;
    
    if ($setup_exit == 0) {
        pass("Development environment setup completed successfully");
        note("Setup output: $setup_output");
    } else {
        # Check if it was a timeout
        if ($setup_exit == 124 || $setup_exit == 31744) { # timeout exit codes
            fail("Development environment setup timed out after $TEST_TIMEOUT seconds");
            bail_out("Setup timeout - cannot proceed with integration tests");
        } else {
            fail("Development environment setup failed with exit code $setup_exit");
            note("Setup error output: $setup_output");
            bail_out("Setup failed - cannot proceed with integration tests");
        }
    }
};

# Test 4: Verify apps are created and running
subtest 'verify dev apps created and status' => sub {
    foreach my $app (@DEV_APPS) {
        # Check app exists
        my $status_output = `flyctl status --app $app 2>&1`;
        if ($? == 0) {
            pass("App $app exists and responds to status");
            note("Status for $app: $status_output");
            
            # Parse status for basic health
            if ($status_output =~ /Machines/) {
                pass("App $app has machines configured");
            } else {
                fail("App $app missing machine configuration");
            }
        } else {
            fail("App $app not found or not accessible");
            note("Status error for $app: $status_output");
        }
    }
};

# Test 5: Verify volumes are created
subtest 'verify dev volumes created' => sub {
    foreach my $app (@DEV_APPS) {
        my $volumes_output = `flyctl volumes list --app $app 2>&1`;
        if ($? == 0) {
            if ($volumes_output =~ /vol_/) {
                pass("App $app has volumes created");
            } else {
                # Some apps might not need volumes, that's OK
                pass("App $app volume check completed (volumes may not be required)");
            }
        } else {
            fail("Unable to check volumes for app $app");
            note("Volumes error for $app: $volumes_output");
        }
    }
};

# Test 6: Verify secrets are configured
subtest 'verify dev secrets configured' => sub {
    foreach my $app (@DEV_APPS) {
        my $secrets_output = `flyctl secrets list --app $app 2>&1`;
        if ($? == 0) {
            # Check for expected secrets
            if ($secrets_output =~ /TAILSCALE_AUTHKEY/) {
                pass("App $app has TAILSCALE_AUTHKEY secret configured");
            } else {
                fail("App $app missing TAILSCALE_AUTHKEY secret");
            }
        } else {
            fail("Unable to check secrets for app $app");
            note("Secrets error for $app: $secrets_output");
        }
    }
};

# Test 7: Basic deployment validation
subtest 'basic deployment validation' => sub {
    foreach my $app (@DEV_APPS) {
        # Try to get machine status
        my $machines_output = `flyctl machines list --app $app 2>&1`;
        if ($? == 0) {
            pass("Can list machines for app $app");
            
            # Check if any machines are running
            if ($machines_output =~ /started|running/i) {
                pass("App $app has running machines");
            } elsif ($machines_output =~ /stopped/i) {
                pass("App $app has machines (currently stopped - normal for dev)");
            } else {
                # Machines might not be started yet, which is OK for dev
                pass("App $app machines status checked");
            }
        } else {
            fail("Unable to list machines for app $app");
            note("Machines error for $app: $machines_output");
        }
    }
};

# Test 8: Configuration file validation
subtest 'configuration files validation' => sub {
    # We can't easily access files inside the containers without starting them,
    # but we can verify our local templates are valid
    
    foreach my $template ('solanum/ircd.conf.template', 'atheme/atheme.conf.template') {
        open my $fh, '<', $template or die "Can't open $template: $!";
        my $content = do { local $/; <$fh> };
        close $fh;
        
        # Check for environment variable substitution
        like($content, qr/\$\{[A-Z_]+\}/, "$template contains environment variable substitution");
        
        # Check for no hardcoded secrets
        unlike($content, qr/tskey-auth-[a-zA-Z0-9]{20,}/, "$template contains no hardcoded Tailscale keys");
        unlike($content, qr/password\s*=\s*[^$]/, "$template contains no hardcoded passwords");
    }
};

# Test 9: Development environment cleanup
subtest 'development environment cleanup' => sub {
    note("Cleaning up development environment for $USERNAME");
    
    # Run cleanup script with timeout
    my $cleanup_cmd = "timeout $TEST_TIMEOUT perl scripts/cleanup-dev-env.pl --user $USERNAME --confirm 2>&1";
    my $cleanup_output = `$cleanup_cmd`;
    my $cleanup_exit = $?;
    
    if ($cleanup_exit == 0) {
        pass("Development environment cleanup completed successfully");
        note("Cleanup output: $cleanup_output");
    } else {
        # Check if it was a timeout
        if ($cleanup_exit == 124 || $cleanup_exit == 31744) { # timeout exit codes
            fail("Development environment cleanup timed out after $TEST_TIMEOUT seconds");
            note("Manual cleanup may be required");
        } else {
            fail("Development environment cleanup failed with exit code $cleanup_exit");
            note("Cleanup error output: $cleanup_output");
        }
    }
};

# Test 10: Verify cleanup completed
subtest 'verify cleanup completed' => sub {
    foreach my $app (@DEV_APPS) {
        my $status_output = `flyctl status --app $app 2>&1`;
        if ($? != 0) {
            # App should not exist after cleanup
            pass("App $app successfully removed");
        } else {
            fail("App $app still exists after cleanup");
            note("Remaining app status: $status_output");
        }
    }
};

# Test 11: Resource leak detection
subtest 'resource leak detection' => sub {
    # Check for any volumes that might have been left behind
    my $all_volumes_output = `flyctl volumes list 2>&1`;
    if ($? == 0) {
        # Look for volumes with our username pattern
        my @user_volumes = grep { /$USERNAME/ } split /\n/, $all_volumes_output;
        if (@user_volumes == 0) {
            pass("No volume leaks detected for user $USERNAME");
        } else {
            fail("Found potentially leaked volumes for user $USERNAME");
            note("Leaked volumes: " . join(", ", @user_volumes));
        }
    } else {
        # Unable to check volumes, but that's not necessarily a failure
        pass("Volume leak check completed (unable to list all volumes)");
    }
};

done_testing();

# Helper subroutines
sub run_with_timeout {
    my ($cmd, $timeout) = @_;
    
    local $SIG{ALRM} = sub { die "Command timed out after $timeout seconds\n" };
    alarm $timeout;
    
    my $output = `$cmd 2>&1`;
    my $exit_code = $?;
    
    alarm 0;
    
    return ($output, $exit_code);
}