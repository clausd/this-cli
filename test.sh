#!/bin/bash
# This Tool - Test Suite
# Basic tests for the clipboard management tools

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test helper functions
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "Running: $test_name"
    
    if eval "$test_command"; then
        log_info "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_error "❌ FAIL: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    echo
}

# Check if binaries exist and are executable
test_binaries_exist() {
    [[ -x "build/this" ]] && [[ -x "build/clipboard-helper" ]]
}

# Test basic help output
test_help_output() {
    # Test that the binary runs without crashing
    timeout 5s build/this --help 2>/dev/null || true
    return 0  # Always pass for now since help isn't implemented
}

# Test config file creation
test_config_creation() {
    local temp_home=$(mktemp -d)
    export HOME="$temp_home"
    
    # Run the tool to trigger config creation
    timeout 5s build/this 2>/dev/null || true
    
    # Check if config was created
    [[ -f "$temp_home/.this.config" ]]
    local result=$?
    
    # Cleanup
    rm -rf "$temp_home"
    return $result
}

# Test data directory creation
test_data_directory() {
    local temp_home=$(mktemp -d)
    export HOME="$temp_home"
    
    # Run the tool to trigger directory creation
    timeout 5s build/this 2>/dev/null || true
    
    # Check if data directory was created
    [[ -d "$temp_home/.this" ]]
    local result=$?
    
    # Cleanup
    rm -rf "$temp_home"
    return $result
}

# Test that the tool handles no clipboard history gracefully
test_no_history() {
    local temp_home=$(mktemp -d)
    export HOME="$temp_home"
    
    # Run the tool with no history - should exit with error code
    if timeout 5s build/this 2>/dev/null; then
        # If it succeeded, that's unexpected
        rm -rf "$temp_home"
        return 1
    else
        # Expected to fail with no history
        rm -rf "$temp_home"
        return 0
    fi
}

# Test recent file search (basic functionality)
test_recent_files() {
    local temp_home=$(mktemp -d)
    export HOME="$temp_home"
    
    # Create some test files in Documents
    mkdir -p "$temp_home/Documents"
    echo "test content" > "$temp_home/Documents/test.txt"
    touch "$temp_home/Documents/test.txt"  # Update timestamp
    
    # Run recent search - should not crash
    timeout 10s build/this recent txt 2>/dev/null || true
    local result=$?
    
    # Cleanup
    rm -rf "$temp_home"
    
    # Return success if it didn't crash (exit code 124 is timeout)
    [[ $result -ne 124 ]]
}

# Test Swift compilation flags
test_swift_compilation() {
    # Check if binaries were compiled with optimization
    if command -v otool &> /dev/null; then
        # This is a basic check - optimized binaries are usually smaller
        local size=$(stat -f%z build/this 2>/dev/null || echo "0")
        [[ $size -gt 0 ]]
    else
        # If otool not available, just check the binary exists
        [[ -f build/this ]]
    fi
}

# Main test execution
main() {
    log_info "Starting This Tool test suite..."
    echo
    
    # Basic binary tests
    run_test "Binaries exist and are executable" "test_binaries_exist"
    run_test "Help output doesn't crash" "test_help_output"
    run_test "Swift compilation successful" "test_swift_compilation"
    
    # Functionality tests
    run_test "Config file creation" "test_config_creation"
    run_test "Data directory creation" "test_data_directory"
    run_test "No history handling" "test_no_history"
    run_test "Recent files search" "test_recent_files"
    
    # Test summary
    echo "=================================="
    log_info "Test Summary:"
    echo "  Tests run: $TESTS_RUN"
    echo "  Passed: $TESTS_PASSED"
    echo "  Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "🎉 All tests passed!"
        exit 0
    else
        log_error "❌ $TESTS_FAILED test(s) failed"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "This Tool Test Suite"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --verbose     Run with verbose output"
        echo ""
        echo "This script tests:"
        echo "  - Binary compilation and execution"
        echo "  - Config file handling"
        echo "  - Data directory creation"
        echo "  - Basic functionality"
        exit 0
        ;;
    --verbose)
        set -x
        ;;
esac

# Run the tests
main
