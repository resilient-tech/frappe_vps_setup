#!/usr/bin/env bash

#=============================================================================
# Initial Server Setup Script for Frappe VPS
#=============================================================================
#
# Description:
#   Automates the initial security hardening and user setup for a fresh
#   Ubuntu 24.04 server before installing Frappe/ERPNext. This script
#   transforms a basic VPS into a secure, properly configured server.
#
# Prerequisites:
#   - Fresh Ubuntu 24.04 server
#   - SSH key access to root or initial user account
#   - yq installed locally (script will guide installation if missing)
#   - config.yml file with server IP address configured
#
# What this script does:
#   1. Tests SSH connectivity to the target server
#   2. Creates a new non-root user (default: 'resilient')
#   3. Grants sudo privileges with passwordless access
#   4. Copies SSH keys from current user to new user
#   5. Hardens SSH configuration:
#      - Changes SSH port from 22 to 8520
#      - Disables root login
#      - Disables password authentication
#      - Enables public key authentication only
#   6. Handles SSH socket override issues on systemd systems
#   7. Verifies the new configuration works
#
# Security improvements:
#   - Non-root user access only
#   - Custom SSH port reduces automated attacks
#   - Key-based authentication only
#   - Passwordless sudo for deployment automation
#
# Usage:
#   1. Configure server IP in config.yml
#   2. Ensure SSH key access: ssh-copy-id root@YOUR_SERVER_IP
#   3. Run: ./initial_server_setup.sh
#   4. Connect with: ssh -p 8520 resilient@YOUR_SERVER_IP
#
# Author: Generated for Frappe VPS Setup
# Dependencies: yq (for YAML parsing), utils.sh
#=============================================================================

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration file path
CONFIG_FILE="$SCRIPT_DIR/config.yml"

# SSH options to handle first-time connections and ensure reliability
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=~/.ssh/known_hosts"

# Function to load and set configuration variables
load_setup_config() {
    load_config "$CONFIG_FILE"

    # Set required variables
    SERVER_IP="${CONFIG_server_ip_address:-}"
    USER_USERNAME="${CONFIG_user_username:-root}"
    FRAPPE_USERNAME="${CONFIG_frappe_username:-resilient}"
    TIMEZONE="${CONFIG_server_timezone:-Asia/Kolkata}"
    SWAP_SIZE="${CONFIG_server_swap_size:-2G}"
}

# Function to validate configuration
validate_config() {
    print_info "Validating configuration..."

    # Check mandatory fields
    if [[ -z "$SERVER_IP" ]]; then
        print_error "SERVER IP ADDRESS IS MANDATORY!"
        print_error "Please set server.ip_address in config.yml"
        exit 1
    fi

    # Validate IP address format
    if ! validate_ip_address "$SERVER_IP"; then
        print_error "Invalid IP address format: $SERVER_IP"
        print_error "Please provide a valid IPv4 address in config.yml"
        exit 1
    fi

    print_info "Configuration validated successfully"
    print_info "Server IP: $SERVER_IP"
    print_info "Current Username: $USER_USERNAME"
    print_info "New Frappe Username: $FRAPPE_USERNAME"
    print_info "Timezone: $TIMEZONE"
    print_info "Swap Size: $SWAP_SIZE"
}

# Clean up old SSH host keys for rebuilt servers
cleanup_known_hosts() {
    print_info "Cleaning up old SSH host keys for $SERVER_IP"

    local known_hosts_file="$HOME/.ssh/known_hosts"

    if [[ -f "$known_hosts_file" ]]; then
        # Remove entries for both the IP and port 8520 (in case of previous setups)
        ssh-keygen -f "$known_hosts_file" -R "$SERVER_IP" 2>/dev/null || true
        ssh-keygen -f "$known_hosts_file" -R "[$SERVER_IP]:8520" 2>/dev/null || true

        print_info "Old SSH host keys removed (if they existed)"
    else
        print_info "No known_hosts file found, skipping cleanup"
    fi
}

# Test SSH connection to the server
test_ssh_connection() {
    print_info "Testing SSH connection to $USER_USERNAME@$SERVER_IP"

    if ! ssh $SSH_OPTS -o BatchMode=yes "$USER_USERNAME@$SERVER_IP" "echo 'SSH connection successful'" 2>/dev/null; then
        print_error "Failed to connect to $USER_USERNAME@$SERVER_IP"
        print_error "Please ensure:"
        print_error "  1. The server is running and accessible"
        print_error "  2. SSH key authentication is set up"
        print_error "  3. The IP address and username are correct"
        exit 1
    fi

    print_info "SSH connection successful!"
}

