#!/usr/bin/env bash

#=============================================================================
# Remote Dependencies Setup Script for Frappe VPS
#=============================================================================
#
# Description:
#   Copies the dependencies setup script and required files to the remote
#   server and executes it there. This handles the SSH connectivity and
#   remote execution automatically.
#
# Prerequisites:
#   - Initial server setup completed (SSH hardened, user created)
#   - SSH key authentication configured
#   - config.yml with server configuration
#
# What this script does:
#   1. Validates local configuration
#   2. Tests SSH connectivity to hardened server
#   3. Copies dependencies script and utilities to remote server
#   4. Executes dependencies installation remotely
#   5. Cleans up temporary files
#
# Author: Generated for Frappe VPS Setup
# Dependencies: config.yml, utils.sh, dependencies_setup.sh
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

    # Set configuration variables (matching YAML structure)
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

# Function to test SSH connection to hardened server
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
        print_error ""
        print_error "Try connecting manually: ssh -p $SSH_PORT $FRAPPE_USERNAME@$SERVER_IP"
        exit 1
    fi

    print_info "SSH connection successful!"
}

# Function to copy required files to remote server
copy_files_to_remote() {
    print_info "Copying setup files to remote server..."

    # Create temporary directory on remote server
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" "mkdir -p ~/frappe_setup_temp"

    # Copy required files
    scp $SSH_OPTS -P $SSH_PORT \
        "$SCRIPT_DIR/config.yml" \
        "$SCRIPT_DIR/utils.sh" \
        "$SCRIPT_DIR/dependencies_setup.sh" \
        "$FRAPPE_USERNAME@$SERVER_IP:~/frappe_setup_temp/"

    # Make scripts executable
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "chmod +x ~/frappe_setup_temp/dependencies_setup.sh ~/frappe_setup_temp/utils.sh"

    print_info "Files copied successfully"
}

# Function to run dependencies setup on remote server
run_dependencies_remotely() {
    print_info "Starting dependencies installation on remote server..."
    print_info "This may take several minutes..."

    # Execute the dependencies script remotely
    if ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "cd ~/frappe_setup_temp && ./dependencies_setup.sh"; then
        print_info "Dependencies installation completed successfully!"
    else
        print_error "Dependencies installation failed!"
        print_error "Check the output above for details"
        exit 1
    fi
}

# Function to clean up temporary files
cleanup_remote_files() {
    print_info "Cleaning up temporary files..."

    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" \
        "rm -rf ~/frappe_setup_temp" 2>/dev/null || true

    print_info "Cleanup completed"
}

# Function to save success information
save_completion_info() {
    print_info "Saving completion information..."

    # Create a completion marker with important details
    ssh $SSH_OPTS -p $SSH_PORT "$FRAPPE_USERNAME@$SERVER_IP" << 'EOF'
cat > ~/frappe_dependencies_completed.txt << 'MARKER'
Frappe Dependencies Installation Completed
==========================================

Installation Date: $(date)
Server: $(hostname)
User: $(whoami)

✅ Installed Components:
- System packages (git, build-essential, etc.)
- Python 3 with pip and venv
- Redis server (service disabled for Frappe)
- wkhtmltopdf (official DEB package)
- Node.js 22 LTS (via NVM)
- Yarn package manager
- MariaDB with Frappe-optimized configuration

📋 Important Files:
- MariaDB root password: ~/mariadb_root_password.txt
- MariaDB config: /etc/mysql/mariadb.conf.d/erpnext.cnf
- Service limits: /etc/systemd/system/mariadb.service.d/override.conf

🚀 Next Steps:
1. Install Frappe bench: pip install frappe-bench
2. Initialize bench: bench init --python python3 --no-backups frappe-bench
3. Create site: bench new-site <site-name>

MARKER
EOF

    print_info "Completion information saved to ~/frappe_dependencies_completed.txt"
}

# Main execution
main() {
    print_info "Starting Remote Dependencies Installation for Frappe VPS"
    print_info "======================================================"

    # Load and validate configuration
    load_remote_config
    print_info "Target server: $SERVER_IP:$SSH_PORT"
    print_info "Target user: $FRAPPE_USERNAME"

    # Test connection to hardened server
    test_remote_connection

    # Copy files and execute remotely
    copy_files_to_remote
    run_dependencies_remotely
    save_completion_info
    cleanup_remote_files

    print_info ""
    print_success "🎉 Remote dependencies installation completed successfully!"
    print_info ""
    print_info "✅ Summary:"
    print_info "  ✓ Connected to hardened server ($FRAPPE_USERNAME@$SERVER_IP:$SSH_PORT)"
    print_info "  ✓ Copied setup files to remote server"
    print_info "  ✓ Installed all Frappe dependencies remotely"
    print_info "  ✓ Configured MariaDB with optimized settings"
    print_info "  ✓ Cleaned up temporary files"
    print_info "  ✓ Saved completion information"
    print_info ""
    print_info "🔗 Connect to your server:"
    print_info "  ssh -p $SSH_PORT $FRAPPE_USERNAME@$SERVER_IP"
    print_info ""
    print_info "📋 Check completion details:"
    print_info "  cat ~/frappe_dependencies_completed.txt"
    print_info ""
    print_success "🚀 Server is ready for Frappe bench initialization!"
}

# Run main function
main "$@"
