# Claude Code Hooks Workflow

A tool for executing automated workflows using Claude Code's Stop Hooks feature.

## Overview

This tool uses hooks triggered at the end of Claude Code sessions to automate workflows such as test execution, code review, commits, and cleanup processes.

## Basic Usage

### 1. Create Configuration File

Copy `workflow.json.example` to `.claude/workflow.json` in your project:

```bash
cp workflow.json.example .claude/workflow.json
```

Then customize the workflow for your project needs. The configuration file must be placed under the `.claude` directory.

### Configuration File Location

The workflow.sh script searches for the configuration file in the following order:
1. Git repository root: `<git-root>/.claude/workflow.json` (if in a git repository)
2. Current directory: `./.claude/workflow.json` (fallback)

### 2. Set up workflow.sh

Make `workflow.sh` executable and configure it as a Claude Code Stop Hook:

```bash
chmod +x workflow.sh
```

### 3. Start Using

When you end a Claude Code session, the configured workflow will automatically execute.

## Configuration File Details

### Hook Configuration Structure

Each hook consists of the following elements:

- `launch`: State phrase that triggers the hook (null for initial execution)
- `prompt`: Prompt to send to Claude Code (prompt-type hook)
- `path`: Path to the script to execute (path-type hook)
- `next`: Next state phrase (output on script success)
- `handling`: Error handling mode ("pass", "block", "raise")

### Hook Types

#### 1. Prompt-type Hook

```json
{
  "launch": null,
  "prompt": "Run tests. Display TEST_COMPLETED when complete."
}
```

- Sends prompts directly to Claude Code
- Can reference work content using $WORK_SUMMARY

#### 2. Path-type Hook

```json
{
  "launch": "TEST_COMPLETED",
  "path": "self-review.sh",
  "next": "SELF_REVIEWED",
  "handling": "pass"
}
```

- Executes specified script
- References scripts in hooks/ directory
- Absolute paths are also supported

## Error Handling Modes

### 1. pass (Default)
- Continues workflow even if script exits with error
- Displays warning message

### 2. block
- Outputs decision_block JSON if script exits with error
- Delegates handling to Claude Code

### 3. raise
- Stops entire workflow if script exits with error
- Displays error message

## $WORK_SUMMARY Feature

You can reference work content summaries in other hooks:

```json
{
  "launch": "REVIEW_NEEDED",
  "prompt": "Please review the following work:\n\n$WORK_SUMMARY\n\nIf there are no issues, display REVIEW_PASSED."
}
```

## Stopping the Workflow Loop

To properly terminate the workflow sequence, you should include a stop hook at the end of your configuration. This prevents the workflow from continuing indefinitely:

```json
{
  "launch": "FINAL_STATE",
  "path": "workflow.sh",
  "args": ["--stop"]
}
```

**Important Notes:**
- The `--stop` argument tells `workflow.sh` to exit immediately without processing
- This should be the final hook in your workflow sequence
- Without this stop hook, the workflow may continue indefinitely or exhibit unexpected behavior
- The `launch` state should match the final state phrase from your previous hook

**Example Complete Workflow:**
```json
{
  "hooks": [
    {
      "launch": null,
      "path": "hooks/test.sh",
      "next": "TEST_COMPLETED",
      "handling": "block"
    },
    {
      "launch": "TEST_COMPLETED",
      "prompt": "Review and commit changes. Display WORK_FINISHED when done."
    },
    {
      "launch": "WORK_FINISHED",
      "path": "workflow.sh",
      "args": ["--stop"]
    }
  ]
}
```

## Basic Troubleshooting

### 1. Configuration File Not Found
```
WARNING: Configuration file not found: .claude/workflow.json
INFO: Using default configuration
```
- Copy `workflow.json.example` to `.claude/workflow.json`
- The configuration file must be placed in the `.claude` directory
- Or you can run with default configuration

### 2. Script Not Found
```
ERROR: Hook script not found: hooks/script.sh
```
- Check if script file exists in hooks/ directory
- Verify file path spelling

### 3. No Execute Permission
```
ERROR: Hook script lacks execute permission: hooks/script.sh
```
- Grant execute permission with `chmod +x hooks/script.sh`

### 4. Missing Dependencies
```
ERROR: Following dependencies not found: jq
```
- Install required commands: `brew install jq` (macOS)

### 5. Transcript File Not Found
```
ERROR: Claude transcripts directory not found
```
- Verify Claude Code is properly installed
- Check if `~/.claude/projects/` directory exists

### 6. Claude AI Rate Limit Errors
If you encounter rate limit errors from Claude AI, the workflow will:
- Automatically skip error messages and find the last valid assistant response
- Continue with the workflow using the most recent valid work summary

### 7. CI Check Hanging Issue
If ci-check.sh appears to hang indefinitely:
- This was fixed to properly handle projects without GitHub Actions
- The script now exits normally when no workflow runs are found
- No manual intervention required for projects without CI setup

## Cross-platform Compatibility

This tool supports both Linux and macOS environments:
- **Linux**: Uses `tac` command for reverse text processing
- **macOS**: Uses `tail -r` command as an alternative
- **Fallback**: Works even without these commands with slightly reduced performance

## Requirements

- jq
- grep
- tail
- tac or tail -r (platform-specific, see Cross-platform Compatibility section)
- mktemp
- bash (4.0+ recommended)
