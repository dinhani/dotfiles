import hashlib
import json
import locale
import math
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from enum import StrEnum
from pathlib import Path
from typing import Any

PROFILES = ("claude", "claude-2", "claude-3")
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
TOKEN_URL = "https://platform.claude.com/v1/oauth/token"
OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

ORANGE = "\033[38;2;217;119;87m"
YELLOW = "\033[38;2;229;192;123m"
RED    = "\033[38;2;224;108;117m"
GRAY   = "\033[90m"
RESET  = "\033[0m"


@dataclass(frozen=True)
class Profile:
    name: str

    @property
    def config_dir(self) -> Path | None:
        return None if self.name == PROFILES[0] else Path.home() / f".{self.name}"

    def find_email(self) -> str | None:
        config_file = (self.config_dir or Path.home()) / ".claude.json"
        if not config_file.exists():
            return None
        return json.loads(config_file.read_text(encoding="utf-8")).get("oauthAccount", {}).get("emailAddress")

    @property
    def keychain_service(self) -> str:
        service = "Claude Code-credentials"
        if self.config_dir:
            service += "-" + hashlib.sha256(str(self.config_dir).encode()).hexdigest()[:8]
        return service

    @property
    def credentials_file(self) -> Path:
        return (self.config_dir or Path.home() / ".claude") / ".credentials.json"

    def find_access_token(self) -> str | None:
        credentials = self.find_credentials()
        if credentials is None:
            return None
        oauth = credentials.get("claudeAiOauth")
        if not oauth:
            return None
        now_ms = time.time() * 1000
        if oauth.get("expiresAt", 0) > now_ms:
            return oauth["accessToken"]
        if not oauth.get("refreshToken") or oauth.get("refreshTokenExpiresAt", math.inf) <= now_ms:
            return None

        body = {"grant_type": "refresh_token", "refresh_token": oauth["refreshToken"], "client_id": OAUTH_CLIENT_ID, "scope": " ".join(oauth.get("scopes", []))}
        request = urllib.request.Request(TOKEN_URL, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "User-Agent": "claude-cli"})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                payload = json.load(response)
        except (urllib.error.URLError, TimeoutError):
            return None

        oauth_refreshed = {
            **oauth,
            "accessToken": payload["access_token"],
            "refreshToken": payload.get("refresh_token", oauth["refreshToken"]),
            "expiresAt": round(now_ms + payload["expires_in"] * 1000),
        }
        if "refresh_token_expires_in" in payload:
            oauth_refreshed["refreshTokenExpiresAt"] = round(now_ms + payload["refresh_token_expires_in"] * 1000)
        self.save_credentials({**credentials, "claudeAiOauth": oauth_refreshed})
        return oauth_refreshed["accessToken"]

    def find_credentials(self) -> dict[str, Any] | None:
        if sys.platform == "darwin":
            keychain = subprocess.run(["security", "find-generic-password", "-s", self.keychain_service, "-w"], capture_output=True, text=True)
            credentials_text = keychain.stdout if keychain.returncode == 0 else None
        else:
            credentials_text = self.credentials_file.read_text(encoding="utf-8") if self.credentials_file.exists() else None
        return json.loads(credentials_text) if credentials_text else None

    def save_credentials(self, credentials: dict[str, Any]) -> None:
        credentials_text = json.dumps(credentials, separators=(",", ":"))
        if sys.platform == "darwin":
            keychain = subprocess.run(["security", "find-generic-password", "-s", self.keychain_service], capture_output=True, text=True, check=True)
            account = re.search(r'"acct"<blob>="(.*)"', keychain.stdout).group(1)
            subprocess.run(["security", "add-generic-password", "-U", "-a", account, "-s", self.keychain_service, "-w", credentials_text], check=True)
            return

        credentials_temp = self.credentials_file.with_suffix(".tmp")
        credentials_temp.write_text(credentials_text, encoding="utf-8", newline="\n")
        credentials_temp.replace(self.credentials_file)


@dataclass(frozen=True)
class Limit:
    percent: int
    resets_at: datetime | None

    @classmethod
    def from_payload(cls, payload: dict) -> "Limit":
        resets_at = payload.get("resets_at")
        return cls(
            percent=min(max(round(payload.get("percent") or 0), 0), 100),
            resets_at=datetime.fromisoformat(resets_at) if resets_at else None,
        )

    def is_full(self) -> bool:
        return self.percent >= 100

    def to_reset_text(self) -> str:
        if self.resets_at is None:
            return "not started"
        resets_at_local = (self.resets_at + timedelta(seconds=30)).astimezone()
        pattern = "%H:%M" if resets_at_local.date() == date.today() else "%a %H:%M"
        return resets_at_local.strftime(pattern).replace(".", "")

    def to_cell(self, label: str, reset_text: str, reset_width: int) -> str:
        color = RED if self.percent >= 90 else YELLOW if self.percent >= 70 else ORANGE
        return f"{label} {color}{f'{self.percent}%':>4}{RESET}  {reset_text:<{reset_width}}"


