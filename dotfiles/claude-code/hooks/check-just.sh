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
# - Commands are split with parse_command from _helpers.sh.
# - This hook runs on every Bash call, and starting a process costs 30-50 ms on Windows,
#   so it avoids processes until a block is likely:
#   - cwd and command are read with parse_json from _helpers.sh, without starting a
#     process. This hook has no keyword to check before parsing, unlike the other hooks.
#   - The justfile is found by walking up the folders with builtins; none found, exit.
#   - `just` and jq only run when the first word of a command appears in the justfile text.
#     jq is used there because the recipes come from `just --dump` as JSON. deny_hook prints
#     the answer with jq and only runs when the hook blocks.
#   - Files are read with $(<file): `read -d ''` reads one byte per system call, ~80 ms
#     on a network drive.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq and just. jq on Windows
#   writes CRLF, so \r is removed from its output.
# - Bypass: prefix the command with BYPASS_JUST=1. Every hook has its own BYPASS_* flag,
#   so bypassing one check does not skip the others.
# - Fails open: any error exits without a decision, and Claude Code runs the command.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)

# Parse input
parse_json "$input" cwd
directory=$REPLY
parse_json "$input" command
command=$REPLY
case "$command" in
  BYPASS_JUST=1*) exit 0 ;;
esac

# Find justfile
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

# Check justfile mentions a command
parse_command "$command"
commands=$REPLY
justfile_text=$(<"$justfile")
word_known=false
while IFS= read -r segment; do
  [[ $justfile_text == *"${segment%%[[:space:]]*}"* ]] && word_known=true
done <<<"$commands"
[ "$word_known" = true ] || exit 0

# Read recipes
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

# Find recipe that runs the command
recipe_found=false
while IFS=$'\t' read -r recipe line; do
  [ -n "$line" ] || continue
  while IFS= read -r segment; do
    case "$segment" in
      "$line" | "$line "*) recipe_found=true; break 2 ;;
    esac
  done <<<"$commands"
done <<<"$recipes"
[ "$recipe_found" = true ] || exit 0

# Deny
deny_hook "Recipe '$recipe' runs '$line'. Run 'just $recipe' instead. If this is a different task, prefix the command with 'BYPASS_JUST=1 '."
