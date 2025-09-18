#!/usr/bin/env bash

#=============================================================================
# Remote Bench Initialization Script for Frappe VPS
#=============================================================================
#
# Description:
#   Copies the bench initialization script and required files to the remote
#   server and executes it there. This handles the SSH connectivity and
#   remote execution automatically.
#
# Prerequisites:
#   - Dependencies setup completed
#   - SSH key authentication configured
#   - config.yml with site configuration
#
# What this script does:
#   1. Validates local configuration
#   2. Tests SSH connectivity to server
#   3. Copies bench init script and utilities to remote server
#   4. Executes bench initialization remotely
#   5. Cleans up temporary files
#
# Author: Generated for Frappe VPS Setup
# Dependencies: config.yml, utils.sh, bench_init.sh
#=============================================================================

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration file path
CONFIG_FILE="$SCRIPT_DIR/config.yml"

# SSH options for hardened server
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=~/.ssh/known_hosts"

# Function to load configuration
load_remote_config() {
    load_config "$CONFIG_FILE"

    # Set configuration variables
    SERVER_IP="${CONFIG_server_ip_address:-}"
    FRAPPE_USERNAME="${CONFIG_frappe_username:-resilient}"
    BENCH_NAME="${CONFIG_frappe_bench_name:-resilient-bench}"
    SITE_NAME="${CONFIG_frappe_site_name:-}"
    SSH_PORT="8520"  # Fixed port after hardening

    # Validate required configuration
    if [[ -z "$SERVER_IP" ]]; then
        print_error "Server IP not found in configuration"
        exit 1
    fi

    if [[ -z "$SITE_NAME" ]]; then
        print_error "Site name is required but not found in configuration"
        print_error "Please set 'frappe.site_name' in config.yml"
        exit 1
    fi

    if ! validate_ip_address "$SERVER_IP"; then
        print_error "Invalid IP address format: $SERVER_IP"
        exit 1
    fi
}

# Function to test SSH connection
test_remote_connection() {
    print_info "Testing SSH connection to $FRAPPE_USERNAME@$SERVER_IP:$SSH_PORT"

    if ! ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" "echo 'Connection successful'" 2>/dev/null; then
        print_error "Failed to connect to $FRAPPE_USERNAME@$SERVER_IP:$SSH_PORT"
        print_error ""
        print_error "Please ensure:"
        print_error "  1. Dependencies setup has been completed"
        print_error "  2. SSH is running on port $SSH_PORT"
        print_error "  3. User '$FRAPPE_USERNAME' exists with SSH key access"
        print_error "  4. Server is accessible at $SERVER_IP"
        exit 1
    fi

    print_info "SSH connection successful!"
}

# Function to copy required files to remote server
copy_files_to_remote() {
    print_info "Copying bench initialization files to remote server..."

    # Create temporary directory on remote server
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" "mkdir -p ~/frappe_bench_init_temp"

    # Copy required files
    scp $SSH_OPTS -P $SSH_PORT \
        "$SCRIPT_DIR/config.yml" \
        "$SCRIPT_DIR/utils.sh" \
        "$SCRIPT_DIR/bench_init.sh" \
        "$FRAPPE_USERNAME@$SERVER_IP:~/frappe_bench_init_temp/"

    # Make scripts executable
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "chmod +x ~/frappe_bench_init_temp/bench_init.sh ~/frappe_bench_init_temp/utils.sh"

    print_info "Files copied successfully"
}

# Function to run bench initialization on remote server
run_bench_init_remotely() {
    print_info "Starting Frappe bench initialization on remote server..."
    print_info "Site: $SITE_NAME"
    print_info "This may take 10-15 minutes depending on your server..."

    # Execute the bench init script remotely from home directory
    # Copy the script to temp directory but run it from home directory
    if ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "cd ~ && ~/frappe_bench_init_temp/bench_init.sh"; then
        print_info "Bench initialization completed successfully!"
    else
        print_error "Bench initialization failed!"
        print_error "Check the output above for details"
        exit 1
    fi
}

# Function to clean up temporary files
cleanup_remote_files() {
    print_info "Cleaning up temporary files..."

    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "rm -rf ~/frappe_bench_init_temp" 2>/dev/null || true

    print_info "Cleanup completed"
}

# Main execution
main() {
    print_info "Starting Remote Frappe Bench Initialization"
    print_info "==========================================="

    # Load and validate configuration
    load_remote_config
    print_info "Target server: $SERVER_IP:$SSH_PORT"
    print_info "Target user: $FRAPPE_USERNAME"
    print_info "Site name: $SITE_NAME"

    # Test connection
    test_remote_connection

    # Copy files and execute remotely
    copy_files_to_remote
    run_bench_init_remotely
    cleanup_remote_files

    print_info ""
    print_success "🎉 Remote Frappe bench initialization completed successfully!"
    print_info ""
    print_info "✅ Summary:"
    print_info "  ✓ Connected to server ($FRAPPE_USERNAME@$SERVER_IP:$SSH_PORT)"
    print_info "  ✓ Copied bench initialization files"
    print_info "  ✓ Initialized Frappe bench with site: $SITE_NAME"
    print_info "  ✓ Saved admin credentials to ~/frappe_admin_credentials.txt"
    print_info "  ✓ Cleaned up temporary files"
    print_info ""
    print_info "🔗 Connect to your server and start development:"
    print_info "  ssh -p $SSH_PORT $FRAPPE_USERNAME@$SERVER_IP"
    print_info "  cd $BENCH_NAME"
    print_info "  bench start"
    print_info ""
    print_info "🌐 Access your site:"
    print_info "  http://$SITE_NAME:8000"
    print_info ""
    print_info "📋 Check credentials:"
    print_info "  cat ~/frappe_admin_credentials.txt"
    print_info ""
    print_success "🚀 Frappe is ready for development!"
}

# Run main function
main "$@"
