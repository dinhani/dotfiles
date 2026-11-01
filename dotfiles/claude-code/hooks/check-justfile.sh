#!/usr/bin/env bash
# PostToolUse hook on Write|Edit. After a justfile is written, checks the minimum justfile
# rules and returns decision "block" with the list of errors. The edit is already on disk;
# Claude Code passes the list to Claude, which must fix the justfile before moving on.
# Cursor ignores decision "block" in postToolUse, so when the input has cursor_version the
# list is returned as additional_context instead.
#
# Checks: the justfile parses; `default` is the first recipe and only lists the recipes
# (`just --list`, any flags); every public recipe has a [group] attribute and a [doc]
# attribute (a # comment does not count).
#
# Decisions:
# - Only the minimum that holds in every project. Group names and order, windows-shell,
#   aliases and exported variables are personal conventions and are not checked, because
#   company projects follow their own.
# - The justfile is parsed by `just --dump --dump-format json`, not by hand. The dump sorts
#   recipes by name, so source order comes from `just --summary --unsorted`.
# - Private recipes are not checked.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "ustfile" (justfile, Justfile, .justfile).
# - The input JSON is read with parse_json and parse_agent from _helpers.sh, without
#   starting a process. jq is required to read the `just --dump` JSON. block_hook prints
#   the answer with jq and only runs when the hook blocks.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq and just. jq on Windows
#   writes CRLF, so \r is removed from its output. Paths split on both / and \.
# - Bypass: environment variable BYPASS_JUSTFILE=1, set in settings.json "env" or in the
#   shell before starting claude. Write and Edit have no command to prefix.
# - Fails open: any error exits without a decision.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)
[ "${BYPASS_JUSTFILE:-}" = 1 ] && exit 0
[[ $input == *ustfile* ]] || exit 0

# Parse input
parse_json "$input" file_path
file=$REPLY
parse_agent "$input"
agent=$REPLY
case "${file##*[/\\]}" in
  justfile | Justfile | .justfile) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Read justfile
directory=${file%[/\\]*}
[ "$directory" != "$file" ] || directory=.
dump=$(just --justfile "$file" --working-directory "$directory" --dump --dump-format json 2>&1) \
  || block_hook "$agent" "just cannot parse $file: ${dump//$'\r'/}"
order=$(just --justfile "$file" --working-directory "$directory" --summary --unsorted 2>/dev/null || true)
order=${order//$'\r'/}

# Check rules
errors=$(jq -r --arg order "$order" '
  (.recipes | with_entries(select(.value.private | not))) as $recipes
  | ($order | split(" ") | map(select(. != "" and (contains("::") | not)))) as $names
  | def attribute($name): [(.attributes // [])[] | objects | .[$name] // empty] | first;
  [
    (if ($names | first) != "default" then "default must be the first recipe" else empty end),
    (if ($recipes.default.body // [] | map(map(strings) | join("")) | join("\n") | test("^@?just --list( [^\n]*)?$") | not)
      then "default must only list the recipes (just --list)" else empty end),
    ($recipes | to_entries[] | .key as $recipe | .value |
      (if attribute("group") == null then "recipe \($recipe): add [group(\"...\")]" else empty end),
      (if attribute("doc") == null then "recipe \($recipe): add [doc(\"...\")] (a # comment is not accepted)" else empty end))
  ] | .[] | "- \(.)"
' <<<"$dump")
errors=${errors//$'\r'/}
[ -n "$errors" ] || exit 0

# Block
block_hook "$agent" "Justfile errors in $file:
$errors
Fix them now. If this justfile must keep this shape, the user can set BYPASS_JUSTFILE=1."
