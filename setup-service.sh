#!/bin/bash
#
# WiFi Keep-Alive Service Installer
# ==================================
#
# Installs wifi-keep-alive.py as a systemd service on Raspberry Pi OS Bookworm+.
#
# Features:
#   - Creates/uses a dedicated system user for the service
#   - Installs Python script to /opt/wifi-keep-alive/
#   - Creates and enables a systemd service with security hardening
#
# Usage:
#   sudo ./setup-service.sh              # Install
#   sudo ./setup-service.sh --uninstall  # Uninstall
#   sudo ./setup-service.sh --help       # Help
#
# Requirements: Raspberry Pi OS Bookworm (12+), root privileges, Python 3.6+
#

set -e  # Exit on any error

# =============================================================================
# Configuration
# =============================================================================

readonly SERVICE_NAME="wifi-keep-alive"
readonly INSTALL_DIR="/opt/${SERVICE_NAME}"
readonly SCRIPT_NAME="wifi-keep-alive.py"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
readonly DEFAULT_USER="wifi-keepalive"
readonly DEFAULT_INTERVAL=60

# =============================================================================
# Output Helpers
# =============================================================================

print_info()    { echo -e "\e[34m[INFO]\e[0m $1"; }
print_success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
print_warning() { echo -e "\e[33m[WARNING]\e[0m $1"; }
print_error()   { echo -e "\e[31m[ERROR]\e[0m $1"; }

# =============================================================================
# Validation Functions
# =============================================================================

check_root() {
    [[ $EUID -eq 0 ]] || { print_error "This script must be run as root (use sudo)"; exit 1; }
}

check_system() {
    print_info "Checking system compatibility..."

    # Verify os-release exists and source it
    [[ -f /etc/os-release ]] || { print_error "Cannot determine OS version"; exit 1; }
    source /etc/os-release

    # Require Bookworm (version 12) or newer
    if [[ -n "$VERSION_ID" && "$VERSION_ID" -lt 12 ]]; then
        print_error "Requires Raspberry Pi OS Bookworm (12) or higher. Detected: $VERSION_ID ($VERSION_CODENAME)"
        exit 1
    fi

    # Verify Python 3 is available
    command -v python3 &>/dev/null || { print_error "Python 3 is required but not installed"; exit 1; }

    print_success "System check passed: $PRETTY_NAME"
}

user_exists() { id "$1" &>/dev/null; }

# =============================================================================
# Service User Management
# =============================================================================

create_service_user() {
    local username="$1"

    if user_exists "$username"; then
        print_info "User '$username' already exists"
    else
        print_info "Creating system user '$username'..."
        # Create system user: no home, no login shell, with matching group
        useradd --system --shell /usr/sbin/nologin --no-create-home \
                --user-group --comment "WiFi Keep-Alive Service User" "$username" \
            || { print_error "Failed to create user '$username'"; exit 1; }
        print_success "User '$username' created"
    fi

    # Ensure user and group exist (handles edge cases)
    user_exists "$username" || { print_error "User '$username' verification failed"; exit 1; }
    
    if ! getent group "$username" &>/dev/null; then
        print_warning "Creating missing group '$username'..."
        groupadd --system "$username" 2>/dev/null || true
        usermod -g "$username" "$username" 2>/dev/null || true
    fi
}

# =============================================================================
# Configuration Prompts
# =============================================================================

get_configuration() {
    echo ""
    echo "=========================================="
    echo "  WiFi Keep-Alive Service Configuration"
    echo "=========================================="
    echo ""

    # Service user (with validation)
    read -p "Service user [$DEFAULT_USER]: " SERVICE_USER
    SERVICE_USER="${SERVICE_USER:-$DEFAULT_USER}"
    [[ "$SERVICE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] \
        || { print_error "Invalid username. Use lowercase letters, numbers, underscores, hyphens."; exit 1; }

    # Target host (required)
    while [[ -z "$TARGET_HOST" ]]; do
        read -p "Target host to ping (IP or hostname): " TARGET_HOST
        [[ -z "$TARGET_HOST" ]] && print_warning "Target host is required"
    done

    # Ping interval (with validation)
    read -p "Ping interval in seconds [$DEFAULT_INTERVAL]: " PING_INTERVAL
    PING_INTERVAL="${PING_INTERVAL:-$DEFAULT_INTERVAL}"
    [[ "$PING_INTERVAL" =~ ^[0-9]+$ && "$PING_INTERVAL" -ge 1 ]] \
        || { print_error "Interval must be a positive integer"; exit 1; }

    # Confirmation
    echo ""
    print_info "Configuration: User=$SERVICE_USER, Host=$TARGET_HOST, Interval=${PING_INTERVAL}s"
    echo ""
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    [[ "${CONFIRM:-Y}" =~ ^[Yy]$ ]] || { print_info "Installation cancelled"; exit 0; }
}

# =============================================================================
# Installation Functions
# =============================================================================

install_script() {
    print_info "Installing script to $INSTALL_DIR..."

    # Locate source script
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ -f "$script_dir/$SCRIPT_NAME" ]] \
        || { print_error "Cannot find $SCRIPT_NAME in $script_dir"; exit 1; }

    # Create directory and copy script with proper ownership/permissions
    mkdir -p "$INSTALL_DIR"
    cp "$script_dir/$SCRIPT_NAME" "$INSTALL_DIR/"
    
    # Set ownership (root:service_group) and permissions (rwxr-xr-x)
    chown -R root:"$SERVICE_USER" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR" "$INSTALL_DIR/$SCRIPT_NAME"

    print_success "Script installed to $INSTALL_DIR/$SCRIPT_NAME"
}

