#!/usr/bin/env bash

#=============================================================================
# Frappe Bench Initialization Script
#=============================================================================
#
# Description:
#   Initializes Frappe bench and creates the first site. This script should
#   be run after all dependencies have been installed successfully.
#
# Prerequisites:
#   - Dependencies setup completed (dependencies_setup.sh)
#   - MariaDB configured and secured
#   - All required tools installed (Node.js, Python, etc.)
#   - config.yml with site configuration
#
# What this script does:
#   1. Loads configuration from config.yml
#   2. Initializes Frappe bench with specified version
#   3. Configures MariaDB credentials globally
#   4. Creates the first Frappe site
#   5. Installs ERPNext if configured
#   6. Saves admin credentials to file
#
# Author: Generated for Frappe VPS Setup
# Dependencies: utils.sh, config.yml
#=============================================================================

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're running from temp directory (remote execution)
# If so, use the temp directory for config and utils files
if [[ "$SCRIPT_DIR" == *"frappe_bench_init_temp"* ]]; then
    source "$SCRIPT_DIR/utils.sh"
    CONFIG_FILE="$SCRIPT_DIR/config.yml"
else
    # Local execution - use script directory
    source "$SCRIPT_DIR/utils.sh"
    CONFIG_FILE="$SCRIPT_DIR/config.yml"
fi

# Function to load bench configuration
load_bench_config() {
    # Install yq if not available (required for YAML parsing)
    if ! command -v yq >/dev/null 2>&1; then
        print_info "Installing yq for YAML configuration parsing..."
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
        print_info "✓ yq installed successfully"
    fi

    load_config "$CONFIG_FILE"

    # Set configuration variables
    FRAPPE_USERNAME="${CONFIG_frappe_username:-resilient}"
    FRAPPE_VERSION="${CONFIG_frappe_version:-develop}"
    BENCH_NAME="${CONFIG_frappe_bench_name:-resilient-bench}"
    SITE_NAME="${CONFIG_frappe_site_name:-}"
    ADMIN_PASSWORD="${CONFIG_frappe_admin_password:-}"
    INSTALL_ERPNEXT="${CONFIG_frappe_install_erpnext:-true}"

    # Validate required configuration
    if [[ -z "$SITE_NAME" ]]; then
        print_error "Site name is required but not found in configuration"
        print_error "Please set 'frappe.site_name' in config.yml"
        exit 1
    fi

    # Generate admin password if not provided
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-16)
        print_info "Generated secure admin password"
    fi

    # Load MariaDB root password
    local mariadb_password_file="/home/$FRAPPE_USERNAME/mariadb_root_password.txt"
    if [[ -f "$mariadb_password_file" ]]; then
        DB_ROOT_PASSWORD=$(grep "MariaDB Root Password:" "$mariadb_password_file" | cut -d' ' -f4-)
        print_info "Loaded MariaDB root password from file"
    else
        print_error "MariaDB password file not found: $mariadb_password_file"
        print_error "Please run dependencies setup first"
        exit 1
    fi
}

# Function to setup environment and check prerequisites
setup_environment() {
    print_info "Setting up Frappe environment..."

    # Ensure we're running as the frappe user
    if [[ "$(whoami)" != "$FRAPPE_USERNAME" ]]; then
        print_error "This script must be run as the $FRAPPE_USERNAME user"
        print_error "Please SSH as: ssh -p 8520 $FRAPPE_USERNAME@<server-ip>"
        exit 1
    fi

    # Setup PATH for bench and Node.js
    export PATH="$HOME/.local/bin:$PATH"
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # Verify prerequisites
    echo "=== Verifying Prerequisites ==="

    if ! command -v bench >/dev/null 2>&1; then
        echo "❌ Frappe bench not found"
        exit 1
    fi
    echo "✓ Frappe bench available: $(bench --version)"

    if ! command -v node >/dev/null 2>&1; then
        echo "❌ Node.js not found"
        exit 1
    fi
    echo "✓ Node.js available: $(node --version)"

    if ! command -v yarn >/dev/null 2>&1; then
        echo "❌ Yarn not found"
        exit 1
    fi
    echo "✓ Yarn available: v$(yarn --version)"

    if ! command -v mariadb >/dev/null 2>&1; then
        echo "❌ MariaDB client not found"
        exit 1
    fi
    echo "✓ MariaDB client available"

    print_success "✓ All prerequisites verified"
}

