#!/usr/bin/env bash
# Functions the check-*.sh hooks source. Not a hook: settings.json does not register it.
#
# Decisions:
# - Functions return their result in REPLY, the variable `read` also uses, instead of being
#   called as $(...): command substitution forks a subshell, which is slow on Windows.
# - parse_json reads a string value from the hook input JSON with a bash regex instead
#   of jq. Starting a process costs 30-50 ms on Windows (~45 ms for jq), so the hooks read
#   their input without starting any process.
# - Decodes \\ \n \t \" \/ and removes \r. \uXXXX, \b and \f are not decoded. Claude Code
#   writes non-ASCII characters as they are, so only control characters reach the hooks as
#   \uXXXX. In these hooks that gap can only miss a block, never cause a wrong one.
# - The first "key": "value" pair wins, at any depth of the JSON. A key name inside a string
#   value cannot match, because its quotes are escaped there. A key whose value is not a
#   string reads as empty.
# - parse_agent returns cursor when the input has a cursor_version key, otherwise claude.
#   Cursor runs the same hooks, but some of its answers differ.
# - parse_command splits on && || ; | $( ( ) and backticks, so commands inside $(...) and
#   subshells are found, and removes leading VAR=value assignments and the wrappers sudo,
#   exec, time, env, command, nohup and xargs (with its options), so the first word is the
#   program that runs. It ignores quotes, so a separator inside quotes also splits. It returns
#   one command per line, without trailing spaces or empty lines, because bash 3.2 has no
#   way to return an array.
# - deny_hook is the PreToolUse deny answer. block_hook is the PostToolUse block answer:
#   decision "block" for Claude Code, additional_context for Cursor, which ignores decision
#   "block" in postToolUse.
# - deny_hook and block_hook print the answer with jq -n and exit, so jq only runs when a
#   hook blocks. They do not use -b: the CRLF jq writes on Windows is still valid JSON.
# - Portable: bash 3.2 features only (macOS), jq.

parse_json() {
  local json=$1 key=$2 pattern value=""
  pattern="\"$key\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  if [[ $json =~ $pattern ]]; then
    value=${BASH_REMATCH[1]//\\\\/$'\001'}
    value=${value//\\n/$'\n'}
    value=${value//\\t/$'\t'}
    value=${value//\\r/}
    value=${value//\\\"/\"}
    value=${value//\\\//\/}
    value=${value//$'\001'/\\}
  fi
  REPLY=$value
}

parse_agent() {
  if [[ $1 =~ \"cursor_version\"[[:space:]]*: ]]; then
    REPLY=cursor
  else
    REPLY=claude
  fi
}

parse_command() {
  local segments=$1 segment commands=""
  local prefix='^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|exec|time|env|command|nohup|xargs([[:space:]]+-[^[:space:]]+)*)[[:space:]]+)*(.*)$'
  segments=${segments//&&/$'\n'}
  segments=${segments//||/$'\n'}
  segments=${segments//;/$'\n'}
  segments=${segments//|/$'\n'}
  segments=${segments//\$(/$'\n'}
  segments=${segments//(/$'\n'}
  segments=${segments//)/$'\n'}
  segments=${segments//\`/$'\n'}
  while IFS= read -r segment; do
    [[ $segment =~ $prefix ]] && segment=${BASH_REMATCH[4]}
    segment=${segment%"${segment##*[![:space:]]}"}
    [ -n "$segment" ] && commands+=$segment$'\n'
  done <<<"$segments"
  REPLY=$commands
}

deny_hook() {
  jq -n --arg reason "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

block_hook() {
  local agent=$1 reason=$2
  if [ "$agent" = cursor ]; then
    jq -n --arg reason "$reason" '{additional_context: $reason}'
  else
    jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
  fi
  exit 0
}
