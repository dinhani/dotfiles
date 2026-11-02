#!/usr/bin/env bash
# PreToolUse hook on Bash. Blocks uv commands that do not set UV_PROJECT_ENVIRONMENT
# explicitly in the command.
#
# Decisions:
# - Without UV_PROJECT_ENVIRONMENT, uv creates the project venv as .venv inside the project.
#   The venv must live outside the project, at the path the project's justfile exports.
# - Every uv command is checked, in any folder and with any subcommand. The variable counts
#   as set only when the command text assigns it a non-empty value: a VAR=value prefix,
#   `env VAR=value` or `export VAR=value`. The environment of the hook process is not
#   checked: it is the environment of Claude Code, not of the shell that runs the command.
# - A uv command is uv (with any path, with or without .exe) as the first word of a command
#   from parse_command in _helpers.sh. uvx is a different program and is not checked.
# - The assignment is searched in the whole command text, not per command: parse_command
#   removes VAR=value prefixes.
# - The deny message includes the value from `just --evaluate UV_PROJECT_ENVIRONMENT` when
#   the project's justfile defines it. just only runs when the hook blocks.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "uv".
# - The input JSON is read with parse_json from _helpers.sh, without starting a
#   process. deny_hook prints the answer with jq and only runs when the hook blocks.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq and just.
# - Bypass: prefix the command with BYPASS_UV_ENV=1.
# - Fails open: any error exits without a decision, and Claude Code runs the command.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)
[[ $input == *uv* ]] || exit 0

# Parse input
parse_json "$input" cwd
directory=$REPLY
parse_json "$input" command
command=$REPLY
case "$command" in
  BYPASS_UV_ENV=1*) exit 0 ;;
esac

# Find uv command
parse_command "$command"
commands=$REPLY
violation=""
while IFS= read -r segment; do
  program=${segment%%[[:space:]]*}
  program=${program##*[/\\]}
  program=${program%.exe}
  if [ "$program" = uv ]; then
    violation=$segment
    break
  fi
done <<<"$commands"
[ -n "$violation" ] || exit 0

# Check explicit assignment
assignment="(^|[^A-Za-z0-9_])UV_PROJECT_ENVIRONMENT=([^[:space:]\"';&|]|\"[^\"]|'[^'])"
[[ $command =~ $assignment ]] && exit 0

# Deny
cd "${directory:-.}" 2>/dev/null || true
environment=$(just --evaluate UV_PROJECT_ENVIRONMENT 2>/dev/null) || environment=""
environment=${environment//$'\r'/}
if [ -n "$environment" ]; then
  deny_hook "'$violation' runs without UV_PROJECT_ENVIRONMENT, so uv would create .venv inside the project. Prefix the command with UV_PROJECT_ENVIRONMENT='$environment' (the value the justfile exports), or run the matching just recipe. To run it as is, prefix the command with 'BYPASS_UV_ENV=1 '."
fi
deny_hook "'$violation' runs without UV_PROJECT_ENVIRONMENT, so uv would create .venv inside the project. Prefix the command with UV_PROJECT_ENVIRONMENT=<local data folder>/uv/envs/<project> (on Windows: \$LOCALAPPDATA/uv/envs/<project>). To run it as is, prefix the command with 'BYPASS_UV_ENV=1 '."
