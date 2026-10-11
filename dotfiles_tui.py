from collections.abc import Mapping
from dataclasses import dataclass

from prompt_toolkit import Application
from prompt_toolkit.data_structures import Point
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import Dimension, HSplit, Layout, VSplit, Window, WindowAlign
from prompt_toolkit.layout.containers import HorizontalAlign, VerticalAlign
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


def show_tui(items: dict[str, list[str]], items_disabled: dict[str, set[str]], items_hint: Mapping[str, str], panel_left: str, panel_right: str) -> list[tuple[str, str]]:
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

    @kb.add("tab")
    @kb.add("s-tab")
    def _(event):
        state.switch_panel()

    @kb.add("left")
    def _(event):
        state.activate_panel(panel_left)

    @kb.add("right")
    def _(event):
        state.activate_panel(panel_right)

    @kb.add("up")
    @kb.add("k")
    def _(event):
        state.move_cursor(-1)

    @kb.add("down")
    @kb.add("j")
    def _(event):
        state.move_cursor(1)

    @kb.add("home")
    def _(event):
        state.cursor_to_first()

    @kb.add("end")
    def _(event):
        state.cursor_to_last()

    @kb.add("space")
    def _(event):
        state.toggle_item()

    @kb.add("a")
    def _(event):
        state.select_all()

    @kb.add("n")
    def _(event):
        state.select_none()

    @kb.add("enter")
    def _(event):
        event.app.exit(result=True)

    @kb.add("c-c")
    @kb.add("escape")
    @kb.add("q")
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
            if on_cursor and state.is_active(panel):
                row_style, hint_style, item_cursor = "class:focused", "class:focused", "▶"
            elif on_cursor:
                row_style, hint_style, item_cursor = "class:cursor-inactive", "class:hint", "·"
            else:
                row_style, hint_style, item_cursor = "class:item", "class:hint", " "

            # determine if selected or not
            item_marker = "[●]" if row.name in state.panel_selected[panel] else "[ ]"

            # render item
            item_text = f" {item_cursor} {item_marker} {row.name}"
            item_hint = items_hint.get(row.name, "")
            item_padding = max(1, panel_width - 2 - len(item_text) - len(item_hint) - 1)
            fragments.append((row_style, item_text + " " * item_padding))
            fragments.append((hint_style, f"{item_hint} \n"))

        return FormattedText(fragments)

    def tui_panel_title(panel: str) -> str:
        return f"{'●' if state.is_active(panel) else ' '} {panel} ({len(state.panel_selected[panel])})"

    tui_theme = Style.from_dict({
        "category":         "bold ansicyan",
        "focused":          "reverse bold",
        "cursor-inactive":  "ansiblue",
        "disabled":         "ansibrightblack",
        "hint":             "ansibrightblack",
        "help":             "ansibrightblack",
        "frame.label":      "bold",
    })

    tui_layout = Layout(
        HSplit([
            # side-by-side panels
            VSplit([
                Frame(Window(FormattedTextControl(lambda: tui_panel(panel_left), get_cursor_position=lambda: Point(0, state.panel_cursors[panel_left] or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(panel_left)),
                Frame(Window(FormattedTextControl(lambda: tui_panel(panel_right), get_cursor_position=lambda: Point(0, state.panel_cursors[panel_right] or 0)), height=panel_height), width=panel_width, title=lambda: tui_panel_title(panel_right)),
            ], padding=1, align=HorizontalAlign.CENTER),
            # help text
            Window(
                FormattedTextControl("[Tab/←→] panel  [↑↓/jk] move  [Home/End] first/last  [Space] toggle  [a] all  [n] none  [Enter] confirm  [q/Esc] cancel"),
                height=1, style="class:help", align=WindowAlign.CENTER
            )
        ], align=VerticalAlign.CENTER)
    )

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
