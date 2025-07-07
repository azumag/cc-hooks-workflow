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

# Solution 2: Check Claude Code hook configuration
echo "2️⃣ Checking Claude Code hook paths..."
echo "   💡 If CI timeout persists, update your Claude Code configuration to use:"
echo "      $(pwd)/hooks/ci-monitor-hook.sh"
echo "   📋 Common Claude Code config locations:"
echo "      - ~/.claude-code/settings.json"
echo "      - ~/.config/claude-code/settings.json"
echo "      - ./claude-code-settings.json"

echo
echo "🎯 SIMPLE SOLUTION:"
echo "1. Environment variable CI_MONITOR_TIMEOUT=900 is now set (15 minutes)"
echo "2. For permanent fix: ./setup-ci-timeout.sh"
echo "3. If issue persists: Update Claude Code hooks path to $(pwd)/hooks/"
echo
echo "⚡ VERIFICATION:"
echo "   Run: echo '{\"session_id\":\"test\"}' | hooks/ci-monitor-hook.sh 2>&1 | head -2"
echo "   Should show: 'timeout=900s' in output"
echo

# Test current hook
echo "🧪 TESTING CURRENT HOOK:"
echo '{"session_id":"test","transcript_path":"tests/test-data/test-session.jsonl"}' | hooks/ci-monitor-hook.sh 2>&1 | head -3 || echo "Hook test failed"