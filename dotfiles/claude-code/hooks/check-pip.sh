#!/usr/bin/env bash
# PreToolUse hook on Bash. Blocks pip in uv projects.
#
# Decisions:
# - Only in uv projects: uv.lock, or a [tool.uv] section in pyproject.toml, in the command's
#   folder or a parent folder. Projects that use pip or poetry are not touched.
# - Blocks pip, pip3 and python/python3/py [-X.Y] -m pip, with or without a path or .exe.
#   `uv pip` is allowed: its first word is uv.
# - Commands are split on && || ; | and leading VAR=value, sudo, exec, time are skipped.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "pip". The uv project lookup runs only after
#   a pip command is found. Files are read with $(<file), not `read -d ''` (one byte per
#   system call).
# - Portable: no machine paths, bash 3.2 features only (macOS), jq. jq on Windows writes
#   CRLF, so \r is removed from its output.
# - Bypass: prefix the command with BYPASS_PIP=1.
# - Fails open: any error exits without a decision, and Claude Code runs the command.
set -euo pipefail

input=$(cat)
[[ $input == *pip* ]] || exit 0
{ IFS= read -r directory; IFS= read -r -d '' command || true; } < <(jq -r '(.cwd // ""), (.tool_input.command // "")' <<<"$input")
directory=${directory%$'\r'}
command=${command//$'\r'/}

case "$command" in
  BYPASS_PIP=1*) exit 0 ;;
esac

segments=${command//&&/$'\n'}
segments=${segments//||/$'\n'}
segments=${segments//;/$'\n'}
segments=${segments//|/$'\n'}
prefix='^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|exec|time)[[:space:]]+)*(.*)$'
pip='^(pip3?|(python3?|py)([[:space:]]+-[0-9.]+)?[[:space:]]+-m[[:space:]]+pip)([[:space:]]|$)'
pip_used=false
while IFS= read -r segment; do
  [[ $segment =~ $prefix ]] && segment=${BASH_REMATCH[3]}
  word=${segment%%[[:space:]]*}
  arguments=${segment#"$word"}
  word=${word##*[/\\]}
  word=${word%.exe}
  if [[ $word$arguments =~ $pip ]]; then
    pip_used=true
    break
  fi
done <<<"$segments"
[ "$pip_used" = true ] || exit 0

cd "${directory:-.}" 2>/dev/null || exit 0
project=""
current=$PWD
while [ -z "$project" ]; do
  if [ -f "$current/uv.lock" ]; then
    project=${current:-/}
  elif [ -f "$current/pyproject.toml" ]; then
    pyproject=$(<"$current/pyproject.toml")
    [[ $'\n'$pyproject == *$'\n[tool.uv'* ]] && project=${current:-/}
  fi
  [ -n "$current" ] || break
  current=${current%/*}
done
[ -n "$project" ] || exit 0

reason="$project is a uv project. Use uv instead of pip: 'uv add', 'uv remove', 'uv sync', or 'uv pip'. If pip is required, prefix the command with 'BYPASS_PIP=1 '."
jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
