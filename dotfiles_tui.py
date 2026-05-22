from prompt_toolkit import Application
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import HSplit, Layout, VSplit, Window, WindowAlign
from prompt_toolkit.layout.containers import HorizontalAlign, VerticalAlign
from prompt_toolkit.layout.controls import FormattedTextControl
from prompt_toolkit.styles import Style
from prompt_toolkit.widgets import Frame


class TuiState:
    # panels
    panel_left: str # label for left panel
    panel_right: str # label for right panel

    # panel selection
    panel_active: str # which panel is active (left or right)
    panel_cursors: dict[str, int] # position of cursor in each panel
    panel_selected: dict[str, set[str]] # selected item names in each panel

    menu_items: list[tuple[str, bool]] # (label, is_item) for each menu row, in display order
    menu_items_indices: list[int] # indexes of menu_rows that are selectable (is_item = True)

    def __init__(self, panel_left: str, panel_right: str, items: dict[str, dict[str, object]]):
        self.panel_left = panel_left
        self.panel_right = panel_right

        # set menu state
        self.menu_items = []
        for category_name, members in items.items():
            self.menu_items.append((category_name, False))
            for item_name in members:
                self.menu_items.append((item_name, True))

        self.menu_items_indices = [i for i, (_, is_item) in enumerate(self.menu_items) if is_item]

        # set panel state
        self.panel_active = panel_left
        self.panel_cursors = {panel_left: self.menu_items_indices[0], panel_right: self.menu_items_indices[0]}
        self.panel_selected = {panel_left: set(), panel_right: set()}

    def switch_panel(self) -> None:
        self.panel_active = self.panel_right if self.is_active(self.panel_left) else self.panel_left

    def move_cursor(self, delta: int) -> None:
        current = self.menu_items_indices.index(self.panel_cursors[self.panel_active])
        new = max(0, min(len(self.menu_items_indices) - 1, current + delta))
        self.panel_cursors[self.panel_active] = self.menu_items_indices[new]

    def cursor_to_first(self) -> None:
        self.panel_cursors[self.panel_active] = self.menu_items_indices[0]

    def cursor_to_last(self) -> None:
        self.panel_cursors[self.panel_active] = self.menu_items_indices[-1]

    def toggle_item(self) -> None:
        name = self.menu_items[self.panel_cursors[self.panel_active]][0]
        self.panel_selected[self.panel_active] ^= {name}

    def select_all(self) -> None:
        self.panel_selected[self.panel_active] = {label for label, is_item in self.menu_items if is_item}

    def select_none(self) -> None:
        self.panel_selected[self.panel_active].clear()

    def is_active(self, panel: str) -> bool:
        return panel == self.panel_active


def show_tui(items: dict[str, dict[str, object]], left_panel: str, right_panel: str) -> list[tuple[str, str]]:
    """Two-panel picker over `items` (category → name → ...).
    Returns (panel_label, item_name) pairs in menu order.
    """

    state = TuiState(
        panel_left=left_panel,
        panel_right=right_panel,
        items=items,
    )

    # --------------------------------------------------------------------------
    # TUI events
    # --------------------------------------------------------------------------
    kb = KeyBindings()

    @kb.add("tab")
    @kb.add("s-tab")
    @kb.add("right")
    @kb.add("left")
    def _(event):
        state.switch_panel()

    @kb.add("up")
    def _(event):
        state.move_cursor(-1)

    @kb.add("down")
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
    def tui_panel(panel: str) -> FormattedText:
        fragments: list[tuple[str, str]] = []

        for row_index, (item_label, item_is_item) in enumerate(state.menu_items):
            # render category
            if not item_is_item:
                fragments.append(("class:category", f" {item_label}\n"))
                continue

            # determine if on cursor or not
            on_cursor = row_index == state.panel_cursors[panel]
            if on_cursor and state.is_active(panel):
                row_style, item_cursor = "class:focused", "▶"
            elif on_cursor:
                row_style, item_cursor = "class:cursor-inactive", "·"
            else:
                row_style, item_cursor = "class:item", " "

            # determine if selected or not
            item_marker = "[●]" if item_label in state.panel_selected[panel] else "[ ]"

            # render item
            fragments.append((row_style, f" {item_cursor} {item_marker} {item_label}\n"))

        return FormattedText(fragments)

    def tui_panel_title(panel: str) -> str:
        return f"{'●' if state.is_active(panel) else ' '} {panel}"

    tui_theme = Style.from_dict({
        "category":         "bold ansicyan",
        "focused":          "reverse bold",
        "cursor-inactive":  "ansiblue",
        "help":             "ansibrightblack",
        "frame.label":      "bold",
    })

    tui_layout = Layout(
        HSplit([
            # side-by-side panels
            VSplit([
                Frame(Window(FormattedTextControl(lambda: tui_panel(left_panel)), height=len(state.menu_items)), width=40, title=lambda: tui_panel_title(left_panel)),
                Frame(Window(FormattedTextControl(lambda: tui_panel(right_panel)), height=len(state.menu_items)), width=40, title=lambda: tui_panel_title(right_panel)),
            ], padding=1, align=HorizontalAlign.CENTER),
            # help text
            Window(
                FormattedTextControl("[Tab/←→] switch panel  [↑↓] move  [Space] toggle  [a] all  [n] none  [Enter] confirm  [q/Esc] cancel"),
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
        (panel, name)
        for panel in (left_panel, right_panel)
        for name, is_item in state.menu_items
        if is_item and name in state.panel_selected[panel]
    ]
