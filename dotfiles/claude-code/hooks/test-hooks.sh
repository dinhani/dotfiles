#!/usr/bin/env bash
# Test cases for the check-*.sh hooks in this folder. Run: bash test-hooks.sh
# Prints one line per case and exits 1 if any case fails.
#
# Layout: case functions, fixtures, syntax check, one section per hook in the order
# settings.json registers them, summary. Within a section: blocked cases, allowed cases,
# bypass.
#
# Decisions:
# - Not a hook: settings.json does not register it.
# - Each case feeds the hook the same stdin JSON Claude Code sends (tool_input, cwd) and
#   compares the decision: deny/block, or pass when the hook prints nothing.
# - Fixtures (justfiles, pyproject.toml, uv.lock) are created in a temporary folder, one
#   folder per scenario, so the cases do not depend on any project or machine path and no
#   fixture changes between cases.
# - The Windows-style paths in the check-memory cases are input data: they test that the
#   hooks handle \ separators.
# - check-jq only acts on Windows, so its blocked cases expect deny on Windows and pass on
#   Linux and macOS.
# - Multi-line commands are printed with \n so cases stay distinguishable on one line.
set -uo pipefail

hooks=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
failures=0
total=0

case "${OSTYPE:-}" in
  msys* | cygwin*) deny_on_windows=deny ;;
  *) deny_on_windows=pass ;;
esac

