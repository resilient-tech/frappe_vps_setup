#!/usr/bin/env bash

# utils.sh - Common utility functions for Frappe VPS Setup

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if yq is installed and install if needed
check_yq_dependency() {
    if ! command -v yq >/dev/null 2>&1; then
        print_error "yq is required but not installed!"
        print_error ""
        print_error "Install yq on Ubuntu/Debian with:"
        print_error "  # Method 1: Direct download (recommended)"
        print_error "  sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        print_error "  sudo chmod +x /usr/local/bin/yq"
        print_error ""
        print_error "  # Method 2: Using snap (fallback):"
        print_error "  sudo snap install yq"
        print_error ""
        print_error "Then run this script again."
        exit 1
    fi
}

# Function to parse YAML using yq
parse_yaml() {
    local file="$1"
    local prefix="$2"

    # Parse YAML and create bash variables using yq
    eval "$(yq eval '
        .. | select(type == "!!str" or type == "!!int" or type == "!!bool") |
        path as $p |
        . as $v |
        ($p | join("_")) as $key |
        "'"$prefix"'" + $key + "=\"" + ($v | tostring) + "\""
    ' "$file")"
}

# Function to load configuration from YAML file
load_config() {
    local config_file="$1"

    print_info "Loading configuration from $config_file"

    # Check yq dependency first
    check_yq_dependency

    if [[ ! -f "$config_file" ]]; then
        print_error "Configuration file not found: $config_file"
        print_error "Please create config.yml with required settings."
        exit 1
    fi

    # Parse YAML and create variables
    parse_yaml "$config_file" "CONFIG_"
}

# Function to validate IP address format
validate_ip_address() {
    local ip="$1"

    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    return 0
}
