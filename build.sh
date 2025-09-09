#!/bin/bash
# This Tool - Build Script
# Builds both the command line tool and clipboard helper with error handling

set -e  # Exit on any error

# Configuration
BUILD_DIR="build"
SWIFT_FLAGS="-O"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check for Swift compiler
    if ! command -v swiftc &> /dev/null; then
        log_error "Swift compiler not found. Please install Xcode Command Line Tools:"
        log_error "  xcode-select --install"
        exit 1
    fi
    
    # Check Swift version
    SWIFT_VERSION=$(swiftc --version | head -n1)
    log_info "Found: $SWIFT_VERSION"
    
    # Check macOS version
    MACOS_VERSION=$(sw_vers -productVersion)
    log_info "macOS version: $MACOS_VERSION"
    
    # Warn if macOS version might be too old
    if [[ $(echo "$MACOS_VERSION" | cut -d. -f1) -lt 10 ]] || 
       [[ $(echo "$MACOS_VERSION" | cut -d. -f1) -eq 10 && $(echo "$MACOS_VERSION" | cut -d. -f2) -lt 15 ]]; then
        log_warn "macOS 10.15+ recommended for best compatibility"
    fi
}

# Create build directory
setup_build_dir() {
    log_info "Setting up build directory..."
    mkdir -p "$BUILD_DIR"
}

# Build the command line tool
build_this_tool() {
    log_info "Building 'this' command line tool..."
    
    if [[ ! -f "this.swift" ]]; then
        log_error "this.swift not found in current directory"
        exit 1
    fi
    
    swiftc $SWIFT_FLAGS -o "$BUILD_DIR/this" this.swift
    
    if [[ $? -eq 0 ]]; then
        log_info "✅ Successfully built: $BUILD_DIR/this"
    else
        log_error "Failed to build this tool"
        exit 1
    fi
}

# Build the clipboard helper
build_clipboard_helper() {
    log_info "Building 'clipboard-helper' menu bar app..."
    
    if [[ ! -f "clipboard_helper.swift" ]]; then
        log_error "clipboard_helper.swift not found in current directory"
        exit 1
    fi
    
    swiftc $SWIFT_FLAGS -framework Cocoa -o "$BUILD_DIR/clipboard-helper" clipboard_helper.swift
    
    if [[ $? -eq 0 ]]; then
        log_info "✅ Successfully built: $BUILD_DIR/clipboard-helper"
    else
        log_error "Failed to build clipboard helper"
        exit 1
    fi
}

# Verify builds
verify_builds() {
    log_info "Verifying builds..."
    
    if [[ -x "$BUILD_DIR/this" ]]; then
        log_info "✅ this tool is executable"
    else
        log_error "this tool build verification failed"
        exit 1
    fi
    
    if [[ -x "$BUILD_DIR/clipboard-helper" ]]; then
        log_info "✅ clipboard-helper is executable"
    else
        log_error "clipboard-helper build verification failed"
        exit 1
    fi
}

# Main build process
main() {
    log_info "Starting This Tool build process..."
    
    check_dependencies
    setup_build_dir
    build_this_tool
    build_clipboard_helper
    verify_builds
    
    log_info "🎉 Build completed successfully!"
    log_info "Binaries available in: $BUILD_DIR/"
    log_info "Run 'make install' or './install.sh' to install system-wide"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "This Tool Build Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --clean       Clean build directory first"
        echo ""
        echo "Environment variables:"
        echo "  BUILD_DIR     Build directory (default: build)"
        echo "  SWIFT_FLAGS   Swift compiler flags (default: -O)"
        exit 0
        ;;
    --clean)
        log_info "Cleaning build directory..."
        rm -rf "$BUILD_DIR"
        ;;
esac

# Run main build process
main
