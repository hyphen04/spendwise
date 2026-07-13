#!/usr/bin/env bash
# PostToolUse hook (advisory, non-blocking): after an Edit/Write to an AI-outbound
# or PII-bearing file, remind to run the spendwise-privacy-audit skill before
# committing. Reads the tool event JSON from stdin (Claude Code hooks protocol).
# Exit 0 always — this is advisory only.

set -u

input="$(cat)"

# Extract file_path from the tool_input. tool_input is a JSON object; file_path
# is present for Edit/Write. Use a simple grep/sed parse to stay portable and
# avoid a jq dependency.
file_path="$(printf '%s' "$input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')"

[ -z "$file_path" ] && exit 0

# Match the AI-outbound boundary files and the PII-bearing tables.
ai_boundary='lib/features/ai/domain/(ai_payload_builder|ai_gatekeeper|schema_metadata|sql_guard)\.dart$'
pii_tables='lib/data/db/tables/(due_|ai_|goals_table|recurring_items_table)'

if printf '%s' "$file_path" | grep -Eq "$ai_boundary" || printf '%s' "$file_path" | grep -Eq "$pii_tables"; then
  cat <<'EOF' >&2
[spendwise] Reminder: you just edited an AI-outbound boundary file or a PII-bearing
table. Run the `spendwise-privacy-audit` skill (or @spendwise-privacy-auditor)
before committing this change — no personal details may leave the device.
EOF
fi

exit 0