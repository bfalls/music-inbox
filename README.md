# music-inbox

A macOS folder-to-Music automation: place a URL request in a queue, download and tag its audio with yt-dlp, then import it into Apple Music.

## Status

This repository is the portable foundation for Music Inbox. It intentionally contains no browser cookies, media, personal paths, request history, or user configuration.

The initial setup creates this folder hierarchy from one chosen root:

```text
1 Drafts/
2 Queued/
3 Processing/
4 Done/
5 Failed/
```

That root may be synced—for example, an Obsidian vault in iCloud—because it contains the small, user-facing request notes and completed results. Music Inbox separately stores all machine-only data in a local folder.

## Setup

```bash
git clone https://github.com/OWNER/music-inbox.git
cd music-inbox
./install.sh
./bin/music-inbox doctor
```

The installer asks for the inbox root, a **local-only** data folder, browser-cookie preference, whether to remove the temporary MP3 after a confirmed Music import, and whether to enable optional local transcription. It stores the answers in `~/.config/music-inbox/config.env` with owner-only permissions and keeps its installed program files in `~/Library/Application Support/music-inbox`.

The installer places the `music-inbox` command in `/usr/local/bin` and registers that standard macOS command location in `/etc/paths.d`. Immediately before requesting an administrator password, it explains that permission is used only for those two shared system locations; the worker, notes, media, and models continue to run as your user. No shell-profile edits, reboot, or manual PATH setup are needed for a normal macOS Terminal shell.

The default local-only folder is `~/Library/Application Support/music-inbox`. Do not place it in iCloud Drive, Dropbox, OneDrive, an Obsidian vault, or another sync service. It holds downloaded media, partial downloads, language models, logs, locks, and duplicate-processing state. The installer warns when the chosen path looks synced.

Setup creates `1 Drafts/Default Music Request.md`. On an upgrade, an unchanged template updates automatically. A customized or unknown template is preserved and the new shipped version is added as `Default Music Request v<N>.md`. Duplicate the template you prefer, replace its example URL, uncomment the optional fields you want, and move the duplicate to `2 Queued`.

## Dependencies

The worker requires `yt-dlp`, `ffmpeg`, `ffprobe`, and a JavaScript runtime such as Deno for YouTube challenge handling. By default it lets yt-dlp obtain its EJS challenge component from GitHub; this advanced option can be disabled in the local configuration. `music-inbox doctor` detects common Homebrew and MacPorts locations. The installer reports missing tools and asks before installing them.

Use one package manager consistently. The installer uses a package manager already present on the Mac; when both Homebrew and MacPorts are available, it asks which one to use. It never installs a package manager itself.

## Local transcription

Music Inbox uses the local [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) backend for optional, offline transcription. It does not use the larger Python Whisper environment.

Enable it during initial setup, or later run:

```bash
music-inbox install-transcription
```

The setup checks for Homebrew's `whisper-cpp` or MacPorts' `whisper` package, asks before installing it, then asks before downloading the selected speech model. It shows the model's approximate download size, free disk space, and a recommended amount of working space. Models are stored locally at `~/Library/Application Support/music-inbox/state/models/` by default, never in the synced inbox root.

Choose a multilingual model such as `base` if you want Russian or another non-English language. English-only models have a `.en` suffix, such as `base.en`. `base` is the default because it supports multiple languages without further setup.

Queue-note options will be:

```md
URL: https://youtu.be/example
transcribe: yes
language: ru
transcript-format: txt,srt
```

`language:` is optional; when omitted, Whisper detects the spoken language. The worker will validate these requests before downloading video or audio. If local transcription, its executable, or its model is unavailable, it will move the request to `5 Failed` and write a companion error note with the exact recovery command. Transcript generation will happen before temporary audio is removed. The resulting transcript is a deliberate user-facing result and will sit with the completed request note, so it may sync with the inbox root.

Speech translation into English is planned as a later, separate option. Arbitrary target-language translation is not part of this local Whisper backend.

## Request notes

Only recognized `key: value` lines are processed; the rest of the Markdown note is yours to use. Validate a note without changing it:

```bash
music-inbox validate "/path/to/2 Queued/My request.md"
```

Supported request fields so far are `URL` (required), `playlist`, `create-playlist`, `transcribe`, `language`, `transcript-format`, and `translate`. `create-playlist` defaults to `no` and is ignored when `playlist` is absent. `translate: yes` produces an early explanatory failure until that future feature exists.

Before any media download, the queue pipeline parses the note, verifies local capabilities such as transcription, and checks the completed-request ledger. It atomically claims a note by moving it from `2 Queued` to `3 Processing`; malformed, unsupported, or duplicate requests move to `5 Failed` with a companion `— error.md` note. Failed requests are deliberately **not** counted as duplicates.

## Process queued requests

Run one safe queue pass manually with:

```bash
music-inbox process
```

Each request is checked before download. If a playlist is named, Music Inbox verifies it exists before downloading; `create-playlist: yes` permits the later import step to create a missing playlist. Audio is downloaded to the local-only data directory using a filesystem-safe video-title-and-ID name, imported into Music, and only then removed when cleanup is enabled. A successful request moves to `4 Done` with a companion result note and a completed-request record.

## Development

```bash
zsh tests/test-config.zsh
zsh tests/test-request-and-queue.zsh
zsh tests/test-media-handler.zsh
```

Next milestones: queue-worker media processing, Apple Music integration, launchd setup, transcription execution, and mocked end-to-end tests.
