#!/usr/bin/env bash
# PreToolUse hook on Bash. Blocks a command that a recipe in the project's justfile
# already runs, and names the recipe to run instead.
#
# Decisions:
# - Matches against the real recipes from `just --dump --dump-format json`, not a fixed
#   list of tools, so tasks without a recipe (`uv add`, `python -c`) are never blocked.
#   A command is blocked when it equals a recipe line or starts with it followed by a space.
#   The recipe line is its literal text before the first {{...}} interpolation, without
#   @/- prefixes and VAR=value assignments. Recipe lines starting with #, cd, echo or just
#   are ignored, so `cd web` in a recipe does not block every `cd web`.
# - Commands are split on && || ; | and leading VAR=value, sudo, exec, time are skipped.
# - This hook runs on every Bash call, and starting a process costs 30-50 ms on Windows,
#   so it avoids processes until a block is likely:
#   - cwd and command are read from the input JSON with a bash regex (parse_json_string)
#     instead of jq. It decodes \\ \n \t \r \" \/ but not \uXXXX; that gap can only miss a
#     block, never cause a wrong one.
#   - The justfile is found by walking up the folders with builtins; none found, exit.
#   - `just` and jq only run when the first word of a command appears in the justfile text.
#   - Files are read with $(<file): `read -d ''` reads one byte per system call, ~80 ms
#     on a network drive.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq and just. jq on Windows
#   writes CRLF, so \r is removed from its output.
# - Bypass: prefix the command with BYPASS_JUST=1. Every hook has its own BYPASS_* flag,
#   so bypassing one check does not skip the others.
# - Fails open: any error exits without a decision, and Claude Code runs the command.
set -euo pipefail

input=$(cat)
parse_json_string() {
  local pattern="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\"" value=""
  if [[ $input =~ $pattern ]]; then
    value=${BASH_REMATCH[1]//\\\\/$'\001'}
    value=${value//\\n/$'\n'}
    value=${value//\\t/$'\t'}
    value=${value//\\r/}
    value=${value//\\\"/\"}
    value=${value//\\\//\/}
    value=${value//$'\001'/\\}
  fi
  printf -v "$2" '%s' "$value"
}
parse_json_string cwd directory
parse_json_string command command

case "$command" in
  BYPASS_JUST=1*) exit 0 ;;
esac

cd "${directory:-.}" 2>/dev/null || exit 0
justfile=""
current=$PWD
while [ -z "$justfile" ]; do
  for name in justfile Justfile .justfile; do
    if [ -f "$current/$name" ]; then
      justfile="$current/$name"
      break
    fi
  done
  [ -n "$current" ] || break
  current=${current%/*}
done
[ -n "$justfile" ] || exit 0

segments=${command//&&/$'\n'}
segments=${segments//||/$'\n'}
segments=${segments//;/$'\n'}
segments=${segments//|/$'\n'}
prefix='^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|exec|time)[[:space:]]+)*(.*)$'
justfile_text=$(<"$justfile")
commands=()
word_known=false
while IFS= read -r segment; do
  [[ $segment =~ $prefix ]] && segment=${BASH_REMATCH[3]}
  segment=${segment%"${segment##*[![:space:]]}"}
  [ -n "$segment" ] || continue
  commands+=("$segment")
  [[ $justfile_text == *"${segment%%[[:space:]]*}"* ]] && word_known=true
done <<<"$segments"
[ "$word_known" = true ] || exit 0

dump=$(just --dump --dump-format json 2>/dev/null) || exit 0
recipes=$(jq -r '
  .recipes | to_entries[] | .key as $recipe | .value.body[]
  | map(if type == "string" then . else "\u0001" end) | join("")
  | sub("^\\s*[@-]+"; "")
  | sub("^\\s*([A-Za-z_][A-Za-z0-9_]*=\\S*\\s+)+"; "")
  | split("\u0001")[0]
  | sub("^\\s+"; "") | sub("\\s+$"; "")
  | select(. != "" and (test("^(#|cd\\b|echo\\b|just\\b)") | not))
  | "\($recipe)\t\(.)"
' <<<"$dump")
recipes=${recipes//$'\r'/}

while IFS=$'\t' read -r recipe line; do
  [ -n "$line" ] || continue
  for segment in "${commands[@]}"; do
    case "$segment" in
      "$line" | "$line "*)
        reason="Recipe '$recipe' runs '$line'. Run 'just $recipe' instead. If this is a different task, prefix the command with 'BYPASS_JUST=1 '."
        jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
        exit 0
        ;;
    esac
  done
done <<<"$recipes"
