import ast
import difflib
import inspect
import os
import platform
import shutil
import subprocess
import sys
from collections.abc import Callable, Generator, Iterable
from contextlib import contextmanager
from dataclasses import dataclass
from enum import Enum, StrEnum
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "_lib" / "vendor"))

from tqdm import tqdm

from dotfiles_tui import Disabled, Hint, Progress, show_tui

# ------------------------------------------------------------------------------
# Platform
# ------------------------------------------------------------------------------
class OS(StrEnum):
    WIN   = "Windows"
    MAC   = "Darwin"
    LINUX = "Linux"

SYSTEM = OS(platform.system())

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
COLOR_RESET  = "\033[0m"
COLOR_RED    = "\033[91m"
COLOR_GREEN  = "\033[92m"
COLOR_YELLOW = "\033[93m"

class LogKind(StrEnum):
    TRANSFER = "transfer"
    ERROR    = "error"
    SKIP     = "skip"

LOG_COLORS = {LogKind.TRANSFER: COLOR_GREEN, LogKind.ERROR: COLOR_RED, LogKind.SKIP: COLOR_YELLOW}

errors_logged: list[Exception] = []

def print_log(kind: LogKind, label: str, message: str) -> None:
    print("")
    print(f"{LOG_COLORS[kind]}{label:<4}{COLOR_RESET}  {message}")

log_handler: Callable[[LogKind, str, str], None] = print_log

@contextmanager
def logging_to(progress: Progress) -> Generator[None]:
    global log_handler
    log_handler = lambda kind, label, message: progress.log(kind.value, f"{label:<4}  {message}")
    try:
        yield
    finally:
        log_handler = print_log

def log_transfer(kind: str, source: Path, target: Path) -> None:
    log_handler(LogKind.TRANSFER, kind, f"{source} → {target}")

def log_error(message: str, exception: Exception) -> None:
    errors_logged.append(exception)
    log_handler(LogKind.ERROR, "err", f"{message}: {exception}")

def log_missing(source: Path) -> None:
    log_handler(LogKind.SKIP, "skip", f"{source}: not found")

def log_unsupported(item: str) -> None:
    log_handler(LogKind.SKIP, "skip", f"{item}: unsupported on {SYSTEM}")

# ------------------------------------------------------------------------------
# Sync
# ------------------------------------------------------------------------------
class Transfer(Enum):
    COPY    = "copy"
    COMPARE = "compare"

HINT_COLOR_GREEN  = "ansigreen"
HINT_COLOR_ORANGE = "#d75f00"
HINT_COLOR_YELLOW = "#af8700"
HINT_COLOR_RED    = "ansired"
HINT_COLOR_GRAY   = "ansibrightblack"

class Sync(StrEnum):
    IN_SYNC       = "in sync"
    MACHINE_NEWER = "machine newer"
    BACKUP_NEWER  = "backup newer"
    MIXED         = "mixed"
    NO_FILES      = "no files"

    @classmethod
    def from_files(cls, files: set["Sync"]) -> "Sync":
        files_changed = files - {cls.IN_SYNC}
        if not files:
            return cls.NO_FILES
        if not files_changed:
            return cls.IN_SYNC
        if len(files_changed) > 1:
            return cls.MIXED
        return files_changed.pop()

    def has_machine_changes(self) -> bool:
        return self in (Sync.MACHINE_NEWER, Sync.MIXED)

    def to_hint(self) -> Hint:
        return Hint(text=self.value, color=SYNC_COLORS[self])

SYNC_COLORS = {
    Sync.IN_SYNC:       HINT_COLOR_GREEN,
    Sync.MACHINE_NEWER: HINT_COLOR_ORANGE,
    Sync.BACKUP_NEWER:  HINT_COLOR_YELLOW,
    Sync.MIXED:         HINT_COLOR_RED,
    Sync.NO_FILES:      HINT_COLOR_GRAY,
}

