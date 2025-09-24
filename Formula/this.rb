class This < Formula
  desc "Context-aware clipboard and file tool"
  homepage "https://github.com/yourusername/this-tool"
  url "https://github.com/yourusername/this-tool.git", using: :git, tag: "v1.0.0"
  version "1.0.0"
  head "https://github.com/yourusername/this-tool.git", branch: "main"

  depends_on :macos

  def install
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
