import asyncio
import threading
from collections.abc import Callable, Iterator, Mapping, Sequence
from dataclasses import dataclass
from enum import Enum, auto
from typing import TypeVar

from prompt_toolkit import Application
from prompt_toolkit.data_structures import Point
from prompt_toolkit.filters import Condition
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import Dimension, HSplit, Layout, VSplit, Window, WindowAlign
from prompt_toolkit.layout.containers import ConditionalContainer, Float, FloatContainer, HorizontalAlign, VerticalAlign
from prompt_toolkit.layout.controls import FormattedTextControl
from prompt_toolkit.styles import Style
from prompt_toolkit.widgets import Frame


@dataclass(frozen=True)
class Category:
    name: str

@dataclass(frozen=True)
class Item:
    name: str

MenuRow = Category | Item


DIFF_PAGE = 20
PROGRESS_BAR_WIDTH = 40
PROGRESS_LAYOUT_ROWS = 13

T = TypeVar("T")


class Mode(Enum):
    BROWSING = auto()
    DIFF = auto()
    CONFIRM = auto()
    RUNNING = auto()
    FINISHED = auto()


class Progress:
    total: int
    done: int
    phase: str
    current: str
    status: str
    errors: int
    lines: list[tuple[str, str]] # (log kind, text)

    def __init__(self, on_change: Callable[[], None]):
        self.total = 0
        self.done = 0
        self.phase = ""
        self.current = ""
        self.status = ""
        self.errors = 0
        self.lines = []
        self.on_change = on_change

    def clear(self) -> None:
        self.total = 0
        self.done = 0
        self.phase = ""
        self.current = ""
        self.status = "running..."
        self.errors = 0
        self.lines.clear()
        self.on_change()

    def log(self, kind: str, text: str) -> None:
        if kind == "error":
            self.errors += 1
        self.lines.append((kind, text))
        self.on_change()

    def track(self, items: Sequence[T], phase: str, label: Callable[[T], str]) -> Iterator[T]:
        self.phase = phase
        self.total = len(items)
        self.done = 0
        for item in items:
            self.current = label(item)
            self.on_change()
            yield item
            self.done += 1
            self.on_change()