@dataclass(frozen=True)
class BackupHistory:
    commit_times: dict[Path, float]
    paths_uncommitted: frozenset[Path]

    @classmethod
    def from_git(cls, dotfiles: Path) -> "BackupHistory":
        repo = dotfiles.parent
        git = ["git", "-c", "core.quotePath=false"]
        git_log = subprocess.run([*git, "log", "--format=@%ct", "--name-only", "--", dotfiles.name], cwd=repo, capture_output=True, encoding="utf-8", check=True).stdout
        git_status = subprocess.run([*git, "status", "--porcelain", "--untracked-files=all", "--", dotfiles.name], cwd=repo, capture_output=True, encoding="utf-8", check=True).stdout

        commit_times: dict[Path, float] = {}
        commit_time = 0.0
        for line in git_log.splitlines():
            if line.startswith("@"):
                commit_time = float(line[1:])
            elif line:
                commit_times.setdefault(repo / line, commit_time)
        paths_uncommitted = frozenset(repo / line[3:].split(" -> ")[-1] for line in git_status.splitlines())

        return cls(commit_times=commit_times, paths_uncommitted=paths_uncommitted)

    def get_time(self, backup: Path) -> float:
        if backup in self.paths_uncommitted or backup not in self.commit_times:
            return backup.stat().st_mtime
        return self.commit_times[backup]

# ------------------------------------------------------------------------------
# Files
# ------------------------------------------------------------------------------
@dataclass(frozen=True)
class Rewrite:
    old: str
    new: str

    def apply(self, text: str) -> str:
        return text.replace(self.old, self.new)

    def reversed(self) -> "Rewrite":
        return Rewrite(old=self.new, new=self.old)

class File(Path):
    # applied to the content of this file when it is the source of a copy or comparison
    _rewrite: Rewrite | None = None
    # track dotfiles dirs that we already deleted
    _deleted: set[Path] = set()
    # when False, deletes dotfiles/<app>/; when True, deletes dotfiles/<category>/<app>/ (example: JetBrains/<app>/)
    _subdir: bool = False
    _transfer: Transfer = Transfer.COPY
    _compared: list[tuple["File", "File"]] = []

    @classmethod
    @contextmanager
    def session(cls, subdir: bool, transfer: Transfer) -> Generator[None]:
        cls._subdir = subdir
        cls._transfer = transfer
        try:
            yield
        finally:
            cls._subdir = False
            cls._transfer = Transfer.COPY

    def __rshift__(self, other: Path | str) -> None:
        """Copy a source to a target. Automatically detects if source is a file or directory."""
        target = File(other)
        if File._transfer is Transfer.COMPARE:
            if self.is_dir() or target.is_dir():
                files = {path.relative_to(root) for root in (self, target) for path in root.rglob("*") if path.is_file()}
                File._compared.extend((self / file, target / file) for file in sorted(files))
            else:
                File._compared.append((self, target))
            return

        if not self.exists():
            log_missing(self)
            return

        target._delete_dotfiles_root_once()
        if self.is_file():
            self._copy_file(target)
        else:
            self._copy_dir(target)

    def rewriting(self, rewrite: Rewrite) -> "File":
        file = File(self)
        file._rewrite = rewrite
        return file

    def read_content(self) -> bytes:
        if self._rewrite is None:
            return self.read_bytes()
        return self._rewrite.apply(self.read_text(encoding="utf-8")).encode("utf-8")

    def read_comparable(self) -> bytes:
        return self.read_content().removesuffix(b"\n")

    def append_missing_newline(self) -> None:
        """Append a newline if the file is non-empty and doesn't already end with one."""
        try:
            with open(self, "rb+") as f:
                f.seek(0, os.SEEK_END)
                if f.tell() == 0:
                    return
                f.seek(-1, os.SEEK_END)
                if f.read(1) != b"\n":
                    f.write(b"\n")
        except Exception as e:
            log_error("Failed to append missing newline", e)

    def compare_to_backup(self, backup: "File", history: BackupHistory) -> Sync | None:
        if not self.is_file() and not backup.is_file():
            return None
        if not backup.is_file():
            return Sync.MACHINE_NEWER
        if not self.is_file():
            return Sync.BACKUP_NEWER

        if self.read_comparable() == backup.read_comparable():
            return Sync.IN_SYNC

        if self.stat().st_mtime > history.get_time(backup):
            return Sync.MACHINE_NEWER
        return Sync.BACKUP_NEWER

    def diff_to(self, other: "File") -> str:
        """Unified diff from this file to `other`; empty when contents are equal."""
        old = self.read_comparable() if self.is_file() else b""
        new = other.read_comparable() if other.is_file() else b""
        if old == new:
            return ""

        try:
            lines_old, lines_new = old.decode("utf-8").splitlines(), new.decode("utf-8").splitlines()
        except UnicodeDecodeError:
            return f"{self} -> {other}\nbinary files differ"

        label_old = str(self) if self.is_file() else "(missing)"
        label_new = str(other) if other.is_file() else "(missing)"
        return "\n".join(difflib.unified_diff(lines_old, lines_new, fromfile=label_old, tofile=label_new, lineterm=""))

    def _copy_dir(self, target: "File") -> None:
        """Copy a local directory to a local target."""
        try:
            log_transfer("dir", self, target)
            target.mkdir(parents=True, exist_ok=True)
            shutil.copytree(self, target, dirs_exist_ok=True)
            if target._is_backup():
                for path in target.rglob("*"):
                    if path.is_file():
                        path.append_missing_newline()
        except Exception as e:
            log_error("Failed to copy directory", e)

    def _copy_file(self, target: "File") -> None:
        """Copy a local file to a local target."""
        try:
            log_transfer("file", self, target)
            target.parent.mkdir(parents=True, exist_ok=True)
            if self._rewrite is None:
                shutil.copy2(self, target)
            else:
                target.write_bytes(self.read_content())
            if target._is_backup():
                target.append_missing_newline()
        except Exception as e:
            log_error("Failed to copy file", e)

    def _is_backup(self) -> bool:
        """True when this path is a backup target (inside the dotfiles dir)."""
        return self.is_relative_to(DOTFILES)

    def _delete_dotfiles_root_once(self) -> None:
        """First write into the cleanup root (dotfiles/<app>/... by default) deletes it once per session."""
        # check if inside dotfiles dir
        if not self._is_backup():
            return

        # extract root to delete; if `subdir` is set, go one level deeper than dotfiles/<app>/
        parts = self.relative_to(DOTFILES).parts
        if File._subdir:
            root = DOTFILES / parts[0] / parts[1]
        else:
            root = DOTFILES / parts[0]

        # check if already deleted
        if root in File._deleted:
            return

        # delete and track
        shutil.rmtree(root, ignore_errors=True)
        File._deleted.add(root)

