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

`<name>` is the video file name without its extension. Take the pending videos in path order, so the episodes of a show run in order and each one reads the `translation-decisions.md` the previous ones wrote.

## Usage limit

The status line saves the usage limits to `~/.claude/state/rate-limits.json`: `rate_limits.five_hour.used_percentage` and `rate_limits.seven_day.used_percentage`, from 0 to 100, with `resets_at` in Unix seconds. Read it fresh before each video. When the 5-hour window is at 85% or more, or the 7-day window at 97% or more, do not start the video: a translation started that close to the limit runs out before it finishes. When the file does not exist, go on without the check and say so in the report.

## Loop

1. Find the pending videos. With none, report and stop.
2. Read the usage limits. At or above either limit, stop and report the window and its reset time.
3. Start one subagent for the first pending video, with the prompt below.
4. Wait for it to finish. Do not poll it and do not start anything else meanwhile.
5. Check that `<name>.pob.claude.report.md` now exists next to the video.
6. When the subagent failed, stopped on a question or left no report, stop the loop and report: do not start the next video.
7. Otherwise go back to step 1.

## Subagent prompt

Use the `general-purpose` agent type, with this prompt, filling in the video path:

```
You are a subagent. Do not spawn subagents: do the work yourself.

Translate the video `<video path>` with the app-translate skill: invoke it with the Skill tool and follow it to the end, including the review gate and the report.

You cannot ask the user anything. When the skill requires asking the user, stop without translating and say what you would have asked.

When you finish, reply with: the output .srt path, the report path, the number of concerns, and any decision that departs from the skill. When you stop early, reply with why.
```

## Report

When the loop stops, give the user one line per video handled: the video, and its report path with the number of concerns, or why it stopped. Then list the videos still pending, if any.
