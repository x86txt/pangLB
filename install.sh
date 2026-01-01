#!/bin/bash
#
# Installation/uninstallation script for pangLB (Newt Health Daemon)
#
# Easy install (run one of these commands):
#   curl -fsSL https://raw.githubusercontent.com/x86txt/pangLB/main/install.sh | sudo bash
#   wget -qO- https://raw.githubusercontent.com/x86txt/pangLB/main/install.sh | sudo bash
#
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/x86txt/pangLB/main/install.sh | sudo bash -s -- --uninstall
#   sudo ./install.sh --uninstall
#
# Or download and run manually:
#   curl -fsSL -o install.sh https://raw.githubusercontent.com/x86txt/pangLB/main/install.sh
#   chmod +x install.sh
#   sudo ./install.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REPO="x86txt/pangLB"
BINARY_NAME="newt-healthd"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="newt-healthd.service"
SERVICE_URL="https://raw.githubusercontent.com/${REPO}/refs/heads/main/${SERVICE_FILE}"
CERT_DIR="/etc/ssl/newt-health"

# Function to print colored output
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Uninstall function
uninstall() {
    info "Starting uninstall process..."
    
    # Check if running on Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "This uninstaller is designed for Linux systems with systemd. Detected OS: $OSTYPE"
    fi
    
    # Check for systemctl
    if ! command -v systemctl &> /dev/null; then
        error "Required command 'systemctl' is not installed."
    fi
    
    # Stop and disable service if it exists
    if systemctl list-unit-files --type=service | grep -q "^${SERVICE_FILE}"; then
        info "Stopping and disabling ${SERVICE_FILE}..."
        sudo systemctl stop "$SERVICE_FILE" 2>/dev/null || warn "Service was not running"
        sudo systemctl disable "$SERVICE_FILE" 2>/dev/null || warn "Service was not enabled"
    else
        info "Service ${SERVICE_FILE} not found, skipping..."
    fi
    
    # Remove service file
    if [ -f "/etc/systemd/system/${SERVICE_FILE}" ]; then
        info "Removing systemd service file..."
        sudo rm -f "/etc/systemd/system/${SERVICE_FILE}"
        sudo systemctl daemon-reload
    else
        info "Service file not found, skipping..."
    fi
    
    # Remove binary
    if [ -f "${INSTALL_DIR}/${BINARY_NAME}" ]; then
        info "Removing binary from ${INSTALL_DIR}/${BINARY_NAME}..."
        sudo rm -f "${INSTALL_DIR}/${BINARY_NAME}"
    else
        info "Binary not found, skipping..."
    fi
    
    # Ask about certificates
    if [ -d "$CERT_DIR" ]; then
        echo
        read -p "Do you want to remove TLS certificates from ${CERT_DIR}? (y/n) " -n 1 -r < /dev/tty
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Removing TLS certificates..."
            sudo rm -rf "$CERT_DIR"
        else
            info "Keeping TLS certificates at ${CERT_DIR}/"
        fi
    fi
    
    echo
    info "Uninstall completed successfully!"
    echo
    exit 0
}

# Check for uninstall flag
if [[ "${1:-}" == "--uninstall" ]] || [[ "${1:-}" == "-u" ]]; then
    uninstall
fi

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    error "This installer is designed for Linux systems with systemd. Detected OS: $OSTYPE"
fi

# Check for required commands
for cmd in curl systemctl hostname; do
    if ! command -v "$cmd" &> /dev/null; then
        error "Required command '$cmd' is not installed. Please install it and try again."
    fi
done

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        PLATFORM="linux-amd64"
        ARCHIVE_EXT="tar.gz"
        ;;
    aarch64|arm64)
        PLATFORM="linux-arm64"
        ARCHIVE_EXT="tar.gz"
        ;;
    *)
        error "Unsupported architecture: $ARCH. Supported architectures: x86_64, aarch64/arm64"
        ;;
esac

info "Detected platform: $PLATFORM"

# Get latest release version
info "Fetching latest release version..."
LATEST_TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_TAG" ]; then
    error "Failed to fetch latest release version. Please check your internet connection."
fi

info "Latest release: $LATEST_TAG"

# Construct download URL
BINARY_FILE="panglb-${PLATFORM}.${ARCHIVE_EXT}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${BINARY_FILE}"

# Download and install binary
info "Downloading binary from ${DOWNLOAD_URL}..."
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

cd "$TMP_DIR"
if ! curl -fsSL -o "$BINARY_FILE" "$DOWNLOAD_URL"; then
    error "Failed to download binary. Please check your internet connection and try again."
fi

