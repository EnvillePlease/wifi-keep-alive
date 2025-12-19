#!/bin/bash
#
# WiFi Keep-Alive Service Installer
# ==================================
#
# This script installs the wifi-keep-alive.py script as a systemd service
# on a Raspberry Pi running Raspberry Pi OS Bookworm or higher.
#
# Features:
# ---------
#   - Creates or uses an existing system user for running the service
#   - Installs the Python script to /opt/wifi-keep-alive/
#   - Creates and enables a systemd service
#   - Prompts for host and interval configuration
#
# Usage:
# ------
#   sudo ./setup-service.sh
#
# Requirements:
# -------------
#   - Raspberry Pi OS Bookworm or higher
#   - Root/sudo privileges
#   - Python 3.6+
#
# Uninstall:
# ----------
#   sudo ./setup-service.sh --uninstall
#

set -e  # Exit on any error

# =============================================================================
# Configuration Variables
# =============================================================================

SERVICE_NAME="wifi-keep-alive"
INSTALL_DIR="/opt/${SERVICE_NAME}"
SCRIPT_NAME="wifi-keep-alive.py"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DEFAULT_USER="wifi-keepalive"
DEFAULT_INTERVAL=60

# =============================================================================
# Helper Functions
# =============================================================================

# Print colored output for better visibility
print_info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

print_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1"
}

print_warning() {
    echo -e "\e[33m[WARNING]\e[0m $1"
}

print_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Check if script is running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if running on a compatible system
check_system() {
    print_info "Checking system compatibility..."

    # Check for Raspberry Pi OS
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine OS version"
        exit 1
    fi

    # Source the os-release file to get VERSION_CODENAME
    source /etc/os-release

    # Check for Bookworm or newer (version 12+)
    if [[ -n "$VERSION_ID" ]]; then
        if [[ "$VERSION_ID" -lt 12 ]]; then
            print_error "This script requires Raspberry Pi OS Bookworm (version 12) or higher"
            print_error "Detected version: $VERSION_ID ($VERSION_CODENAME)"
            exit 1
        fi
    fi

    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi

    print_success "System check passed: $PRETTY_NAME"
}

# Check if a user exists
user_exists() {
    id "$1" &>/dev/null
}

# Create a system user for the service
create_service_user() {
    local username="$1"

    if user_exists "$username"; then
        print_info "User '$username' already exists"
    else
        print_info "Creating system user '$username'..."

        # Create system user with:
        #   --system     : Create a system account (no aging, UID in system range)
        #   --shell      : Set shell to nologin (no interactive login)
        #   --no-create-home : Don't create a home directory
        #   --group      : Create a group with the same name
        if ! useradd \
            --system \
            --shell /usr/sbin/nologin \
            --no-create-home \
            --group \
            --comment "WiFi Keep-Alive Service User" \
            "$username" 2>/dev/null; then
            print_error "Failed to create user '$username'"
            exit 1
        fi

        print_success "User '$username' created successfully"
    fi

    # Verify the user exists and is valid
    if ! user_exists "$username"; then
        print_error "User '$username' does not exist after creation attempt"
        exit 1
    fi

    # Verify the user's group exists
    if ! getent group "$username" &>/dev/null; then
        print_warning "Group '$username' does not exist, creating it..."
        groupadd --system "$username" 2>/dev/null || true
        usermod -g "$username" "$username" 2>/dev/null || true
    fi

    print_info "Verified user '$username' is ready for service"
}

