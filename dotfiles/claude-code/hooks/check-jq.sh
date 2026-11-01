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
#   there without doing anything.
# - A jq call is jq (with any path, with or without .exe) as the first word of a command,
#   after VAR=value assignments and the wrappers sudo, exec, time, env, command, nohup and
#   xargs (with its options). Commands are split on && || ; | $( ( ) and backticks, so jq
#   inside $(...) is found. jq as an argument (`grep jq file`) is not a jq call.
# - -b counts as present when a word after jq is --binary or a short option group that
#   contains b (-b, -rb, -nrb).
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "jq".
# - Portable: no machine paths, bash 3.2 features only (macOS), jq. The hook's own jq calls
#   use -b, which is safe because the hook only runs past the $OSTYPE check on Windows.
# - Bypass: prefix the command with BYPASS_JQ=1.
# - Fails open: any error exits without a decision, and Claude Code runs the command.
set -euo pipefail

case "${OSTYPE:-}" in
  msys* | cygwin*) ;;
  *) exit 0 ;;
esac
input=$(cat)
[[ $input == *jq* ]] || exit 0
command=$(jq -rb '.tool_input.command // ""' <<<"$input")

case "$command" in
  BYPASS_JQ=1*) exit 0 ;;
esac

segments=${command//&&/$'\n'}
segments=${segments//||/$'\n'}
segments=${segments//;/$'\n'}
segments=${segments//|/$'\n'}
segments=${segments//\$(/$'\n'}
segments=${segments//(/$'\n'}
segments=${segments//)/$'\n'}
segments=${segments//\`/$'\n'}

violation=""
while IFS= read -r segment; do
  read -r -a words <<<"$segment" || true
  index=0
  count=${#words[@]}
  while [ "$index" -lt "$count" ]; do
    word=${words[$index]}
    case "$word" in
      [A-Za-z_]*=*) index=$((index + 1)); continue ;;
      sudo | exec | time | env | command | nohup) index=$((index + 1)); continue ;;
      xargs)
        index=$((index + 1))
        while [ "$index" -lt "$count" ] && [[ ${words[$index]} == -* ]]; do index=$((index + 1)); done
        continue
        ;;
    esac
    break
  done
  [ "$index" -lt "$count" ] || continue
  program=${words[$index]##*[/\\]}
  program=${program%.exe}
  [ "$program" = jq ] || continue

  binary=false
  for word in "${words[@]:$((index + 1))}"; do
    if [ "$word" = --binary ] || [[ $word =~ ^-[A-Za-z]*b[A-Za-z]*$ ]]; then
      binary=true
      break
    fi
  done
  if [ "$binary" = false ]; then
    violation=$segment
    break
  fi
done <<<"$segments"
[ -n "$violation" ] || exit 0

violation=${violation#"${violation%%[![:space:]]*}"}
reason="On Windows jq writes CRLF line endings. Add -b (--binary) to '$violation' so it writes LF. If CRLF is intended, prefix the command with 'BYPASS_JQ=1 '."
jq -nb --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
