#!/usr/bin/env bash
# PreToolUse hook on Bash. On Windows, blocks jq calls without -b (--binary).
#
# Decisions:
# - jq on Windows is a native program and writes its output in text mode: every \n becomes
#   \r\n. A file written with `jq ... > file` ends up with CRLF line endings, and \r leaks
#   into pipes and variables (`jq -r ... | while read`, `x=$(jq ...)`). -b writes \n.
# - Every jq call is checked, not only calls that write a file: the \r in pipes and variables
#   causes errors that are hard to see.
# - Windows only ($OSTYPE msys or cygwin). jq on Linux and macOS writes \n, so the hook exits
#   there without doing anything. The input is read before that check, as in every hook, so
#   Claude Code never writes into a pipe the hook has already closed.
# - A jq call is jq (with any path, with or without .exe) as the first word of a command
#   from parse_command in _helpers.sh, which finds jq inside $(...) and behind wrappers such
#   as env and xargs. jq as an argument (`grep jq file`) is not a jq call.
# - -b counts as present when a word after jq is --binary or a short option group that
#   contains b (-b, -rb, -nrb).
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "jq".
# - The input JSON is read with parse_json from _helpers.sh, without starting a
#   process. deny_hook prints the answer with jq and only runs when the hook blocks.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq.
# - Bypass: prefix the command with BYPASS_JQ=1.
# - Fails open: any error exits without a decision, and Claude Code runs the command.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)
case "${OSTYPE:-}" in
  msys* | cygwin*) ;;
  *) exit 0 ;;
esac
[[ $input == *jq* ]] || exit 0

# Parse input
parse_json "$input" command
command=$REPLY
case "$command" in
  BYPASS_JQ=1*) exit 0 ;;
esac

# Find jq call without -b
parse_command "$command"
commands=$REPLY
binary='[[:space:]](--binary|-[A-Za-z]*b[A-Za-z]*)[[:space:]]'
violation=""
while IFS= read -r segment; do
  program=${segment%%[[:space:]]*}
  program=${program##*[/\\]}
  program=${program%.exe}
  [ "$program" = jq ] || continue
  [[ " $segment " =~ $binary ]] && continue
  violation=$segment
  break
done <<<"$commands"
[ -n "$violation" ] || exit 0

# Deny
deny_hook "On Windows jq writes CRLF line endings. Add -b (--binary) to '$violation' so it writes LF. If CRLF is intended, prefix the command with 'BYPASS_JQ=1 '."
