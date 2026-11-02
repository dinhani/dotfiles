#!/usr/bin/env bash
# Test cases for the check-*.sh hooks and _helpers.sh in this folder. Run: bash _tests.sh
# Prints one line per case and exits 1 if any case fails.
#
# Layout: case functions, fixtures, syntax check, _helpers.sh, one section per hook in the
# order settings.json registers them, summary. Within a hook section: blocked cases, allowed
# cases, bypass.
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

hooks=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
failures=0
total=0

case "${OSTYPE:-}" in
  msys* | cygwin*) deny_on_windows=deny ;;
  *) deny_on_windows=pass ;;
esac

# ------------------------------------------------------------------------------
# Case functions
# ------------------------------------------------------------------------------
record_case() {
  local expected=$1 actual=$2 label=$3 status=ok
  total=$((total + 1))
  if [ "$actual" != "$expected" ]; then
    status=FAIL
    failures=$((failures + 1))
  fi
  label=${label//$'\n'/\\n}
  printf '  %-4s %s -> %s\n' "$status" "${label:0:100}" "${actual//$'\n'/\\n}"
}
run_case() {
  local expected=$1 hook=$2 json=$3 label=$4 actual
  actual=$(bash "$hooks/$hook" <<<"$json" | jq -r '.hookSpecificOutput.permissionDecision // .decision // (.additional_context | values | "context") // empty' 2>/dev/null)
  actual=${actual//$'\r'/}
  record_case "$expected" "${actual:-pass}" "$label"
}
command_case() {
  local expected=$1 hook=$2 directory=$3 command=$4
  run_case "$expected" "$hook" "$(jq -nc --arg c "$command" --arg d "$directory" '{tool_input:{command:$c},cwd:$d}')" "$command"
}
file_case() {
  local expected=$1 hook=$2 file=$3 content=${4:-}
  run_case "$expected" "$hook" "$(jq -nc --arg f "$file" --arg c "$content" '{tool_input:{file_path:$f,content:$c}}')" "$file"
}
parse_json_case() {
  local expected=$1 key=$2 json=$3
  parse_json "$json" "$key"
  record_case "$expected" "$REPLY" "$json"
}
parse_agent_case() {
  local expected=$1 json=$2
  parse_agent "$json"
  record_case "$expected" "$REPLY" "$json"
}
parse_command_case() {
  local expected=$1 command=$2
  parse_command "$command"
  record_case "$expected" "$REPLY" "$command"
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

[doc("Rename files")]
[group("data")]
[script]
rename:
    $folders = if ($args) { $args } else { '.' }
    Get-ChildItem $folders | ForEach-Object {
        Write-Output $_.Name
    }

[doc("Extract subtitles")]
[group("run")]
[script]
[positional-arguments]
extract *paths:
    uv run extract.py @args
    exit $LASTEXITCODE

[doc("Translate subtitles")]
[group("run")]
[positional-arguments]
translate *paths:
    ./translate.sh "$@"

[doc("Check files")]
[group("data")]
check:
    #!/usr/bin/env bash
    if [ -f x ]; then
        cat x
    fi
EOF

uv_tool=$fixtures/uv-tool
mkdir -p "$uv_tool/src"
printf '[project]\nname = "x"\n\n[tool.uv]\ndev = 1\n' > "$uv_tool/pyproject.toml"

uv_lock=$fixtures/uv-lock
mkdir -p "$uv_lock"
touch "$uv_lock/uv.lock"

uv_env=$fixtures/uv-env
mkdir -p "$uv_env/sub"
touch "$uv_env/uv.lock"
printf 'export UV_PROJECT_ENVIRONMENT := "/envs/uv-env"\n\ndefault:\n    @just --list\n' > "$uv_env/justfile"

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
for script in "$hooks"/_helpers.sh "$hooks"/check-*.sh; do
  syntax=valid
  bash -n "$script" || syntax=invalid
  record_case valid "$syntax" "${script##*/}"
done

# ------------------------------------------------------------------------------
# _helpers.sh
# ------------------------------------------------------------------------------
echo "== _helpers.sh"
source "$hooks/_helpers.sh"
parse_json_case 'git status' command '{"tool_input":{"command":"git status"}}'
parse_json_case 'echo "a"' command '{"tool_input":{"command":"echo \"a\""}}'
parse_json_case 'C:\Users\x' file_path '{"tool_input":{"file_path":"C:\\Users\\x"}}'
parse_json_case 'a\nb' command '{"command":"a\\nb"}'
parse_json_case $'a\nb\tc' command '{"command":"a\nb\tc"}'
parse_json_case $'a\nb' command '{"command":"a\r\nb"}'
parse_json_case 'a/b' command '{"command":"a\/b"}'
parse_json_case 'x' command '{"command" : "x"}'
parse_json_case '' command '{"cwd":"/x"}'
parse_json_case '' command '{"command":1}'
parse_json_case '/x' cwd '{"tool_input":{"content":"\"cwd\": \"/y\""},"cwd":"/x"}'

parse_agent_case cursor '{"tool_input":{"file_path":"x"},"cursor_version":"1.7"}'
parse_agent_case claude '{"tool_input":{"file_path":"x"}}'
parse_agent_case claude '{"tool_input":{"content":"\"cursor_version\": \"1\""}}'

parse_command_case $'git status\n' 'git status'
parse_command_case $'cd x\nuv sync\n' 'cd x && uv sync'
parse_command_case $'a\nb\nc\nd\n' 'a || b; c | d'
parse_command_case $'uv run pytest\n' 'A=1 B=2 sudo time uv run pytest'
parse_command_case $'a\nb\n' $'  a  \n\n  b  ;'
parse_command_case '' ' ; '
parse_command_case $'echo "\nuv sync\n"\n' 'echo "$(uv sync)"'
parse_command_case $'cd x\npip list\n' '(cd x && pip list)'
parse_command_case $'echo\ngit status\n' 'echo `git status`'
parse_command_case $'jq .\n' 'env A=1 nohup xargs -n1 -0 jq .'
parse_command_case $'-v jq\n' 'command -v jq'

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
command_case deny check-just.sh "$project" 'output=$(uv run pytest -x)'
command_case deny check-just.sh "$project" '(cd web && npm run dev)'
command_case deny check-just.sh "$project" "uv run extract.py"
command_case deny check-just.sh "$project" "uv run extract.py Z:/x 'a b'"
command_case deny check-just.sh "$project" "./translate.sh x"
command_case pass check-just.sh "$project" "git status"
command_case pass check-just.sh "$project" "python -c 'x'"
command_case pass check-just.sh "$project" "python -c \"print('dotfiles.py')\""
command_case pass check-just.sh "$project" "echo \"python dotfiles.py\""
command_case pass check-just.sh "$project" "uv sync"
command_case pass check-just.sh "$project" "uv add httpx"
command_case pass check-just.sh "$project" "cd web"
command_case pass check-just.sh "$project" '{ git status; }'
command_case pass check-just.sh "$project" 'if true; then git status; fi'
command_case pass check-just.sh "$project" 'for f in *; do git status; done'
command_case pass check-just.sh "$project" 'uv run extract_all.py'
command_case pass check-just.sh "$project" 'exit $LASTEXITCODE'
command_case pass check-just.sh "$project" "just sync"
command_case pass check-just.sh "$project" "just extract Z:/x 'a b'"
command_case pass check-just.sh "$project" "cd web && just frontend"
command_case pass check-just.sh "$project" "just --list --unsorted"
command_case pass check-just.sh "$fixtures" "python dotfiles.py"
command_case pass check-just.sh "$project" "BYPASS_JUST=1 python dotfiles.py"

# ------------------------------------------------------------------------------
# check-pip
# ------------------------------------------------------------------------------
echo "== check-pip"
command_case deny check-pip.sh "$uv_tool/src" "pip install httpx"
command_case deny check-pip.sh "$uv_lock" "python -m pip install x"
command_case deny check-pip.sh "$uv_tool" "cd x && /usr/bin/pip3.exe list"
command_case deny check-pip.sh "$uv_tool" 'echo "$(pip freeze)"'
command_case deny check-pip.sh "$uv_tool" 'cat reqs.txt | xargs -n1 pip install'
command_case pass check-pip.sh "$uv_tool" "uv pip install x"
command_case pass check-pip.sh "$uv_tool" "git status"
command_case pass check-pip.sh "$pip_project" "pip install httpx"
command_case pass check-pip.sh "$uv_tool" "BYPASS_PIP=1 pip install x"

# ------------------------------------------------------------------------------
# check-uv-env
# ------------------------------------------------------------------------------
echo "== check-uv-env"
command_case deny check-uv-env.sh "$uv_tool" "uv run python scratch.py"
command_case deny check-uv-env.sh "$uv_env/sub" "uv sync"
command_case deny check-uv-env.sh "$fixtures" "uv --version"
command_case deny check-uv-env.sh "$uv_tool" "cd x && uv add httpx"
command_case deny check-uv-env.sh "$uv_tool" "/c/Users/x/.local/bin/uv.exe pip list"
command_case deny check-uv-env.sh "$uv_tool" 'output=$(uv run pytest)'
command_case deny check-uv-env.sh "$uv_tool" "UV_PROJECT_ENVIRONMENT= uv sync"
command_case deny check-uv-env.sh "$uv_tool" 'UV_PROJECT_ENVIRONMENT="" uv sync'
command_case deny check-uv-env.sh "$uv_tool" "MY_UV_PROJECT_ENVIRONMENT=x uv sync"
command_case pass check-uv-env.sh "$uv_tool" "UV_PROJECT_ENVIRONMENT=/envs/x uv run python scratch.py"
command_case pass check-uv-env.sh "$uv_tool" "export UV_PROJECT_ENVIRONMENT='C:\\envs\\x' && uv sync"
command_case pass check-uv-env.sh "$uv_tool" 'env UV_PROJECT_ENVIRONMENT="$HOME/envs/x" uv run pytest'
command_case pass check-uv-env.sh "$uv_tool" "just sync"
command_case pass check-uv-env.sh "$uv_tool" "uvx ruff check"
command_case pass check-uv-env.sh "$uv_tool" "grep uv README.md"
command_case pass check-uv-env.sh "$uv_tool" 'echo "uv sync"'
command_case pass check-uv-env.sh "$uv_tool" "git status"
command_case pass check-uv-env.sh "$uv_tool" "BYPASS_UV_ENV=1 uv sync"

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
command_case "$deny_on_windows" check-jq.sh "$project" "env LC_ALL=C jq .a x.json"
command_case pass check-jq.sh "$project" "jq -b '.a' settings.json > settings.new"
command_case pass check-jq.sh "$project" "cat x.json | jq -rb .name"
command_case pass check-jq.sh "$project" "jq --binary -n '1'"
command_case pass check-jq.sh "$project" "jq -n --arg x 1 -b '\$x'"
command_case pass check-jq.sh "$project" "grep jq README.md"
command_case pass check-jq.sh "$project" "command -v jq"
command_case pass check-jq.sh "$project" "echo 'use jq here'"
command_case pass check-jq.sh "$project" "git status"
command_case pass check-jq.sh "$project" "BYPASS_JQ=1 jq . x.json"

# ------------------------------------------------------------------------------
# check-memory
# ------------------------------------------------------------------------------
echo "== check-memory"
file_case deny check-memory.sh "$memory_windows\\rule.md" "$memory_feedback"
file_case deny check-memory.sh "$memory_unix/rule.md" "$memory_feedback"
run_case deny check-memory.sh "$(jq -nc --arg f "$memory_unix/rule.md" --arg c "$memory_feedback" '{tool_input:{file_path:$f,old_string:"x",new_string:$c}}')" "edit: $memory_unix/rule.md"
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
run_case context check-justfile.sh "$(jq -nc --arg f "$justfiles/no-default/justfile" '{tool_input:{file_path:$f},cursor_version:"1"}')" "cursor: $justfiles/no-default/justfile"
file_case block check-justfile.sh "$justfiles/no-default/justfile" '"cursor_version"'
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
