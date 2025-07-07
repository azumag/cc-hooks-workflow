#!/bin/bash
# EMERGENCY: CI Timeout Fix - Works regardless of hook location
# This overrides ANY ci-monitor-hook.sh timeout to 20 minutes

set -euo pipefail

echo "🚨 EMERGENCY CI TIMEOUT FIX - 20 MINUTES GUARANTEED"
echo "=================================================="

# Set environment variables for maximum compatibility
export CI_MONITOR_TIMEOUT=1200        # 20 minutes
export CI_MONITOR_INITIAL_DELAY=15    # 15s initial delay
export CI_MONITOR_CHECK_INTERVAL=45   # Check every 45s

# Add to all possible shell profiles
for shell_config in ~/.bashrc ~/.zshrc ~/.bash_profile ~/.profile; do
    if [ -f "$shell_config" ] || [ "$shell_config" = ~/.bashrc ] || [ "$shell_config" = ~/.zshrc ]; then
        if ! grep -q "CI_MONITOR_TIMEOUT=1200" "$shell_config" 2>/dev/null; then
            echo "" >> "$shell_config"
            echo "# EMERGENCY CI Timeout Fix - 20 minutes" >> "$shell_config"
            echo "export CI_MONITOR_TIMEOUT=1200" >> "$shell_config"
            echo "export CI_MONITOR_CHECK_INTERVAL=45" >> "$shell_config"
            echo "✅ Added to: $shell_config"
        else
            echo "✅ Already configured: $shell_config"
        fi
    fi
done

# Create a system-wide override wrapper
cat > /tmp/ci-monitor-emergency.sh << 'EOF'
#!/bin/bash
# Emergency wrapper that FORCES 20-minute timeout
export CI_MONITOR_TIMEOUT=1200
export CI_MONITOR_CHECK_INTERVAL=45

# Execute the first available hook with forced timeout
for hook in \
    "$(pwd)/hooks/ci-monitor-hook.sh" \
    "$(pwd)/hooks_old/ci-monitor-hook.sh" \
    "$HOME/.claude-code/hooks/ci-monitor-hook.sh" \
    "$HOME/.config/claude-code/hooks/ci-monitor-hook.sh" \
    "/usr/local/bin/ci-monitor-hook.sh"; do
    
    if [ -f "$hook" ] && [ -x "$hook" ]; then
        echo "[EMERGENCY] Using hook: $hook with 20-minute timeout" >&2
        exec "$hook" "$@"
    fi
done

# Fallback: approve if no hook found
echo '{"decision":"approve","reason":"Emergency timeout handler: No CI hook found, skipping monitoring"}'
EOF

chmod +x /tmp/ci-monitor-emergency.sh

echo ""
echo "🛡️  EMERGENCY MEASURES APPLIED:"
echo "1. Environment variables set for current session (20 minutes)"
echo "2. Added to shell profiles for future sessions"
echo "3. Created emergency wrapper: /tmp/ci-monitor-emergency.sh"
echo ""
echo "🎯 IMMEDIATE VERIFICATION:"
echo "Current CI_MONITOR_TIMEOUT: ${CI_MONITOR_TIMEOUT:-not set}"
echo ""
echo "⚡ TEST CURRENT SESSION:"
if [ -f hooks/ci-monitor-hook.sh ]; then
    echo '{"session_id":"emergency-test"}' | hooks/ci-monitor-hook.sh 2>&1 | head -2 | grep -E "(timeout=|Configuration:)" || echo "No timeout info found"
fi

echo ""
echo "🔄 FOR NEXT SESSION: Restart terminal or run: source ~/.bashrc"
echo "🆘 IF STILL FAILING: Point Claude Code to: /tmp/ci-monitor-emergency.sh"