# Function to initialize Frappe bench
initialize_bench() {
    print_info "Initializing Frappe bench..."
    print_info "Version: $FRAPPE_VERSION"
    print_info "This may take several minutes..."

    # Initialize bench with verbose output and no backups
    print_info "Running: bench init --verbose --no-backups --frappe-branch $FRAPPE_VERSION $BENCH_NAME"

    if bench init --verbose --no-backups --frappe-branch "$FRAPPE_VERSION" "$BENCH_NAME"; then
        print_success "✓ Frappe bench initialized successfully"
    else
        print_error "❌ Frappe bench initialization failed"
        exit 1
    fi

    # Change to bench directory
    cd "$BENCH_NAME" || {
        print_error "Failed to change to $BENCH_NAME directory"
        exit 1
    }

    print_success "✓ Changed to $BENCH_NAME directory"
}

# Function to configure database credentials
configure_database() {
    print_info "Configuring database credentials..."

    # Set MariaDB root password in common_site_config
    if bench set-config -g root_password "$DB_ROOT_PASSWORD"; then
        echo "✓ MariaDB root password configured globally"
    else
        print_error "Failed to set MariaDB root password"
        exit 1
    fi

    # Set admin password in common_site_config
    if bench set-config -g admin_password "$ADMIN_PASSWORD"; then
        echo "✓ Admin password configured globally"
    else
        print_error "Failed to set admin password"
        exit 1
    fi

    print_success "✓ Database credentials configured"
}

# Function to start bench services
start_bench() {
    print_info "Starting Frappe bench services..."
    print_info "This is required for app installation and site operations"

    # Start bench in background
    bench start > /dev/null 2>&1 &
    local bench_pid=$!
    echo "$bench_pid" > /tmp/bench_init.pid

    # Wait a moment for services to initialize
    sleep 5

    # Check if bench is running
    if ps -p "$bench_pid" > /dev/null 2>&1; then
        print_success "✓ Frappe bench services started (PID: $bench_pid)"
    else
        print_error "❌ Bench services failed to start properly"
        exit 1
    fi
}

# Function to stop bench services
stop_bench() {
    print_info "Stopping Frappe bench services..."

    if [[ -f /tmp/bench_init.pid ]]; then
        local bench_pid=$(cat /tmp/bench_init.pid)

        if ps -p "$bench_pid" > /dev/null 2>&1; then
            if kill "$bench_pid" 2>/dev/null; then
                print_success "✓ Bench services stopped (PID: $bench_pid)"
            else
                print_info "Using fallback method to stop bench..."
                pkill -f "bench start" 2>/dev/null || true
                print_success "✓ Bench services stopped"
            fi
        else
            print_info "Bench services already stopped"
        fi

        rm -f /tmp/bench_init.pid
    else
        print_info "Bench services were not tracked, attempting to stop any running bench processes..."
        pkill -f "bench start" 2>/dev/null || true
        print_success "✓ Any running bench services stopped"
    fi
}

# Function to get ERPNext app
get_erpnext_app() {
    if [[ "$INSTALL_ERPNEXT" == "true" ]]; then
        print_info "Getting ERPNext application..."
        print_info "Running: bench get-app --resolve-deps erpnext"

        if bench get-app --resolve-deps erpnext; then
            print_success "✓ ERPNext app downloaded successfully"
        else
            print_error "❌ Failed to get ERPNext app"
            exit 1
        fi
    else
        print_info "Skipping ERPNext app download (install_erpnext: false)"
    fi
}

# Function to create Frappe site
create_site() {
    print_info "Creating Frappe site: $SITE_NAME"
    print_info "⚠️  NOTE: Backups are DISABLED (--no-backups flag used)"
    print_info "    You will need to implement your own backup strategy"

    # Create site with verbose output and admin password
    local create_cmd="bench new-site --verbose --admin-password '$ADMIN_PASSWORD'"

    # Add ERPNext installation if configured
    if [[ "$INSTALL_ERPNEXT" == "true" ]]; then
        create_cmd="$create_cmd --install-app erpnext"
        print_info "ERPNext will be installed during site creation"
    fi

    create_cmd="$create_cmd '$SITE_NAME'"

    print_info "Running: $create_cmd"

    if eval "$create_cmd"; then
        print_success "✓ Site '$SITE_NAME' created successfully"
        if [[ "$INSTALL_ERPNEXT" == "true" ]]; then
            print_success "✓ ERPNext installed on site"
        fi
    else
        print_error "❌ Site creation failed"
        exit 1
    fi
}

