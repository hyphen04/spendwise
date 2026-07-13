#!/usr/bin/env bash
# PreToolUse hook (blocking): before a `git commit` Bash command runs, execute
# `flutter analyze lib/` and abort the commit on error. Reads the tool event
# JSON from stdin (Claude Code hooks protocol).
#
# Exit codes:
#   0  -> allow the commit to proceed
#   2  -> block the commit (analyze failed); stderr is surfaced to Claude.

set -u

input="$(cat)"

# Extract the Bash command from tool_input.command.
command="$(printf '%s' "$input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"

# Only act on git commit invocations.
if ! printf '%s' "$command" | grep -Eq 'git[[:space:]]+commit'; then
  exit 0
fi

# Run flutter analyze lib/ from the repo root. The hook runs with cwd at the
# project root.
if ! flutter analyze lib/ >/tmp/spendwise_precommit_analyze.log 2>&1; then
  cat <<'EOF' >&2
[spendwise] Pre-commit guard: `flutter analyze lib/` failed — commit aborted.
Fix the analyze errors before committing. Output:
EOF
  cat /tmp/spendwise_precommit_analyze.log >&2
  exit 2
fi

exit 0