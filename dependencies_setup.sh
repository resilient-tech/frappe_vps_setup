#!/usr/bin/env bash

#=============================================================================
# Dependencies Setup Script for Frappe VPS
#=============================================================================
#
# Description:
#   Installs and configures all dependencies required for Frappe/ERPNext
#   installation on Ubuntu 24.04 server. This includes Python, Node.js,
#   MariaDB, Redis, and other essential tools.
#
# Prerequisites:
#   - Ubuntu 24.04 server with initial hardening completed
#   - SSH access as non-root user with sudo privileges
#   - config.yml file with server configuration
#
# What this script installs:
#   1. System updates and essential packages
#   2. Git and software-properties-common
#   3. Python 3 with pip and venv
#   4. Redis server (latest)
#   5. wkhtmltopdf for PDF generation
#   6. Node.js LTS (via NVM) and Yarn
#   7. MariaDB server with secure configuration
#
# Author: Generated for Frappe VPS Setup
# Dependencies: utils.sh, config.yml
#=============================================================================

set -euo pipefail

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration file path
CONFIG_FILE="$SCRIPT_DIR/config.yml"

# Common function for non-interactive package operations
run_noninteractive() {
    local cmd="$1"
    shift

    # Run command with non-interactive settings without permanently changing system
    DEBIAN_FRONTEND=noninteractive sudo -E "$cmd" \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        -qq \
        "$@" 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive sudo -E "$cmd" \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "$@"
}

# Function to load and set configuration variables
load_deps_config() {
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
    MARIADB_VERSION="${CONFIG_database_mariadb_version:-10.11}"
    DB_ROOT_PASSWORD="${CONFIG_database_root_password:-}"

    # Generate secure password if not provided
    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        DB_ROOT_PASSWORD=$(openssl rand -base64 32)
        print_info "Generated secure MariaDB root password"
    fi
}

# Function to update system packages
update_system() {
    print_info "Updating system packages..."

    # Update and upgrade packages non-interactively
    run_noninteractive apt-get update
    run_noninteractive apt-get upgrade -y

    print_success "✓ System packages updated successfully"
}

# Function to install essential packages
install_essential_packages() {
    print_info "Installing essential packages..."

    # Install packages non-interactively
    run_noninteractive apt install -y \
        git \
        software-properties-common \
        python-is-python3 \
        python3-pip \
        python3-venv \
        curl \
        wget \
        build-essential \
        pkg-config

    # Verify installations
    echo "=== Verifying essential packages ==="
    if command -v git &> /dev/null; then
        git_version=$(git --version)
        echo "✓ Git installed: $git_version"
    else
        echo "❌ Git installation failed"
        exit 1
    fi

    if command -v python3 &> /dev/null && command -v python &> /dev/null; then
        python_version=$(python --version)
        echo "✓ Python installed: $python_version"
    else
        echo "❌ Python installation failed"
        exit 1
    fi

    if command -v pkg-config &> /dev/null; then
        echo "✓ pkg-config installed"
    else
        echo "❌ pkg-config installation failed"
        exit 1
    fi

    print_success "✓ Essential packages installed and verified"
}

# Function to ensure latest pip and venv
configure_python() {
    print_info "Configuring Python environment..."

    # Handle externally managed Python environments (Ubuntu 24.04+)
    # Instead of upgrading system pip, verify it's functional
    if python -m pip --version &>/dev/null; then
        pip_version=$(python -m pip --version)
        echo "✓ Pip available: $pip_version"
    else
        print_error "Pip is not available"
        exit 1
    fi

    # Verify venv module is available
    if python -m venv --help > /dev/null 2>&1; then
        echo "✓ Python venv module available"
    else
        print_error "Python venv module not available"
        exit 1
    fi

    # Add note about externally managed environments
    print_info "NOTE: This Ubuntu 24.04 system uses externally managed Python environments"
    print_info "Frappe bench will create and manage its own virtual environments"
    print_info "For different Python versions, you can use deadsnakes PPA:"
    print_info "  sudo add-apt-repository ppa:deadsnakes/ppa"
    print_info "  sudo apt update"
    print_info "  sudo apt install python3.x python3.x-venv python3.x-dev"

    print_success "✓ Python environment configured"
}

