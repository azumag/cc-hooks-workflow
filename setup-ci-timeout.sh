#!/bin/bash
# Permanent CI Timeout Fix Setup
# Run once to configure your environment for extended CI monitoring

set -euo pipefail

echo "🔧 Setting up permanent CI timeout fix..."

# Add to shell profile
SHELL_RC=""
if [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
    SHELL_RC="$HOME/.bash_profile"
fi

if [ -n "$SHELL_RC" ]; then
    if ! grep -q "CI_MONITOR_TIMEOUT" "$SHELL_RC"; then
        echo "" >> "$SHELL_RC"
        echo "# Claude Code CI Monitor - Extended Timeout" >> "$SHELL_RC"
        echo "export CI_MONITOR_TIMEOUT=900  # 15 minutes" >> "$SHELL_RC"
        echo "export CI_MONITOR_CHECK_INTERVAL=30  # Check every 30 seconds" >> "$SHELL_RC"
        echo "✅ Added CI timeout settings to $SHELL_RC"
    else
        echo "✅ CI timeout settings already in $SHELL_RC"
    fi
else
    echo "⚠️  Could not find shell profile, please manually add:"
    echo "   export CI_MONITOR_TIMEOUT=900"
fi

# Set for current session
export CI_MONITOR_TIMEOUT=900
export CI_MONITOR_CHECK_INTERVAL=30

echo "✅ CI monitor timeout set to 15 minutes for current session"
echo "✅ New shell sessions will automatically use 15-minute timeout"
echo ""
echo "🎯 Next steps:"
echo "1. Restart your terminal or run: source $SHELL_RC"
echo "2. Verify with: echo \$CI_MONITOR_TIMEOUT (should show 900)"
echo "3. Test CI monitoring - it will now wait 15 minutes instead of 5"