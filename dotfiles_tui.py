from prompt_toolkit import Application
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import HSplit, Layout, VSplit, Window
from prompt_toolkit.layout.controls import FormattedTextControl
from prompt_toolkit.layout.dimension import Dimension
from prompt_toolkit.styles import Style
from prompt_toolkit.widgets import Frame


def show_tui(items: dict[str, dict[str, object]], left_panel: str, right_panel: str) -> list[tuple[str, str]]:
    """Two-panel picker over `items` (category → name → ...).

    Returns (panel_label, item_name) pairs in menu order.
    """
    # --- state ---
    # menu_rows: (label, is_item). Categories are headers, items are selectable.
    menu_rows: list[tuple[str, bool]] = []
    for category, members in items.items():
        menu_rows.append((category, False))
        for name in members:
            menu_rows.append((name, True))

    selectable_indexes = [i for i, (_, is_item) in enumerate(menu_rows) if is_item]

    active_panel = [left_panel]
    cursors  = {left_panel: selectable_indexes[0], right_panel: selectable_indexes[0]}
    selected: dict[str, set[str]] = {left_panel: set(), right_panel: set()}
    kb = KeyBindings()

    # --- functions & handlers ---
    def render(panel: str) -> FormattedText:
        fragments: list[tuple[str, str]] = []
        is_active_panel = active_panel[0] == panel
        for row_index, (label, is_item) in enumerate(menu_rows):
            if not is_item:
                fragments.append(("class:category", f" {label}\n"))
                continue
            marker = "[x]" if label in selected[panel] else "[ ]"
            on_cursor = row_index == cursors[panel]
            if on_cursor and is_active_panel:
                row_style, prefix = "class:focused", "▶"
            elif on_cursor:
                row_style, prefix = "class:cursor-inactive", "·"
            else:
                row_style, prefix = "class:item", " "
            fragments.append((row_style, f" {prefix} {marker} {label}\n"))
        return FormattedText(fragments)

    def move_cursor(delta: int) -> None:
        panel = active_panel[0]
        current_position = selectable_indexes.index(cursors[panel])
        new_position = max(0, min(len(selectable_indexes) - 1, current_position + delta))
        cursors[panel] = selectable_indexes[new_position]

    def panel_title(panel: str) -> str:
        return f"{'●' if active_panel[0] == panel else ' '} {panel}"

    @kb.add("tab")
    @kb.add("s-tab")
    @kb.add("right")
    @kb.add("left")
    def _(event):
        active_panel[0] = right_panel if active_panel[0] == left_panel else left_panel

    @kb.add("up")
    def _(event):
        move_cursor(-1)

    @kb.add("down")
    def _(event):
        move_cursor(1)

    @kb.add("home")
    def _(event):
        cursors[active_panel[0]] = selectable_indexes[0]

    @kb.add("end")
    def _(event):
        cursors[active_panel[0]] = selectable_indexes[-1]

    @kb.add("space")
    def _(event):
        panel = active_panel[0]
        name = menu_rows[cursors[panel]][0]
        selected[panel] ^= {name}

    @kb.add("a")
    def _(event):
        selected[active_panel[0]] = {label for label, is_item in menu_rows if is_item}

    @kb.add("n")
    def _(event):
        selected[active_panel[0]].clear()

    @kb.add("enter")
    def _(event):
        event.app.exit(result=True)

    @kb.add("c-c")
    @kb.add("escape")
    @kb.add("q")
    def _(event):
        event.app.exit(result=False)

    # --- build & run ---
    panel_height = Dimension(preferred=len(menu_rows), min=len(menu_rows))
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
        if name in selected[panel]
    ]
