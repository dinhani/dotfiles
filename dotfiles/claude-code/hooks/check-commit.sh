#!/usr/bin/env bash
# PreToolUse hook on Bash. Blocks a git commit whose subject is not a Conventional Commit:
# type(scope)!: subject, with type feat fix docs style refactor perf test build ci chore revert.
#
# Decisions:
# - A Claude Code hook, not a git commit-msg hook: a global core.hooksPath would disable
#   repository hooks (husky, pre-commit). It covers only Claude.
# - Reads the first -m / --message value after `git commit` (combined flags such as -am
#   included). Text before `git commit` is ignored, so a heredoc that writes another file
#   is not taken as the message.
# - When the value is "$(cat <<'EOF' ... EOF)", the subject is the first non-empty line
#   inside the heredoc.
# - Not checked: no message found (editor, -F file, --amend --no-edit), a message that starts
#   with $ (a variable the hook cannot evaluate), and messages git writes itself: Merge,
#   Revert, fixup!, squash!, amend!.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input does not contain "commit".
# - The input JSON is read with parse_json from _helpers.sh, without starting a
#   process. deny_hook prints the answer with jq and only runs when the hook blocks.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq, POSIX awk.
# - Bypass: prefix the command with BYPASS_COMMIT=1.
# - Fails open: any error exits without a decision, and Claude Code runs the command.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)
[[ $input == *commit* ]] || exit 0

# Parse input
parse_json "$input" command
command=$REPLY
case "$command" in
  BYPASS_COMMIT=1*) exit 0 ;;
esac

# Find git commit
git_commit='(^|[;&|[:space:]])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
[[ $command =~ $git_commit ]] || exit 0
arguments=${command#*"${BASH_REMATCH[0]}"}

# Read subject
subject=$(awk 'BEGIN { RS = "\001" }
  match($0, /(^|[[:space:]])(-[A-Za-z]*m|--message)(=|[[:space:]]+)("[^"]*"|\047[^\047]*\047|[^[:space:]]+)/) {
    value = substr($0, RSTART, RLENGTH)
    sub(/^[[:space:]]*(-[A-Za-z]*m|--message)(=|[[:space:]]+)/, "", value)
    sub(/^["\047]/, "", value)
    sub(/["\047]$/, "", value)
    count = split(value, lines, "\n")
    if (lines[1] !~ /^\$\(cat[[:space:]]*<</) { print lines[1]; exit }
    for (i = 2; i <= count; i++) if (lines[i] ~ /[^[:space:]]/) { print lines[i]; exit }
  }' <<<"$arguments")
subject=${subject#"${subject%%[![:space:]]*}"}
subject=${subject%"${subject##*[![:space:]]}"}

# Check subject
case "$subject" in
  '' | '$'* | 'Merge '* | 'Revert '* | 'fixup! '* | 'squash! '* | 'amend! '*) exit 0 ;;
esac
conventional='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([^)]+\))?!?: [^[:space:]]'
[[ $subject =~ $conventional ]] && exit 0

# Deny
deny_hook "Commit message '$subject' is not a Conventional Commit. Use 'type(scope): subject' with type feat, fix, docs, style, refactor, perf, test, build, ci, chore or revert. If this message is intended, prefix the command with 'BYPASS_COMMIT=1 '."