create_service() {
    print_info "Creating systemd service..."

    cat > "$SERVICE_FILE" << EOF
# WiFi Keep-Alive Service - Generated $(date +%Y-%m-%d)
# Config: Host=$TARGET_HOST, Interval=${PING_INTERVAL}s, User=$SERVICE_USER

[Unit]
Description=WiFi Keep-Alive Service
Documentation=https://github.com/EnvillePlease/wifi-keep-alive
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
ExecStart=/usr/bin/python3 $INSTALL_DIR/$SCRIPT_NAME $TARGET_HOST --interval $PING_INTERVAL

# Network capability for ICMP ping without root
AmbientCapabilities=CAP_NET_RAW

# Restart on failure with 10s delay
Restart=on-failure
RestartSec=10

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Logging to journald
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_FILE"
    print_success "Service file created: $SERVICE_FILE"
}

enable_service() {
    print_info "Enabling and starting service..."

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    # Verify startup (brief wait for service to initialize)
    sleep 1
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Service is running"
    else
        print_warning "Service may not have started. Check: sudo systemctl status $SERVICE_NAME"
    fi
}

show_post_install_info() {
    cat << EOF

==========================================
  Installation Complete!
==========================================

Useful commands:
  sudo systemctl status $SERVICE_NAME     # Check status
  sudo journalctl -u $SERVICE_NAME -f     # View logs
  sudo systemctl restart $SERVICE_NAME    # Restart
  sudo systemctl stop $SERVICE_NAME       # Stop
  sudo systemctl disable $SERVICE_NAME    # Disable auto-start

Config: $SERVICE_FILE
Script: $INSTALL_DIR/$SCRIPT_NAME

Uninstall: sudo $0 --uninstall

EOF
}

# =============================================================================
# Uninstallation
# =============================================================================

uninstall() {
    print_info "Uninstalling WiFi Keep-Alive service..."

    # Extract service user from existing config (if available)
    local service_user="$DEFAULT_USER"
    if [[ -f "$SERVICE_FILE" ]]; then
        local extracted_user
        extracted_user=$(grep -oP '^User=\K.*' "$SERVICE_FILE" 2>/dev/null || true)
        [[ -n "$extracted_user" ]] && service_user="$extracted_user"
    fi

    # Stop and disable service (ignore errors if not running/enabled)
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    # Remove files
    [[ -f "$SERVICE_FILE" ]] && rm -f "$SERVICE_FILE" && print_info "Removed service file"
    [[ -d "$INSTALL_DIR" ]] && rm -rf "$INSTALL_DIR" && print_info "Removed installation directory"

    systemctl daemon-reload

    # Optionally remove service user
    echo ""
    read -p "Remove service user '$service_user'? [y/N]: " REMOVE_USER
    if [[ "$REMOVE_USER" =~ ^[Yy]$ ]] && user_exists "$service_user"; then
        userdel "$service_user" 2>/dev/null || true
        print_success "User '$service_user' removed"
    fi

    print_success "Uninstallation complete"
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  WiFi Keep-Alive Service Installer"
    echo "=========================================="

    case "${1:-}" in
        --uninstall|-u)
            check_root
            uninstall
            ;;
        --help|-h)
            echo "Usage: sudo $0 [--uninstall|-u] [--help|-h]"
            echo "  --uninstall, -u  Remove service and files"
            echo "  --help, -h       Show this help"
            ;;
        *)
            check_root
            check_system
            get_configuration
            create_service_user "$SERVICE_USER"
            install_script
            create_service
            enable_service
            show_post_install_info
            ;;
    esac
}

main "$@"
