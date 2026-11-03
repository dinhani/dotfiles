import asyncio
import threading
from collections.abc import Callable, Iterator, Mapping, Sequence
from dataclasses import dataclass, replace
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


@dataclass(frozen=True)
class Hint:
    text: str
    color: str


@dataclass(frozen=True)
class Disabled:
    icon: str
    color: str
    reason: str


DIFF_PAGE = 20
PROGRESS_BAR_WIDTH = 40
PROGRESS_LAYOUT_ROWS = 13

T = TypeVar("T")


@dataclass(frozen=True)
class Browsing:
    pass

@dataclass(frozen=True)
class Diffing:
    title: str
    lines: tuple[str, ...]
    scroll: int # first visible line

    def scrolled(self, delta: int) -> "Diffing":
        return replace(self, scroll=max(0, min(len(self.lines) - 1, self.scroll + delta)))

    def scrolled_to_start(self) -> "Diffing":
        return replace(self, scroll=0)

    def scrolled_to_end(self) -> "Diffing":
        return replace(self, scroll=len(self.lines) - 1)

@dataclass(frozen=True)
class Confirming:
    message: str

@dataclass(frozen=True)
class Running:
    pass

@dataclass(frozen=True)
class Finished:
    pass

Mode = Browsing | Diffing | Confirming | Running | Finished


class Progress:
    total: int
    done: int
    phase: str
    current: str
    status: str
    errors: int
    lines: list[tuple[str, str]] # (log kind, text)

    def __init__(self, on_change: Callable[[], None]):
        self.on_change = on_change
        self.lines = []
        self.clear()

    def clear(self) -> None:
        self.total = 0
        self.done = 0
        self.phase = ""
        self.current = ""
        self.status = "running..."
        self.errors = 0
        self.lines.clear()

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


class Panel:
    label: str
    disabled: dict[str, Disabled] # disabled items, with the reason
    item_rows: list[int] # indexes of menu_rows that are selectable (enabled Item rows)
    selected: set[int]

    def __init__(self, label: str, menu_rows: list[MenuRow], disabled: dict[str, Disabled]):
        self.label = label
        self.disabled = disabled
        self.item_rows = [i for i, row in enumerate(menu_rows) if isinstance(row, Item) and row.name not in disabled]
        self.selected = set()

    def nearest_item(self, row: int) -> int | None:
        return min(self.item_rows, key=lambda i: (abs(i - row), i), default=None)

    def toggle(self, row: int) -> None:
        self.selected ^= {row}

    def select_all(self) -> None:
        self.selected = set(self.item_rows)

    def clear_selection(self) -> None:
        self.selected.clear()

    def is_selected(self, row: int) -> bool:
        return row in self.selected


