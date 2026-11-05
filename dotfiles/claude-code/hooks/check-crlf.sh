#!/usr/bin/env bash
# PreToolUse hook on Bash|PowerShell|Write|Edit. On Windows, blocks file writes that produce
# CRLF line endings.
#
# Decisions:
# - Python text-mode writes turn every \n into \r\n on Windows. A read-replace-write edit
#   script (`p.write_text(p.read_text().replace(...))`) turns an LF file into CRLF. Blocked:
#   .write_text( and open( with a text write mode (w, a, x, without b) when the call has no
#   newline= argument; csv.writer(, csv.DictWriter( and .to_csv( without lineterminator=,
#   because csv and pandas write \r\n even when the file is opened with newline="\n".
# - The Python calls are checked in Bash and PowerShell commands (heredocs, python -c) and
#   in the text of Write and Edit on .py files. Other files are not checked: a Markdown file
#   that mentions write_text( does not write anything.
# - The arguments of a call are read up to the matching ), so calls that span lines are
#   handled. Quotes are tracked without escapes, and the scan stops after 2000 characters.
# - Redirected output of python, py, uv, uvx, pwsh and powershell is CRLF on Windows:
#   > and >> to a file are blocked in those commands. Targets &N, /dev/null, nul and $null
#   are allowed. For redirects, quoted text is removed from the command first, so a > or |
#   inside quotes (`python -c "print(a > b)"`) is not a redirect or a split. Then the
#   command is split only on && || ; | and lines, because parse_command also splits on (
#   and ), which would cut `python -c "print(1)" > file` before the >. The program is the
#   first word from parse_command.
# - PowerShell writes CRLF with Set-Content, Add-Content and Out-File (blocked without
#   -NoNewline, checked in every command because Bash commands can run pwsh -c), and with
#   > and >> (blocked in PowerShell tool commands).
# - Windows only ($OSTYPE msys or cygwin). Python and PowerShell write LF on Linux and macOS,
#   so the hook exits there without doing anything. The input is read before that check,
#   as in every hook, so Claude Code never writes into a pipe the hook has already closed.
# - Commands are split with parse_command from _helpers.sh. The first violation found is
#   reported.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before any
#   process when the input contains none of the checked names and no >.
# - The input JSON is read with parse_json from _helpers.sh, without starting a
#   process. deny_hook prints the answer with jq and only runs when the hook blocks.
# - Portable: no machine paths, bash 3.2 features only (macOS), jq.
# - Bypass: prefix the command with BYPASS_CRLF=1. For Write and Edit, environment variable
#   BYPASS_CRLF=1, set in settings.json "env" or in the shell before starting claude.
# - Fails open: any error exits without a decision, and Claude Code runs the tool.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

# Read input
input=$(cat)
case "${OSTYPE:-}" in
  msys* | cygwin*) ;;
  *) exit 0 ;;
esac
[ "${BYPASS_CRLF:-}" = 1 ] && exit 0
case "$input" in
  *write_text* | *open\(* | *riter\(* | *to_csv* | *[Cc]ontent* | *[Oo]ut-[Ff]ile* | *\>*) ;;
  *) exit 0 ;;
esac

# Parse input
parse_json "$input" tool_name
tool=$REPLY
command=""
python=""
case "$tool" in
  Bash | PowerShell)
    parse_json "$input" command
    command=$REPLY
    case "$command" in
      BYPASS_CRLF=1*) exit 0 ;;
    esac
    python=$command
    ;;
  Write | Edit)
    parse_json "$input" file_path
    case "$REPLY" in
      *.py | *.pyw) ;;
      *) exit 0 ;;
    esac
    parse_json "$input" content
    [ -n "$REPLY" ] || parse_json "$input" new_string
    python=$REPLY
    ;;
  *) exit 0 ;;
esac

