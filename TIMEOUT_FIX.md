# CI Monitoring Timeout Fix (300s → 600s+)

## 🚨 Issue
Getting "CI monitoring timeout reached after 300s" error.

## 🔍 Root Cause
Your Claude Code configuration is pointing to the old hook with 300s timeout:
- ❌ Old hooks with 300s timeout  
- ✅ `hooks/ci-monitor-hook.sh` (900s timeout, configurable)

## 🔧 Simple Solutions (In Order of Preference)

### ✅ Option 1: Environment Variable (Recommended)
```bash
# Immediate fix - run once:
export CI_MONITOR_TIMEOUT=900

# Permanent fix - add to shell profile:
echo 'export CI_MONITOR_TIMEOUT=900' >> ~/.bashrc  # or ~/.zshrc
```

### 🔧 Option 2: Update Claude Code Configuration 
Update your Claude Code hooks path to:
```
/path/to/your/project/hooks/ci-monitor-hook.sh
```
Check these common config locations:
- `~/.claude-code/settings.json`
- `~/.config/claude-code/settings.json`

### 🆘 Option 3: Run Setup Script
```bash
./setup-ci-timeout.sh  # Automatically configures environment variables
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
CI_MONITOR_TIMEOUT=900        # Total timeout (default: 15 minutes)
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