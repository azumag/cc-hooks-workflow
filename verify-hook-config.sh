#!/bin/bash
# Hook Configuration Verification Script

set -euo pipefail

echo "🔍 Claude Code Hooks Configuration Verification"
echo "==============================================="
echo

# Check current directory
echo "📁 Current project directory: $(pwd)"
echo

# Check for hooks directories
echo "📂 Available hooks directories:"
for dir in hooks hooks_old; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir/ exists"
        if [ -f "$dir/ci-monitor-hook.sh" ]; then
            # Check timeout value in the hook
            timeout_line=$(grep -n "MAX_WAIT_TIME" "$dir/ci-monitor-hook.sh" | head -1)
            echo "    - ci-monitor-hook.sh: $timeout_line"
        fi
    else
        echo "  ✗ $dir/ not found"
    fi
done
echo

# Check workflow script mapping
echo "🔀 Workflow state mapping check:"
if [ -f "workflow.sh" ]; then
    mapping_line=$(grep -A1 -B1 "ci-monitor-hook.sh" workflow.sh | head -3)
    echo "  Current mapping in workflow.sh:"
    echo "  $mapping_line"
else
    echo "  ✗ workflow.sh not found"
fi
echo

# Check Claude Code configuration (common locations)
echo "⚙️  Claude Code configuration check:"
claude_config_locations=(
    "$HOME/.claude-code/settings.json"
    "$HOME/.config/claude-code/settings.json" 
    "./.claude-code/settings.json"
    "./claude-code-settings.json"
)

config_found=false
for config_path in "${claude_config_locations[@]}"; do
    if [ -f "$config_path" ]; then
        echo "  ✓ Found config: $config_path"
        if grep -q "hooks" "$config_path" 2>/dev/null; then
            echo "    - Contains hooks configuration"
            hooks_config=$(grep -A5 -B5 "hooks" "$config_path" 2>/dev/null || echo "    - Could not parse hooks config")
            echo "$hooks_config"
        else
            echo "    - No hooks configuration found"
        fi
        config_found=true
        echo
    fi
done

if [ "$config_found" = false ]; then
    echo "  ⚠️  No Claude Code configuration files found"
    echo "     This might be normal if hooks are configured differently"
fi
echo

# Test hook execution
echo "🧪 Hook execution test:"
if [ -f "hooks/ci-monitor-hook.sh" ]; then
    echo "  Testing new ci-monitor-hook.sh..."
    test_input='{"session_id":"test","transcript_path":"tests/test-data/test-session.jsonl","work_summary_file_path":"/tmp/test"}'
    
    # Run hook and capture first few lines of stderr to see version info
    hook_output=$(echo "$test_input" | ./hooks/ci-monitor-hook.sh 2>&1 | head -5)
    echo "  Output preview:"
    echo "$hook_output" | sed 's/^/    /'
else
    echo "  ✗ hooks/ci-monitor-hook.sh not found"
fi
echo

# Recommendations
echo "💡 Recommendations:"
echo "=================="
echo

if grep -q "MAX_WAIT_TIME=300" hooks_old/ci-monitor-hook.sh 2>/dev/null; then
    echo "❌ ISSUE IDENTIFIED: Old hook with 300s timeout found in hooks_old/"
    echo
    echo "🔧 SOLUTIONS:"
    echo "1. Update your Claude Code hooks configuration to use the new hooks/ directory:"
    echo "   - If using Claude Code settings, point hooks path to: $(pwd)/hooks/"
    echo "   - Ensure ci-monitor-hook.sh points to: $(pwd)/hooks/ci-monitor-hook.sh"
    echo
    echo "2. If you're using a different hooks system, copy the updated hook:"
    echo "   cp hooks/ci-monitor-hook.sh [your-hooks-directory]/"
    echo
    echo "3. Test the configuration:"
    echo "   ./workflow.sh test-session tests/test-data/test-session.jsonl"
    echo
    echo "4. Environment variable override (temporary fix):"
    echo "   export CI_MONITOR_TIMEOUT=900  # 15 minutes"
    echo
else
    echo "✅ Configuration appears correct"
    echo "   If you're still getting 300s timeout, check your Claude Code hooks configuration"
fi

echo "📋 Hook version comparison:"
echo "Old hook timeout: $(grep "MAX_WAIT_TIME=" hooks_old/ci-monitor-hook.sh 2>/dev/null || echo 'Not found')"
echo "New hook timeout: $(grep "MAX_WAIT_TIME=" hooks/ci-monitor-hook.sh 2>/dev/null || echo 'Not found')"