#!/usr/bin/env bash
# PreToolUse hook on Bash, PowerShell, Grep and Glob. Blocks a search whose root is the NAS
# root or a folder directly under it (Z:/codigos, Z:/jogos): these hold terabytes and never
# finish.
#
# Decisions:
# - The NAS is Z:, also written as /z and //192.168.100.3/dinhani, with / or \ separators,
#   in any case. These are the only machine paths in the hooks.
# - A root is too broad when it resolves to Z: or Z:/<folder>. Z:/<folder>/<folder> and
#   deeper are allowed.
# - Bash: a search is rg, fd, find, tree, grep/egrep/fgrep with -r or -R, or ls with -R, as
#   the first word of a command from parse_command in _helpers.sh.
# - PowerShell: a search is rg, fd, find, tree, or Get-ChildItem (gci, ls, dir) with -Recurse
#   or -Depth, or any prefix PowerShell accepts for them (-r, -rec, -de). Command names and
#   parameters match in any case. Set-Location, sl, chdir, pushd and Push-Location count
#   as cd. -Name:value is read as value.
# - The roots of a search are the words that are absolute paths, start with . or .. or $, or
#   name an existing file or folder in the current folder. Without any, the root is the
#   current folder. A cd earlier in the same call changes the current folder.
# - $NAME, ${NAME}, $env:NAME and ${env:NAME} at the start of a word expand to the
#   environment variable, so a search in "$DIR_NAS_GAMES" is checked.
# - rg, fd and grep take the pattern before the paths, so a . that is not the last word is
#   the pattern (`fd . Z:/x`), not a path.
# - Grep: the root is path, or the current folder without it. Glob: the root is pattern
#   joined to path, or to the current folder without it; an absolute pattern stands alone.
# - A path is cut before its first segment with * ? [ or {, so `Z:/codigos/*` and the Glob
#   pattern `Z:/codigos/**/*.py` resolve to Z:/codigos.
# - Words are split on spaces without quote handling, so a quoted path with spaces is checked
#   up to its first space.
# - Speed: starting a process costs 30-50 ms on Windows, so the hook exits before parsing
#   when the input mentions no NAS spelling and no DIR_ variable. The cwd is part of the
#   input, so a session on the NAS always parses. Paths are resolved with builtins; only
#   [ -e ] touches the disk. deny_hook prints the answer with jq and only runs when the hook
#   blocks.
# - Bypass: prefix the command with BYPASS_NAS_SEARCH=1 in Bash, $env:BYPASS_NAS_SEARCH=1;
#   in PowerShell, where a VAR=value prefix is not valid syntax. Grep and Glob have no command
#   to prefix, so their message tells Claude to run the search with Bash.
# - Fails open: any error exits without a decision, and Claude Code runs the search.

# Setup
set -euo pipefail
source "${BASH_SOURCE[0]%/*}/_helpers.sh"

resolve_path() {
  local path=$1 base=$2 name segment result="" segments IFS=/
  if [[ $path =~ ^\$\{?([eE][nN][vV]:)?([A-Za-z_][A-Za-z0-9_]*)\}?(.*)$ ]]; then
    name=${BASH_REMATCH[2]}
    path=${!name:-}${BASH_REMATCH[3]}
  fi
  path=${path//\\//}
  case "$path" in
    //192.168.100.3/[dD][iI][nN][hH][aA][nN][iI] | //192.168.100.3/[dD][iI][nN][hH][aA][nN][iI]/*) path=Z:${path:23} ;;
    /[zZ] | /[zZ]/*) path=Z:${path:2} ;;
    [a-zA-Z]:* | /*) ;;
    *) path=${base%/}/$path ;;
  esac
  set -f
  segments=($path)
  set +f
  for segment in "${segments[@]}"; do
    case "$segment" in
      "" | .) ;;
      ..) [[ $result == /*/* ]] && result=${result%/*} ;;
      *[*?[{]*) break ;;
      *) result+=/$segment ;;
    esac
  done
  [[ $result == /?:* ]] && result=${result#/}
  REPLY=${result:-/}
}

# Read input
input=$(cat)
[[ $input == *[zZ]:* || $input == */[zZ]* || $input == *192.168.100.3* || $input == *DIR_* ]] || exit 0

