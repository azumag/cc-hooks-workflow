# CI Monitoring Timeout Fix (300s → 600s+)

## 🚨 Issue
Getting "CI monitoring timeout reached after 300s" error.

## 🔍 Root Cause
Your Claude Code configuration is pointing to the old hook with 300s timeout:
- ❌ `hooks_old/ci-monitor-hook.sh` (300s timeout)
- ✅ `hooks/ci-monitor-hook.sh` (600s timeout, configurable)

## 🔧 Quick Solutions

### Option 1: Environment Variable (Immediate Fix)
```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export CI_MONITOR_TIMEOUT=900        # 15 minutes
export CI_MONITOR_CHECK_INTERVAL=30  # Check every 30 seconds
```

### Option 2: Update Claude Code Hooks Path
Update your Claude Code configuration to use:
```
/Users/azumag/work/cc-hooks-workflow/hooks/ci-monitor-hook.sh
```

### Option 3: Replace Old Hook
```bash
cp hooks/ci-monitor-hook.sh hooks_old/ci-monitor-hook.sh
```

## 🧪 Verify Fix
```bash
# Run verification script
./verify-hook-config.sh

# Test the hook directly
echo '{"session_id":"test","transcript_path":"tests/test-data/test-session.jsonl"}' | hooks/ci-monitor-hook.sh
```

## ⚙️ Configuration Options
```bash
# Available environment variables:
CI_MONITOR_TIMEOUT=600        # Total timeout (default: 10 minutes)
CI_MONITOR_INITIAL_DELAY=10   # Wait before first check (default: 10s)
CI_MONITOR_CHECK_INTERVAL=15  # Time between checks (default: 15s)
```

## 📋 Expected Output After Fix
```
[ci-monitor-hook] Starting CI monitoring for session: xxx (v2.0-enhanced-timeout)
[ci-monitor-hook] Configuration: timeout=600s, check_interval=15s
```

## 🔗 Related Files
- `hooks/ci-monitor-hook.sh` - New version with 600s timeout
- `hooks_old/ci-monitor-hook.sh` - Old version with 300s timeout  
- `verify-hook-config.sh` - Diagnostic script