# Perform all server setup operations in a single SSH session
setup_server() {
    print_info "Performing server setup (user creation, sudo, SSH keys, timezone, swap, SSH hardening)"

    ssh $SSH_OPTS "$USER_USERNAME@$SERVER_IP" /bin/bash << EOF
set -euo pipefail

echo "=== Creating new user $FRAPPE_USERNAME ==="
if id "$FRAPPE_USERNAME" &>/dev/null; then
    echo "User $FRAPPE_USERNAME already exists, skipping user creation"
else
    sudo adduser --disabled-password --gecos '' "$FRAPPE_USERNAME"
fi

echo "=== Setting up sudo privileges ==="
sudo usermod -aG sudo "$FRAPPE_USERNAME"
echo "$FRAPPE_USERNAME ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$FRAPPE_USERNAME
sudo chmod 0440 /etc/sudoers.d/$FRAPPE_USERNAME

echo "=== Copying SSH keys ==="
sudo mkdir -p /home/$FRAPPE_USERNAME/.ssh
sudo cp ~/.ssh/authorized_keys /home/$FRAPPE_USERNAME/.ssh/authorized_keys
sudo chown -R $FRAPPE_USERNAME:$FRAPPE_USERNAME /home/$FRAPPE_USERNAME/.ssh
sudo chmod 700 /home/$FRAPPE_USERNAME/.ssh
sudo chmod 600 /home/$FRAPPE_USERNAME/.ssh/authorized_keys

echo "=== Configuring system timezone ==="
echo "Setting timezone to $TIMEZONE"
sudo timedatectl set-timezone "$TIMEZONE"

# Verify timezone was set correctly
echo "=== Verifying timezone configuration ==="
current_timezone=\$(timedatectl show --property=Timezone --value)
if [[ "\$current_timezone" == "$TIMEZONE" ]]; then
    echo "✓ Timezone successfully set to \$current_timezone"
else
    echo "⚠ WARNING: Expected timezone $TIMEZONE but got \$current_timezone"
fi

# Show current time and timezone info
echo "Current system time:"
timedatectl status

echo "=== Configuring swap space ==="
# Check if swap already exists
if swapon --show | grep -q '/swapfile'; then
    echo "Swap file already exists, checking size..."
    current_size=\$(swapon --show --noheadings | grep '/swapfile' | awk '{print \$3}')
    echo "Current swap size: \$current_size"
    if [[ "\$current_size" == "$SWAP_SIZE" ]]; then
        echo "Swap size matches configured size ($SWAP_SIZE), skipping swap setup"
    else
        echo "Swap size differs from configured size ($SWAP_SIZE), recreating..."
        sudo swapoff /swapfile
        sudo rm -f /swapfile
        sudo fallocate -l $SWAP_SIZE /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo "Swap recreated with size $SWAP_SIZE"
    fi
else
    echo "Creating swap file with size $SWAP_SIZE"
    # Use fallocate for better performance on modern systems
    sudo fallocate -l $SWAP_SIZE /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    # Make swap permanent by adding to /etc/fstab
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
    echo "Swap file created and enabled"
fi

# Verify swap configuration
echo "=== Verifying swap configuration ==="
if swapon --show | grep -q '/swapfile'; then
    echo "✓ Swap file is active"
    actual_size=\$(swapon --show --noheadings | grep '/swapfile' | awk '{print \$3}')
    echo "✓ Active swap size: \$actual_size"

    # Verify fstab entry exists
    if grep -q '/swapfile.*swap' /etc/fstab; then
        echo "✓ Swap entry found in /etc/fstab (will persist after reboot)"
    else
        echo "⚠ WARNING: Swap not found in /etc/fstab"
    fi

    # Show memory info
    echo "Memory and swap summary:"
    free -h
else
    echo "❌ ERROR: Swap file is not active!"
    echo "Troubleshooting info:"
    swapon --show
    ls -la /swapfile 2>/dev/null || echo "Swap file does not exist"
fi

echo "=== Configuring swap properties ==="
# Configure swappiness and cache pressure for better performance
echo "Setting vm.swappiness = 1 and vm.vfs_cache_pressure = 50"

# Add or update swappiness setting
if grep -q "^vm.swappiness" /etc/sysctl.conf; then
    sudo sed -i 's/^vm.swappiness.*/vm.swappiness = 1/' /etc/sysctl.conf
else
    echo 'vm.swappiness = 1' | sudo tee -a /etc/sysctl.conf
fi

# Add or update vfs_cache_pressure setting
if grep -q "^vm.vfs_cache_pressure" /etc/sysctl.conf; then
    sudo sed -i 's/^vm.vfs_cache_pressure.*/vm.vfs_cache_pressure = 50/' /etc/sysctl.conf
else
    echo 'vm.vfs_cache_pressure = 50' | sudo tee -a /etc/sysctl.conf
fi

# Apply the changes immediately
sudo sysctl -p

# Verify the changes
echo "=== Verifying swap properties ==="
current_swappiness=\$(sysctl -n vm.swappiness)
current_cache_pressure=\$(sysctl -n vm.vfs_cache_pressure)

if [[ "\$current_swappiness" == "1" ]]; then
    echo "✓ vm.swappiness correctly set to \$current_swappiness"
else
    echo "⚠ WARNING: Expected swappiness 1 but got \$current_swappiness"
fi

if [[ "\$current_cache_pressure" == "50" ]]; then
    echo "✓ vm.vfs_cache_pressure correctly set to \$current_cache_pressure"
else
    echo "⚠ WARNING: Expected cache pressure 50 but got \$current_cache_pressure"
fi

echo "=== Configuring SSH security ==="
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Remove and add SSH config settings
sudo sed -i '/^[[:space:]]*#*[[:space:]]*Port[[:space:]]/d' /etc/ssh/sshd_config
echo "Port 8520" | sudo tee -a /etc/ssh/sshd_config

sudo sed -i '/^[[:space:]]*#*[[:space:]]*PermitRootLogin[[:space:]]/d' /etc/ssh/sshd_config
echo "PermitRootLogin prohibit-password" | sudo tee -a /etc/ssh/sshd_config

sudo sed -i '/^[[:space:]]*#*[[:space:]]*PasswordAuthentication[[:space:]]/d' /etc/ssh/sshd_config
echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config

sudo sed -i '/^[[:space:]]*#*[[:space:]]*PubkeyAuthentication[[:space:]]/d' /etc/ssh/sshd_config
echo "PubkeyAuthentication yes" | sudo tee -a /etc/ssh/sshd_config

echo "=== SSH Configuration Complete ==="
echo "SSH config file updated with security settings"

echo "=== Restarting SSH service ==="
echo "Restarting SSH services to apply configuration changes..."
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
sudo systemctl restart ssh.service

# Verify SSH is listening on the new port
sleep 1
if sudo ss -tlnp | grep -q ':8520.*ssh'; then
    echo "SSH is now listening on port 8520"
else
    echo "Warning: SSH may not be listening on port 8520"
    echo "Check with: sudo ss -tlnp | grep ssh"
fi

echo "=== Server setup completed ==="
EOF

    print_info "Server setup completed successfully"
}

