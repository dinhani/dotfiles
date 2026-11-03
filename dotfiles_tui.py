from collections.abc import Callable, Mapping
from dataclasses import dataclass

from prompt_toolkit import Application
from prompt_toolkit.data_structures import Point
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.filters import Condition
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


class TuiState:
    # panels
    panel_left: str # label for left panel
    panel_right: str # label for right panel

    # panel selection
    panel_active: str # which panel is active (left or right)
    panel_cursors: dict[str, int | None] # position of cursor in each panel (None when the panel has no enabled items)
    panel_selected: dict[str, set[str]] # selected item names in each panel
    panel_disabled: dict[str, set[str]] # disabled item names in each panel
    panel_item_indices: dict[str, list[int]] # indexes of menu_rows that are selectable in each panel (enabled Item rows)

    menu_rows: list[MenuRow] # category and item rows, in display order

    # diff popup
    diff_title: str # title of the open diff popup
    diff_lines: list[str] | None # lines of the open diff popup (None when closed)
    diff_scroll: int # first visible line of the diff popup

    def __init__(self, panel_left: str, panel_right: str, items: dict[str, list[str]], items_disabled: dict[str, set[str]]):
        self.panel_left = panel_left
        self.panel_right = panel_right

        # set menu state
        self.menu_rows = []
        for category_name, item_names in items.items():
            self.menu_rows.append(Category(category_name))
            self.menu_rows.extend(Item(item_name) for item_name in item_names)

        # set panel state
        self.panel_active = panel_left
        self.panel_selected = {panel_left: set(), panel_right: set()}
        self.panel_disabled = {panel: items_disabled.get(panel, set()) for panel in (panel_left, panel_right)}
        self.panel_item_indices = {
            panel: [i for i, row in enumerate(self.menu_rows) if isinstance(row, Item) and row.name not in self.panel_disabled[panel]]
            for panel in (panel_left, panel_right)
        }
        self.panel_cursors = {panel: indices[0] if indices else None for panel, indices in self.panel_item_indices.items()}

        # set diff popup state
        self.diff_title = ""
        self.diff_lines = None
        self.diff_scroll = 0

    def switch_panel(self) -> None:
        self.panel_active = self.panel_right if self.is_active(self.panel_left) else self.panel_left

    def activate_panel(self, panel: str) -> None:
        self.panel_active = panel

    def move_cursor(self, delta: int) -> None:
        indices = self.panel_item_indices[self.panel_active]
        cursor = self.panel_cursors[self.panel_active]
        if cursor is None:
            return
        new = max(0, min(len(indices) - 1, indices.index(cursor) + delta))
        self.panel_cursors[self.panel_active] = indices[new]

    def cursor_to_first(self) -> None:
        indices = self.panel_item_indices[self.panel_active]
        if not indices:
            return
        self.panel_cursors[self.panel_active] = indices[0]

    def cursor_to_last(self) -> None:
        indices = self.panel_item_indices[self.panel_active]
        if not indices:
            return
        self.panel_cursors[self.panel_active] = indices[-1]

    def toggle_item(self) -> None:
        cursor = self.panel_cursors[self.panel_active]
        if cursor is None:
            return
        name = self.menu_rows[cursor].name
        self.panel_selected[self.panel_active] ^= {name}

    def select_all(self) -> None:
        self.panel_selected[self.panel_active] = {self.menu_rows[i].name for i in self.panel_item_indices[self.panel_active]}

    def select_none(self) -> None:
        self.panel_selected[self.panel_active].clear()

    def is_active(self, panel: str) -> bool:
        return panel == self.panel_active

    def diff_is_open(self) -> bool:
        return self.diff_lines is not None

    def open_diff(self, title: str, text: str) -> None:
        self.diff_title = title
        self.diff_lines = text.splitlines() or ["no differences"]
        self.diff_scroll = 0

    def close_diff(self) -> None:
        self.diff_lines = None

    def scroll_diff(self, delta: int) -> None:
        assert self.diff_lines is not None
        self.diff_scroll = max(0, min(len(self.diff_lines) - 1, self.diff_scroll + delta))

    def cursor_item_name(self) -> str | None:
        cursor = self.panel_cursors[self.panel_active]
        if cursor is None:
            return None
        return self.menu_rows[cursor].name


@dataclass(frozen=True)
class Hint:
    text: str
    color: str


