# cc-hooks-workflow

A simple workflow system using Claude Code hooks for test → review → commit → stop flow.

## Usage

Run `workflow.sh` to start the workflow. The system will guide you through:
1. Testing (`test.sh`)
2. Self-review (`self-review.sh`) 
3. Commit (`commit.sh`)
4. Stop (`stop.sh`)

## Dependencies

- jq, grep, tail, mktemp (checked automatically)