# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

# Merges, reviews and checks a translated subtitle against its English source.

# ------------------------------------------------------------------------------
# Libraries
# ------------------------------------------------------------------------------
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass
from io import TextIOWrapper
from pathlib import Path
from typing import cast

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
TAG = re.compile(r"<[^>]+>|\{\\[^}]+\}")
LYRIC_MARK = re.compile("[♪♫]")
EUROPEAN_PORTUGUESE = re.compile(
    r"\btu\b|\b(?:estou|estás|está|estamos|estão|estava|estavam) a \w+r\b|\bfacto\b|\bequipa\b|\w+ámos\b",
    flags=re.IGNORECASE,
)

# ------------------------------------------------------------------------------
# Args
# ------------------------------------------------------------------------------
def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Merges, reviews and checks a translated subtitle against its English source.")
    commands = parser.add_subparsers(dest="command", required=True)

    merge_parser = commands.add_parser("merge", help="write the translated .srt from part files and the English numbers and timestamps")
    merge_parser.add_argument("english", type=Path)
    merge_parser.add_argument("output", type=Path)
    merge_parser.add_argument("parts", type=Path, nargs="+")
    merge_parser.add_argument("--allow-lines", type=int, nargs="+", default=[], metavar="ENTRY", help="entries whose line count may differ from the English")

    review_parser = commands.add_parser("review", help="write the English and translated lines of each entry next to each other")
    review_parser.add_argument("english", type=Path)
    review_parser.add_argument("translated", type=Path)
    review_parser.add_argument("output", type=Path)
    review_parser.add_argument("--first", type=int, default=0)
    review_parser.add_argument("--last", type=int, default=sys.maxsize)

    check_parser = commands.add_parser("check", help="check a written translation against the English")
    check_parser.add_argument("english", type=Path)
    check_parser.add_argument("translated", type=Path)
    check_parser.add_argument("--allow-lines", type=int, nargs="+", default=[], metavar="ENTRY", help="entries whose line count may differ from the English")

    return parser

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        cast(TextIOWrapper, stream).reconfigure(encoding="utf-8")
    arguments = create_parser().parse_args()

    match arguments.command:
        case "merge":
            merge(english_path=arguments.english, output_path=arguments.output, part_paths=arguments.parts, allowed_line_changes=set(arguments.allow_lines))
        case "review":
            review(english_path=arguments.english, translated_path=arguments.translated, output_path=arguments.output, first=arguments.first, last=arguments.last)
        case "check":
            check(english_path=arguments.english, translated_path=arguments.translated, allowed_line_changes=set(arguments.allow_lines))


def merge(english_path: Path, output_path: Path, part_paths: list[Path], allowed_line_changes: set[int]) -> None:
    english = Subtitle.from_file(english_path)

    lines_by_number: dict[int, tuple[str, ...]] = {}
    for path in part_paths:
        for block in split_blocks(path.read_text(encoding="utf-8-sig")):
            number = int(block[0])
            if number in lines_by_number:
                sys.exit(f"{path}: entry {number} is duplicated")
            lines_by_number[number] = tuple(block[1:])

    missing = [number for number in english.entries if number not in lines_by_number]
    extra = sorted(set(lines_by_number) - set(english.entries))
    if missing or extra:
        sys.exit(f"missing entries: {missing}\nextra entries: {extra}")

    translated = english.with_lines(lines_by_number)
    errors = translated.compare_structure(english=english, allowed_line_changes=allowed_line_changes)
    if errors:
        sys.exit("\n".join(errors))

    translated.write(output_path)
    for warning in translated.find_warnings(english):
        print(f"warning: {warning}")
    print(f"{len(translated.entries)} entries written to {output_path}")


def review(english_path: Path, translated_path: Path, output_path: Path, first: int, last: int) -> None:
    english = Subtitle.from_file(english_path)
    translated = Subtitle.from_file(translated_path)
    errors = translated.compare_timing(english)
    if errors:
        sys.exit("\n".join(errors))

    rows: list[str] = []
    for number, entry in english.entries.items():
        if not first <= number <= last:
            continue
        rows.append(f"{number} | " + " / ".join(entry.lines))
        rows.append("    = " + " / ".join(translated.entries[number].lines))

    output_path.write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(rows) // 2} entries written to {output_path}")