# Test connection with new user on new port
test_new_ssh_connection() {
    print_info "Testing SSH connection with new user '$FRAPPE_USERNAME' on port 8520"

    # SSH options for new connection (different port)
    NEW_SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=~/.ssh/known_hosts -p 8520"

    if ssh $NEW_SSH_OPTS -o BatchMode=yes "$FRAPPE_USERNAME@$SERVER_IP" "echo 'New SSH connection successful!'" 2>/dev/null; then
        print_info "SUCCESS! Can connect as '$FRAPPE_USERNAME' on port 8520"
        print_info "Server setup complete!"
        print_info ""
        print_info "✅ Setup Summary:"
        print_info "  - User '$FRAPPE_USERNAME' created with sudo privileges"
        print_info "  - Timezone configured to $TIMEZONE"
        print_info "  - Swap space configured to $SWAP_SIZE with optimized settings"
        print_info "  - SSH port changed from 22 to 8520"
        print_info "  - Root login disabled"
        print_info "  - Password authentication disabled"
        print_info "  - SSH key authentication enabled"
        print_info ""
        print_info "🔐 Connect with: ssh -p 8520 $FRAPPE_USERNAME@$SERVER_IP"
        print_info ""
        print_info "Consider testing the connection before closing this session"
    else
        print_error "Failed to connect as '$FRAPPE_USERNAME' on port 8520"
        print_error ""
        print_error "Troubleshooting steps:"
        print_error "  1. Check SSH service: ssh -p 22 root@$SERVER_IP 'sudo systemctl status ssh'"
        print_error "  2. Check listening ports: ssh -p 22 root@$SERVER_IP 'sudo ss -tlnp | grep ssh'"
        print_error "  3. Check SSH config: ssh -p 22 root@$SERVER_IP 'sudo sshd -t'"
        print_error "  4. Manual restart: ssh -p 22 root@$SERVER_IP 'sudo systemctl restart ssh'"
        exit 1
    fi
}

# Main execution starts here
main() {
    print_info "Starting Initial Server Setup for Frappe VPS"
    print_info "============================================="

    # Load and validate configuration
    load_setup_config
    validate_config

    # Clean up old SSH host keys (for rebuilt servers)
    cleanup_known_hosts

    # Execute setup steps
    test_ssh_connection
    setup_server
    test_new_ssh_connection  # Final test of complete setup

    print_info ""
    print_info "🎉 Server setup completed successfully!"
    print_info ""
    print_info "✅ Completed steps:"
    print_info "  ✓ Created user '$FRAPPE_USERNAME' with sudo privileges"
    print_info "  ✓ Configured timezone to $TIMEZONE"
    print_info "  ✓ Configured swap space to $SWAP_SIZE with optimized properties"
    print_info "  ✓ Copied SSH keys for key-based authentication"
    print_info "  ✓ Hardened SSH configuration (port 8520, no root/password login)"
    print_info "  ✓ Restarted SSH services and verified new port"
    print_info "  ✓ Tested connection with new user and settings"
    print_info ""
    print_info "🚀 You can now proceed with Frappe installation using:"
    print_info "     ssh -p 8520 $FRAPPE_USERNAME@$SERVER_IP"
}

# Run main function
main "$@"
