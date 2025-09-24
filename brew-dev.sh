#!/bin/bash
# Development helper for Homebrew formula testing

set -e

TAP_NAME="local/this/this"
FORMULA_PATH="Formula/this.rb"

# Create local tap if it doesn't exist
create_local_tap() {
    local tap_dir="$(brew --repository)/Library/Taps/local/homebrew-this"
    local current_dir="$(pwd)"
    
    if [[ ! -d "$tap_dir" ]]; then
        echo "Creating local tap..."
        mkdir -p "$tap_dir"
    fi
    
    echo "Updating local tap with current directory: $current_dir"
    
    # Create a local development version of the formula that builds from current directory
    cat > "$tap_dir/this.rb" << EOF
class This < Formula
  desc "Context-aware clipboard and file tool"
  homepage "https://github.com/clausd/this-cli"
  url "https://github.com/clausd/this-cli.git", using: :git, revision: "HEAD"
  version "1.0.0-dev"

  depends_on :macos

  def install
    # Change to the source directory
    cd "$current_dir"
    
    # Build the tools
    system "make", "all"
    
    # Install binaries
    bin.install "build/this"
    bin.install "build/clipboard-helper"
    
    # Install default config template
    (etc/"this").mkpath
    (etc/"this").install ".this.config" => "config.json"
  end

  def post_install
    # Create user data directory
    (var/"this").mkpath
    
    # Create user config if it doesn't exist
    user_config = Pathname.new(Dir.home) + ".this.config"
    unless user_config.exist?
      user_config.write <<~EOS
        {
          "searchDirectories": [
            "~/Documents",
            "~/Desktop", 
            "~/Downloads"
          ],
          "maxRecentDays": 3,
          "maxFreshnessMinutes": 10
        }
      EOS
    end
    
    # Install launch agent for current user
    launch_agent_dir = Pathname.new(Dir.home) + "Library/LaunchAgents"
    launch_agent_dir.mkpath
    launch_agent_plist = launch_agent_dir + "com.this.clipboard-helper.plist"
    
    launch_agent_plist.write <<~EOS
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key>
          <string>com.this.clipboard-helper</string>
          <key>ProgramArguments</key>
          <array>
              <string>#{bin}/clipboard-helper</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>StandardOutPath</key>
          <string>#{var}/this/clipboard-helper.log</string>
          <key>StandardErrorPath</key>
          <string>#{var}/this/clipboard-helper.error.log</string>
      </dict>
      </plist>
    EOS
  end

  service do
    run [opt_bin/"clipboard-helper"]
    keep_alive true
    log_path var/"this/clipboard-helper.log"
    error_log_path var/"this/clipboard-helper.error.log"
  end

  test do
    # Test that binaries exist and are executable
    assert_predicate bin/"this", :exist?
    assert_predicate bin/"clipboard-helper", :exist?
    
    # Test help output
    output = shell_output("#{bin}/this --help")
    assert_match "Context-aware clipboard and file tool", output
    
    # Test status command (should work even without clipboard data)
    system bin/"this", "status"
  end
end
EOF
    
    echo "Created/updated local tap at: $tap_dir"
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
        tap_dir="$(brew --repository)/Library/Taps/local/homebrew-this"
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