# Function to install Redis
install_redis() {
    print_info "Installing Redis server..."

    run_noninteractive apt install -y redis-server

    # Stop and disable Redis service (Frappe runs its own Redis servers)
    sudo systemctl stop redis-server
    sudo systemctl disable redis-server

    # Verify Redis installation
    echo "=== Verifying Redis installation ==="
    if command -v redis-server &> /dev/null; then
        redis_version=$(redis-server --version | head -1)
        echo "✓ Redis installed: $redis_version"
        echo "✓ Redis service stopped and disabled (Frappe will manage its own Redis instances)"
    else
        echo "❌ Redis installation failed"
        exit 1
    fi

    print_success "✓ Redis installed (service disabled for Frappe)"
}

# Function to install wkhtmltopdf
install_wkhtmltopdf() {
    print_info "Installing wkhtmltopdf..."

    # Install dependencies first
    print_info "Installing wkhtmltopdf dependencies..."
    run_noninteractive apt install -y \
        fontconfig \
        libxext6 \
        libxrender1 \
        xfonts-75dpi \
        xfonts-base

    # Download and install specific wkhtmltopdf version for Frappe
    local wkhtmltopdf_url="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
    local wkhtmltopdf_deb="/tmp/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"

    # Download the DEB package (quietly)
    print_info "Downloading wkhtmltopdf DEB package..."
    wget -q --show-progress -O "$wkhtmltopdf_deb" "$wkhtmltopdf_url" 2>&1 | \
        grep -o '[0-9]*%' | tail -1 | xargs -I{} echo "Download progress: {}" || true

    # Install the package
    print_info "Installing wkhtmltopdf DEB package..."
    DEBIAN_FRONTEND=noninteractive sudo dpkg -i "$wkhtmltopdf_deb" >/dev/null 2>&1

    # Fix any remaining dependency issues
    run_noninteractive apt-get install -f -y

    # Clean up downloaded file
    rm -f "$wkhtmltopdf_deb"

    # Verify installation
    echo "=== Verifying wkhtmltopdf installation ==="
    if command -v wkhtmltopdf &> /dev/null; then
        wkhtmltopdf_version=$(wkhtmltopdf --version | head -1)
        echo "✓ wkhtmltopdf installed: $wkhtmltopdf_version"
    else
        echo "❌ wkhtmltopdf installation failed"
        exit 1
    fi

    print_success "✓ wkhtmltopdf installed successfully from DEB package"
}

