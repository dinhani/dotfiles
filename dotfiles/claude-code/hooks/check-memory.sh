#!/usr/bin/env bash
# PreToolUse hook on Write|Edit. Blocks writing any memory/*.md file, MEMORY.md included.
# Facts and rules go into CLAUDE.md, which other agents also read.
#
# Decisions:
# - Paths are compared with \ replaced by /, so Windows and Unix paths match.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "memory".
# - The input JSON is read with parse_json from _helpers.sh, without starting a
#   process. deny_hook prints the answer with jq and only runs when the hook blocks.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq.
# - Bypass: environment variable BYPASS_MEMORY=1, set in settings.json "env" or in the shell
#   before starting claude. Write and Edit have no command to prefix, so only the user can
#   bypass this hook.
# - Fails open: any error exits without a decision, and Claude Code runs the write.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)
[ "${BYPASS_MEMORY:-}" = 1 ] && exit 0
[[ $input == *memory* ]] || exit 0

# Parse input
parse_json "$input" file_path
file=${REPLY//\\//}
case "$file" in
  */memory/*.md) ;;
  *) exit 0 ;;
esac

# Deny
deny_hook "Memories are not allowed. Ask the user whether to add this to the project's CLAUDE.md or to the global CLAUDE.md, and edit the chosen file."