class Dir(File):
    """Path known to be a directory. On restore the target directory is always created, even if the backup has none."""

    def __truediv__(self, key: str | Path) -> File:
        return File(super().__truediv__(key))

    def __rshift__(self, other: Path | str) -> None:
        target = File(other)
        if File._transfer is Transfer.COPY and not self.is_dir():
            if not target._is_backup():
                target.mkdir(parents=True, exist_ok=True)
            return
        super().__rshift__(other)

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
DOTFILES: File = File(Path(__file__).parent / "dotfiles")
"""Path of local dotfiles directory (relative to this script)."""

SCRIPTS: File = File(Path(__file__).parent / "scripts")

UNIX_HOME: File = File(Path.home())
"""Path of Unix home directory (Linux and Mac)."""

WIN_HOME: File = File(os.environ.get("USERPROFILE", ""))
"""Path of Windows home directory."""

HOME: File = WIN_HOME if SYSTEM is OS.WIN else UNIX_HOME
"""Path of the home directory of the current OS."""

WIN_ROAMING: File = WIN_HOME / "AppData" / "Roaming"
"""Path of Windows AppData/Roaming directory."""

WIN_LOCAL: File = WIN_HOME / "AppData" / "Local"
"""Path of Windows AppData/Local directory."""

WIN_SCOOP: File = File(os.environ.get("SCOOP") or WIN_HOME / "scoop")
"""Path of Windows Scoop directory; portable apps keep their data under `persist/<app>/`."""

MAC_APP_SUPPORT: File = File(Path.home() / "Library" / "Application Support")
"""Path of Mac Application Support directory."""

# ------------------------------------------------------------------------------
# Handlers
# ------------------------------------------------------------------------------
class Op(StrEnum):
    BACKUP  = "Backup"
    RESTORE = "Restore"