class TuiState:
    # panels
    panel_left: str # label for left panel
    panel_right: str # label for right panel

    # panel selection
    panel_active: str # which panel is active (left or right)
    cursor: int | None # menu_rows index of the cursor in the active panel (None when the active panel has no enabled items)
    panel_selected: dict[str, set[str]] # selected item names in each panel
    panel_disabled: dict[str, dict[str, "Disabled"]] # disabled items in each panel, with the reason
    panel_item_indices: dict[str, list[int]] # indexes of menu_rows that are selectable in each panel (enabled Item rows)

    menu_rows: list[MenuRow] # category and item rows, in display order
    items_hint: Mapping[str, "Hint"] # sync hint of each item

    mode: Mode # which popup is open (BROWSING when none)

    # diff popup
    diff_title: str # title of the open diff popup
    diff_lines: list[str] # lines of the open diff popup
    diff_scroll: int # first visible line of the diff popup

    # confirm popup
    confirm_message: str

    def __init__(self, panel_left: str, panel_right: str, items: dict[str, list[str]], items_disabled: dict[str, dict[str, "Disabled"]], items_hint: Mapping[str, "Hint"]):
        self.panel_left = panel_left
        self.panel_right = panel_right
        self.items_hint = items_hint
        self.mode = Mode.BROWSING
        self.confirm_message = ""

        # set menu state
        self.menu_rows = []
        for category_name, item_names in items.items():
            self.menu_rows.append(Category(category_name))
            self.menu_rows.extend(Item(item_name) for item_name in item_names)

        # set panel state
        self.panel_active = panel_left
        self.panel_selected = {panel_left: set(), panel_right: set()}
        self.panel_disabled = {panel: items_disabled.get(panel, {}) for panel in (panel_left, panel_right)}
        self.panel_item_indices = {
            panel: [i for i, row in enumerate(self.menu_rows) if isinstance(row, Item) and row.name not in self.panel_disabled[panel]]
            for panel in (panel_left, panel_right)
        }
        self.cursor = next(iter(self.panel_item_indices[panel_left]), None)

        # set diff popup state
        self.diff_title = ""
        self.diff_lines = []
        self.diff_scroll = 0

    def switch_panel(self) -> None:
        self.activate_panel(self.panel_right if self.is_active(self.panel_left) else self.panel_left)

    def activate_panel(self, panel: str) -> None:
        self.panel_active = panel
        cursor_previous = self.cursor or 0
        self.cursor = min(self.panel_item_indices[panel], key=lambda i: (abs(i - cursor_previous), i), default=None)

    def move_cursor(self, delta: int) -> None:
        indices = self.panel_item_indices[self.panel_active]
        if self.cursor is None:
            return
        new = max(0, min(len(indices) - 1, indices.index(self.cursor) + delta))
        self.cursor = indices[new]

    def cursor_to_first(self) -> None:
        indices = self.panel_item_indices[self.panel_active]
        if not indices:
            return
        self.cursor = indices[0]

    def cursor_to_last(self) -> None:
        indices = self.panel_item_indices[self.panel_active]
        if not indices:
            return
        self.cursor = indices[-1]

    def toggle_item(self) -> None:
        if self.cursor is None:
            return
        name = self.menu_rows[self.cursor].name
        self.panel_selected[self.panel_active] ^= {name}

    def select_all(self) -> None:
        self.panel_selected[self.panel_active] = {self.menu_rows[i].name for i in self.panel_item_indices[self.panel_active]}

    def select_none(self) -> None:
        self.panel_selected[self.panel_active].clear()

    def select_nothing(self) -> None:
        for selected in self.panel_selected.values():
            selected.clear()

    def selections(self) -> list[tuple[str, str]]:
        return [
            (panel, row.name)
            for panel in (self.panel_left, self.panel_right)
            for row in self.menu_rows
            if isinstance(row, Item) and row.name in self.panel_selected[panel]
        ]

    def is_active(self, panel: str) -> bool:
        return panel == self.panel_active

    def open_diff(self, title: str, text: str) -> None:
        self.diff_title = title
        self.diff_lines = text.splitlines() or ["no differences"]
        self.diff_scroll = 0
        self.mode = Mode.DIFF

    def close_diff(self) -> None:
        self.mode = Mode.BROWSING

    def scroll_diff(self, delta: int) -> None:
        self.diff_scroll = max(0, min(len(self.diff_lines) - 1, self.diff_scroll + delta))

    def cursor_item_name(self) -> str | None:
        if self.cursor is None:
            return None
        return self.menu_rows[self.cursor].name


@dataclass(frozen=True)
class Hint:
    text: str
    color: str


@dataclass(frozen=True)
class Disabled:
    icon: str
    color: str
    reason: str


