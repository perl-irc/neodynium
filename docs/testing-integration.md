# ABOUTME: Integration testing documentation for Magnet IRC Network development environment
# ABOUTME: Guide for running end-to-end tests that validate dev environment deployment and cleanup

# Integration Testing Guide

This document describes how to run integration tests that validate the complete development environment deployment and cleanup process.

## Overview

Integration tests verify the end-to-end functionality of:
- Development environment setup via `scripts/setup-dev-env.pl`
- Docker image building and deployment on Fly.io
- Tailscale mesh networking configuration
- Volume and secrets management
- Environment cleanup and resource management

## Prerequisites

### Required Tools
- **Fly.io CLI**: `flyctl` must be installed and authenticated
- **Perl**: For running test scripts and setup scripts
- **Fly.io Account**: With appropriate permissions for app creation/destruction

### Authentication Setup
```bash
# Install flyctl (if not already installed)
curl -L https://fly.io/install.sh | sh

# Authenticate with Fly.io
flyctl auth login
```

### Environment Variables
```bash
# Optional: Customize test user (defaults to $USER)
export USER=your-username
```

## Running Integration Tests

### Basic Execution
```bash
# Run integration tests only
prove -v t/03-integration-dev-environment.t

# Run all tests including integration
prove -v t/
```

### Expected Test Flow
The integration test performs the following sequence:

1. **Prerequisites Validation**: Checks flyctl auth, required scripts, and templates
2. **Environment Cleanup**: Removes any existing dev environment for the test user
3. **Environment Setup**: Runs `setup-dev-env.pl` to create dev environment
4. **App Verification**: Validates that Fly.io apps are created and accessible
5. **Volume Verification**: Checks that persistent volumes are properly created
6. **Secrets Verification**: Validates that Tailscale auth keys are configured
7. **Deployment Validation**: Verifies machine deployment and status
8. **Configuration Validation**: Checks template validity and security
9. **Environment Cleanup**: Runs `cleanup-dev-env.pl` to remove dev environment
10. **Cleanup Verification**: Confirms all resources are properly removed
11. **Leak Detection**: Checks for any remaining resources that might indicate leaks

### Test Output Interpretation

#### Successful Run
```
t/03-integration-dev-environment.t .. 
ok 1 - prerequisites validation
ok 2 - environment cleanup before test
ok 3 - development environment setup
ok 4 - verify dev apps created and status
ok 5 - verify dev volumes created
ok 6 - verify dev secrets configured
ok 7 - basic deployment validation
ok 8 - configuration files validation
ok 9 - development environment cleanup
ok 10 - verify cleanup completed
ok 11 - resource leak detection
1..11
ok
All tests successful.
```

#### Common Failure Scenarios

**Authentication Failure**:
```
1..0 # SKIP Not authenticated with Fly.io - run 'flyctl auth login'
```
*Solution*: Run `flyctl auth login` and authenticate

**Missing Prerequisites**:
```
1..0 # SKIP flyctl not available - required for integration tests
```
*Solution*: Install Fly.io CLI


**Setup Timeout**:
```
not ok 3 - development environment setup
# Setup timeout - cannot proceed with integration tests
```
*Solution*: Check network connectivity and Fly.io status

## Test Configuration

### Timeouts
- **Environment Operations**: 5 minutes (300 seconds)
- **Individual Commands**: Varies by operation complexity

### Test Isolation
- Each test user gets isolated apps: `magnet-hub-{username}`, `magnet-services-{username}`
- Username sanitization ensures valid Fly.io app names
- Automatic cleanup prevents resource conflicts between test runs

### Resource Management
The integration tests create and destroy:
- **Fly.io Apps**: Per-user development applications
- **Volumes**: Persistent storage for configuration and data
- **Secrets**: Tailscale auth keys and other sensitive configuration
- **Machines**: Container instances (may be stopped in dev mode)

## Continuous Integration

### GitHub Actions Integration
Integration tests can be enabled in CI by adding the environment variable:

```yaml
env:
  FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
```

**Note**: Currently disabled in CI to avoid resource usage and authentication complexity.

### Local Development Workflow
```bash
# Before making changes
prove -v t/03-integration-dev-environment.t

# After making changes
prove -v t/  # All tests including integration
```

## Troubleshooting

### Common Issues

**Existing Apps Conflict**:
If apps from previous failed tests exist, manually clean up:
```bash
flyctl apps destroy magnet-hub-{username} --yes
flyctl apps destroy magnet-services-{username} --yes
```

**Volume Cleanup Issues**:
List and manually remove stuck volumes:
```bash
flyctl volumes list
flyctl volumes destroy {volume-id} --yes
```

**Authentication Expiry**:
Re-authenticate if token expires:
```bash
flyctl auth login
```

**Network/Timeout Issues**:
- Check internet connectivity
- Verify Fly.io service status
- Increase timeout values in test if needed

### Debug Mode
Add verbose output to integration tests:
```bash
# Run with detailed output
prove -v t/03-integration-dev-environment.t

# Run individual subtests
perl -Ilib t/03-integration-dev-environment.t
```

### Manual Verification
Verify environment manually:
```bash
# Check apps exist
flyctl apps list | grep {username}

# Check app status
flyctl status --app magnet-hub-{username}

# Check secrets
flyctl secrets list --app magnet-hub-{username}
```

## Security Considerations

### Secrets Handling
- Integration tests verify that no hardcoded secrets are present
- Tailscale auth keys are validated to be environment variables only
- Test cleanup ensures secrets are removed with app destruction

### Resource Isolation
- Each user gets isolated test environment
- No cross-user resource sharing or conflicts
- Automatic cleanup prevents resource accumulation

### Access Control
- Requires authenticated Fly.io access
- Uses user's existing Fly.io permissions
- No privilege escalation or shared credentials

## Performance Expectations

### Typical Runtimes
- **Setup Phase**: 2-3 minutes (including image building)
- **Validation Phase**: 30-60 seconds
- **Cleanup Phase**: 1-2 minutes
- **Total Runtime**: 4-6 minutes per full test cycle

### Resource Usage
- **CPU**: Minimal local usage (mostly API calls)
- **Memory**: <100MB for test execution
- **Network**: Moderate (image uploads, API calls)
- **Fly.io Resources**: Temporary apps and volumes (cleaned up automatically)

## Contributing

When modifying integration tests:

1. **Maintain Isolation**: Ensure tests don't interfere with each other
2. **Complete Cleanup**: Always clean up resources in test teardown
3. **Timeout Handling**: Use appropriate timeouts for all operations
4. **Error Handling**: Provide meaningful error messages and debugging info
5. **Documentation**: Update this guide when adding new test scenarios

### Adding New Test Cases
```perl
# Add new subtest to integration test
subtest 'new test case' => sub {
    # Test implementation
    pass("Test description");
};
```

Ensure new tests follow the existing pattern of setup → validation → cleanup.