# Find Python text write
violation=""
mode='(^|[^A-Za-z0-9_])['\''"]([rwxabt+]{1,4})['\''"]'
for call in .write_text open csv.writer csv.DictWriter .to_csv; do
  text=$python
  while [[ $text == *"$call("* ]]; do
    text=${text#*"$call("}
    chunk=${text:0:2000}
    arguments=""
    depth=1
    quote=""
    for ((i = 0; i < ${#chunk}; i++)); do
      char=${chunk:i:1}
      if [ -n "$quote" ]; then
        [ "$char" = "$quote" ] && quote=""
      else
        case "$char" in
          \' | \") quote=$char ;;
          \() depth=$((depth + 1)) ;;
          \)) depth=$((depth - 1)) ;;
        esac
        [ "$depth" -eq 0 ] && break
      fi
      arguments+=$char
    done
    snippet="$call(${arguments:0:80})"
    case "$call" in
      .write_text)
        [[ $arguments == *newline=* ]] || violation="On Windows, Python text-mode writes turn \\n into \\r\\n. Add newline=\"\\n\" to '$snippet'."
        ;;
      open)
        [[ $arguments =~ $mode ]] || continue
        mode_value=${BASH_REMATCH[2]}
        [[ $mode_value == *b* ]] && continue
        [[ $mode_value == *[wxa]* ]] || continue
        [[ $arguments == *newline=* ]] || violation="On Windows, Python text-mode writes turn \\n into \\r\\n. Add newline=\"\\n\" to '$snippet'."
        ;;
      *)
        [[ $arguments == *lineterminator=* ]] || violation="csv and pandas write \\r\\n line endings by default. Add lineterminator=\"\\n\" to '$snippet'."
        ;;
    esac
    [ -n "$violation" ] && break 2
  done
done

# Find PowerShell write cmdlet
if [ -z "$violation" ] && [ -n "$command" ]; then
  parse_command "$command"
  commands=$REPLY
  shopt -s nocasematch
  while IFS= read -r segment; do
    program=${segment%%[[:space:]]*}
    case "$program" in
      Set-Content | Add-Content | Out-File)
        [[ $segment == *-NoNewline* ]] && continue
        violation="$program writes CRLF line endings. Write the file with the Write tool, or with [IO.File]::WriteAllText(\$path, \$text) and \`n line endings, instead of '$segment'."
        break
        ;;
    esac
  done <<<"$commands"
  shopt -u nocasematch
fi

# Find redirect
if [ -z "$violation" ] && [ -n "$command" ]; then
  quoted='"[^"]*"|'\''[^'\'']*'\'''
  segments=$command
  while [[ $segments =~ $quoted ]]; do
    segments=${segments/"${BASH_REMATCH[0]}"/}
  done
  segments=${segments//&&/$'\n'}
  segments=${segments//||/$'\n'}
  segments=${segments//;/$'\n'}
  segments=${segments//|/$'\n'}
  redirect='>>?[[:space:]]*([^[:space:]]+)'
  while IFS= read -r segment; do
    [[ $segment == *\>* ]] || continue
    parse_command "$segment"
    program=${REPLY%%[[:space:]$'\n']*}
    program=${program##*[/\\]}
    program=${program%.exe}
    case "$program" in
      python | python3 | py | uv | uvx | pwsh | powershell) ;;
      *) [ "$tool" = PowerShell ] || continue ;;
    esac
    rest=$segment
    while [[ $rest =~ $redirect ]]; do
      target=${BASH_REMATCH[1]}
      rest=${rest#*"${BASH_REMATCH[0]}"}
      case "$target" in
        \&* | /dev/null | [Nn][Uu][Ll] | \$null) continue ;;
      esac
      if [ "$tool" = PowerShell ]; then
        violation="PowerShell > and >> write CRLF line endings. Write the file with the Write tool, or with [IO.File]::WriteAllText(\$path, \$text) and \`n line endings, instead of '$segment'."
      else
        violation="On Windows, $program writes CRLF line endings to redirected output. Write the file from the script with newline=\"\\n\", or remove \\r before the redirect ($program ... | tr -d '\\r' > $target), instead of '$segment'."
      fi
      break 2
    done
  done <<<"$segments"
fi
[ -n "$violation" ] || exit 0

# Deny
if [ -n "$command" ]; then
  deny_hook "$violation If CRLF is intended, prefix the command with 'BYPASS_CRLF=1 '."
fi
deny_hook "$violation"
