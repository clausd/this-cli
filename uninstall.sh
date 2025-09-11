#!/bin/bash
# This Tool - Uninstallation Script
# Removes the clipboard management tools from the system

set -e  # Exit on any error

# Configuration
INSTALL_PREFIX="/usr/local"
BIN_DIR="$INSTALL_PREFIX/bin"
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

# Stop and remove launch agent
remove_launch_agent() {
    log_step "Stopping clipboard monitoring service..."
    
    local plist_path="$LAUNCH_AGENT_DIR/$LAUNCH_AGENT_PLIST"
    
    if [[ -f "$plist_path" ]]; then
        # Unload the launch agent
        launchctl unload "$plist_path" 2>/dev/null || true
        log_info "✅ Service stopped"
        
        # Remove the plist file
        rm -f "$plist_path"
        log_info "✅ Removed launch agent: $plist_path"
    else
        log_info "Launch agent not found, skipping"
    fi
}

# Remove binaries
remove_binaries() {
    log_step "Removing binaries..."
    
    # Remove this tool
    if [[ -f "$BIN_DIR/this" ]]; then
        if [[ -w "$BIN_DIR" ]]; then
            rm -f "$BIN_DIR/this"
        else
            sudo rm -f "$BIN_DIR/this"
        fi
        log_info "✅ Removed: $BIN_DIR/this"
    else
        log_info "Binary not found: $BIN_DIR/this"
    fi
    
    # Remove clipboard helper
    if [[ -f "$BIN_DIR/clipboard-helper" ]]; then
        if [[ -w "$BIN_DIR" ]]; then
            rm -f "$BIN_DIR/clipboard-helper"
        else
            sudo rm -f "$BIN_DIR/clipboard-helper"
        fi
        log_info "✅ Removed: $BIN_DIR/clipboard-helper"
    else
        log_info "Binary not found: $BIN_DIR/clipboard-helper"
    fi
}

# Remove data directory (with confirmation)
remove_data_directory() {
    log_step "Removing data directory..."
    
    if [[ -d "$DATA_DIR" ]]; then
        echo -n "Remove clipboard history and data directory $DATA_DIR? [y/N]: "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$DATA_DIR"
            log_info "✅ Removed: $DATA_DIR"
        else
            log_info "Keeping data directory: $DATA_DIR"
        fi
    else
        log_info "Data directory not found: $DATA_DIR"
    fi
}

# Remove config file (with confirmation)
remove_config_file() {
    log_step "Removing configuration file..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -n "Remove configuration file $CONFIG_FILE? [y/N]: "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -f "$CONFIG_FILE"
            log_info "✅ Removed: $CONFIG_FILE"
        else
            log_info "Keeping configuration file: $CONFIG_FILE"
        fi
    else
        log_info "Configuration file not found: $CONFIG_FILE"
    fi
}

# Verify uninstallation
verify_uninstallation() {
    log_step "Verifying uninstallation..."
    
    local issues=0
    
    # Check if binaries are still in PATH
    if command -v this &> /dev/null; then
        log_warn "⚠️  'this' command still found in PATH"
        issues=$((issues + 1))
    else
        log_info "✅ 'this' command removed from PATH"
    fi
    
    if command -v clipboard-helper &> /dev/null; then
        log_warn "⚠️  'clipboard-helper' command still found in PATH"
        issues=$((issues + 1))
    else
        log_info "✅ 'clipboard-helper' command removed from PATH"
    fi
    
    # Check if launch agent is still loaded
    if launchctl list | grep -q "com.this.clipboard-helper"; then
        log_warn "⚠️  Clipboard monitoring service may still be running"
        issues=$((issues + 1))
    else
        log_info "✅ Clipboard monitoring service stopped"
    fi
    
    return $issues
}

# Show post-uninstall information
show_post_uninstall_info() {
    echo ""
    if [[ $1 -eq 0 ]]; then
        log_info "🎉 Uninstallation completed successfully!"
    else
        log_warn "⚠️  Uninstallation completed with $1 issue(s)"
        log_warn "   You may need to restart your terminal or log out/in"
    fi
    echo ""
    echo "If you kept your data directory ($DATA_DIR),"
    echo "you can reinstall later and your clipboard history will be preserved."
    echo ""
    echo "To reinstall: ./install.sh"
}

# Main uninstallation process
main() {
    log_info "Starting This Tool uninstallation..."
    
    remove_launch_agent
    remove_binaries
    remove_data_directory
    remove_config_file
    
    if verify_uninstallation; then
        show_post_uninstall_info 0
    else
        show_post_uninstall_info $?
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "This Tool Uninstallation Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --force       Skip confirmation prompts"
        echo ""
        echo "This script will:"
        echo "  1. Stop and remove clipboard monitoring service"
        echo "  2. Remove binaries from $BIN_DIR"
        echo "  3. Optionally remove data directory and config file"
        exit 0
        ;;
    --force)
        # Set environment variable to skip confirmations
        export FORCE_UNINSTALL=1
        ;;
esac

# Run main uninstallation
main
