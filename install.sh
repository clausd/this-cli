#!/bin/bash
# This Tool - Installation Script
# Installs the clipboard management tools system-wide

set -e  # Exit on any error

# Configuration
INSTALL_PREFIX="/usr/local"
BIN_DIR="$INSTALL_PREFIX/bin"
BUILD_DIR="build"
DATA_DIR="$HOME/.this"
CONFIG_FILE="$HOME/.this.config"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="com.this.clipboard-helper.plist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root (we don't want that)
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Please don't run this installer as root/sudo"
        log_error "It will install to your user directory and /usr/local/bin"
        exit 1
    fi
}

# Check if binaries exist
check_binaries() {
    log_step "Checking for built binaries..."
    
    if [[ ! -f "$BUILD_DIR/this" ]]; then
        log_error "Binary not found: $BUILD_DIR/this"
        log_error "Please run 'make' or './build.sh' first"
        exit 1
    fi
    
    if [[ ! -f "$BUILD_DIR/clipboard-helper" ]]; then
        log_error "Binary not found: $BUILD_DIR/clipboard-helper"
        log_error "Please run 'make' or './build.sh' first"
        exit 1
    fi
    
    log_info "✅ Found both binaries"
}

# Create necessary directories
create_directories() {
    log_step "Creating directories..."
    
    # Create data directory
    mkdir -p "$DATA_DIR"
    log_info "Created: $DATA_DIR"
    
    # Create launch agent directory
    mkdir -p "$LAUNCH_AGENT_DIR"
    log_info "Created: $LAUNCH_AGENT_DIR"
    
    # Ensure /usr/local/bin exists and is writable
    if [[ ! -d "$BIN_DIR" ]]; then
        log_warn "$BIN_DIR doesn't exist, creating it..."
        sudo mkdir -p "$BIN_DIR"
    fi
    
    if [[ ! -w "$BIN_DIR" ]]; then
        log_warn "$BIN_DIR is not writable, will need sudo for binary installation"
    fi
}

# Install binaries
install_binaries() {
    log_step "Installing binaries..."
    
    # Install this tool
    if [[ -w "$BIN_DIR" ]]; then
        cp "$BUILD_DIR/this" "$BIN_DIR/this"
    else
        sudo cp "$BUILD_DIR/this" "$BIN_DIR/this"
    fi
    chmod +x "$BIN_DIR/this"
    log_info "✅ Installed: $BIN_DIR/this"
    
    # Install clipboard helper
    if [[ -w "$BIN_DIR" ]]; then
        cp "$BUILD_DIR/clipboard-helper" "$BIN_DIR/clipboard-helper"
    else
        sudo cp "$BUILD_DIR/clipboard-helper" "$BIN_DIR/clipboard-helper"
    fi
    chmod +x "$BIN_DIR/clipboard-helper"
    log_info "✅ Installed: $BIN_DIR/clipboard-helper"
}

# Create default config if it doesn't exist
create_default_config() {
    log_step "Setting up configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "Creating default configuration..."
        cat > "$CONFIG_FILE" << 'EOF'
{
  "searchDirectories": [
    "~/Documents",
    "~/Desktop", 
    "~/Downloads"
  ],
  "maxRecentDays": 3
}
EOF
        log_info "✅ Created: $CONFIG_FILE"
    else
        log_info "Configuration already exists: $CONFIG_FILE"
    fi
}

# Create launch agent for clipboard helper
create_launch_agent() {
    log_step "Setting up clipboard monitoring..."
    
    local plist_path="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_PLIST"
    
    cat > "$plist_path" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.this.clipboard-helper</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_DIR/clipboard-helper</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$DATA_DIR/clipboard-helper.log</string>
    <key>StandardErrorPath</key>
    <string>$DATA_DIR/clipboard-helper.error.log</string>
</dict>
</plist>
EOF
    
    log_info "✅ Created launch agent: $plist_path"
}

# Load launch agent
load_launch_agent() {
    log_step "Starting clipboard monitoring service..."
    
    local plist_path="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_PLIST"
    
    # Unload if already loaded (for reinstalls)
    launchctl unload "$plist_path" 2>/dev/null || true
    
    # Load the launch agent
    if launchctl load "$plist_path" 2>/dev/null; then
        log_info "✅ Clipboard monitoring service started"
    else
        log_warn "⚠️  Could not start clipboard monitoring service automatically"
        log_warn "   You can start it manually with: make start-service"
    fi
}

# Verify installation
verify_installation() {
    log_step "Verifying installation..."
    
    # Check if binaries are in PATH and executable
    if command -v this &> /dev/null; then
        log_info "✅ 'this' command is available"
    else
        log_error "❌ 'this' command not found in PATH"
        return 1
    fi
    
    if command -v clipboard-helper &> /dev/null; then
        log_info "✅ 'clipboard-helper' command is available"
    else
        log_error "❌ 'clipboard-helper' command not found in PATH"
        return 1
    fi
    
    # Check if launch agent is loaded
    if launchctl list | grep -q "com.this.clipboard-helper"; then
        log_info "✅ Clipboard monitoring service is running"
    else
        log_warn "⚠️  Clipboard monitoring service may not be running"
    fi
}

# Show post-install information
show_post_install_info() {
    echo ""
    log_info "🎉 Installation completed successfully!"
    echo ""
    echo "Usage examples:"
    echo "  this                    # Get most recent clipboard content"
    echo "  this | grep foo         # Pipe clipboard content to grep"
    echo "  this > file.txt         # Save clipboard content to file"
    echo "  this image              # Get most recent image from clipboard"
    echo "  this recent txt         # Get most recent .txt file"
    echo ""
    echo "Configuration:"
    echo "  Config file: $CONFIG_FILE"
    echo "  Data directory: $DATA_DIR"
    echo ""
    echo "The clipboard monitoring service is now running in the background."
    echo "You should see a 📋 icon in your menu bar."
    echo ""
    echo "Service management:"
    echo "  make start-service      # Start clipboard monitoring"
    echo "  make stop-service       # Stop clipboard monitoring"
    echo "  make restart-service    # Restart clipboard monitoring"
    echo ""
    echo "To uninstall: ./uninstall.sh"
}

# Main installation process
main() {
    log_info "Starting This Tool installation..."
    
    check_not_root
    check_binaries
    create_directories
    install_binaries
    create_default_config
    create_launch_agent
    load_launch_agent
    
    if verify_installation; then
        show_post_install_info
    else
        log_error "Installation verification failed"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "This Tool Installation Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --uninstall   Uninstall instead of install"
        echo ""
        echo "This script will:"
        echo "  1. Install binaries to $BIN_DIR"
        echo "  2. Create data directory at $DATA_DIR"
        echo "  3. Set up clipboard monitoring service"
        echo "  4. Create default configuration"
        exit 0
        ;;
    --uninstall)
        exec ./uninstall.sh
        ;;
esac

# Run main installation
main