class TuiState:
    # panels
    left: Panel
    right: Panel
    active: Panel # which panel is active (left or right)
    cursor: int | None # menu_rows index of the cursor in the active panel (None when the active panel has no enabled items)

    menu_rows: list[MenuRow] # category and item rows, in display order
    items_hint: Mapping[str, Hint] # sync hint of each item

    mode: Mode # which popup is open (Browsing when none)

    def __init__(self, panel_left: str, panel_right: str, items: dict[str, list[str]], items_disabled: dict[str, dict[str, Disabled]], items_hint: Mapping[str, Hint]):
        self.items_hint = items_hint
        self.mode = Browsing()

        # set menu state
        self.menu_rows = []
        for category_name, item_names in items.items():
            self.menu_rows.append(Category(category_name))
            self.menu_rows.extend(Item(item_name) for item_name in item_names)

        # set panel state
        self.left = Panel(panel_left, self.menu_rows, items_disabled.get(panel_left, {}))
        self.right = Panel(panel_right, self.menu_rows, items_disabled.get(panel_right, {}))
        self.active = self.left
        self.cursor = next(iter(self.left.item_rows), None)

    def switch_panel(self) -> None:
        self.activate_panel(self.right if self.is_active(self.left) else self.left)

    def activate_panel(self, panel: Panel) -> None:
        self.active = panel
        self.cursor = panel.nearest_item(self.cursor or 0)

    def move_cursor(self, delta: int) -> None:
        rows = self.active.item_rows
        if self.cursor is None:
            return
        new = max(0, min(len(rows) - 1, rows.index(self.cursor) + delta))
        self.cursor = rows[new]

    def cursor_to_first(self) -> None:
        rows = self.active.item_rows
        if not rows:
            return
        self.cursor = rows[0]

    def cursor_to_last(self) -> None:
        rows = self.active.item_rows
        if not rows:
            return
        self.cursor = rows[-1]

    def toggle_item(self) -> None:
        if self.cursor is None:
            return
        self.active.toggle(self.cursor)

    def clear_selections(self) -> None:
        self.left.clear_selection()
        self.right.clear_selection()

    def selections(self) -> list[tuple[str, str]]:
        return [(panel.label, self.menu_rows[row].name) for panel in (self.left, self.right) for row in sorted(panel.selected)]

    def is_active(self, panel: Panel) -> bool:
        return panel is self.active

    def cursor_item_name(self) -> str | None:
        if self.cursor is None:
            return None
        return self.menu_rows[self.cursor].name

    def open_diff(self, title: str, text: str) -> None:
        self.mode = Diffing(title=title, lines=tuple(text.splitlines()) or ("no differences",), scroll=0)

    def scroll_diff(self, scroll: Callable[[Diffing], Diffing]) -> None:
        if not isinstance(self.mode, Diffing):
            return
        self.mode = scroll(self.mode)

    def open_confirm(self, message: str) -> None:
        self.mode = Confirming(message=message)

    def close_popup(self) -> None:
        self.mode = Browsing()


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
    browsing = Condition(lambda: isinstance(state.mode, Browsing))
    diffing = Condition(lambda: isinstance(state.mode, Diffing))
    confirming = Condition(lambda: isinstance(state.mode, Confirming))
    running = Condition(lambda: isinstance(state.mode, Running))
    finished = Condition(lambda: isinstance(state.mode, Finished))

    def start_worker(app: Application, task: Callable[[], None], mode_after: Mode) -> None:
        loop = asyncio.get_running_loop()
        state.mode = Running()

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
            state.clear_selections()

        progress.clear()
        start_worker(app, run_task, Finished())

    @kb.add("tab", filter=browsing)
    @kb.add("s-tab", filter=browsing)
    def _(event):
        state.switch_panel()

    @kb.add("left", filter=browsing)
    def _(event):
        state.activate_panel(state.left)

    @kb.add("right", filter=browsing)
    def _(event):
        state.activate_panel(state.right)

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
        state.active.select_all()

    @kb.add("n", filter=browsing)
    def _(event):
        state.active.clear_selection()

    @kb.add("enter", filter=browsing)
    def _(event):
        selections = state.selections()
        if not selections:
            return
        message = confirm(selections)
        if message is None:
            start_run(event.app, selections)
            return
        state.open_confirm(message)

    @kb.add("y", filter=confirming)
    @kb.add("enter", filter=confirming)
    def _(event):
        start_run(event.app, state.selections())

    @kb.add("n", filter=confirming)
    @kb.add("q", filter=confirming)
    @kb.add("escape", filter=confirming)
    def _(event):
        state.close_popup()

    @kb.add("d", filter=browsing)
    def _(event):
        name = state.cursor_item_name()
        if name is None:
            return
        state.open_diff(title=f"{state.active.label}: {name}", text=item_diff(state.active.label, name))

    @kb.add("d", filter=diffing)
    @kb.add("q", filter=diffing)
    @kb.add("escape", filter=diffing)
    def _(event):
        state.close_popup()

    @kb.add("up", filter=diffing)
    @kb.add("k", filter=diffing)
    def _(event):
        state.scroll_diff(lambda diff: diff.scrolled(-1))

    @kb.add("down", filter=diffing)
    @kb.add("j", filter=diffing)
    def _(event):
        state.scroll_diff(lambda diff: diff.scrolled(1))

    @kb.add("pageup", filter=diffing)
    def _(event):
        state.scroll_diff(lambda diff: diff.scrolled(-DIFF_PAGE))

    @kb.add("pagedown", filter=diffing)
    def _(event):
        state.scroll_diff(lambda diff: diff.scrolled(DIFF_PAGE))

    @kb.add("home", filter=diffing)
    def _(event):
        state.scroll_diff(Diffing.scrolled_to_start)

    @kb.add("end", filter=diffing)
    def _(event):
        state.scroll_diff(Diffing.scrolled_to_end)

    @kb.add("c-c", filter=~running)
    @kb.add("escape", filter=browsing)
    @kb.add("q", filter=browsing)
    def _(event):
        event.app.exit()

    @kb.add("<any>", filter=finished)
    def _(event):
        state.close_popup()

    # --------------------------------------------------------------------------
    # mount TUI
    # --------------------------------------------------------------------------
    panel_width = 42
    panel_height = Dimension(min=1, max=len(state.menu_rows), preferred=len(state.menu_rows))

    def tui_panel(panel: Panel) -> FormattedText:
        fragments: list[tuple[str, str]] = []

        for row_index, row in enumerate(state.menu_rows):
            # render category
            if isinstance(row, Category):
                fragments.append(("class:category", f" {row.name}\n"))
                continue

            item_disabled = panel.disabled.get(row.name)
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
            item_marker = "[●]" if panel.is_selected(row_index) else "[ ]"

            # render item
            item_text = f" {item_cursor}   {item_marker} {row.name}"
            item_padding = max(1, panel_width - 2 - len(item_text) - len(item_hint.text) - 1)
            fragments.append((row_style, item_text + " " * item_padding))
            fragments.append((hint_style, f"{item_hint.text} \n"))

        return FormattedText(fragments)

    def tui_diff() -> FormattedText:
        if not isinstance(state.mode, Diffing):
            return FormattedText([])
        fragments: list[tuple[str, str]] = []
        for line in state.mode.lines:
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
        if not isinstance(state.mode, Finished):
            return FormattedText([("class:help", f" {progress.status}")])
        if progress.errors:
            return FormattedText([("class:log-error", f" done with {progress.errors} errors"), ("class:help", "   [any key] close")])
        return FormattedText([("class:log-transfer", " done, no errors"), ("class:help", "   [any key] close")])

    def tui_confirm() -> FormattedText:
        if not isinstance(state.mode, Confirming):
            return FormattedText([])
        return FormattedText([("", f" {state.mode.message}\n\n"), ("class:help", " [y/Enter] run  [n/Esc] cancel")])

    def tui_help() -> str:
        match state.mode:
            case Diffing():
                return "[↑↓/jk] scroll  [PgUp/PgDn] page  [Home/End] first/last  [d/q/Esc] close"
            case Confirming():
                return "[y/Enter] run  [n/Esc] cancel"
            case Running():
                return "running..."
            case Finished():
                return "[any key] close"
            case Browsing():
                return "[Tab/←→] panel  [↑↓/jk] move  [Home/End] first/last  [Space] toggle  [a] all  [n] none  [d] diff  [Enter] run  [q/Esc] quit"

    def tui_legend() -> FormattedText:
        disabled_all = {disabled for panel in (state.left, state.right) for disabled in panel.disabled.values()}
        fragments: list[tuple[str, str]] = []
        for disabled in sorted(disabled_all, key=lambda disabled: disabled.reason):
            fragments.append((f"fg:{disabled.color}", disabled.icon))
            fragments.append(("class:help", f" {disabled.reason}   "))
        return FormattedText(fragments)

    def tui_panel_title(panel: Panel) -> str:
        return f"{'●' if state.is_active(panel) else ' '} {panel.label} ({len(panel.selected)})"

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
            Frame(Window(FormattedTextControl(lambda: tui_panel(state.left), get_cursor_position=lambda: Point(0, state.cursor or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(state.left)),
            Frame(Window(FormattedTextControl(lambda: tui_panel(state.right), get_cursor_position=lambda: Point(0, state.cursor or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(state.right)),
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
            Window(FormattedTextControl(tui_diff), get_vertical_scroll=lambda window: state.mode.scroll if isinstance(state.mode, Diffing) else 0, wrap_lines=False),
            title=lambda: f"diff — {state.mode.title}" if isinstance(state.mode, Diffing) else "diff",
        ),
        filter=diffing,
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
        filter=running | finished,
    )

    tui_confirm_popup = ConditionalContainer(
        Frame(Window(FormattedTextControl(tui_confirm), wrap_lines=True), title="confirm"),
        filter=confirming,
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
