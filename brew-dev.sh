#!/bin/bash
# Development helper for Homebrew formula testing

set -e

TAP_NAME="local/this/this"
FORMULA_PATH="Formula/this.rb"

# Create local tap if it doesn't exist
create_local_tap() {
    local tap_dir="$(brew --repository)/Library/Taps/local/homebrew-this"
    
    if [[ ! -d "$tap_dir" ]]; then
        echo "Creating local tap..."
        mkdir -p "$tap_dir"
        cp "$FORMULA_PATH" "$tap_dir/this.rb"
        echo "Created local tap at: $tap_dir"
    else
        echo "Updating local tap..."
        cp "$FORMULA_PATH" "$tap_dir/this.rb"
    fi
}

case "${1:-}" in
    install)
        echo "Installing from local tap..."
        create_local_tap
        brew install --build-from-source "$TAP_NAME"
        ;;
    uninstall)
        echo "Uninstalling..."
        brew uninstall "$TAP_NAME" 2>/dev/null || true
        ;;
    reinstall)
        echo "Reinstalling..."
        brew uninstall "$TAP_NAME" 2>/dev/null || true
        create_local_tap
        brew install --build-from-source "$TAP_NAME"
        ;;
    test)
        echo "Testing formula..."
        create_local_tap
        brew test "$TAP_NAME"
        ;;
    service-start)
        echo "Starting service..."
        brew services start "$TAP_NAME"
        ;;
    service-stop)
        echo "Stopping service..."
        brew services stop "$TAP_NAME"
        ;;
    audit)
        echo "Auditing formula..."
        create_local_tap
        brew audit --strict "$TAP_NAME"
        ;;
    clean)
        echo "Cleaning up local tap..."
        local tap_dir="$(brew --repository)/Library/Taps/local/homebrew-this"
        if [[ -d "$tap_dir" ]]; then
            rm -rf "$tap_dir"
            echo "Removed local tap"
        fi
        ;;
    *)
        echo "Usage: $0 {install|uninstall|reinstall|test|service-start|service-stop|audit|clean}"
        echo ""
        echo "Development helper for Homebrew formula testing"
        echo ""
        echo "Commands:"
        echo "  install       - Create local tap and install formula"
        echo "  uninstall     - Uninstall formula"
        echo "  reinstall     - Uninstall and reinstall"
        echo "  test          - Run formula tests"
        echo "  service-start - Start the clipboard service"
        echo "  service-stop  - Stop the clipboard service"
        echo "  audit         - Audit the formula"
        echo "  clean         - Remove local tap"
        exit 1
        ;;
esac
