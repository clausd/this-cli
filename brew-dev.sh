#!/bin/bash
# Development helper for Homebrew formula testing

set -e

FORMULA_PATH="Formula/this.rb"

case "${1:-}" in
    install)
        echo "Installing from local formula..."
        brew install --build-from-source "$FORMULA_PATH"
        ;;
    uninstall)
        echo "Uninstalling..."
        brew uninstall this 2>/dev/null || true
        ;;
    reinstall)
        echo "Reinstalling..."
        brew uninstall this 2>/dev/null || true
        brew install --build-from-source "$FORMULA_PATH"
        ;;
    test)
        echo "Testing formula..."
        brew test this
        ;;
    service-start)
        echo "Starting service..."
        brew services start this
        ;;
    service-stop)
        echo "Stopping service..."
        brew services stop this
        ;;
    audit)
        echo "Auditing formula..."
        brew audit --strict "$FORMULA_PATH"
        ;;
    *)
        echo "Usage: $0 {install|uninstall|reinstall|test|service-start|service-stop|audit}"
        echo ""
        echo "Development helper for Homebrew formula testing"
        exit 1
        ;;
esac
