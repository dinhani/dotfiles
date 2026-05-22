from dataclasses import dataclass, field

from prompt_toolkit import Application
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import HSplit, Layout, VSplit, Window
from prompt_toolkit.layout.controls import FormattedTextControl
from prompt_toolkit.layout.dimension import Dimension
from prompt_toolkit.styles import Style
from prompt_toolkit.widgets import Frame


@dataclass
class _State:
    left_panel: str
    right_panel: str
    menu_rows: list[tuple[str, bool]]
    selectable_indexes: list[int]
    active_panel: str
    cursors: dict[str, int]
    selected: dict[str, set[str]]

    def switch_panel(self) -> None:
        self.active_panel = self.right_panel if self.active_panel == self.left_panel else self.left_panel

    def move_cursor(self, delta: int) -> None:
        current = self.selectable_indexes.index(self.cursors[self.active_panel])
        new = max(0, min(len(self.selectable_indexes) - 1, current + delta))
        self.cursors[self.active_panel] = self.selectable_indexes[new]

    def cursor_to_first(self) -> None:
        self.cursors[self.active_panel] = self.selectable_indexes[0]

    def cursor_to_last(self) -> None:
        self.cursors[self.active_panel] = self.selectable_indexes[-1]

    def toggle_item(self) -> None:
        name = self.menu_rows[self.cursors[self.active_panel]][0]
        self.selected[self.active_panel] ^= {name}

    def select_all(self) -> None:
        self.selected[self.active_panel] = {label for label, is_item in self.menu_rows if is_item}

    def select_none(self) -> None:
        self.selected[self.active_panel].clear()


def show_tui(items: dict[str, dict[str, object]], left_panel: str, right_panel: str) -> list[tuple[str, str]]:
    """Two-panel picker over `items` (category → name → ...).

    Returns (panel_label, item_name) pairs in menu order.
    """
    menu_rows: list[tuple[str, bool]] = []
    for category, members in items.items():
        menu_rows.append((category, False))
        for name in members:
            menu_rows.append((name, True))

    selectable_indexes = [i for i, (_, is_item) in enumerate(menu_rows) if is_item]

    state = _State(
        left_panel=left_panel,
        right_panel=right_panel,
        menu_rows=menu_rows,
        selectable_indexes=selectable_indexes,
        active_panel=left_panel,
        cursors={left_panel: selectable_indexes[0], right_panel: selectable_indexes[0]},
        selected={left_panel: set(), right_panel: set()},
    )

    kb = KeyBindings()

    # --- functions & handlers ---
    def render(panel: str) -> FormattedText:
        fragments: list[tuple[str, str]] = []
        is_active_panel = state.active_panel == panel
        for row_index, (label, is_item) in enumerate(state.menu_rows):
            if not is_item:
                fragments.append(("class:category", f" {label}\n"))
                continue
            marker = "[x]" if label in state.selected[panel] else "[ ]"
            on_cursor = row_index == state.cursors[panel]
            if on_cursor and is_active_panel:
                row_style, prefix = "class:focused", "▶"
            elif on_cursor:
                row_style, prefix = "class:cursor-inactive", "·"
            else:
                row_style, prefix = "class:item", " "
            fragments.append((row_style, f" {prefix} {marker} {label}\n"))
        return FormattedText(fragments)

    def panel_title(panel: str) -> str:
        return f"{'●' if state.active_panel == panel else ' '} {panel}"

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

    # --- build & run ---
    panel_height = Dimension(preferred=len(state.menu_rows), min=len(state.menu_rows))
    panels_area = VSplit([
        Frame(Window(FormattedTextControl(lambda: render(left_panel)),  height=panel_height), title=lambda: panel_title(left_panel)),
        Frame(Window(FormattedTextControl(lambda: render(right_panel)), height=panel_height), title=lambda: panel_title(right_panel)),
    ], padding=1)

    help_text = "[Tab/←→] switch panel  [↑↓] move  [Space] toggle  [a] all  [n] none  [Enter] confirm  [q/Esc] cancel"
    help_bar = Window(FormattedTextControl(help_text), height=1, style="class:help")
    app_layout = Layout(HSplit([panels_area, help_bar]))

    app_theme = Style.from_dict({
        "category":         "bold ansicyan",
        "focused":          "reverse bold",
        "cursor-inactive":  "ansiblue",
        "help":             "ansibrightblack",
        "frame.label":      "bold",
    })

    application = Application(layout=app_layout, key_bindings=kb, style=app_theme, full_screen=True, mouse_support=False)
    if not application.run():
        return []

    return [
        (panel, name)
        for members in items.values()
        for name in members
        for panel in (left_panel, right_panel)
        if name in state.selected[panel]
    ]
