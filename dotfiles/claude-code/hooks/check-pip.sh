#!/usr/bin/env bash
# PreToolUse hook on Bash. Blocks pip in uv projects.
#
# Decisions:
# - Only in uv projects: uv.lock, or a [tool.uv] section in pyproject.toml, in the command's
#   folder or a parent folder. Projects that use pip or poetry are not touched.
# - Blocks pip, pip3 and python/python3/py [-X.Y] -m pip, with or without a path or .exe.
#   `uv pip` is allowed: its first word is uv.
# - Commands are split with parse_command from _helpers.sh.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "pip". The uv project lookup runs only after
#   a pip command is found. Files are read with $(<file), not `read -d ''` (one byte per
#   system call).
# - The input JSON is read with parse_json from _helpers.sh, without starting a
#   process. deny_hook prints the answer with jq and only runs when the hook blocks.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq.
# - Bypass: prefix the command with BYPASS_PIP=1.
# - Fails open: any error exits without a decision, and Claude Code runs the command.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)
[[ $input == *pip* ]] || exit 0

# Parse input
parse_json "$input" cwd
directory=$REPLY
parse_json "$input" command
command=$REPLY
case "$command" in
  BYPASS_PIP=1*) exit 0 ;;
esac

# Find pip command
parse_command "$command"
commands=$REPLY
pip='^(pip3?|(python3?|py)([[:space:]]+-[0-9.]+)?[[:space:]]+-m[[:space:]]+pip)([[:space:]]|$)'
pip_used=false
while IFS= read -r segment; do
  program=${segment%%[[:space:]]*}
  arguments=${segment#"$program"}
  program=${program##*[/\\]}
  program=${program%.exe}
  if [[ $program$arguments =~ $pip ]]; then
    pip_used=true
    break
  fi
done <<<"$commands"
[ "$pip_used" = true ] || exit 0

# Find uv project
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

# Deny
deny_hook "$project is a uv project. Use uv instead of pip: 'uv add', 'uv remove', 'uv sync', or 'uv pip'. If pip is required, prefix the command with 'BYPASS_PIP=1 '."