def check(english_path: Path, translated_path: Path, allowed_line_changes: set[int]) -> None:
    english = Subtitle.from_file(english_path)
    translated = Subtitle.from_file(translated_path)

    errors = translated.compare_structure(english=english, allowed_line_changes=allowed_line_changes)
    if b"\r" in translated_path.read_bytes():
        errors.insert(0, "CRLF line endings")
    warnings = translated.find_warnings(english)

    for warning in warnings:
        print(f"warning: {warning}")
    if errors:
        sys.exit("\n".join(errors))
    print(f"ok: {len(translated.entries)} entries, {len(warnings)} warnings")


@dataclass(frozen=True)
class Subtitle:
    entries: dict[int, Entry]

    @staticmethod
    def from_file(path: Path) -> Subtitle:
        entries: dict[int, Entry] = {}
        for block in split_blocks(path.read_text(encoding="utf-8-sig")):
            entry = Entry(number=int(block[0]), timestamp=block[1], lines=tuple(block[2:]))
            entries[entry.number] = entry
        return Subtitle(entries=entries)

    def with_lines(self, lines_by_number: dict[int, tuple[str, ...]]) -> Subtitle:
        return Subtitle(entries={number: Entry(number=number, timestamp=entry.timestamp, lines=lines_by_number[number]) for number, entry in self.entries.items()})

    def write(self, path: Path) -> None:
        blocks = [f"{entry.number}\n{entry.timestamp}\n" + "\n".join(entry.lines) for entry in self.entries.values()]
        path.write_text("\n\n".join(blocks) + "\n", encoding="utf-8", newline="\n")

    def compare_timing(self, english: Subtitle) -> list[str]:
        errors: list[str] = []
        missing = [number for number in english.entries if number not in self.entries]
        extra = [number for number in self.entries if number not in english.entries]
        if missing:
            errors.append(f"missing entries: {missing}")
        if extra:
            errors.append(f"extra entries: {extra}")
        for number, entry in self.entries.items():
            original = english.entries.get(number)
            if original is not None and original.timestamp != entry.timestamp:
                errors.append(f"{number}: timestamp {entry.timestamp!r}, English {original.timestamp!r}")
        return errors

    def compare_structure(self, english: Subtitle, allowed_line_changes: set[int]) -> list[str]:
        errors = self.compare_timing(english)
        for number, entry in self.entries.items():
            original = english.entries.get(number)
            if original is None:
                continue
            if number in allowed_line_changes:
                if Counter(TAG.findall(" ".join(original.lines))) != Counter(TAG.findall(" ".join(entry.lines))):
                    errors.append(f"{number}: tags differ: {original.lines} -> {entry.lines}")
                continue
            if len(original.lines) != len(entry.lines):
                errors.append(f"{number}: {len(original.lines)} English lines, {len(entry.lines)} translated lines: {original.lines} -> {entry.lines}")
                continue
            for english_line, line in zip(original.lines, entry.lines):
                if Counter(TAG.findall(english_line)) != Counter(TAG.findall(line)):
                    errors.append(f"{number}: tags differ: {english_line!r} -> {line!r}")
        return errors

    def find_warnings(self, english: Subtitle) -> list[str]:
        warnings: list[str] = []
        previous = ""
        for number, entry in self.entries.items():
            original = english.entries.get(number)
            if original is not None and len(original.lines) == len(entry.lines):
                for english_line, line in zip(original.lines, entry.lines):
                    sung = LYRIC_MARK.sub("", english_line).strip()
                    if LYRIC_MARK.search(english_line) and not sung.startswith(("[", "(")) and line != english_line:
                        warnings.append(f"{number}: lyric changed: {english_line!r} -> {line!r}")

            for line in entry.lines:
                for match in EUROPEAN_PORTUGUESE.finditer(line):
                    warnings.append(f"{number}: European Portuguese {match.group()!r}: {line}")

                plain = re.sub(r"\[[^\]]*\]|\([^)]*\)|<[^>]+>|\{\\[^}]+\}", "", line).strip()
                plain = re.sub(r"^[A-ZÀ-Ú][a-zà-ú]+(?: [A-Za-zÀ-ú#0-9]+)?: ", "", plain).lstrip('"- ')
                if not plain or LYRIC_MARK.search(plain):
                    continue
                ending = previous.rstrip('"')
                if ending and ending[-1] in ".!?" and not ending.endswith("...") and plain[0].islower():
                    warnings.append(f"{number}: lowercase start after a finished sentence: {line}")
                previous = plain
        return warnings


@dataclass(frozen=True)
class Entry:
    number: int
    timestamp: str
    lines: tuple[str, ...]


def split_blocks(text: str) -> list[list[str]]:
    normalized = text.replace("\r", "").strip()
    return [block.split("\n") for block in re.split(r"\n\s*\n", normalized) if block.strip()]

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    main()
