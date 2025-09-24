# This Tool - Context-aware clipboard and file management

A macOS command-line tool that provides intelligent access to clipboard history and recent files.

## Installation

### Homebrew (Recommended)

```bash
# Install from local development tap
./brew-dev.sh install

# Start the clipboard monitoring service
./brew-dev.sh service-start

# Or install from a published tap (when available)
brew tap yourusername/this-tool
brew install this
```

### Manual Installation

```bash
# Build and install
make install

# Or use the install script directly
./install.sh
```

## Usage

```bash
# Get most recent clipboard content or file
this

# Filter by type
this image              # Most recent image
this txt               # Most recent text file
this recent pdf        # Most recent PDF file

# List recent candidates
this -l                # List 10 most recent items
this -l image          # List 10 most recent images

# Get specific item by index
this -3                # Get 3rd most recent item
this -1 txt            # Get most recent text item

# Status and help
this status            # Check system status
this --help            # Show help
```

## Integration Examples

```bash
# Open most relevant file
open `this`

# Copy most relevant file
cp `this` backup/

# View content
cat `this`

# Edit most recent text file
vim `this txt`
```

## Configuration

Configuration file: `~/.this.config`

```json
{
  "searchDirectories": [
    "~/Documents",
    "~/Desktop", 
    "~/Downloads"
  ],
  "maxRecentDays": 3,
  "maxFreshnessMinutes": 10
}
```

## Service Management

```bash
# With Homebrew
brew services start this
brew services stop this
brew services restart this

# Manual
make start-service
make stop-service
make restart-service
```

## Uninstallation

```bash
# With Homebrew
brew uninstall this

# Manual
make uninstall
# or
./uninstall.sh
```