# Parse input
parse_json "$input" tool_name
tool=$REPLY
parse_json "$input" cwd
resolve_path "$REPLY" /
directory=$REPLY

# Find roots
roots=""
case "$tool" in
  Grep)
    parse_json "$input" path
    resolve_path "${REPLY:-$directory}" "$directory"
    roots=$REPLY
    ;;
  Glob)
    parse_json "$input" path
    resolve_path "${REPLY:-$directory}" "$directory"
    base=$REPLY
    parse_json "$input" pattern
    resolve_path "$REPLY" "$base"
    roots=$REPLY
    ;;
  *)
    parse_json "$input" command
    command=$REPLY
    case "$command" in
      BYPASS_NAS_SEARCH=1* | '$env:BYPASS_NAS_SEARCH=1'*) exit 0 ;;
    esac
    [ "$tool" = PowerShell ] && shopt -s nocasematch
    recurse='[[:space:]]-(r(e(c(u(r(s(e)?)?)?)?)?)?|de(p(t(h)?)?)?)[[:space:]:]'
    parse_command "$command"
    commands=$REPLY
    while IFS= read -r segment; do
      [ -n "$segment" ] || continue
      set -f
      words=($segment)
      set +f
      program=${words[0]##*[/\\]}
      program=${program%.exe}
      program=${program%.com}
      case "$tool:$program" in
        *:cd | PowerShell:chdir | PowerShell:sl | PowerShell:set-location | PowerShell:pushd | PowerShell:push-location)
          [ "${#words[@]}" -gt 1 ] && resolve_path "${words[1]}" "$directory" && directory=$REPLY
          continue
          ;;
        PowerShell:get-childitem | PowerShell:gci | PowerShell:ls | PowerShell:dir) [[ " $segment " =~ $recurse ]] || continue ;;
        *:rg | *:fd | *:find | *:tree) ;;
        *:grep | *:egrep | *:fgrep) [[ " $segment " =~ [[:space:]](-[A-Za-z]*[rR][A-Za-z]*|--recursive|--dereference-recursive)[[:space:]] ]] || continue ;;
        *:ls) [[ " $segment " =~ [[:space:]](-[A-Za-z]*R[A-Za-z]*|--recursive)[[:space:]] ]] || continue ;;
        *) continue ;;
      esac
      last=$((${#words[@]} - 1))
      path_found=false
      for ((i = 1; i <= last; i++)); do
        word=${words[i]}
        word=${word#[\"\']}
        word=${word%[\"\']}
        case "$word" in
          --*=*) word=${word#*=} ;;
          -[A-Za-z]*:*) word=${word#*:} ;;
          -*) continue ;;
        esac
        case "$program:$word" in
          rg:. | fd:. | grep:. | egrep:. | fgrep:.) [ "$i" -eq "$last" ] || continue ;;
        esac
        case "$word" in
          [a-zA-Z]:* | /* | \\* | . | .. | ./* | ../* | \$*) ;;
          *) [ -e "${directory%/}/$word" ] || continue ;;
        esac
        resolve_path "$word" "$directory"
        roots+=$REPLY$'\n'
        path_found=true
      done
      [ "$path_found" = true ] || roots+=$directory$'\n'
    done <<<"$commands"
    shopt -u nocasematch
    ;;
esac

# Find broad root
broad=""
while IFS= read -r root; do
  case "$root" in
    [zZ]:/*/*) ;;
    [zZ]:) broad=$root/; break ;;
    [zZ]:/*) broad=$root; break ;;
  esac
done <<<"$roots"
[ -n "$broad" ] || exit 0

# Deny
case "$tool" in
  Grep | Glob) bypass="run it with Bash and prefix the command with BYPASS_NAS_SEARCH=1" ;;
  PowerShell) bypass="prefix the command with \$env:BYPASS_NAS_SEARCH=1;" ;;
  *) bypass="prefix the command with BYPASS_NAS_SEARCH=1" ;;
esac
deny_hook "Search root $broad is too broad on the NAS. Search only inside the project or area folder you are working in, or read the DIR_* env vars to find the right folder. If the user asked for this search, $bypass."