info "Extracting binary..."
if [ "$ARCHIVE_EXT" = "tar.gz" ]; then
    tar -xzf "$BINARY_FILE"
    EXTRACTED_BINARY="panglb-${PLATFORM}"
else
    error "Unsupported archive format: $ARCHIVE_EXT"
fi

if [ ! -f "$EXTRACTED_BINARY" ]; then
    error "Binary extraction failed. Expected file: $EXTRACTED_BINARY"
fi

info "Installing binary to ${INSTALL_DIR}/${BINARY_NAME}..."
sudo install -m 755 "$EXTRACTED_BINARY" "${INSTALL_DIR}/${BINARY_NAME}"

# Download and install systemd service file
info "Downloading systemd service file..."
SERVICE_TMP=$(mktemp)
if ! curl -fsSL -o "$SERVICE_TMP" "$SERVICE_URL"; then
    error "Failed to download service file. Please check your internet connection."
fi

info "Installing systemd service file..."
sudo install -m 644 "$SERVICE_TMP" "/etc/systemd/system/${SERVICE_FILE}"

# Handle TLS certificates
info "Checking TLS certificate configuration..."
if [ -f "${CERT_DIR}/tls.crt" ] && [ -f "${CERT_DIR}/tls.key" ]; then
    info "TLS certificates already exist at ${CERT_DIR}/"
    read -p "Do you want to use existing certificates? (y/n) " -n 1 -r < /dev/tty
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        CERT_EXISTS=false
    else
        CERT_EXISTS=true
    fi
else
    CERT_EXISTS=false
fi

if [ "$CERT_EXISTS" = false ]; then
    echo
    echo "TLS certificate setup:"
    echo "1) Generate a self-signed certificate automatically"
    echo "2) Provide your own certificate files"
    read -p "Choose an option (1 or 2): " -n 1 -r < /dev/tty
    echo
    
    if [[ $REPLY =~ ^[1]$ ]]; then
        info "Generating self-signed certificate..."
        sudo mkdir -p "$CERT_DIR"
        
        HOSTNAME_FQDN=$(hostname -f 2>/dev/null || hostname)
        if [ -z "$HOSTNAME_FQDN" ]; then
            HOSTNAME_FQDN="localhost"
        fi
        
        sudo openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "${CERT_DIR}/tls.key" \
            -out "${CERT_DIR}/tls.crt" \
            -subj "/CN=${HOSTNAME_FQDN}"
        
        sudo chmod 600 "${CERT_DIR}/tls.key"
        sudo chmod 644 "${CERT_DIR}/tls.crt"
        
        info "Certificate generated successfully at ${CERT_DIR}/"
    elif [[ $REPLY =~ ^[2]$ ]]; then
        info "Please provide your certificate files."
        read -p "Path to certificate file (.crt or .pem): " CERT_PATH < /dev/tty
        read -p "Path to private key file (.key): " KEY_PATH < /dev/tty
        
        if [ ! -f "$CERT_PATH" ]; then
            error "Certificate file not found: $CERT_PATH"
        fi
        
        if [ ! -f "$KEY_PATH" ]; then
            error "Private key file not found: $KEY_PATH"
        fi
        
        sudo mkdir -p "$CERT_DIR"
        sudo cp "$CERT_PATH" "${CERT_DIR}/tls.crt"
        sudo cp "$KEY_PATH" "${CERT_DIR}/tls.key"
        sudo chmod 644 "${CERT_DIR}/tls.crt"
        sudo chmod 600 "${CERT_DIR}/tls.key"
        
        info "Certificate files installed successfully at ${CERT_DIR}/"
    else
        error "Invalid option selected."
    fi
fi

# Reload systemd and enable service
info "Reloading systemd daemon..."
sudo systemctl daemon-reload

info "Enabling and starting ${SERVICE_FILE}..."
sudo systemctl enable --now "$SERVICE_FILE"

# Wait a moment for service to start
sleep 2

# Check service status
info "Service status:"
sudo systemctl status "$SERVICE_FILE" --no-pager || warn "Service status check failed"

# Test the health endpoint
info "Testing health endpoint..."
if curl -kfsSL https://127.0.0.1:8443/healthz > /dev/null; then
    info "Health endpoint is responding!"
    echo
    info "Installation completed successfully!"
    echo
    echo "The service is now running and accessible at:"
    echo "  - Health check: https://127.0.0.1:8443/healthz"
    echo "  - Root endpoint: https://127.0.0.1:8443/"
    echo
    echo "To check service status: sudo systemctl status ${SERVICE_FILE}"
    echo "To view logs: sudo journalctl -u ${SERVICE_FILE} -f"
else
    warn "Health endpoint test failed. Please check the service logs:"
    echo "  sudo journalctl -u ${SERVICE_FILE} -n 50"
fi
