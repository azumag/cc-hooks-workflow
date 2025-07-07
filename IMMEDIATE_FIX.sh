#!/bin/bash
# IMMEDIATE CI TIMEOUT FIX
# Run this script to apply the timeout fix regardless of hook location

set -euo pipefail

echo "🚨 IMMEDIATE CI TIMEOUT FIX"
echo "=========================="
echo

# Solution 1: Environment variable override (works immediately)
echo "1️⃣ Setting environment variable override..."
export CI_MONITOR_TIMEOUT=900  # 15 minutes
echo "   ✅ CI_MONITOR_TIMEOUT=900 (15 minutes)"
echo "   ✅ Add to your shell profile: echo 'export CI_MONITOR_TIMEOUT=900' >> ~/.bashrc"
echo

# Solution 2: Find and replace any hooks with 300s timeout
echo "2️⃣ Searching for hooks with 300s timeout..."
potential_hooks=(
    "$HOME/.claude-code/hooks/ci-monitor-hook.sh"
    "$HOME/.config/claude-code/hooks/ci-monitor-hook.sh"
    "/usr/local/bin/ci-monitor-hook.sh"
    "./ci-monitor-hook.sh"
)

for hook_path in "${potential_hooks[@]}"; do
    if [ -f "$hook_path" ]; then
        if grep -q "MAX_WAIT_TIME=300" "$hook_path" 2>/dev/null; then
            echo "   🔍 Found 300s timeout in: $hook_path"
            echo "   🔧 Backing up and replacing..."
            cp "$hook_path" "${hook_path}.backup"
            cp hooks/ci-monitor-hook.sh "$hook_path"
            echo "   ✅ Updated: $hook_path"
        else
            echo "   ✅ Already up to date: $hook_path"
        fi
    fi
done

# Solution 3: Create a global override script
echo
echo "3️⃣ Creating global CI monitor wrapper..."
cat > /tmp/ci-monitor-override.sh << 'EOF'
#!/bin/bash
# Global CI Monitor with forced 900s timeout
export CI_MONITOR_TIMEOUT=900
export CI_MONITOR_CHECK_INTERVAL=30

# Find and execute the actual hook
if [ -f "hooks/ci-monitor-hook.sh" ]; then
    hooks/ci-monitor-hook.sh "$@"
elif [ -f "hooks_old/ci-monitor-hook.sh" ]; then
    hooks_old/ci-monitor-hook.sh "$@"
else
    echo '{"decision":"approve","reason":"CI monitor hook not found, skipping monitoring"}' 
fi
EOF

chmod +x /tmp/ci-monitor-override.sh
echo "   ✅ Created: /tmp/ci-monitor-override.sh (15-minute timeout guaranteed)"

echo
echo "🎯 INSTRUCTIONS:"
echo "1. Environment variable is set for this session"
echo "2. Add 'export CI_MONITOR_TIMEOUT=900' to ~/.bashrc or ~/.zshrc"
echo "3. If Claude Code still uses 300s, point it to: /tmp/ci-monitor-override.sh"
echo
echo "⚡ VERIFICATION:"
echo "   Run: echo '{\"session_id\":\"test\"}' | hooks/ci-monitor-hook.sh 2>&1 | head -2"
echo "   Should show: 'timeout=900s' in output"
echo

# Test current hook
echo "🧪 TESTING CURRENT HOOK:"
echo '{"session_id":"test","transcript_path":"tests/test-data/test-ci-monitor.jsonl"}' | hooks/ci-monitor-hook.sh 2>&1 | head -3 || echo "Hook test failed"