# Function to save credentials
save_credentials() {
    print_info "Saving admin credentials..."

    # Create credentials file in home directory
    local credentials_file="$HOME/frappe_admin_credentials.txt"

    cat > "$credentials_file" << EOF
Frappe Site Administrator Credentials
====================================

Site: $SITE_NAME
Administrator Username: Administrator
Administrator Password: $ADMIN_PASSWORD

Generated on: $(date)
Frappe Version: $FRAPPE_VERSION
ERPNext Installed: $INSTALL_ERPNEXT

⚠️  IMPORTANT SECURITY NOTES:
- Keep this password file secure
- Change the default Administrator password after first login
- This file contains sensitive information - protect it appropriately

🌐 Access your site:
- Development: http://$SITE_NAME:8000
- Production (after SSL): https://$SITE_NAME

📋 Backup Information:
- Backups are DISABLED by default (--no-backups flag used)
- You need to implement your own backup strategy
- Consider setting up automated backups for production use
EOF

    # Set secure permissions
    chmod 600 "$credentials_file"

    echo "✓ Credentials saved to: $credentials_file"
    echo "✓ File permissions set to 600 (owner read/write only)"

    print_success "✓ Admin credentials saved securely"
}

# Function to display completion summary
show_completion_summary() {
    print_info ""
    print_success "🎉 Frappe bench initialization completed successfully!"
    print_info ""
    print_info "✅ Summary:"
    print_info "  ✓ Frappe bench initialized (version: $FRAPPE_VERSION)"
    if [[ "$INSTALL_ERPNEXT" == "true" ]]; then
        print_info "  ✓ ERPNext app downloaded with dependencies"
    fi
    print_info "  ✓ Database credentials configured"
    print_info "  ✓ Site created: $SITE_NAME"
    if [[ "$INSTALL_ERPNEXT" == "true" ]]; then
        print_info "  ✓ ERPNext installed on site"
    fi
    print_info "  ✓ Admin credentials saved to ~/frappe_admin_credentials.txt"
    print_info ""
    print_info "📋 Important Files:"
    print_info "  - Admin credentials: ~/frappe_admin_credentials.txt"
    print_info "  - MariaDB password: ~/mariadb_root_password.txt"
    print_info "  - Bench directory: ~/$BENCH_NAME"
    print_info ""
    print_info "⚠️  Backup Warning:"
    print_info "  - Backups are DISABLED (--no-backups flag used)"
    print_info "  - Implement your own backup strategy for production"
    print_info ""
    print_info "🚀 Next Steps:"
    print_info "  1. Start development server: cd $BENCH_NAME && bench start"
    print_info "  2. Access your site: http://$SITE_NAME:8000"
    print_info "  3. Login with Administrator / <your-admin-password>"
    print_info ""
    if [[ "$INSTALL_ERPNEXT" == "true" ]]; then
        print_info "💡 ERPNext is installed and ready to use!"
    else
        print_info "💡 To install ERPNext later: bench --site $SITE_NAME install-app erpnext"
    fi
    print_info ""
    print_info "ℹ️  Note: Bench services have been stopped after setup completion."
    print_info "   Start them manually when ready to develop or test your site."
    print_info ""
    print_success "🏆 Frappe setup is complete and ready for development!"
}

# Main execution
main() {
    print_info "Starting Frappe Bench Initialization"
    print_info "===================================="

    # Load configuration
    load_bench_config
    print_info "Bench name: $BENCH_NAME"
    print_info "Target site: $SITE_NAME"
    print_info "Frappe version: $FRAPPE_VERSION"
    print_info "Install ERPNext: $INSTALL_ERPNEXT"

    # Setup and verify environment
    setup_environment

    # Initialize bench and configure database
    initialize_bench
    configure_database

    # Start bench services (required for app installation)
    start_bench

    # Install ERPNext app and create site
    get_erpnext_app
    create_site
    save_credentials

    # Stop bench services after setup
    stop_bench

    show_completion_summary
}

# Run main function
main "$@"
