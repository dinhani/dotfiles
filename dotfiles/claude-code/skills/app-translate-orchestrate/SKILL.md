---
name: app-translate-orchestrate
description: Translate every pending movie or episode under a folder to Brazilian Portuguese, one subagent at a time, each running the app-translate skill. Use when asked to translate a queue, a batch, a collection, a season or all pending videos with Claude.
---

# app-translate-orchestrate

You orchestrate the translation of every pending video under a folder. You never translate yourself: each video is translated by a subagent that runs the `app-translate` skill.

## Hard gate: one subagent at a time

Never run two translation subagents at the same time. Start the next subagent only after the previous one has finished and you have read its result. Several subagents running together use up the tokens and none of them finishes. This gate has no exceptions: running two at once is a failed task.

## Folder

The folder is the path the user gives, or the current working directory when none is given. Search it recursively; the skill does not depend on any fixed library path.

## Pending videos

A video is a `.mkv`, `.mp4`, `.avi` or `.m4v` file. It is pending when all of these hold:

- its `_subs` folder has an English `.srt`: a file `<name>.*.eng.srt` or `<name>.*.eng.sdh.srt`;
- it has no `pob` subtitle, in any format, in `_subs` or next to the video, other than the `pob.claude` files;
- it has no `<name>.pob.claude.report.md` next to the video. The report is the last step of `app-translate`, so a video with the `.srt` but no report was interrupted and is pending again.

`<name>` is the video file name without its extension.

`pending.py`, in this skill folder, finds the pending videos. Run it with `UV_PROJECT_ENVIRONMENT="$LOCALAPPDATA/_dev/uv/envs/app-translate-orchestrate" uv run <skill folder>/pending.py <command>`:

- `pending.py claim <folder> --order <order> [--skip <video>...]`: locks the first pending video, skipping the given ones, and prints its path. Prints nothing when there is none.
- `pending.py list <folder> --order <order>`: prints every pending video, one path per line, without locking any.

## Order

The caller may pass an order: `asc`, `desc` or `random`. The default is `asc`.

- `asc`: path order, so the episodes of a show run in order and each one reads the `translation-decisions.md` the previous ones wrote.
- `desc`: reverse path order.
- `random`: a new shuffle each time the list is read.

When several orchestrators work on the same folder at the same time, give each one a different order so they reach the same videos later.

## Lock

`claim` creates `<name>.pob.claude.lock` next to the video, with the claim time and your config directory. Only one orchestrator can create it, and both commands leave out a locked video, so two orchestrators never translate the same video. A lock older than 60 minutes counts as abandoned, so a video whose orchestrator died is picked again. Delete the lock as soon as the subagent finishes, whatever its result.

## Usage limit

The status line saves the usage limits to `state/rate-limits.json` in your Claude config directory: `$CLAUDE_CONFIG_DIR` when it is set, otherwise `~/.claude`. Read the one for your own config directory, never another account's: `rate_limits.five_hour.used_percentage` and `rate_limits.seven_day.used_percentage`, from 0 to 100, with `resets_at` in Unix seconds. Read it fresh before each video. When the 5-hour window is at 85% or more, or the 7-day window at 97% or more, do not start the video: a translation started that close to the limit runs out before it finishes. When the file does not exist, go on without the check and say so in the report.

## Loop

1. Read the usage limits. At or above either limit, stop and report the window and its reset time.
2. Run `pending.py claim` with the order and, in `--skip`, the videos already handled in this run. With no video printed, report and stop.
3. Start one subagent for that video, with the prompt below.
4. Wait for it to finish. Do not poll it and do not start anything else meanwhile.
5. Delete the video's lock, then check that `<name>.pob.claude.report.md` now exists next to the video.
6. When the subagent stopped on a question, reported concerns or left no report, record its question or concerns for the final report and go on to the next video. Stop the loop only when the subagent itself failed (an error or a cut-off run), since that usually means the usage ran out.
7. Go back to step 1.

## Subagent prompt

Use the `general-purpose` agent type, with this prompt, filling in the video path:

```
You are a subagent. Do not spawn subagents: do the work yourself.

Translate the video `<video path>` with the app-translate skill: invoke it with the Skill tool and follow it to the end, including the review gate and the report.

You cannot ask the user anything. When something needs the user before you start translating, stop without translating and say what you would have asked. Once you start translating, never stop: settle every doubt with your best judgment, log it in the report's Concerns, and finish the translation, the review and the report.

When you finish, reply with: the output .srt path, the report path, the number of concerns, and any decision that departs from the skill. When you stop early, reply with why.
```

## Report

When the loop stops, give the user one line per video handled: the video, and its report path with the number of concerns, or why it stopped. Then give each question a subagent stopped on, as its own numbered callout. Then list the videos still pending, from `pending.py list`, if any.
