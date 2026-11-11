# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///

# Lists and claims the videos under a folder that are pending translation to Brazilian Portuguese.

# ------------------------------------------------------------------------------
# Libraries
# ------------------------------------------------------------------------------
from __future__ import annotations

import argparse
import json
import os
import random
import sys
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from io import TextIOWrapper
from pathlib import Path
from typing import cast

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".m4v"}
LOCK_EXPIRY = timedelta(minutes=60)


class Order(StrEnum):
    ASC = "asc"
    DESC = "desc"
    RANDOM = "random"

# ------------------------------------------------------------------------------
# Args
# ------------------------------------------------------------------------------
def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Lists and claims the videos under a folder that are pending translation to Brazilian Portuguese.")
    commands = parser.add_subparsers(dest="command", required=True)

    list_parser = commands.add_parser("list", help="print the pending videos that no other agent has locked")
    claim_parser = commands.add_parser("claim", help="lock the first pending video and print its path; print nothing when there is none")
    for command_parser in (list_parser, claim_parser):
        command_parser.add_argument("folder", type=Path, nargs="?", default=Path.cwd())
        command_parser.add_argument("--order", type=Order, choices=list(Order), default=Order.ASC, help="asc and desc sort by path; random shuffles")
    claim_parser.add_argument("--skip", type=Path, nargs="+", default=[], metavar="VIDEO", help="videos already handled in this run")

    return parser

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------
def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        cast(TextIOWrapper, stream).reconfigure(encoding="utf-8")
    arguments = create_parser().parse_args()

    videos = sorted(video for video in Video.find_all(arguments.folder) if video.pending() and not video.locked())

    match arguments.order:
        case Order.DESC:
            videos.reverse()
        case Order.RANDOM:
            random.shuffle(videos)

    match arguments.command:
        case "list":
            for video in videos:
                print(video.path)
        case "claim":
            skipped = {path.resolve() for path in arguments.skip}
            claimed = next((video for video in videos if video.path.resolve() not in skipped and video.claim()), None)
            if claimed is not None:
                print(claimed.path)


@dataclass(frozen=True, order=True)
class Video:
    path: Path

    @staticmethod
    def find_all(folder: Path) -> list[Video]:
        return [
            Video(path=path)
            for path in folder.rglob("*")
            if path.suffix.lower() in VIDEO_EXTENSIONS and not path.stem.lower().endswith("-sample") and path.is_file()
        ]

    @property
    def lock(self) -> Path:
        return self.path.parent / f"{self.path.stem}.pob.translated.claude.lock"

    def claim(self) -> bool:
        if self.locked():
            return False
        self.lock.unlink(missing_ok=True)

        try:
            with self.lock.open("x", encoding="utf-8", newline="\n") as file:
                account = os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude"))
                json.dump({"claimed_at": datetime.now(UTC).isoformat(), "account": account}, file)
                file.write("\n")
        except FileExistsError:
            return False

        if not self.pending():
            self.lock.unlink(missing_ok=True)
            return False
        return True

    def pending(self) -> bool:
        name = self.path.stem
        files = [
            path
            for folder in (self.path.parent, self.path.parent / "_subs")
            if folder.is_dir()
            for path in folder.iterdir()
            if path.name.startswith(f"{name}.")
        ]

        english = any(path.parent.name == "_subs" and path.name.endswith((".eng.srt", ".eng.sdh.srt")) for path in files)
        pob = any("pob" in tags and "claude" not in tags for tags in (path.name[len(name) :].split(".") for path in files))
        report = any(path.parent == self.path.parent and path.name.endswith(".claude.report.md") for path in files)

        return english and not pob and not report

    def locked(self) -> bool:
        try:
            claimed_at = datetime.fromtimestamp(self.lock.stat().st_mtime, tz=UTC)
        except FileNotFoundError:
            return False
        return datetime.now(UTC) - claimed_at < LOCK_EXPIRY

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    main()
