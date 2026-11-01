#!/usr/bin/env bash
# PreToolUse hook on Write|Edit. Blocks writing a feedback memory (type: feedback) into a
# memory/*.md file. Rules about how to work go into CLAUDE.md, which other agents also read.
#
# Decisions:
# - Checks the written text: content for Write, new_string for Edit.
# - Paths are compared with \ replaced by /, so Windows and Unix paths match.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "memory".
# - Portable: no machine paths, bash 3.2 features only (macOS), jq. jq on Windows writes
#   CRLF, so \r is removed from its output.
# - Bypass: environment variable BYPASS_MEMORY=1, set in settings.json "env" or in the shell
#   before starting claude. Write and Edit have no command to prefix, so only the user can
#   bypass this hook.
# - Fails open: any error exits without a decision, and Claude Code runs the write.
set -euo pipefail

input=$(cat)
[ "${BYPASS_MEMORY:-}" = 1 ] && exit 0
[[ $input == *memory* ]] || exit 0
{ IFS= read -r file; IFS= read -r -d '' content || true; } < <(jq -r '(.tool_input.file_path // ""), (.tool_input.content // .tool_input.new_string // "")' <<<"$input")
file=${file%$'\r'}
file=${file//\\//}
content=${content//$'\r'/}

case "$file" in
  */memory/*.md) ;;
  *) exit 0 ;;
esac
feedback='(^|'$'\n'')[[:space:]]*type:[[:space:]]*feedback([[:space:]]|$)'
[[ $content =~ $feedback ]] || exit 0

reason="Feedback memories are not allowed. Ask the user whether to add this rule to the project's CLAUDE.md or to the global CLAUDE.md, and edit the chosen file."
jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
