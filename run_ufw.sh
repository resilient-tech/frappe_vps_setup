#!/usr/bin/env bash

#=============================================================================
# Remote UFW Setup Script for Frappe VPS
#=============================================================================
#
# Description:
#   Copies the UFW configuration script to the remote server and executes
#   it there. Configures firewall for SSH, HTTP, and HTTPS access.
#
# Prerequisites:
#   - Initial server setup completed
#   - SSH key authentication configured
#   - config.yml with server configuration
#
# What this script does:
#   1. Validates local configuration
#   2. Tests SSH connectivity to server
#   3. Copies UFW setup script to remote server
#   4. Executes UFW configuration remotely
#   5. Cleans up temporary files
#
# Author: Generated for Frappe VPS Setup
# Dependencies: config.yml, utils.sh, ufw_setup.sh
#=============================================================================

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration file path
CONFIG_FILE="$SCRIPT_DIR/config.yml"

# SSH options
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=~/.ssh/known_hosts"

# Function to load configuration
load_remote_config() {
    load_config "$CONFIG_FILE"

    # Set configuration variables
    SERVER_IP="${CONFIG_server_ip_address:-}"
    FRAPPE_USERNAME="${CONFIG_frappe_username:-resilient}"
    SSH_PORT="8520"  # Fixed port after hardening

    # Validate required configuration
    if [[ -z "$SERVER_IP" ]]; then
        print_error "Server IP not found in configuration"
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
        print_error "  1. Initial server setup has been completed"
        print_error "  2. SSH is running on port $SSH_PORT"
        print_error "  3. User '$FRAPPE_USERNAME' exists with SSH key access"
        print_error "  4. Server is accessible at $SERVER_IP"
        exit 1
    fi

    print_info "SSH connection successful!"
}

# Function to copy required files to remote server
copy_files_to_remote() {
    print_info "Copying UFW setup files to remote server..."

    # Create temporary directory on remote server
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" "mkdir -p ~/frappe_ufw_temp"

    # Copy required files
    scp $SSH_OPTS -P $SSH_PORT \
        "$SCRIPT_DIR/utils.sh" \
        "$SCRIPT_DIR/ufw_setup.sh" \
        "$FRAPPE_USERNAME@$SERVER_IP:~/frappe_ufw_temp/"

    # Make scripts executable
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "chmod +x ~/frappe_ufw_temp/ufw_setup.sh ~/frappe_ufw_temp/utils.sh"

    print_info "Files copied successfully"
}

# Function to execute UFW setup remotely
execute_remote_setup() {
    print_info "Executing UFW setup on remote server..."
    echo ""

    # Run the UFW setup script remotely
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "cd ~/frappe_ufw_temp && ./ufw_setup.sh"

    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_success "✓ UFW setup completed successfully on remote server"
    else
        print_error "UFW setup failed on remote server (exit code: $exit_code)"
        return 1
    fi
}

# Function to cleanup temporary files
cleanup_remote_files() {
    print_info "Cleaning up temporary files on remote server..."

    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "rm -rf ~/frappe_ufw_temp"

    print_info "Cleanup complete"
}

# Main execution
main() {
    print_info "Starting remote UFW configuration..."
    echo ""

    # Load configuration
    load_remote_config

    print_info "Configuration loaded:"
    print_info "  Server: $SERVER_IP"
    print_info "  User: $FRAPPE_USERNAME"
    print_info "  SSH Port: $SSH_PORT"
    echo ""

    # Test connection
    test_remote_connection

    # Copy files
    copy_files_to_remote

    # Execute setup
    if execute_remote_setup; then
        # Cleanup
        cleanup_remote_files

        echo ""
        print_success "====================================="
        print_success "Remote UFW Setup Complete!"
        print_success "====================================="
        echo ""
        print_info "Firewall configured on $SERVER_IP with:"
        print_info "  - Port 8520: SSH"
        print_info "  - Port 80: HTTP"
        print_info "  - Port 443: HTTPS"
        echo ""
        print_info "To check firewall status on the server:"
        print_info "  ssh -p $SSH_PORT $FRAPPE_USERNAME@$SERVER_IP 'sudo ufw status'"
        echo ""
    else
        print_error "Remote UFW setup failed"
        cleanup_remote_files
        exit 1
    fi
}

# Run main function
main
