from prompt_toolkit import Application
from prompt_toolkit.formatted_text import FormattedText
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import HSplit, Layout, VSplit, Window
from prompt_toolkit.layout.controls import FormattedTextControl
from prompt_toolkit.layout.dimension import Dimension
from prompt_toolkit.styles import Style
from prompt_toolkit.widgets import Frame


def show_tui(items: dict[str, dict[str, object]], panels: tuple[str, str]) -> list[tuple[str, str]]:
    """Two-panel picker over `items` (category → name → ...).

    `panels` provides the labels of the left and right panel (e.g. ("Backup", "Restore")).
    Returns a list of (panel_label, item_name), in menu order, with left-panel picks before right-panel picks.
    """
    LEFT, RIGHT = panels

    def other(panel: str) -> str:
        return RIGHT if panel == LEFT else LEFT

    # flatten items into a row list shared by both panels
    rows: list[tuple[str, str]] = []  # (kind, label) where kind is "category" or "item"
    for category, members in items.items():
        rows.append(("category", category))
        for name in members:
            rows.append(("item", name))

    item_indexes = [i for i, (kind, _) in enumerate(rows) if kind == "item"]
    first_item = item_indexes[0]

    # state, keyed by panel label
    active: list[str] = [LEFT]
    cursors:  dict[str, int]      = {LEFT: first_item, RIGHT: first_item}
    selected: dict[str, set[str]] = {LEFT: set(),      RIGHT: set()}

    def render(panel: str) -> FormattedText:
        out: list[tuple[str, str]] = []
        is_active_panel = (active[0] == panel)
        for i, (kind, label) in enumerate(rows):
            if kind == "category":
                out.append(("class:category", f" {label}\n"))
                continue
            marker = "[x]" if label in selected[panel] else "[ ]"
            on_cursor = (i == cursors[panel])
            if on_cursor and is_active_panel:
                style = "class:focused"
                prefix = "▶"
            elif on_cursor:
                style = "class:cursor-inactive"
                prefix = "·"
            else:
                style = "class:item"
                prefix = " "
            out.append((style, f" {prefix} {marker} {label}\n"))
        return FormattedText(out)

    def move(delta: int) -> None:
        panel = active[0]
        try:
            pos = item_indexes.index(cursors[panel])
        except ValueError:
            pos = 0
        pos = max(0, min(len(item_indexes) - 1, pos + delta))
        cursors[panel] = item_indexes[pos]

    kb = KeyBindings()

    @kb.add("tab")
    @kb.add("s-tab")
    @kb.add("right")
    @kb.add("left")
    def _(event):
        active[0] = other(active[0])

    @kb.add("up")
    def _(event):
        move(-1)

    @kb.add("down")
    def _(event):
        move(1)

    @kb.add("home")
    def _(event):
        cursors[active[0]] = item_indexes[0]

    @kb.add("end")
    def _(event):
        cursors[active[0]] = item_indexes[-1]

    @kb.add("space")
    def _(event):
        panel = active[0]
        name = rows[cursors[panel]][1]
        bucket = selected[panel]
        bucket.discard(name) if name in bucket else bucket.add(name)

    @kb.add("a")
    def _(event):
        selected[active[0]] = {label for kind, label in rows if kind == "item"}

    @kb.add("n")
    def _(event):
        selected[active[0]].clear()

    @kb.add("enter")
    def _(event):
        event.app.exit(result=True)

    @kb.add("c-c")
    @kb.add("escape")
    def _(event):
        event.app.exit(result=False)

    def title(panel: str) -> str:
        marker = "●" if active[0] == panel else " "
        return f"{marker} {panel}"

    height = Dimension(preferred=len(rows), min=len(rows))
    left_window  = Window(content=FormattedTextControl(lambda: render(LEFT)),  height=height)
    right_window = Window(content=FormattedTextControl(lambda: render(RIGHT)), height=height)

    body = VSplit([
        Frame(left_window,  title=lambda: title(LEFT)),
        Frame(right_window, title=lambda: title(RIGHT)),
    ], padding=1)

    help_text = "[Tab/←→] switch panel  [↑↓] move  [Space] toggle  [a] all  [n] none  [Enter] confirm  [Esc] cancel"
    help_window = Window(content=FormattedTextControl(help_text), height=1, style="class:help")

    layout = Layout(HSplit([body, help_window]))

    style = Style.from_dict({
        "category":         "bold ansicyan",
        "item":             "",
        "focused":          "reverse bold",
        "cursor-inactive":  "ansiblue",
        "help":             "ansibrightblack",
        "frame.label":      "bold",
    })

    app = Application(layout=layout, key_bindings=kb, style=style, full_screen=True, mouse_support=False)
    confirmed = app.run()
    if not confirmed:
        return []

    # preserve menu order: left picks before right picks
    result: list[tuple[str, str]] = []
    for members in items.values():
        for name in members:
            for panel in (LEFT, RIGHT):
                if name in selected[panel]:
                    result.append((panel, name))
    return result