# ------------------------------------------------------------------------------
# Case functions
# ------------------------------------------------------------------------------
run_case() {
  local expected=$1 hook=$2 json=$3 label=$4 actual status=ok
  actual=$(bash "$hooks/$hook" <<<"$json" | jq -r '.hookSpecificOutput.permissionDecision // .decision // empty' 2>/dev/null)
  actual=${actual//$'\r'/}
  actual=${actual:-pass}
  total=$((total + 1))
  if [ "$actual" != "$expected" ]; then
    status=FAIL
    failures=$((failures + 1))
  fi
  label=${label//$'\n'/\\n}
  printf '  %-4s %-5s %s\n' "$status" "$actual" "${label:0:100}"
}
command_case() {
  local expected=$1 hook=$2 directory=$3 command=$4
  run_case "$expected" "$hook" "$(jq -nc --arg c "$command" --arg d "$directory" '{tool_input:{command:$c},cwd:$d}')" "$command"
}
file_case() {
  local expected=$1 hook=$2 file=$3 content=${4:-}
  run_case "$expected" "$hook" "$(jq -nc --arg f "$file" --arg c "$content" '{tool_input:{file_path:$f,content:$c}}')" "$file"
}

# ------------------------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------------------------
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT

project=$fixtures/project
mkdir -p "$project/sub"
cat > "$project/justfile" <<'EOF'
[doc("List recipes")]
[group("project")]
default:
    @just --list --unsorted

[doc("Format Python code")]
[group("project")]
lint:
    yapf -i dotfiles.py dotfiles_tui.py

[doc("Install dependencies")]
[group("project")]
sync:
    @uv sync --all-extras

[doc("Backup or restore dotfiles")]
[group("run")]
dotfiles:
    python dotfiles.py

[doc("Setup Linux or macOS")]
[group("run")]
setup email="someone@example.com":
    EMAIL={{email}} ./setup-unix.sh

[doc("Start frontend")]
[group("run")]
frontend:
    cd web
    -npm run dev

[doc("Run tests")]
[group("test")]
test *args:
    uv run pytest {{args}}
EOF

uv_tool=$fixtures/uv-tool
mkdir -p "$uv_tool/src"
printf '[project]\nname = "x"\n\n[tool.uv]\ndev = 1\n' > "$uv_tool/pyproject.toml"

uv_lock=$fixtures/uv-lock
mkdir -p "$uv_lock"
touch "$uv_lock/uv.lock"

pip_project=$fixtures/pip-project
mkdir -p "$pip_project"
printf '[project]\nname = "x"\n' > "$pip_project/pyproject.toml"

memory_windows='C:\Users\someone\.claude\projects\x\memory'
memory_unix=/home/someone/.claude/projects/x/memory
memory_feedback=$'---\nname: x\nmetadata:\n  type: feedback\n---\nbody'
memory_user=$'---\nname: x\nmetadata:\n  type: user\n---\nbody'

justfiles=$fixtures/justfiles
mkdir -p "$justfiles/valid" "$justfiles/missing-attributes" "$justfiles/no-default" "$justfiles/syntax-error"
cat > "$justfiles/valid/justfile" <<'EOF'
[doc("List recipes")]
[group("misc")]
default:
    @just --list

[doc("Run tests")]
[group("anything")]
test:
    uv run pytest
alias t := test

_helper:
    echo
EOF
cat > "$justfiles/missing-attributes/justfile" <<'EOF'
# Run tests
test:
    uv run pytest

default:
    @echo hi
EOF
printf 'build:\n    make\n' > "$justfiles/no-default/justfile"
printf '[group("run")]\nfoo:\n    echo {{\n' > "$justfiles/syntax-error/justfile"

# ------------------------------------------------------------------------------
# Syntax
# ------------------------------------------------------------------------------
echo "== syntax"
for script in "$hooks"/check-*.sh; do
  total=$((total + 1))
  if bash -n "$script"; then
    printf '  %-4s %s\n' ok "${script##*/}"
  else
    printf '  %-4s %s\n' FAIL "${script##*/}"
    failures=$((failures + 1))
  fi
done

# ------------------------------------------------------------------------------
# check-just
# ------------------------------------------------------------------------------
echo "== check-just"
command_case deny check-just.sh "$project" "python dotfiles.py"
command_case deny check-just.sh "$project" "yapf -i dotfiles.py dotfiles_tui.py"
command_case deny check-just.sh "$project" "./setup-unix.sh"
command_case deny check-just.sh "$project" "uv sync --all-extras"
command_case deny check-just.sh "$project" "npm run dev"
command_case deny check-just.sh "$project/sub" "uv run pytest -k foo"
command_case deny check-just.sh "$project" "cd x && UV_X=1 uv run pytest"
command_case deny check-just.sh "$project" $'echo "start"\npython dotfiles.py'
command_case deny check-just.sh "$project" "printf 'a\\nb' | python dotfiles.py"
command_case pass check-just.sh "$project" "git status"
command_case pass check-just.sh "$project" "python -c 'x'"
command_case pass check-just.sh "$project" "python -c \"print('dotfiles.py')\""
command_case pass check-just.sh "$project" "echo \"python dotfiles.py\""
command_case pass check-just.sh "$project" "uv sync"
command_case pass check-just.sh "$project" "uv add httpx"
command_case pass check-just.sh "$project" "cd web"
command_case pass check-just.sh "$fixtures" "python dotfiles.py"
command_case pass check-just.sh "$project" "BYPASS_JUST=1 python dotfiles.py"

# ------------------------------------------------------------------------------
# check-pip
# ------------------------------------------------------------------------------
echo "== check-pip"
command_case deny check-pip.sh "$uv_tool/src" "pip install httpx"
command_case deny check-pip.sh "$uv_lock" "python -m pip install x"
command_case deny check-pip.sh "$uv_tool" "cd x && /usr/bin/pip3.exe list"
command_case pass check-pip.sh "$uv_tool" "uv pip install x"
command_case pass check-pip.sh "$uv_tool" "git status"
command_case pass check-pip.sh "$pip_project" "pip install httpx"
command_case pass check-pip.sh "$uv_tool" "BYPASS_PIP=1 pip install x"

# ------------------------------------------------------------------------------
# check-commit
# ------------------------------------------------------------------------------
echo "== check-commit"
command_case deny check-commit.sh "$project" 'git add . && git commit -m "added stuff"'
command_case deny check-commit.sh "$project" "git commit --message=wip"
command_case deny check-commit.sh "$project" $'git commit -m "$(cat <<\'EOF\'\nUpdated things\nEOF\n)"'
command_case pass check-commit.sh "$project" 'git commit -m "feat(hooks): add check"'
command_case pass check-commit.sh "$project" "git commit -am 'fix: typo'"
command_case pass check-commit.sh "$project" $'git commit -m "$(cat <<\'EOF\'\nfeat: heredoc\n\nbody\nEOF\n)"'
command_case pass check-commit.sh "$project" $'cat > notes <<\'EOF\'\nnot a commit\nEOF\ngit commit -m "docs: add notes"'
command_case pass check-commit.sh "$project" "git commit --amend --no-edit"
command_case pass check-commit.sh "$project" 'git commit -m "Merge branch main"'
command_case pass check-commit.sh "$project" 'git commit -m "$MESSAGE"'
command_case pass check-commit.sh "$project" 'git log --oneline'
command_case pass check-commit.sh "$project" 'BYPASS_COMMIT=1 git commit -m "wip"'

# ------------------------------------------------------------------------------
# check-jq
# ------------------------------------------------------------------------------
echo "== check-jq"
command_case "$deny_on_windows" check-jq.sh "$project" "jq '.a' settings.json > settings.new"
command_case "$deny_on_windows" check-jq.sh "$project" "cat x.json | jq -r .name"
command_case "$deny_on_windows" check-jq.sh "$project" 'name=$(jq -r .name x.json)'
command_case "$deny_on_windows" check-jq.sh "$project" "find . -name '*.json' | xargs -n1 jq -c ."
command_case "$deny_on_windows" check-jq.sh "$project" "/c/tools/jq.exe . x.json"
command_case "$deny_on_windows" check-jq.sh "$project" "jq -rb .a x.json && jq .b x.json"
command_case pass check-jq.sh "$project" "jq -b '.a' settings.json > settings.new"
command_case pass check-jq.sh "$project" "cat x.json | jq -rb .name"
command_case pass check-jq.sh "$project" "jq --binary -n '1'"
command_case pass check-jq.sh "$project" "jq -n --arg x 1 -b '\$x'"
command_case pass check-jq.sh "$project" "grep jq README.md"
command_case pass check-jq.sh "$project" "echo 'use jq here'"
command_case pass check-jq.sh "$project" "git status"
command_case pass check-jq.sh "$project" "BYPASS_JQ=1 jq . x.json"

# ------------------------------------------------------------------------------
# check-memory
# ------------------------------------------------------------------------------
echo "== check-memory"
file_case deny check-memory.sh "$memory_windows\\rule.md" "$memory_feedback"
file_case deny check-memory.sh "$memory_unix/rule.md" "$memory_feedback"
file_case pass check-memory.sh "$memory_windows\\user.md" "$memory_user"
file_case pass check-memory.sh 'C:\src\notes.md' "$memory_feedback"
BYPASS_MEMORY=1 file_case pass check-memory.sh "$memory_windows\\rule.md" "$memory_feedback"

# ------------------------------------------------------------------------------
# check-justfile
# ------------------------------------------------------------------------------
echo "== check-justfile"
file_case block check-justfile.sh "$justfiles/missing-attributes/justfile"
file_case block check-justfile.sh "$justfiles/no-default/justfile"
file_case block check-justfile.sh "$justfiles/syntax-error/justfile"
file_case pass check-justfile.sh "$project/justfile"
file_case pass check-justfile.sh "$justfiles/valid/justfile"
file_case pass check-justfile.sh "$justfiles/valid/README.md"
BYPASS_JUSTFILE=1 file_case pass check-justfile.sh "$justfiles/syntax-error/justfile"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo
if [ "$failures" -gt 0 ]; then
  echo "$failures of $total failed"
  exit 1
fi
echo "all $total passed"