@dataclass(frozen=True)
class Handler:
    op: Op
    app: str
    dir: str
    subdir: bool
    fn: Callable[[str, Dir], None]
    systems_unsupported: frozenset[OS]
    source_of_truth: OS | None

    def __call__(self, transfer: Transfer = Transfer.COPY) -> None:
        with File.session(subdir=self.subdir, transfer=transfer):
            self.fn(self.app, Dir(DOTFILES / self.dir))

    def find_disabled(self) -> Disabled | None:
        if self.source_of_truth is not None and self.source_of_truth != SYSTEM:
            return Disabled(icon=self.source_of_truth.name[0], color=HINT_COLOR_YELLOW, reason=f"backup only from {self.source_of_truth.name.title()}")
        if SYSTEM in self.systems_unsupported:
            return Disabled(icon="✗", color=HINT_COLOR_RED, reason="app not on this OS")
        return None

    def collect_transfers(self) -> list[tuple[File, File]]:
        File._compared = []
        self(transfer=Transfer.COMPARE)
        return File._compared

HANDLERS_BY_APP: dict[str, dict[Op, Handler]] = {}

def operation(op: Op, app: str, dir: str, subdir: bool = False, source_of_truth: OS | None = None) -> Callable[[Callable[[str, Dir], None]], Handler]:
    """Wrap a backup/restore function, injecting the app name and the resolved `dotfiles/<dir>` path, and register it in `HANDLERS_BY_APP`.

    Set `subdir=True` for apps whose backup lives one level deeper (e.g. JetBrains, where each tool has
    its own subdir under `dotfiles/jetbrains/` that must be preserved when the tool isn't installed on
    the current machine).
    """
    def decorator(fn: Callable[[str, Dir], None]) -> Handler:
        systems_unsupported: set[OS] = set()
        for node in ast.walk(ast.parse(inspect.getsource(fn))):
            match node:
                case ast.match_case(pattern, body=[ast.Expr(ast.Call(ast.Name(name)))]) if name == log_unsupported.__name__:
                    systems_unsupported |= {OS[value.attr] for value in ast.walk(pattern) if isinstance(value, ast.Attribute)}

        handler = Handler(op=op, app=app, dir=dir, subdir=subdir, fn=fn, systems_unsupported=frozenset(systems_unsupported), source_of_truth=source_of_truth)
        handlers = HANDLERS_BY_APP.setdefault(app, {})
        if op in handlers:
            raise ValueError(f"{app}: {op.value} registered twice")
        handlers[op] = handler
        return handler
    return decorator

# ------------------------------------------------------------------------------
# App - Claude Code
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "Claude Code", "claude-code")
def backup_claude_code(app: str, dir: Dir):
    HOME / ".claude/settings.json" >> dir / "settings.json"
    HOME / ".claude/CLAUDE.md" >> dir / "CLAUDE.md"
    Dir(HOME / ".claude/hooks") >> dir / "hooks"
    Dir(HOME / ".claude/scripts") >> dir / "scripts"