def show_tui(
    items: dict[str, list[str]],
    items_disabled: dict[str, dict[str, Disabled]],
    items_hint: Mapping[str, Hint],
    item_diff: Callable[[str, str], str],
    run: Callable[[list[tuple[str, str]], Progress], None],
    refresh: Callable[[], Mapping[str, Hint]],
    confirm: Callable[[list[tuple[str, str]]], str | None],
    panel_left: str,
    panel_right: str,
) -> None:
    """Two-panel picker over `items` (category → item names).
    Enter runs the selected (panel_label, item_name) pairs through `run` with a progress popup,
    then calls `refresh` to get new hints and returns to the menu. `confirm` returns a warning
    message to confirm before running, or None. Re-raises any exception raised by a callback.
    """

    state = TuiState(
        panel_left=panel_left,
        panel_right=panel_right,
        items=items,
        items_disabled=items_disabled,
        items_hint=items_hint,
    )
    failures: list[BaseException] = []

    # --------------------------------------------------------------------------
    # TUI events
    # --------------------------------------------------------------------------
    kb = KeyBindings()
    browsing = Condition(lambda: state.mode is Mode.BROWSING)
    diffing = Condition(lambda: state.mode is Mode.DIFF)
    confirming = Condition(lambda: state.mode is Mode.CONFIRM)
    running = Condition(lambda: state.mode is Mode.RUNNING)
    finished = Condition(lambda: state.mode is Mode.FINISHED)
    not_running = Condition(lambda: state.mode is not Mode.RUNNING)

    def start_worker(app: Application, task: Callable[[], None], mode_after: Mode) -> None:
        loop = asyncio.get_running_loop()
        state.mode = Mode.RUNNING

        def work() -> None:
            try:
                task()
            except BaseException as error:
                failures.append(error)
                loop.call_soon_threadsafe(app.exit)
                return
            state.mode = mode_after
            app.invalidate()

        threading.Thread(target=work).start()

    def start_run(app: Application, selections: list[tuple[str, str]]) -> None:
        def run_task() -> None:
            run(selections, progress)
            progress.status = "updating status..."
            progress.on_change()
            state.items_hint = refresh()
            state.select_nothing()

        progress.clear()
        start_worker(app, run_task, Mode.FINISHED)

    @kb.add("tab", filter=browsing)
    @kb.add("s-tab", filter=browsing)
    def _(event):
        state.switch_panel()

    @kb.add("left", filter=browsing)
    def _(event):
        state.activate_panel(panel_left)

    @kb.add("right", filter=browsing)
    def _(event):
        state.activate_panel(panel_right)

    @kb.add("up", filter=browsing)
    @kb.add("k", filter=browsing)
    def _(event):
        state.move_cursor(-1)

    @kb.add("down", filter=browsing)
    @kb.add("j", filter=browsing)
    def _(event):
        state.move_cursor(1)

    @kb.add("home", filter=browsing)
    def _(event):
        state.cursor_to_first()

    @kb.add("end", filter=browsing)
    def _(event):
        state.cursor_to_last()

    @kb.add("space", filter=browsing)
    def _(event):
        state.toggle_item()

    @kb.add("a", filter=browsing)
    def _(event):
        state.select_all()

    @kb.add("n", filter=browsing)
    def _(event):
        state.select_none()

    @kb.add("enter", filter=browsing)
    def _(event):
        selections = state.selections()
        if not selections:
            return
        message = confirm(selections)
        if message is None:
            start_run(event.app, selections)
            return
        state.confirm_message = message
        state.mode = Mode.CONFIRM

    @kb.add("y", filter=confirming)
    @kb.add("enter", filter=confirming)
    def _(event):
        start_run(event.app, state.selections())

    @kb.add("n", filter=confirming)
    @kb.add("q", filter=confirming)
    @kb.add("escape", filter=confirming)
    def _(event):
        state.mode = Mode.BROWSING

    @kb.add("d", filter=browsing)
    def _(event):
        name = state.cursor_item_name()
        if name is None:
            return
        state.open_diff(title=f"{state.panel_active}: {name}", text=item_diff(state.panel_active, name))

    @kb.add("d", filter=diffing)
    @kb.add("q", filter=diffing)
    @kb.add("escape", filter=diffing)
    def _(event):
        state.close_diff()

    @kb.add("up", filter=diffing)
    @kb.add("k", filter=diffing)
    def _(event):
        state.scroll_diff(-1)

    @kb.add("down", filter=diffing)
    @kb.add("j", filter=diffing)
    def _(event):
        state.scroll_diff(1)

    @kb.add("pageup", filter=diffing)
    def _(event):
        state.scroll_diff(-DIFF_PAGE)

    @kb.add("pagedown", filter=diffing)
    def _(event):
        state.scroll_diff(DIFF_PAGE)

    @kb.add("home", filter=diffing)
    def _(event):
        state.scroll_diff(-len(state.diff_lines))

    @kb.add("end", filter=diffing)
    def _(event):
        state.scroll_diff(len(state.diff_lines))

    @kb.add("c-c", filter=not_running)
    @kb.add("escape", filter=browsing)
    @kb.add("q", filter=browsing)
    def _(event):
        event.app.exit()

    @kb.add("<any>", filter=finished)
    def _(event):
        state.mode = Mode.BROWSING

    # --------------------------------------------------------------------------
    # mount TUI
    # --------------------------------------------------------------------------
    panel_width = 42
    panel_height = Dimension(min=1, max=len(state.menu_rows), preferred=len(state.menu_rows))

    def tui_panel(panel: str) -> FormattedText:
        fragments: list[tuple[str, str]] = []

        for row_index, row in enumerate(state.menu_rows):
            # render category
            if isinstance(row, Category):
                fragments.append(("class:category", f" {row.name}\n"))
                continue

            item_disabled = state.panel_disabled[panel].get(row.name)
            if item_disabled:
                fragments.append(("class:disabled", "   "))
                fragments.append((f"class:disabled fg:{item_disabled.color}", item_disabled.icon))
                fragments.append(("class:disabled", f" [-] {row.name}\n"))
                continue

            # determine if on cursor or not
            on_cursor = state.is_active(panel) and row_index == state.cursor
            item_hint = state.items_hint.get(row.name, Hint(text="", color="ansibrightblack"))
            if on_cursor:
                row_style, hint_style, item_cursor = "class:focused", f"class:focused fg:{item_hint.color}", "▶"
            else:
                row_style, hint_style, item_cursor = "class:item", f"fg:{item_hint.color}", " "

            # determine if selected or not
            item_marker = "[●]" if row.name in state.panel_selected[panel] else "[ ]"

            # render item
            item_text = f" {item_cursor}   {item_marker} {row.name}"
            item_padding = max(1, panel_width - 2 - len(item_text) - len(item_hint.text) - 1)
            fragments.append((row_style, item_text + " " * item_padding))
            fragments.append((hint_style, f"{item_hint.text} \n"))

        return FormattedText(fragments)

    def tui_diff() -> FormattedText:
        fragments: list[tuple[str, str]] = []
        for line in state.diff_lines or []:
            if line.startswith(("+++", "---", "@@")):
                style = "class:diff-header"
            elif line.startswith("+"):
                style = "class:diff-add"
            elif line.startswith("-"):
                style = "class:diff-remove"
            else:
                style = ""
            fragments.append((style, f"{line}\n"))
        return FormattedText(fragments)

    def tui_progress_status() -> FormattedText:
        filled = PROGRESS_BAR_WIDTH * progress.done // progress.total if progress.total else 0
        return FormattedText([
            ("", f" {progress.phase}  {progress.done}/{progress.total}\n"),
            ("", f" [{'█' * filled}{'░' * (PROGRESS_BAR_WIDTH - filled)}]  {progress.current}"),
        ])

    def tui_progress_log() -> FormattedText:
        lines_visible = max(1, tui.output.get_size().rows - PROGRESS_LAYOUT_ROWS)
        return FormattedText([(f"class:log-{kind}", f" {text}\n") for kind, text in progress.lines[-lines_visible:]])

    def tui_progress_result() -> FormattedText:
        if state.mode is not Mode.FINISHED:
            return FormattedText([("class:help", f" {progress.status}")])
        if progress.errors:
            return FormattedText([("class:log-error", f" done with {progress.errors} errors"), ("class:help", "   [any key] close")])
        return FormattedText([("class:log-transfer", " done, no errors"), ("class:help", "   [any key] close")])

    def tui_confirm() -> FormattedText:
        return FormattedText([("", f" {state.confirm_message}\n\n"), ("class:help", " [y/Enter] run  [n/Esc] cancel")])

    def tui_help() -> str:
        match state.mode:
            case Mode.DIFF:
                return "[↑↓/jk] scroll  [PgUp/PgDn] page  [Home/End] first/last  [d/q/Esc] close"
            case Mode.CONFIRM:
                return "[y/Enter] run  [n/Esc] cancel"
            case Mode.RUNNING:
                return "running..."
            case Mode.FINISHED:
                return "[any key] close"
            case Mode.BROWSING:
                return "[Tab/←→] panel  [↑↓/jk] move  [Home/End] first/last  [Space] toggle  [a] all  [n] none  [d] diff  [Enter] run  [q/Esc] quit"

    def tui_legend() -> FormattedText:
        disabled_all = {disabled for disabled_by_item in state.panel_disabled.values() for disabled in disabled_by_item.values()}
        fragments: list[tuple[str, str]] = []
        for disabled in sorted(disabled_all, key=lambda disabled: disabled.reason):
            fragments.append((f"fg:{disabled.color}", disabled.icon))
            fragments.append(("class:help", f" {disabled.reason}   "))
        return FormattedText(fragments)

    def tui_panel_title(panel: str) -> str:
        return f"{'●' if state.is_active(panel) else ' '} {panel} ({len(state.panel_selected[panel])})"

    tui_theme = Style.from_dict({
        "category":         "bold ansicyan",
        "focused":          "reverse bold",
        "disabled":         "ansibrightblack dim",
        "help":             "ansibrightblack",
        "diff-add":         "ansigreen",
        "diff-remove":      "ansired",
        "diff-header":      "bold ansicyan",
        "rule":             "bold ansicyan",
        "log-transfer":     "ansigreen",
        "log-skip":         "ansiyellow",
        "log-error":        "ansired",
        "frame.label":      "bold",
    })

    tui_browser = HSplit([
        # side-by-side panels
        VSplit([
            Frame(Window(FormattedTextControl(lambda: tui_panel(panel_left), get_cursor_position=lambda: Point(0, state.cursor or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(panel_left)),
            Frame(Window(FormattedTextControl(lambda: tui_panel(panel_right), get_cursor_position=lambda: Point(0, state.cursor or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(panel_right)),
        ], padding=1, align=HorizontalAlign.CENTER),
        # help text
        Window(
            FormattedTextControl(tui_help),
            height=1, style="class:help", align=WindowAlign.CENTER
        ),
        # legend of disabled reasons
        Window(FormattedTextControl(tui_legend), height=1, align=WindowAlign.CENTER),
    ], align=VerticalAlign.CENTER)

    tui_diff_popup = ConditionalContainer(
        Frame(
            Window(FormattedTextControl(tui_diff), get_vertical_scroll=lambda window: state.diff_scroll, wrap_lines=False),
            title=lambda: f"diff — {state.diff_title}",
        ),
        filter=Condition(lambda: state.mode is Mode.DIFF),
    )

    def tui_rule(title: str) -> Window:
        return Window(FormattedTextControl(f"── {title} " + "─" * 300), height=1, style="class:rule")

    tui_progress_popup = ConditionalContainer(
        Frame(HSplit([
            tui_rule("Progress"),
            Window(FormattedTextControl(tui_progress_status), height=2),
            tui_rule("Log"),
            Window(FormattedTextControl(tui_progress_log), wrap_lines=False),
            tui_rule("Result"),
            Window(FormattedTextControl(tui_progress_result), height=1),
        ]), title="Run"),
        filter=Condition(lambda: state.mode in (Mode.RUNNING, Mode.FINISHED)),
    )

    tui_confirm_popup = ConditionalContainer(
        Frame(Window(FormattedTextControl(tui_confirm), wrap_lines=True), title="confirm"),
        filter=Condition(lambda: state.mode is Mode.CONFIRM),
    )

    tui_layout = Layout(FloatContainer(content=tui_browser, floats=[
        Float(content=tui_diff_popup, left=4, right=4, top=2, bottom=2),
        Float(content=tui_progress_popup, left=4, right=4, top=2, bottom=2),
        Float(content=tui_confirm_popup, width=70),
    ]))

    progress = Progress(on_change=lambda: tui.invalidate())
    tui = Application(layout=tui_layout, key_bindings=kb, style=tui_theme, full_screen=True, mouse_support=False)

    # --------------------------------------------------------------------------
    # run TUI
    # --------------------------------------------------------------------------
    tui.run()
    if failures:
        raise failures[0]