@dataclass(frozen=True)
class Usage:
    session: Limit
    week: Limit

    @classmethod
    def from_payload(cls, payload: dict) -> "Usage":
        limits_by_kind = {limit["kind"]: limit for limit in payload.get("limits", [])}
        return cls(
            session=Limit.from_payload(limits_by_kind.get("session", {})),
            week=Limit.from_payload(limits_by_kind.get("weekly_all", {})),
        )

    def to_cells(self, session_reset_width: int) -> str:
        session_reset_text = "weekly limit reached" if self.week.is_full() else self.session.to_reset_text()
        session_cell = self.session.to_cell("session", session_reset_text, session_reset_width)
        week_cell = self.week.to_cell("week", self.week.to_reset_text(), len("not started"))
        return f"{session_cell} │ {week_cell}"


class Problem(StrEnum):
    NOT_LOGGED_IN     = "not logged in"
    TOKEN_EXPIRED     = "token expired"
    USAGE_UNAVAILABLE = "usage unavailable"


@dataclass(frozen=True)
class Account:
    profile: Profile
    email: str | None
    usage: Usage | Problem

    @classmethod
    def load(cls, profile: Profile) -> "Account":
        email = profile.find_email()
        if email is None:
            return cls(profile=profile, email=None, usage=Problem.NOT_LOGGED_IN)
        token = profile.find_access_token()
        if token is None:
            return cls(profile=profile, email=email, usage=Problem.TOKEN_EXPIRED)

        request = urllib.request.Request(USAGE_URL, headers={"Authorization": f"Bearer {token}", "anthropic-beta": "oauth-2025-04-20"})
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                payload = json.load(response)
        except (urllib.error.URLError, TimeoutError):
            return cls(profile=profile, email=email, usage=Problem.USAGE_UNAVAILABLE)
        return cls(profile=profile, email=email, usage=Usage.from_payload(payload))

    def is_week_full(self) -> bool:
        return isinstance(self.usage, Usage) and self.usage.week.is_full()

    def to_row(self, profile_width: int, email_width: int, session_reset_width: int, profile_last: str) -> str:
        usage_text = self.usage.to_cells(session_reset_width) if isinstance(self.usage, Usage) else self.usage.value
        marker = f" {ORANGE}● last{RESET}" if self.profile.name == profile_last else ""
        return f"{self.profile.name}\t{self.profile.name:<{profile_width}} │ {self.email or '':<{email_width}} │ {usage_text}{RESET}{marker}"


def main() -> None:
    locale.setlocale(locale.LC_TIME, "")
    state_dir = Path(os.environ["LOCALAPPDATA"]) if sys.platform == "win32" else Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    selection_file = state_dir / "claude-profile.txt"
    profile_last = selection_file.read_text(encoding="utf-8").strip() if selection_file.exists() else PROFILES[0]
    position = PROFILES.index(profile_last) + 1 if profile_last in PROFILES else 1

    sys.stderr.write(f"\033[2J\033[3J\033[H{GRAY}fetching usage…{RESET}")
    sys.stderr.flush()
    with ThreadPoolExecutor(max_workers=len(PROFILES)) as executor:
        accounts = list(executor.map(Account.load, [Profile(name) for name in PROFILES]))
    sys.stderr.write("\r\033[2K")
    sys.stderr.flush()

    profile_width = max(len(name) for name in PROFILES)
    email_width = max(len(account.email or "") for account in accounts)
    session_reset_width = len("weekly limit reached" if any(account.is_week_full() for account in accounts) else "not started")
    rows = [
        account.to_row(profile_width=profile_width, email_width=email_width, session_reset_width=session_reset_width, profile_last=profile_last)
        for account in accounts
    ]

    fzf = subprocess.run(
        [
            "fzf", "--ansi", "--delimiter", "\t", "--with-nth", "2",
            "--no-input", "--layout", "reverse", "--height", "~10", "--info", "hidden", "--no-scrollbar",
            "--pointer", "▌", "--highlight-line", "--header", "Select Claude profile:",
            "--color", "pointer:#d97757,current-bg:#2a2320,current-fg:white:bold,gutter:-1",
            "--bind", f"load:pos({position}),j:down,k:up,1:pos(1)+accept,2:pos(2)+accept,3:pos(3)+accept",
        ],
        input="\n".join(rows),
        stdout=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    if fzf.returncode != 0:
        sys.exit(1)

    profile_selected = Profile(fzf.stdout.split("\t")[0])
    selection_file.parent.mkdir(parents=True, exist_ok=True)
    selection_file.write_text(profile_selected.name + "\n", encoding="utf-8", newline="\n")
    print(profile_selected.config_dir or "")


if __name__ == "__main__":
    main()