@operation(Op.RESTORE, "Claude Code", "claude-code")
def restore_claude_code(app: str, dir: Dir):
    for profile in (".claude", ".claude-2", ".claude-3"):
        dir >> HOME / profile

    dir / "CLAUDE.md" >> HOME / ".codex/AGENTS.md"
    dir / "CLAUDE.md" >> HOME / ".config/opencode/AGENTS.md"

    rule = HOME / ".cursor/rules/global-rules.mdc"
    try:
        log_transfer("file", dir / "CLAUDE.md", rule)
        rule.parent.mkdir(parents=True, exist_ok=True)
        rule.write_text("---\ndescription: Global programming rules\nalwaysApply: true\n---\n" + (dir / "CLAUDE.md").read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
    except Exception as e:
        log_error("Failed to write Cursor rule", e)

# ------------------------------------------------------------------------------
# App - Ghostty
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "Ghostty", "ghostty")
def backup_ghostty(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".config/ghostty/config" >> dir / "config"

@operation(Op.RESTORE, "Ghostty", "ghostty")
def restore_ghostty(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir >> UNIX_HOME / ".config/ghostty"

# ------------------------------------------------------------------------------
# App - Helix
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "Helix", "helix")
def backup_helix(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            WIN_ROAMING / "helix/config.toml" >> dir / "config.toml"
            WIN_ROAMING / "helix/languages.toml" >> dir / "languages.toml"
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".config/helix/config.toml" >> dir / "config.toml"
            UNIX_HOME / ".config/helix/languages.toml" >> dir / "languages.toml"

@operation(Op.RESTORE, "Helix", "helix")
def restore_helix(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_ROAMING / "helix"
        case OS.LINUX | OS.MAC:
            dir >> UNIX_HOME / ".config/helix"

# ------------------------------------------------------------------------------
# App - JetBrains
# ------------------------------------------------------------------------------
JETBRAINS_TOOLS = (
    "CLion",
    "DataGrip",
    "DataSpell",
    "GoLand",
    "IntelliJIdea",
    "PhpStorm",
    "PyCharm",
    "Rider",
    "RubyMine",
    "RustRover",
    "WebStorm",
)

JETBRAINS_FILES = (
    "keymaps",
    "options/advancedSettings.xml",
    "options/colors.scheme.xml",
    "options/editor-font.xml",
    "options/ide.general.xml",
    "options/laf.xml",
    "options/projectView.xml",
    "options/ui.lnf.xml",
    # "options/editor.xml",
    # "options/find.xml",
    # "options/keymapFlags.xml",
    # "options/terminal-font.xml",
    # "options/window.layouts.xml",
)

def jetbrains_installs() -> dict[str, File]:
    """Latest install folder for each installed JetBrains tool."""
    match SYSTEM:
        case OS.WIN:
            root = WIN_ROAMING / "JetBrains"
        case OS.MAC:
            root = MAC_APP_SUPPORT / "JetBrains"
        case OS.LINUX:
            root = UNIX_HOME / ".config/JetBrains"
    installs: dict[str, File] = {}
    for tool in JETBRAINS_TOOLS:
        versions = sorted(root.glob(f"{tool}[0-9]*"))
        if versions:
            installs[tool] = File(versions[-1])
    return installs

@operation(Op.BACKUP, "JetBrains", "jetbrains", subdir=True)
def backup_jetbrains(app: str, dir: Dir):
    for tool, install in jetbrains_installs().items():
        for file in JETBRAINS_FILES:
            source = install / file
            if not source.exists():
                continue
            source >> dir / tool / file

@operation(Op.RESTORE, "JetBrains", "jetbrains")
def restore_jetbrains(app: str, dir: Dir):
    for tool, install in jetbrains_installs().items():
        for file in JETBRAINS_FILES:
            source = dir / tool / file
            if not source.exists():
                continue
            source >> install / file

# ------------------------------------------------------------------------------
# App - Notable
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "Notable", "notable", source_of_truth=OS.WIN)
def backup_notable(app: str, dir: Dir):
    WIN_HOME / ".notable.json" >> dir / ".notable.json"

@operation(Op.RESTORE, "Notable", "notable")
def restore_notable(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            dir / ".notable.json" >> WIN_HOME / ".notable.json"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# App - OpenCode
# ------------------------------------------------------------------------------
OPENCODE_LAN = Rewrite(old="127.0.0.1", new="192.168.0.11")

@operation(Op.BACKUP, "OpenCode", "opencode")
def backup_opencode(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            WIN_HOME / ".config/opencode/opencode.json" >> dir / "opencode.json"
        case OS.LINUX | OS.MAC:
            (UNIX_HOME / ".config/opencode/opencode.json").rewriting(OPENCODE_LAN.reversed()) >> dir / "opencode.json"

@operation(Op.RESTORE, "OpenCode", "opencode")
def restore_opencode(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            dir / "opencode.json" >> WIN_HOME / ".config/opencode/opencode.json"
        case OS.LINUX | OS.MAC:
            # llama-server runs on the Windows machine; point other machines at it over the LAN
            (dir / "opencode.json").rewriting(OPENCODE_LAN) >> UNIX_HOME / ".config/opencode/opencode.json"

# ------------------------------------------------------------------------------
# App - PowerShell
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "PowerShell", "powershell", source_of_truth=OS.WIN)
def backup_powershell(app: str, dir: Dir):
    WIN_HOME / "Documents/PowerShell/Microsoft.PowerShell_profile.ps1" >> dir / "Microsoft.PowerShell_profile.ps1"
    WIN_HOME / "Documents/PowerShell/Profile" >> dir / "Profile"

@operation(Op.RESTORE, "PowerShell", "powershell")
def restore_powershell(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_HOME / "Documents/PowerShell"
            SCRIPTS / "claude.py" >> WIN_HOME / "scripts/claude.py"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# App - RStudio
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "RStudio", "rstudio", source_of_truth=OS.WIN)
def backup_rstudio(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            WIN_ROAMING / "RStudio/config.json" >> dir / "config.json"
            Dir(WIN_ROAMING / "RStudio/keybindings") >> dir / "keybindings"
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".config/rstudio/rstudio-prefs.json" >> dir / "rstudio-prefs.json"
            Dir(UNIX_HOME / ".config/rstudio/keybindings") >> dir / "keybindings"

@operation(Op.RESTORE, "RStudio", "rstudio")
def restore_rstudio(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_ROAMING / "RStudio"
        case OS.LINUX | OS.MAC:
            dir / "rstudio-prefs.json" >> UNIX_HOME / ".config/rstudio/rstudio-prefs.json"
            Dir(dir / "keybindings") >> UNIX_HOME / ".config/rstudio/keybindings"

# ------------------------------------------------------------------------------
# App - Starship
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "Starship", "starship")
def backup_starship(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".config/starship.toml" >> dir / "starship.toml"

@operation(Op.RESTORE, "Starship", "starship")
def restore_starship(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir / "starship.toml" >> UNIX_HOME / ".config/starship.toml"

# ------------------------------------------------------------------------------
# App - VIM
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "VIM", "vim")
def backup_vim(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".vimrc" >> dir / ".vimrc"

@operation(Op.RESTORE, "VIM", "vim")
def restore_vim(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir / ".vimrc" >> UNIX_HOME / ".vimrc"

# ------------------------------------------------------------------------------
# App - VSCode / Cursor
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "VSCode / Cursor", "vscode")
def backup_vscode(app: str, dir: Dir):
    # Scoop installs VSCode as a portable app, so its config lives under persist/ instead of %AppData%\Code.
    match SYSTEM:
        case OS.WIN:
            WIN_SCOOP / "persist/vscode/data/user-data/User/keybindings.json" >> dir / "keybindings.json"
            WIN_SCOOP / "persist/vscode/data/user-data/User/settings.json" >> dir / "settings.json"
        case OS.LINUX:
            UNIX_HOME / ".config/Code/User/keybindings.json" >> dir / "keybindings.json"
            UNIX_HOME / ".config/Code/User/settings.json" >> dir / "settings.json"
        case OS.MAC:
            MAC_APP_SUPPORT / "Code/User/keybindings.json" >> dir / "keybindings.json"
            MAC_APP_SUPPORT / "Code/User/settings.json" >> dir / "settings.json"

@operation(Op.RESTORE, "VSCode / Cursor", "vscode")
def restore_vscode(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_SCOOP / "persist/vscode/data/user-data/User"
            dir >> WIN_ROAMING / "Cursor/User"
        case OS.LINUX:
            dir >> UNIX_HOME / ".config/Code/User"
            dir >> UNIX_HOME / ".config/Cursor/User"
        case OS.MAC:
            dir >> MAC_APP_SUPPORT / "Code/User"
            dir >> MAC_APP_SUPPORT / "Cursor/User"

# ------------------------------------------------------------------------------
# App - Warp
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "Warp", "warp")
def backup_warp(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".warp/keybindings.yaml" >> dir / "keybindings.yaml"
            UNIX_HOME / ".warp/settings.toml" >> dir / "settings.toml"

@operation(Op.RESTORE, "Warp", "warp")
def restore_warp(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir >> UNIX_HOME / ".warp"

# ------------------------------------------------------------------------------
# App - Windows Terminal
# ------------------------------------------------------------------------------
@operation(Op.BACKUP, "Windows Terminal", "windows-terminal", source_of_truth=OS.WIN)
def backup_windows_terminal(app: str, dir: Dir):
    WIN_LOCAL / "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" >> dir / "settings.json"

@operation(Op.RESTORE, "Windows Terminal", "windows-terminal")
def restore_windows_terminal(app: str, dir: Dir):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_LOCAL / "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Registry
# ------------------------------------------------------------------------------
CATEGORIES: dict[str, tuple[str, ...]] = {
    "AI":       ("Claude Code", "OpenCode"),
    "Terminal": ("Ghostty", "PowerShell", "Starship", "Warp", "Windows Terminal"),
    "Editor":   ("Helix", "JetBrains", "RStudio", "VIM", "VSCode / Cursor"),
    "Notes":    ("Notable",),
}

apps_categorized = {app for apps in CATEGORIES.values() for app in apps}
if apps_categorized != HANDLERS_BY_APP.keys():
    raise ValueError(f"Apps missing a category or a handler: {sorted(apps_categorized ^ HANDLERS_BY_APP.keys())}")
for app_registered, handlers_registered in HANDLERS_BY_APP.items():
    if handlers_registered.keys() != set(Op):
        raise ValueError(f"{app_registered}: needs both a backup and a restore handler")

HANDLERS_BY_APP = {app: HANDLERS_BY_APP[app] for apps in CATEGORIES.values() for app in apps}

# ------------------------------------------------------------------------------
# Comparison
# ------------------------------------------------------------------------------
@dataclass
class Comparison:
    handlers_backup: dict[str, Handler]
    transfers_by_app: dict[str, list[tuple[File, File]]]
    syncs: dict[str, Sync]

    @classmethod
    def from_handlers(
        cls,
        handlers_backup: dict[str, Handler],
        track: Callable[[list[tuple[str, File, File]]], Iterable[tuple[str, File, File]]] = lambda transfers: transfers,
    ) -> "Comparison":
        history = BackupHistory.from_git(DOTFILES)
        transfers = [(app, machine, backup) for app, handler in handlers_backup.items() for machine, backup in handler.collect_transfers()]

        transfers_by_app: dict[str, list[tuple[File, File]]] = {app: [] for app in handlers_backup}
        files_by_app: dict[str, set[Sync | None]] = {app: set() for app in handlers_backup}
        for app, machine, backup in track(transfers):
            transfers_by_app[app].append((machine, backup))
            files_by_app[app].add(machine.compare_to_backup(backup, history))

        syncs = {app: Sync.from_files(files - {None}) for app, files in files_by_app.items()}
        return cls(handlers_backup=handlers_backup, transfers_by_app=transfers_by_app, syncs=syncs)

    def refresh(self, track: Callable[[list[tuple[str, File, File]]], Iterable[tuple[str, File, File]]]) -> None:
        comparison = Comparison.from_handlers(self.handlers_backup, track=track)
        self.transfers_by_app = comparison.transfers_by_app
        self.syncs = comparison.syncs

    def hints(self) -> dict[str, Hint]:
        return {app: sync.to_hint() for app, sync in self.syncs.items()}

    def diff(self, op_label: str, app: str) -> str:
        return "\n\n".join(
            diff
            for machine, backup in self.transfers_by_app.get(app, [])
            if (diff := (backup.diff_to(machine) if op_label == Op.BACKUP else machine.diff_to(backup)))
        )

    def restore_warning(self, selections: list[tuple[str, str]]) -> str | None:
        apps_restore = [app for op_label, app in selections if op_label == Op.RESTORE]
        if not apps_restore:
            return None

        restore_labels = [
            f"{app} ({self.syncs[app]})" if app in self.syncs and self.syncs[app].has_machine_changes() else app
            for app in apps_restore
        ]
        return "Restore overwrites local config for: " + ", ".join(restore_labels) + ". Continue?"

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
def main() -> None:
    handlers_backup = {app: handlers[Op.BACKUP] for app, handlers in HANDLERS_BY_APP.items() if handlers[Op.BACKUP].find_disabled() is None}
    comparison = Comparison.from_handlers(
        handlers_backup,
        track=lambda transfers: tqdm(transfers, desc="Comparing files", unit="file"),
    )

    def run(selections: list[tuple[str, str]], progress: Progress) -> None:
        File._deleted.clear()
        with logging_to(progress):
            for op_label, app in progress.track(selections, phase="Running", label=lambda selection: f"{selection[0]} {selection[1]}"):
                HANDLERS_BY_APP[app][Op(op_label)]()

    def refresh(progress: Progress) -> dict[str, Hint]:
        comparison.refresh(track=lambda transfers: progress.track(transfers, phase="Updating status", label=lambda transfer: str(transfer[1])))
        return comparison.hints()

    show_tui(
        items={category: list(apps) for category, apps in CATEGORIES.items()},
        items_disabled={
            op.value: {app: disabled for app, handlers in HANDLERS_BY_APP.items() if (disabled := handlers[op].find_disabled())}
            for op in Op
        },
        items_hint=comparison.hints(),
        item_diff=comparison.diff,
        run=run,
        refresh=refresh,
        confirm=comparison.restore_warning,
        panel_left=Op.BACKUP,
        panel_right=Op.RESTORE,
    )

    if errors_logged:
        sys.exit(1)

if __name__ == "__main__":
    main()
