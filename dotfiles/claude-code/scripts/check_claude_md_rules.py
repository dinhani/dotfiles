# /// script
# requires-python = ">=3.12"
# dependencies = ["rich"]
# ///
import dataclasses
import io
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from rich import box
from rich.console import Console
from rich.table import Table

RULE_TITLE = re.compile(r"^- \*\*(.+?)\*\*")
HEADING_QUALIFIER = re.compile(r"\s*\(.*\)$")
GATE_PREFIX = "HARD GATE — "
CONTEXT_WINDOW_TOKENS = 200_000
BAR_WIDTH = 24
RULES_LARGEST_COUNT = 10
RULE_NAME_WIDTH = 60
RULE_NAME_WIDTH_MIN = 16
CATEGORY_WIDTH = 28


@dataclass(frozen=True, slots=True)
class Rule:
    category: str
    name: str
    gate: bool
    text: str

    def tokens_estimated(self) -> int:
        return estimate_tokens(self.text)

    def extend(self, line: str) -> "Rule":
        return dataclasses.replace(self, text=f"{self.text}\n{line}")


@dataclass(frozen=True, slots=True)
class RuleDocument:
    path: Path
    text: str
    rules: list[Rule]

    @classmethod
    def parse(cls, path: Path) -> "RuleDocument":
        text = path.read_text(encoding="utf-8")
        rules: list[Rule] = []
        section = ""
        subsection = ""
        inside_rule = False
        for line in text.splitlines():
            if line.startswith("## "):
                section = HEADING_QUALIFIER.sub("", line.removeprefix("## "))
                subsection = ""
                inside_rule = False
                continue
            if line.startswith("### "):
                subsection = line.removeprefix("### ")
                inside_rule = False
                continue
            title = RULE_TITLE.match(line)
            if title:
                category = f"{section} / {subsection}" if subsection else section
                name = title.group(1).rstrip(".")
                rules.append(
                    Rule(category=category, name=name.removeprefix(GATE_PREFIX), gate=name.startswith(GATE_PREFIX), text=line)
                )
                inside_rule = True
                continue
            if inside_rule:
                rules[-1] = rules[-1].extend(line)
        return cls(path=path, text=text, rules=rules)

    def tokens_estimated(self) -> int:
        return estimate_tokens(self.text)

    def share(self, tokens: int) -> float:
        return tokens / self.tokens_estimated()

    def rules_by_category(self) -> dict[str, list[Rule]]:
        categories: dict[str, list[Rule]] = {}
        for rule in self.rules:
            categories.setdefault(rule.category, []).append(rule)
        return categories


def estimate_tokens(text: str) -> int:
    return round(len(text.encode("utf-8")) / 4)


def draw_bar(value: int, maximum: int) -> str:
    return "█" * max(1, round(value / maximum * BAR_WIDTH))


if __name__ == "__main__":
    cast(io.TextIOWrapper, sys.stdout).reconfigure(encoding="utf-8", newline="\n")
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".claude" / "CLAUDE.md"
    document = RuleDocument.parse(path)
    categories = document.rules_by_category()
    category_tokens = {category: sum(rule.tokens_estimated() for rule in rules) for category, rules in categories.items()}
    rule_tokens_max = max(rule.tokens_estimated() for rule in document.rules)
    console = Console()

    console.print()
    console.print(
        f"[bold]{path.name}[/]   ~{document.tokens_estimated():,} tokens · {len(document.rules)} rules ({sum(rule.gate for rule in document.rules)} gates) · "
        f"{document.tokens_estimated() / CONTEXT_WINDOW_TOKENS:.1%} of a 200k window   [dim]tokens ≈ bytes / 4[/]"
    )

    summary = Table(title="[bold]By category[/]", title_justify="left", box=box.SIMPLE_HEAD)
    summary.add_column("Category")
    summary.add_column("Rules", justify="right")
    summary.add_column("Tokens", justify="right")
    summary.add_column("Share", justify="right")
    summary.add_column("", style="cyan", width=BAR_WIDTH)
    for category, rules in categories.items():
        tokens = category_tokens[category]
        summary.add_row(category, str(len(rules)), f"{tokens:,}", f"{document.share(tokens):.0%}", draw_bar(tokens, max(category_tokens.values())))
    console.print(summary)

    largest = Table(title=f"[bold]Largest {RULES_LARGEST_COUNT} rules[/]", title_justify="left", box=box.SIMPLE_HEAD)
    largest.add_column("#", justify="right", style="dim")
    largest.add_column("Gate", style="red", min_width=4)
    largest.add_column("Rule", width=max(RULE_NAME_WIDTH_MIN, min(RULE_NAME_WIDTH, console.width - CATEGORY_WIDTH - 40)), no_wrap=True, overflow="ellipsis")
    largest.add_column("Category", style="dim", width=CATEGORY_WIDTH, no_wrap=True, overflow="ellipsis")
    largest.add_column("Tokens", justify="right", min_width=6)
    largest.add_column("Share", justify="right", min_width=5)
    rules_largest = sorted(document.rules, key=Rule.tokens_estimated, reverse=True)[:RULES_LARGEST_COUNT]
    for position, rule in enumerate(rules_largest, start=1):
        largest.add_row(str(position), "gate" if rule.gate else "", rule.name, rule.category, f"{rule.tokens_estimated():,}", f"{document.share(rule.tokens_estimated()):.1%}")
    console.print(largest)

    for category, rules in categories.items():
        tokens = category_tokens[category]
        detail = Table(
            title=f"[bold]{category}[/]  [dim]{len(rules)} rules · ~{tokens:,} tokens · {document.share(tokens):.0%}[/]",
            title_justify="left",
            box=box.SIMPLE_HEAD,
        )
        detail.add_column("Gate", style="red")
        detail.add_column("Rule", width=max(RULE_NAME_WIDTH_MIN, min(RULE_NAME_WIDTH, console.width - BAR_WIDTH - 40)), no_wrap=True, overflow="ellipsis")
        detail.add_column("Tokens", justify="right")
        detail.add_column("Share", justify="right")
        detail.add_column("", style="cyan", width=BAR_WIDTH)
        for rule in sorted(rules, key=Rule.tokens_estimated, reverse=True):
            detail.add_row("gate" if rule.gate else "", rule.name, f"{rule.tokens_estimated():,}", f"{document.share(rule.tokens_estimated()):.1%}", draw_bar(rule.tokens_estimated(), rule_tokens_max))
        console.print(detail)
