# Build system for clipboard management tools

# Configuration
SWIFT_FLAGS = -O
INSTALL_PREFIX ?= /usr/local
BIN_DIR = $(INSTALL_PREFIX)/bin
MAN_DIR = $(INSTALL_PREFIX)/share/man/man1
BUILD_DIR = build
VAR_DIR = $(INSTALL_PREFIX)/var/this

# Targets
THIS_BINARY = $(BUILD_DIR)/this
CLIPBOARD_HELPER_BINARY = $(BUILD_DIR)/clipboard-helper

.PHONY: all clean install uninstall test help man start-service stop-service restart-service homebrew-install

# Default target
all: $(THIS_BINARY) $(CLIPBOARD_HELPER_BINARY)

# Build the command line tool
$(THIS_BINARY): this.swift | $(BUILD_DIR)
	@echo "Building this command line tool..."
	swiftc $(SWIFT_FLAGS) -o $@ $<
	@echo "✅ Built: $@"

# Build the clipboard helper menu bar app
$(CLIPBOARD_HELPER_BINARY): clipboard_helper.swift | $(BUILD_DIR)
	@echo "Building clipboard-helper menu bar app..."
	swiftc $(SWIFT_FLAGS) -framework Cocoa -o $@ $<
	@echo "✅ Built: $@"

# Create build directory
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	@echo "✅ Clean complete"

# Install to system
install: all
	@echo "Installing This Tool..."
	@./install.sh
	@echo "✅ Installation complete"

# Homebrew-compatible install (used by brew formula)
homebrew-install: all
	@echo "Installing This Tool (Homebrew mode)..."
	@mkdir -p $(BIN_DIR)
	@mkdir -p $(VAR_DIR)
	@cp $(BUILD_DIR)/this $(BIN_DIR)/this
	@cp $(BUILD_DIR)/clipboard-helper $(BIN_DIR)/clipboard-helper
	@chmod +x $(BIN_DIR)/this $(BIN_DIR)/clipboard-helper
	@echo "✅ Homebrew installation complete"

# Uninstall from system
uninstall:
	@echo "Uninstalling This Tool..."
	@./uninstall.sh
	@echo "✅ Uninstall complete"

# Run tests
test: all
	@echo "Running tests..."
	@./test.sh
	@echo "✅ Tests complete"

# Install man page
man: this.1
	@echo "Installing man page..."
	@mkdir -p $(MAN_DIR)
	@cp this.1 $(MAN_DIR)/this.1
	@echo "✅ Man page installed: $(MAN_DIR)/this.1"

# Service management targets
start-service:
	@echo "Starting clipboard monitoring service..."
	@launchctl load ~/Library/LaunchAgents/com.this.clipboard-helper.plist 2>/dev/null || echo "Service may already be running"
	@echo "✅ Service started"

stop-service:
	@echo "Stopping clipboard monitoring service..."
	@launchctl unload ~/Library/LaunchAgents/com.this.clipboard-helper.plist 2>/dev/null || echo "Service may not be running"
	@echo "✅ Service stopped"

restart-service: stop-service start-service

# Show help
help:
	@echo "This Tool - Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  all            - Build both tools (default)"
	@echo "  clean          - Remove build artifacts"
	@echo "  install        - Build and install to system"
	@echo "  uninstall      - Remove from system"
	@echo "  test           - Run test suite"
	@echo "  man            - Install man page"
	@echo "  start-service  - Start clipboard monitoring service"
	@echo "  stop-service   - Stop clipboard monitoring service"
	@echo "  restart-service- Restart clipboard monitoring service"
	@echo "  help           - Show this help"
	@echo ""
	@echo "Configuration:"
	@echo "  INSTALL_PREFIX = $(INSTALL_PREFIX)"
	@echo "  BIN_DIR = $(BIN_DIR)"
	@echo "  MAN_DIR = $(MAN_DIR)"