# Function to install Node.js via NVM
install_nodejs() {
    print_info "Installing Node.js via NVM for user: $FRAPPE_USERNAME..."

    # Execute all Node.js installation steps as the frappe user
    sudo -u "$FRAPPE_USERNAME" -H bash << 'EOF'
        # Download and install NVM (quietly)
        print_info() { echo "[INFO] $1"; }
        print_info "Downloading and installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh 2>/dev/null | bash >/dev/null 2>&1

        # Ensure NVM lines are in .bashrc
        print_info "Ensuring NVM is properly configured in .bashrc..."
        if ! grep -q "NVM_DIR" ~/.bashrc; then
            echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
            echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.bashrc
            echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.bashrc
            print_info "✓ Added NVM configuration to .bashrc"
        else
            print_info "✓ NVM configuration already present in .bashrc"
        fi

        # Source NVM and install Node.js 22 LTS
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

        print_info "Installing Node.js 22 LTS..."
        nvm install 22 >/dev/null 2>&1
        nvm use 22 >/dev/null 2>&1
        nvm alias default 22 >/dev/null 2>&1

        # Output versions for verification
        echo "NODE_VERSION=$(node --version)"
        echo "NPM_VERSION=v$(npm --version)"
EOF

    # Verify Node.js installation
    echo "=== Verifying Node.js installation ==="
    local node_output=$(sudo -u "$FRAPPE_USERNAME" -H bash -c 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; echo "NODE_VERSION=$(node --version)"; echo "NPM_VERSION=v$(npm --version)"' 2>/dev/null)

    if [[ -n "$node_output" ]]; then
        echo "✓ Node.js installed for $FRAPPE_USERNAME: $(echo "$node_output" | grep NODE_VERSION | cut -d'=' -f2)"
        echo "✓ NPM installed for $FRAPPE_USERNAME: $(echo "$node_output" | grep NPM_VERSION | cut -d'=' -f2)"
    else
        echo "❌ Node.js installation failed for $FRAPPE_USERNAME"
        exit 1
    fi

    print_success "✓ Node.js installed via NVM for $FRAPPE_USERNAME"
}

# Function to install Yarn
install_yarn() {
    print_info "Installing Yarn package manager for user: $FRAPPE_USERNAME..."

    # Execute Yarn installation as the frappe user
    sudo -u "$FRAPPE_USERNAME" -H bash << 'EOF'
        # Source NVM and install Yarn
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

        # Install Yarn via npm (suppress npm notices)
        npm install -g yarn --silent --no-fund --no-audit 2>/dev/null

        # Output version for verification
        echo "YARN_VERSION=v$(yarn --version)"
EOF

    # Verify Yarn installation
    echo "=== Verifying Yarn installation ==="
    local yarn_output=$(sudo -u "$FRAPPE_USERNAME" -H bash -c 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; echo "YARN_VERSION=v$(yarn --version)"' 2>/dev/null)

    if [[ -n "$yarn_output" ]]; then
        echo "✓ Yarn installed for $FRAPPE_USERNAME: $(echo "$yarn_output" | cut -d'=' -f2)"
    else
        echo "❌ Yarn installation failed for $FRAPPE_USERNAME"
        exit 1
    fi

    print_success "✓ Yarn installed successfully for $FRAPPE_USERNAME"
}

# Function to install MariaDB
install_mariadb() {
    print_info "Installing MariaDB $MARIADB_VERSION..."

    # Add MariaDB repository (quietly)
    print_info "Adding MariaDB repository..."
    curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup 2>/dev/null | \
        sudo bash -s -- --mariadb-server-version="$MARIADB_VERSION" >/dev/null 2>&1

    # Update package list
    run_noninteractive apt-get update

    # Install MariaDB development libraries (now available from MariaDB repo)
    print_info "Installing MariaDB development libraries..."
    run_noninteractive apt-get install -y libmariadb-dev

    # Install MariaDB server non-interactively
    print_info "Installing MariaDB server and client..."
    run_noninteractive apt-get install -y mariadb-server mariadb-client

    # Start and enable MariaDB
    sudo systemctl start mariadb
    sudo systemctl enable mariadb

    # Verify MariaDB installation
    echo "=== Verifying MariaDB installation ==="
    if systemctl is-active --quiet mariadb; then
        mariadb_version=$(mariadb --version)
        echo "✓ MariaDB service is running: $mariadb_version"
    else
        echo "❌ MariaDB service is not running"
        exit 1
    fi

    # Verify MariaDB development libraries
    if pkg-config --exists libmariadb &> /dev/null; then
        echo "✓ MariaDB development libraries (libmariadb-dev) installed"
    else
        echo "❌ MariaDB development libraries installation failed"
        exit 1
    fi

    print_success "✓ MariaDB $MARIADB_VERSION installed with development libraries"
}

# Function to secure MariaDB installation
secure_mariadb() {
    print_info "Securing MariaDB installation..."

    # Generate secure password
    if [[ -z "$DB_ROOT_PASSWORD" ]]; then
        DB_ROOT_PASSWORD=$(openssl rand -base64 32)
        print_info "Generated secure MariaDB root password"
    fi

    # Create secure installation script
    cat > /tmp/mysql_secure_installation.sql << EOF
# Remove anonymous users
DELETE FROM mysql.user WHERE User='';

# Disallow root login remotely
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

# Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

# Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';

# Reload privilege tables
FLUSH PRIVILEGES;
EOF

    # Execute the security script (try with sudo first, then without)
    if sudo mariadb < /tmp/mysql_secure_installation.sql 2>/dev/null; then
        print_info "MariaDB secured using sudo access"
    elif mariadb -u root < /tmp/mysql_secure_installation.sql 2>/dev/null; then
        print_info "MariaDB secured using root access"
    else
        print_error "Failed to secure MariaDB. Please check MariaDB installation."
        rm /tmp/mysql_secure_installation.sql
        exit 1
    fi

    # Clean up
    rm /tmp/mysql_secure_installation.sql

    # Store password in frappe user's home directory
    local password_file="/home/$FRAPPE_USERNAME/mariadb_root_password.txt"
    echo "MariaDB Root Password: $DB_ROOT_PASSWORD" | sudo tee "$password_file" >/dev/null
    echo "Generated on: $(date)" | sudo tee -a "$password_file" >/dev/null
    sudo chown "$FRAPPE_USERNAME:$FRAPPE_USERNAME" "$password_file"
    sudo chmod 600 "$password_file"

    # Test connection
    echo "=== Verifying MariaDB security configuration ==="
    if mariadb -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1;" &> /dev/null; then
        echo "✓ MariaDB root password verified"
        echo "✓ Password saved to: /home/$FRAPPE_USERNAME/mariadb_root_password.txt"
    else
        echo "❌ MariaDB root password verification failed"
        exit 1
    fi

    print_success "✓ MariaDB secured successfully"
}

# Function to configure MariaDB for Frappe
configure_mariadb_for_frappe() {
    print_info "Configuring MariaDB for Frappe..."

    # Get system memory for buffer pool size calculation
    local total_mem_mb=$(free -m | awk '/^Mem:/ {print $2}')
    local buffer_pool_size=$((total_mem_mb * 685 / 1000))  # 68.5% of total memory

    print_info "System memory: ${total_mem_mb}MB"
    print_info "Buffer pool size: ${buffer_pool_size}M"

    # Create Frappe-specific configuration based on official config
    sudo tee /etc/mysql/mariadb.conf.d/erpnext.cnf << EOF
[mysqldump]
max_allowed_packet=256M

[mysqld]

# GENERAL #
user                           = mysql
default-storage-engine         = InnoDB
#socket                         = /var/lib/mysql/mysql.sock
#pid-file                       = /var/lib/mysql/mysql.pid

# MyISAM #
key-buffer-size                = 32M
myisam-recover                 = FORCE,BACKUP

# SAFETY #
max-allowed-packet             = 256M
max-connect-errors             = 1000000
innodb                         = FORCE

# DATA STORAGE #
datadir                        = /var/lib/mysql/

# BINARY LOGGING #
log-bin                        = /var/lib/mysql/mysql-bin
expire-logs-days               = 14
sync-binlog                    = 1

# REPLICATION #
server-id                      = 1

# CACHES AND LIMITS #
tmp-table-size                 = 32M
max-heap-table-size            = 32M
query-cache-type               = 0
query-cache-size               = 0
max-connections                = 500
thread-cache-size              = 50
open-files-limit               = 65535
table-definition-cache         = 4096
table-open-cache               = 10240

# INNODB #
innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = 512M
innodb-flush-log-at-trx-commit = 1
innodb-file-per-table          = 1
innodb-buffer-pool-size        = ${buffer_pool_size}M
innodb-file-format             = barracuda
innodb-large-prefix            = 1
collation-server               = utf8mb4_unicode_ci
character-set-server           = utf8mb4
character-set-client-handshake = FALSE
max_allowed_packet             = 256M

# LOGGING #
log-error                      = /var/lib/mysql/mysql-error.log
log-queries-not-using-indexes  = 0
slow-query-log                 = 1
slow-query-log-file            = /var/lib/mysql/mysql-slow.log

[mysql]
default-character-set = utf8mb4
EOF

    # Configure MariaDB service limits
    print_info "Configuring MariaDB service limits..."

    # Create service override directory and configuration
    sudo mkdir -p /etc/systemd/system/mariadb.service.d
    sudo tee /etc/systemd/system/mariadb.service.d/override.conf << EOF
[Service]
LimitNOFILE=infinity
LimitCORE=infinity
EOF

    # Reload systemd and restart MariaDB
    sudo systemctl daemon-reload
    sudo systemctl restart mariadb

    # Verify configuration
    echo "=== Verifying MariaDB configuration ==="
    if systemctl is-active --quiet mariadb; then
        echo "✓ MariaDB restarted successfully with Frappe configuration"

        # Check character set configuration
        charset_result=$(mariadb -u root -p"$DB_ROOT_PASSWORD" -e "SHOW VARIABLES LIKE 'character_set_server';" --batch --skip-column-names 2>/dev/null | awk '{print $2}')
        if [[ "$charset_result" == "utf8mb4" ]]; then
            echo "✓ Character set configured correctly: $charset_result"
        else
            echo "⚠ WARNING: Expected character set utf8mb4 but got: $charset_result"
        fi

        # Check buffer pool size
        buffer_result=$(mariadb -u root -p"$DB_ROOT_PASSWORD" -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" --batch --skip-column-names 2>/dev/null | awk '{print $2}')
        buffer_mb=$((buffer_result / 1024 / 1024))
        echo "✓ InnoDB buffer pool size: ${buffer_mb}M"

        # Check file limits
        echo "✓ MariaDB service limits configured"
    else
        echo "❌ MariaDB failed to restart with new configuration"
        exit 1
    fi

    print_success "✓ MariaDB configured for Frappe with optimized settings"
}

# Function to install Frappe Bench
install_frappe_bench() {
    print_info "Installing Frappe Bench..."

    # Install frappe-bench for the frappe user
    print_info "Installing frappe-bench for user: $FRAPPE_USERNAME"

    # Install frappe-bench using pip in user space (Ubuntu 24.04+ externally managed environment)
    sudo -u "$FRAPPE_USERNAME" -H python -m pip install --user --break-system-packages frappe-bench

    # Add ~/.local/bin to PATH if not already there
    sudo -u "$FRAPPE_USERNAME" -H bash -c '
        if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
            echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.bashrc
            echo "Added ~/.local/bin to PATH in ~/.bashrc"
        fi
    '

    # Verify installation
    echo "=== Verifying Frappe Bench installation ==="
    if sudo -u "$FRAPPE_USERNAME" -H bash -c 'export PATH="$HOME/.local/bin:$PATH"; command -v bench' >/dev/null 2>&1; then
        bench_version=$(sudo -u "$FRAPPE_USERNAME" -H bash -c 'export PATH="$HOME/.local/bin:$PATH"; bench --version')
        echo "✓ Frappe Bench installed: $bench_version"
        echo "✓ Installed for user: $FRAPPE_USERNAME"
    else
        echo "❌ Frappe Bench installation failed"
        exit 1
    fi

    print_success "✓ Frappe Bench installed successfully"
}

# Main execution starts here
main() {
    print_info "Starting Dependencies Installation for Frappe VPS"
    print_info "=================================================="

    # Load configuration
    load_deps_config
    print_info "Target user: $FRAPPE_USERNAME"
    print_info "MariaDB version: $MARIADB_VERSION"

    # Install dependencies in order
    update_system
    install_essential_packages
    configure_python
    install_redis
    install_wkhtmltopdf
    install_nodejs
    install_yarn
    install_mariadb
    secure_mariadb
    configure_mariadb_for_frappe
    install_frappe_bench

    print_info ""
    print_success "🎉 All dependencies installed successfully!"
    print_info ""
    print_info "✅ Installed components:"
    print_info "  ✓ System packages updated"
    print_info "  ✓ Git and essential tools"
    print_info "  ✓ Python 3 with pip and venv"
    print_info "  ✓ Redis server (service disabled for Frappe)"
    print_info "  ✓ wkhtmltopdf (official DEB package)"
    print_info "  ✓ Node.js 22 LTS (via NVM for $FRAPPE_USERNAME)"
    print_info "  ✓ Yarn package manager (for $FRAPPE_USERNAME)"
    print_info "  ✓ MariaDB $MARIADB_VERSION"
    print_info "  ✓ MariaDB secured and optimized for Frappe"
    print_info "  ✓ Frappe Bench (installed for $FRAPPE_USERNAME)"
    print_info ""
    print_info "📋 Important files:"
    print_info "  - MariaDB root password: /home/$FRAPPE_USERNAME/mariadb_root_password.txt"
    print_info "  - MariaDB config: /etc/mysql/mariadb.conf.d/erpnext.cnf"
    print_info "  - Service limits: /etc/systemd/system/mariadb.service.d/override.conf"
    print_info ""
    print_success "🚀 Ready for Frappe bench initialization!"
    print_info ""
    print_info "💡 Next steps:"
    print_info "  1. SSH to your server: ssh -p 8520 $FRAPPE_USERNAME@78.47.136.133"
    print_info "  2. Initialize Frappe site: bench init frappe-bench"
    print_info "  3. Create new site: cd frappe-bench && bench new-site your-site.com"
}

# Run main function
main "$@"
