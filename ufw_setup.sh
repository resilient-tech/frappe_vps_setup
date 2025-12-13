#!/usr/bin/env bash

#=============================================================================
# UFW Firewall Configuration Script for Frappe VPS
#=============================================================================
#
# Description:
#   Configures UFW (Uncomplicated Firewall) with rules for Frappe/ERPNext
#   hosting. Opens required ports for SSH, HTTP, HTTPS, and bench serve.
#
# Prerequisites:
#   - Ubuntu 24.04 server
#   - Initial server setup completed
#
# What this script does:
#   1. Installs UFW if not already installed
#   2. Configures firewall rules for:
#      - Port 8520: SSH (custom port)
#      - Port 80: HTTP
#      - Port 443: HTTPS
#   3. Enables UFW
#   4. Displays firewall status
#
# Author: Generated for Frappe VPS Setup
# Dependencies: utils.sh
#=============================================================================

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're running from temp directory (remote execution)
if [[ "$SCRIPT_DIR" == *"frappe_ufw_temp"* ]]; then
    source "$SCRIPT_DIR/utils.sh"
else
    # Local execution - use script directory
    source "$SCRIPT_DIR/utils.sh"
fi

# Function to check if UFW is installed
check_ufw_installed() {
    print_info "Checking UFW installation..."

    if ! command -v ufw >/dev/null 2>&1; then
        print_info "UFW not found, installing..."
        sudo apt update -qq
        sudo apt install -y ufw
        print_success "✓ UFW installed successfully"
    else
        print_info "✓ UFW already installed"
    fi
}

# Function to configure UFW rules
configure_ufw() {
    print_info "Configuring UFW firewall rules..."

    # Reset UFW to default settings (removes all rules)
    print_info "Resetting UFW to default settings..."
    sudo ufw --force reset

    # Set default policies
    print_info "Setting default policies (deny incoming, allow outgoing)..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Allow SSH on port 8520 (custom SSH port)
    print_info "Allowing SSH on port 8520..."
    sudo ufw allow 8520/tcp comment 'SSH custom port'

    # Allow HTTP
    print_info "Allowing HTTP on port 80..."
    sudo ufw allow 80/tcp comment 'HTTP'

    # Allow HTTPS
    print_info "Allowing HTTPS on port 443..."
    sudo ufw allow 443/tcp comment 'HTTPS'

    print_success "✓ UFW rules configured"
}

# Function to enable UFW
enable_ufw() {
    print_info "Enabling UFW..."

    # Enable UFW (non-interactive)
    sudo ufw --force enable

    # Enable UFW to start on boot
    sudo systemctl enable ufw

    print_success "✓ UFW enabled and set to start on boot"
}

# Function to display UFW status
show_ufw_status() {
    print_info "Current UFW status:"
    echo ""
    sudo ufw status verbose
    echo ""
    print_success "✓ UFW configuration complete"
}

# Main execution
main() {
    print_info "Starting UFW firewall configuration..."
    echo ""

    # Ensure we have sudo privileges
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        print_error "Please run with: sudo ./ufw_setup.sh"
        exit 1
    fi

    check_ufw_installed
    configure_ufw
    enable_ufw
    show_ufw_status

    echo ""
    print_success "====================================="
    print_success "UFW Firewall Setup Complete!"
    print_success "====================================="
    echo ""
    print_info "Firewall rules:"
    print_info "  - Port 8520: SSH (custom port)"
    print_info "  - Port 80: HTTP"
    print_info "  - Port 443: HTTPS"
    echo ""
    print_info "To check firewall status: sudo ufw status"
    print_info "To reload firewall: sudo ufw reload"
    echo ""
}

# Run main function
main
