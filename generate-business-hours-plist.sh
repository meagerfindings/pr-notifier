#!/bin/bash

# Generate plist entries for business hours (8 AM - 4 PM MT, Mon-Fri, every 10 minutes)

cat > com.mat.github-mentions-monitor.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mat.github-mentions-monitor</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/Users/mat/git/pr-notifier/github-mentions-monitor.sh</string>
    </array>
    
    <!-- Run every 10 minutes during business hours (8 AM - 4 PM MT, Mon-Fri) -->
    <key>StartCalendarInterval</key>
    <array>
EOF

# Generate entries for Monday-Friday (1-5), 8 AM - 3:50 PM (every 10 minutes)
for weekday in {1..5}; do
    for hour in {8..15}; do
        for minute in 0 10 20 30 40 50; do
            cat >> com.mat.github-mentions-monitor.plist << EOF
        <dict>
            <key>Weekday</key>
            <integer>${weekday}</integer>
            <key>Hour</key>
            <integer>${hour}</integer>
            <key>Minute</key>
            <integer>${minute}</integer>
        </dict>
EOF
        done
    done
done

cat >> com.mat.github-mentions-monitor.plist << 'EOF'
    </array>
    
    <key>StandardOutPath</key>
    <string>/tmp/github-mentions-monitor.out</string>
    
    <key>StandardErrorPath</key>
    <string>/tmp/github-mentions-monitor.err</string>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
    
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

echo "Generated business hours plist with $(grep -c '<dict>' com.mat.github-mentions-monitor.plist) time slots"
