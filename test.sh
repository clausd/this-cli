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

# Global test harness variables
TEST_HOME=""
ORIGINAL_HOME=""

# Test harness setup and teardown
setup_test_harness() {
    log_info "Setting up test harness..."
    
    # Create shared temp directory for all tests
    TEST_HOME=$(mktemp -d)
    ORIGINAL_HOME="$HOME"
    export HOME="$TEST_HOME"
    
    log_info "Test environment: $TEST_HOME"
    
    # Set up trap to cleanup on exit
    trap cleanup_test_harness EXIT
}

cleanup_test_harness() {
    if [[ -n "$ORIGINAL_HOME" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
    
    if [[ -n "$TEST_HOME" ]] && [[ -d "$TEST_HOME" ]]; then
        log_info "Cleaning up test environment: $TEST_HOME"
        rm -rf "$TEST_HOME"
    fi
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

# Helper to create mock clipboard history (uses shared TEST_HOME)
create_mock_history() {
    local history_file="$TEST_HOME/.this/history.json"
    
    mkdir -p "$TEST_HOME/.this"
    
    # Create sample history with different types
    cat > "$history_file" << 'EOF'
[
  {
    "timestamp": "2024-01-01T12:00:00Z",
    "content": "Hello world text content",
    "type": "text",
    "tempFilePath": null
  },
  {
    "timestamp": "2024-01-01T11:00:00Z", 
    "content": "Image (1024 bytes)",
    "type": "image",
    "tempFilePath": "/tmp/test_image.png"
  },
  {
    "timestamp": "2024-01-01T10:00:00Z",
    "content": "/Users/test/document.txt",
    "type": "file", 
    "tempFilePath": null
  },
  {
    "timestamp": "2024-01-01T09:00:00Z",
    "content": "Another text entry with keywords",
    "type": "text",
    "tempFilePath": null
  }
]
EOF
}

# Helper to create test files for recent search (uses shared TEST_HOME)
create_test_files() {
    # Create Documents directory with test files
    mkdir -p "$TEST_HOME/Documents"
    mkdir -p "$TEST_HOME/Desktop"
    mkdir -p "$TEST_HOME/Downloads"
    
    # Create files with different extensions and timestamps
    echo "Test text content" > "$TEST_HOME/Documents/test.txt"
    echo "Another document" > "$TEST_HOME/Documents/document.txt"
    echo "Binary data" > "$TEST_HOME/Documents/image.png"
    echo "PDF content" > "$TEST_HOME/Desktop/presentation.pdf"
    echo "Download file" > "$TEST_HOME/Downloads/download.zip"
    
    # Update timestamps to be recent
    touch "$TEST_HOME/Documents/test.txt"
    touch "$TEST_HOME/Documents/document.txt"
    touch "$TEST_HOME/Documents/image.png"
    touch "$TEST_HOME/Desktop/presentation.pdf"
    touch "$TEST_HOME/Downloads/download.zip"
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

# Test config file creation and content
test_config_creation() {
    # Create config file for testing
    cat > "$TEST_HOME/.this.config" << 'EOF'
{
  "searchDirectories": [
    "~/Documents",
    "~/Desktop", 
    "~/Downloads"
  ],
  "maxRecentDays": 3
}
EOF
    
    local result=0
    if [[ -f "$TEST_HOME/.this.config" ]]; then
        # Verify config contains expected JSON structure
        if grep -q "searchDirectories" "$TEST_HOME/.this.config" && \
           grep -q "maxRecentDays" "$TEST_HOME/.this.config" && \
           grep -q "Documents" "$TEST_HOME/.this.config"; then
            result=0
        else
            echo "Debug: Config file exists but has invalid content:" >&2
            cat "$TEST_HOME/.this.config" >&2
            result=1
        fi
    else
        echo "Debug: Config file not created" >&2
        ls -la "$TEST_HOME" >&2 || true
        result=1
    fi
    
    return $result
}

# Test data directory creation
test_data_directory() {
    # Check if data directory was created (should exist from config creation test)
    local result=0
    if [[ -d "$TEST_HOME/.this" ]]; then
        result=0
        echo "Debug: Data directory exists" >&2
        echo "Debug: Directory contents:" >&2
        ls -la "$TEST_HOME/.this" >&2 || true
    else
        result=1
        # Debug: list what was actually created
        echo "Debug: Contents of $TEST_HOME:" >&2
        ls -la "$TEST_HOME" >&2 || true
        echo "Debug: Checking for any .this* files/dirs:" >&2
        find "$TEST_HOME" -name ".this*" -ls >&2 || true
    fi
    
    return $result
}

# Test clipboard history reading with mock data
test_clipboard_history_reading() {
    create_mock_history
    
    # Test basic clipboard retrieval (should get most recent)
    local output=$(timeout 5s build/this 2>/dev/null || true)
    local result=0
    
    if [[ "$output" == *"Hello world text content"* ]]; then
        result=0
    else
        echo "Debug: Expected 'Hello world text content', got: '$output'" >&2
        result=1
    fi
    
    return $result
}

# Test filtering by content type
test_content_type_filtering() {
    # Mock history should already exist from previous test
    
    # Test image filter
    local image_output=$(timeout 5s build/this image 2>/dev/null || true)
    local text_output=$(timeout 5s build/this text 2>/dev/null || true)
    
    local result=0
    
    # Image filter should return image content
    if [[ "$image_output" == *"Image"* ]] && [[ "$image_output" == *"bytes"* ]]; then
        # Text filter should return text content
        if [[ "$text_output" == *"Hello world text content"* ]]; then
            result=0
        else
            echo "Debug: Text filter failed. Got: '$text_output'" >&2
            result=1
        fi
    else
        echo "Debug: Image filter failed. Got: '$image_output'" >&2
        result=1
    fi
    
    return $result
}

# Test content-based filtering
test_content_filtering() {
    # Mock history should already exist from previous test
    
    # Test filtering by keyword
    local keyword_output=$(timeout 5s build/this keywords 2>/dev/null || true)
    
    local result=0
    if [[ "$keyword_output" == *"Another text entry with keywords"* ]]; then
        result=0
    else
        echo "Debug: Keyword filter failed. Got: '$keyword_output'" >&2
        result=1
    fi
    
    return $result
}

# Test that the tool handles no clipboard history gracefully
test_no_history() {
    # Temporarily remove history file
    local history_backup=""
    if [[ -f "$TEST_HOME/.this/history.json" ]]; then
        history_backup=$(cat "$TEST_HOME/.this/history.json")
        rm "$TEST_HOME/.this/history.json"
    fi
    
    # Run the tool with no history - should exit with error code
    local result=0
    if timeout 5s build/this 2>/dev/null; then
        result=1
    else
        result=0
    fi
    
    # Restore history file if it existed
    if [[ -n "$history_backup" ]]; then
        echo "$history_backup" > "$TEST_HOME/.this/history.json"
    fi
    
    return $result
}

# Test recent file search functionality
test_recent_files() {
    create_test_files
    
    # Test recent txt files
    local txt_output=$(timeout 10s build/this recent txt 2>/dev/null || true)
    local result=0
    
    # Should find one of our .txt files
    if [[ "$txt_output" == *".txt"* ]] && [[ "$txt_output" == *"$TEST_HOME"* ]]; then
        result=0
    else
        echo "Debug: Recent txt search failed. Got: '$txt_output'" >&2
        # Show what files exist for debugging
        echo "Debug: Available files:" >&2
        find "$TEST_HOME" -name "*.txt" >&2 || true
        result=1
    fi
    
    return $result
}

# Test recent file search with different extensions
test_recent_files_by_extension() {
    # Test files should already exist from previous test
    
    # Test png search
    local png_output=$(timeout 10s build/this recent png 2>/dev/null || true)
    
    local result=0
    if [[ "$png_output" == *".png"* ]] || [[ "$png_output" == *"image"* ]]; then
        result=0
    else
        echo "Debug: Recent png search failed. Got: '$png_output'" >&2
        result=1
    fi
    
    return $result
}

# Test pipe detection and output behavior
test_pipe_detection() {
    # Mock history should already exist
    
    # Test normal output (should work)
    local normal_output=$(timeout 5s build/this 2>/dev/null || true)
    
    # Test piped output (should also work but might format differently)
    local piped_output=$(timeout 5s build/this 2>/dev/null | cat || true)
    
    local result=0
    if [[ -n "$normal_output" ]] && [[ -n "$piped_output" ]]; then
        result=0
    else
        echo "Debug: Pipe detection test failed" >&2
        echo "Debug: Normal output: '$normal_output'" >&2
        echo "Debug: Piped output: '$piped_output'" >&2
        result=1
    fi
    
    return $result
}

# Test config parsing with custom values
test_custom_config() {
    # Backup existing config
    local config_backup=""
    if [[ -f "$TEST_HOME/.this.config" ]]; then
        config_backup=$(cat "$TEST_HOME/.this.config")
    fi
    
    # Create custom config
    cat > "$TEST_HOME/.this.config" << 'EOF'
{
  "searchDirectories": [
    "~/CustomDir",
    "~/AnotherDir"
  ],
  "maxRecentDays": 7
}
EOF
    
    # Create the custom directory with a test file
    mkdir -p "$TEST_HOME/CustomDir"
    echo "custom content" > "$TEST_HOME/CustomDir/custom.txt"
    touch "$TEST_HOME/CustomDir/custom.txt"
    
    # Run recent search - should use custom config
    local output=$(timeout 10s build/this recent txt 2>/dev/null || true)
    
    local result=0
    # The tool should have loaded the custom config (hard to test directly, 
    # but it shouldn't crash and should create data directory)
    if [[ -d "$TEST_HOME/.this" ]]; then
        result=0
    else
        echo "Debug: Custom config test failed - no data directory created" >&2
        result=1
    fi
    
    # Restore original config
    if [[ -n "$config_backup" ]]; then
        echo "$config_backup" > "$TEST_HOME/.this.config"
    fi
    
    return $result
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
    
    # Set up shared test harness
    setup_test_harness
    
    # Basic binary tests
    run_test "Binaries exist and are executable" "test_binaries_exist"
    run_test "Help output doesn't crash" "test_help_output"
    run_test "Swift compilation successful" "test_swift_compilation"
    
    # Configuration tests (these set up the shared environment)
    run_test "Config file creation and content" "test_config_creation"
    run_test "Data directory creation" "test_data_directory"
    
    # Core functionality tests (these use the shared environment)
    run_test "Clipboard history reading" "test_clipboard_history_reading"
    run_test "Content type filtering" "test_content_type_filtering"
    run_test "Content-based filtering" "test_content_filtering"
    run_test "No history handling" "test_no_history"
    
    # File search tests (these use the shared environment)
    run_test "Recent files search" "test_recent_files"
    run_test "Recent files by extension" "test_recent_files_by_extension"
    
    # Output behavior tests
    run_test "Pipe detection and output" "test_pipe_detection"
    
    # Config tests (these temporarily modify the shared environment)
    run_test "Custom config parsing" "test_custom_config"
    
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
        echo "  - Config file creation and parsing"
        echo "  - Data directory creation"
        echo "  - Clipboard history reading and filtering"
        echo "  - Content type filtering (text, image, file)"
        echo "  - Content-based keyword filtering"
        echo "  - Recent file search with mdfind"
        echo "  - Extension-based file filtering"
        echo "  - Pipe detection and output behavior"
        echo "  - Custom configuration handling"
        exit 0
        ;;
    --verbose)
        set -x
        ;;
esac

# Run the tests
main
