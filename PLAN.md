# This Tool - Build, Test, and Installation Plan

## Overview
This document outlines the build system, testing strategy, and installation process for the "This" clipboard management tool consisting of:
- `this` - Command line tool for accessing clipboard history and recent files
- `clipboard-helper` - Menu bar app for monitoring clipboard changes

## Goal and Usage Patterns

The `this` command provides context to command line tools by intelligently returning either clipboard content or recent file paths. It works with the `clipboard-helper` menu bar app to access clipboard history.

### Core Usage Patterns
```bash
open `this`              # Opens the most relevant file/content
cp `this` here           # Copies the context file here
cat `this`               # View content of the most relevant file
```

### Filtering
```bash
this image               # Filters to most recent image (clipboard or file)
this png                 # Filters to PNG files specifically
this txt                 # Filters to text files or clipboard text
this recent image        # Most recent image file (not clipboard)
```

### Intelligence
- **File Path Output**: Always outputs file paths for use with other command-line tools
- **Smart Filtering**: Intelligently matches clipboard content and recent files
- **Context Awareness**: Prioritizes most relevant content based on recency and type

### Data Sources
1. **Clipboard History**: From `clipboard-helper` app's stored history
2. **Recent Files**: Using `mdfind` to search configured directories:
   ```bash
   mdfind -onlyin ~/Documents -onlyin ~/Desktop "kMDItemLastUsedDate >= $time.today(-3)"
   ```

### Configuration
- `~/.this.config` - JSON file specifying search directories and preferences
- Default searches: `~/Documents`, `~/Desktop`, `~/Downloads`
- Default time window: 3 days

## 1. Build System

### Components
- **Makefile** - Simple build automation with common targets
- **build.sh** - Build script with error handling and dependency checks
- **Package.swift** - Swift Package Manager support (future enhancement)

### Build Targets
- `this` - Command line tool (from this.swift)
- `clipboard-helper` - Menu bar app (from clipboard_helper.swift)
- `all` - Build both tools
- `clean` - Remove build artifacts
- `install` - Build and install to system

### Build Requirements
- macOS 10.15+ (for Swift 5.0+)
- Xcode Command Line Tools
- Swift compiler

## 2. Testing Strategy

### Unit Tests
- **Config Tests**
  - Config loading from ~/.this.config
  - Default config creation
  - Config validation
- **Filtering Logic Tests**
  - Clipboard entry type filtering (text, image, file)
  - Extension-based filtering (.png, .jpg, .txt, etc.)
  - Content-based text filtering
- **File Search Tests**
  - mdfind query construction
  - Date threshold calculations
  - Directory expansion (~/ handling)

### Integration Tests
- **End-to-End Workflow**
  - Clipboard monitoring → storage → retrieval
  - Recent file search with various filters
  - File path output verification
- **File System Operations**
  - Temp file creation and cleanup
  - History file management
  - Directory creation

### Manual Test Scripts
- **test-clipboard.sh** - Test different clipboard content types
- **test-filters.sh** - Test all filtering scenarios
- **test-output.sh** - Test file path output behavior

## 3. Installation System

### Core Components
- **install.sh** - Main installation script
- **uninstall.sh** - Clean removal script
- **com.this.clipboard-helper.plist** - Launch agent for clipboard monitoring
- **default.this.config** - Default configuration template

### Installation Process
1. **Dependency Check**
   - Verify Swift runtime availability
   - Check macOS version compatibility
2. **Build Tools**
   - Compile both Swift executables
   - Verify successful compilation
3. **System Integration**
   - Install binaries to `/usr/local/bin/`
   - Create `~/.this/` data directory
   - Install default config if none exists
   - Set up launch agent for clipboard-helper
4. **Permissions**
   - Request accessibility permissions for clipboard monitoring
   - Set appropriate file permissions

### Installation Features
- Interactive prompts for user preferences
- Backup existing installations
- Rollback capability on failure
- Verification of successful installation

## 4. Distribution Options

### Simple Distribution
- **Single Script Installer**
  - Self-contained install.sh with embedded binaries
  - Interactive setup with sensible defaults
- **Homebrew Formula**
  - Easy installation via `brew install this-tool`
  - Automatic dependency management

### Advanced Distribution
- **macOS Package (.pkg)**
  - Professional installer with GUI
  - System-wide or user-specific installation options
- **Disk Image (.dmg)**
  - Drag-and-drop installation
  - Bundled documentation and examples
- **Auto-updater**
  - Check for updates functionality
  - Seamless update process

## 5. Documentation

### User Documentation
- **README.md** - Quick start and usage examples
- **USAGE.md** - Comprehensive command reference
- **CONFIG.md** - Configuration options and examples
- **TROUBLESHOOTING.md** - Common issues and solutions

### Developer Documentation
- **CONTRIBUTING.md** - Development setup and guidelines
- **ARCHITECTURE.md** - Code structure and design decisions
- **API.md** - Internal API documentation

### System Documentation
- **Man Pages** - Traditional Unix documentation
  - `man this` - Command line tool reference
  - `man this.config` - Configuration file format
  - `man clipboard-helper` - Menu bar app reference

## 6. Implementation Phases

### Phase 1: Basic Build System ✅
- [x] Create Makefile with essential targets
- [x] Implement build.sh with error handling
- [x] Basic installation script
- [x] Swift compilation with optimization flags
- [x] Clean build artifacts management

### Phase 2: Testing Framework ✅
- [x] Comprehensive unit test suite for core functionality
- [x] Integration test scripts with isolated test environments
- [x] Manual testing procedures with timeout handling
- [x] Mock data creation for clipboard history testing
- [x] File system operation testing
- [x] Configuration file testing
- [x] All 12 tests passing successfully

### Phase 2.5: Enhanced CLI Tool ✅
- [x] Help system with --help flag
- [x] Proper error handling and user-friendly messages
- [x] Clipboard monitor dependency checking
- [x] Automatic fallback between mdfind and manual file search
- [x] ISO8601 date handling for clipboard history
- [x] Consistent file path output for command-line integration

### Phase 3: Professional Installation
- [ ] Enhanced installer with GUI prompts
- [ ] Launch agent setup and management
- [ ] Uninstaller with complete cleanup
- [ ] Man page creation and installation
- [ ] Shell completion scripts (bash, zsh, fish)

### Phase 4: Distribution
- [ ] Homebrew formula
- [ ] GitHub releases automation
- [ ] Documentation website

### Phase 5: Advanced Features
- [ ] Auto-updater
- [ ] macOS package installer
- [ ] Performance optimizations

## Next Steps

1. **Immediate** ✅ - Implement Makefile and build.sh
2. **Short-term** ✅ - Create install.sh and comprehensive test suite
3. **Current** - Enhance clipboard monitor integration and auto-start
4. **Medium-term** - Professional installation with launch agents
5. **Long-term** - Distribution via Homebrew and auto-updater

## Success Criteria

- [ ] One-command build: `make`
- [ ] One-command install: `make install`
- [ ] One-command test: `make test`
- [ ] Zero-configuration clipboard monitoring
- [ ] Intuitive command-line interface
- [ ] Reliable file search and filtering
- [ ] Clean uninstallation process