def show_tui(items: dict[str, list[str]], items_disabled: dict[str, set[str]], items_hint: Mapping[str, Hint], item_diff: Callable[[str, str], str], panel_left: str, panel_right: str) -> list[tuple[str, str]]:
    """Two-panel picker over `items` (category → item names).
    Returns (panel_label, item_name) pairs in menu order.
    """

    state = TuiState(
        panel_left=panel_left,
        panel_right=panel_right,
        items=items,
        items_disabled=items_disabled,
    )

    # --------------------------------------------------------------------------
    # TUI events
    # --------------------------------------------------------------------------
    kb = KeyBindings()
    browsing = Condition(lambda: not state.diff_is_open())
    diffing = Condition(lambda: state.diff_is_open())

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
        event.app.exit(result=True)

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
        state.scroll_diff(-len(state.diff_lines or []))

    @kb.add("end", filter=diffing)
    def _(event):
        state.scroll_diff(len(state.diff_lines or []))

    @kb.add("c-c")
    @kb.add("escape", filter=browsing)
    @kb.add("q", filter=browsing)
    def _(event):
        event.app.exit(result=False)

    # --------------------------------------------------------------------------
    # mount TUI
    # --------------------------------------------------------------------------
    panel_width = 40
    panel_height = Dimension(min=1, max=len(state.menu_rows), preferred=len(state.menu_rows))

    def tui_panel(panel: str) -> FormattedText:
        fragments: list[tuple[str, str]] = []

        for row_index, row in enumerate(state.menu_rows):
            # render category
            if isinstance(row, Category):
                fragments.append(("class:category", f" {row.name}\n"))
                continue

            if row.name in state.panel_disabled[panel]:
                fragments.append(("class:disabled", f"   [-] {row.name}\n"))
                continue

            # determine if on cursor or not
            on_cursor = row_index == state.panel_cursors[panel]
            item_hint = items_hint.get(row.name, Hint(text="", color="ansibrightblack"))
            if on_cursor and state.is_active(panel):
                row_style, hint_style, item_cursor = "class:focused", f"class:focused fg:{item_hint.color}", "▶"
            elif on_cursor:
                row_style, hint_style, item_cursor = "class:cursor-inactive", f"fg:{item_hint.color}", "·"
            else:
                row_style, hint_style, item_cursor = "class:item", f"fg:{item_hint.color}", " "

            # determine if selected or not
            item_marker = "[●]" if row.name in state.panel_selected[panel] else "[ ]"

            # render item
            item_text = f" {item_cursor} {item_marker} {row.name}"
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

    def tui_panel_title(panel: str) -> str:
        return f"{'●' if state.is_active(panel) else ' '} {panel} ({len(state.panel_selected[panel])})"

    tui_theme = Style.from_dict({
        "category":         "bold ansicyan",
        "focused":          "reverse bold",
        "cursor-inactive":  "ansiblue",
        "disabled":         "ansibrightblack",
        "help":             "ansibrightblack",
        "diff-add":         "ansigreen",
        "diff-remove":      "ansired",
        "diff-header":      "bold ansicyan",
        "frame.label":      "bold",
    })

    tui_browser = HSplit([
        # side-by-side panels
        VSplit([
            Frame(Window(FormattedTextControl(lambda: tui_panel(panel_left), get_cursor_position=lambda: Point(0, state.panel_cursors[panel_left] or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(panel_left)),
            Frame(Window(FormattedTextControl(lambda: tui_panel(panel_right), get_cursor_position=lambda: Point(0, state.panel_cursors[panel_right] or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(panel_right)),
        ], padding=1, align=HorizontalAlign.CENTER),
        # help text
        Window(
            FormattedTextControl(lambda: "[↑↓/jk] scroll  [PgUp/PgDn] page  [Home/End] first/last  [d/q/Esc] close" if state.diff_is_open() else "[Tab/←→] panel  [↑↓/jk] move  [Home/End] first/last  [Space] toggle  [a] all  [n] none  [d] diff  [Enter] confirm  [q/Esc] cancel"),
            height=1, style="class:help", align=WindowAlign.CENTER
        )
    ], align=VerticalAlign.CENTER)

    tui_diff_popup = ConditionalContainer(
        Frame(
            Window(FormattedTextControl(tui_diff), get_vertical_scroll=lambda window: state.diff_scroll, wrap_lines=False),
            title=lambda: f"diff — {state.diff_title}",
        ),
        filter=Condition(lambda: state.diff_is_open()),
    )

    tui_layout = Layout(FloatContainer(content=tui_browser, floats=[Float(content=tui_diff_popup, left=4, right=4, top=2, bottom=2)]))

    tui = Application(layout=tui_layout, key_bindings=kb, style=tui_theme, full_screen=True, mouse_support=False)

    # --------------------------------------------------------------------------
    # run TUI
    # --------------------------------------------------------------------------
    if not tui.run():
        return []

    return [
        (panel, row.name)
        for panel in (panel_left, panel_right)
        for row in state.menu_rows
        if isinstance(row, Item) and row.name in state.panel_selected[panel]
    ]