# Prompt user for configuration values
get_configuration() {
    echo ""
    echo "=========================================="
    echo "  WiFi Keep-Alive Service Configuration"
    echo "=========================================="
    echo ""

    # Get service user
    read -p "Service user [$DEFAULT_USER]: " SERVICE_USER
    SERVICE_USER="${SERVICE_USER:-$DEFAULT_USER}"

    # Validate username format
    if [[ ! "$SERVICE_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        print_error "Invalid username format. Use lowercase letters, numbers, underscores, and hyphens."
        exit 1
    fi

    # Get target host (required)
    while [[ -z "$TARGET_HOST" ]]; do
        read -p "Target host to ping (IP or hostname): " TARGET_HOST
        if [[ -z "$TARGET_HOST" ]]; then
            print_warning "Target host is required"
        fi
    done

    # Get ping interval
    read -p "Ping interval in seconds [$DEFAULT_INTERVAL]: " PING_INTERVAL
    PING_INTERVAL="${PING_INTERVAL:-$DEFAULT_INTERVAL}"

    # Validate interval is a positive integer
    if ! [[ "$PING_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$PING_INTERVAL" -lt 1 ]]; then
        print_error "Interval must be a positive integer"
        exit 1
    fi

    echo ""
    print_info "Configuration summary:"
    echo "  Service User: $SERVICE_USER"
    echo "  Target Host:  $TARGET_HOST"
    echo "  Interval:     $PING_INTERVAL seconds"
    echo ""

    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM="${CONFIRM:-Y}"
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
}

# Install the Python script to the installation directory
install_script() {
    print_info "Installing script to $INSTALL_DIR..."

    # Create installation directory
    mkdir -p "$INSTALL_DIR"

    # Get the directory where this setup script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Check if the Python script exists
    if [[ ! -f "$SCRIPT_DIR/$SCRIPT_NAME" ]]; then
        print_error "Cannot find $SCRIPT_NAME in $SCRIPT_DIR"
        exit 1
    fi

    # Copy the script
    cp "$SCRIPT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/"

    # Set ownership: root owns the file, service user's group has access
    # This allows the service user to read and execute the script
    chown root:"$SERVICE_USER" "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Set permissions:
    #   - Owner (root): read, write, execute (7)
    #   - Group (service user): read, execute (5)
    #   - Others: read, execute (5)
    chmod 755 "$INSTALL_DIR/$SCRIPT_NAME"

    # Set directory ownership and permissions
    # The service user needs to be able to access the installation directory
    chown root:"$SERVICE_USER" "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"

    # Verify the service user can access the script
    if ! sudo -u "$SERVICE_USER" test -r "$INSTALL_DIR/$SCRIPT_NAME" 2>/dev/null; then
        print_warning "Service user may not have read access, adjusting permissions..."
        chmod o+rx "$INSTALL_DIR"
        chmod o+rx "$INSTALL_DIR/$SCRIPT_NAME"
    fi

    print_success "Script installed to $INSTALL_DIR/$SCRIPT_NAME"
    print_info "Permissions set for service user '$SERVICE_USER'"
}

# Create the systemd service file
create_service() {
    print_info "Creating systemd service..."

    # Note: The ping command uses raw sockets which normally require root privileges.
    # However, on modern Linux systems, the ping binary has the cap_net_raw capability
    # set, allowing non-root users to send ICMP packets. We use AmbientCapabilities
    # as a fallback to ensure the service can ping without running as root.

    cat > "$SERVICE_FILE" << EOF
# WiFi Keep-Alive Service
# Generated by setup-service.sh on $(date)
#
# This service sends periodic pings to keep WiFi connections alive.
# Configuration:
#   Host:     $TARGET_HOST
#   Interval: $PING_INTERVAL seconds
#   User:     $SERVICE_USER

[Unit]
Description=WiFi Keep-Alive Service
Documentation=https://github.com/EnvillePlease/wifi-keep-alive
# Start after network is available
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Run as the dedicated service user (not root)
User=$SERVICE_USER
Group=$SERVICE_USER

# Grant network capability for ICMP ping packets
# This allows the service to send ping requests without root privileges
AmbientCapabilities=CAP_NET_RAW

# Command to execute
ExecStart=/usr/bin/python3 $INSTALL_DIR/$SCRIPT_NAME $TARGET_HOST --interval $PING_INTERVAL

# Restart policy: always restart on failure
Restart=on-failure
RestartSec=10

# Security hardening options
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
# Start at boot when multi-user target is reached
WantedBy=multi-user.target
EOF

    # Set proper permissions on the service file
    chmod 644 "$SERVICE_FILE"

    print_success "Service file created: $SERVICE_FILE"
}

# Enable and start the service
enable_service() {
    print_info "Enabling and starting the service..."

    # Reload systemd to recognize the new service
    systemctl daemon-reload

    # Enable the service to start at boot
    systemctl enable "$SERVICE_NAME"

    # Start the service now
    systemctl start "$SERVICE_NAME"

    # Give it a moment to start
    sleep 2

    # Check if the service is running
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Service is running"
    else
        print_warning "Service may not have started correctly"
        print_info "Check status with: sudo systemctl status $SERVICE_NAME"
    fi
}

# Display post-installation information
show_post_install_info() {
    echo ""
    echo "=========================================="
    echo "  Installation Complete!"
    echo "=========================================="
    echo ""
    echo "The WiFi Keep-Alive service has been installed and started."
    echo ""
    echo "Useful commands:"
    echo "  Check status:    sudo systemctl status $SERVICE_NAME"
    echo "  View logs:       sudo journalctl -u $SERVICE_NAME -f"
    echo "  Stop service:    sudo systemctl stop $SERVICE_NAME"
    echo "  Start service:   sudo systemctl start $SERVICE_NAME"
    echo "  Restart service: sudo systemctl restart $SERVICE_NAME"
    echo "  Disable service: sudo systemctl disable $SERVICE_NAME"
    echo ""
    echo "Configuration file: $SERVICE_FILE"
    echo "Script location:    $INSTALL_DIR/$SCRIPT_NAME"
    echo ""
    echo "To uninstall, run: sudo $0 --uninstall"
    echo ""
}

# Uninstall the service
uninstall() {
    print_info "Uninstalling WiFi Keep-Alive service..."

    # Stop the service if running
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_info "Stopping service..."
        systemctl stop "$SERVICE_NAME"
    fi

    # Disable the service
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        print_info "Disabling service..."
        systemctl disable "$SERVICE_NAME"
    fi

    # Remove the service file
    if [[ -f "$SERVICE_FILE" ]]; then
        print_info "Removing service file..."
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    # Remove the installation directory
    if [[ -d "$INSTALL_DIR" ]]; then
        print_info "Removing installation directory..."
        rm -rf "$INSTALL_DIR"
    fi

    # Ask about removing the user
    echo ""
    read -p "Remove service user '$DEFAULT_USER'? [y/N]: " REMOVE_USER
    if [[ "$REMOVE_USER" =~ ^[Yy]$ ]]; then
        if user_exists "$DEFAULT_USER"; then
            userdel "$DEFAULT_USER" 2>/dev/null || true
            print_success "User '$DEFAULT_USER' removed"
        fi
    fi

    print_success "Uninstallation complete"
}

# =============================================================================
# Main Script Execution
# =============================================================================

main() {
    echo ""
    echo "=========================================="
    echo "  WiFi Keep-Alive Service Installer"
    echo "=========================================="
    echo ""

    # Check for uninstall flag
    if [[ "$1" == "--uninstall" ]] || [[ "$1" == "-u" ]]; then
        check_root
        uninstall
        exit 0
    fi

    # Check for help flag
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        echo "Usage: sudo $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --uninstall, -u    Remove the service and files"
        echo "  --help, -h         Show this help message"
        echo ""
        exit 0
    fi

    # Run installation steps
    check_root
    check_system
    get_configuration
    create_service_user "$SERVICE_USER"
    install_script
    create_service
    enable_service
    show_post_install_info
}

# Run the main function with all script arguments
main "$@"
