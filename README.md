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

## Setup

```bash
git clone https://github.com/OWNER/music-inbox.git
cd music-inbox
./install.sh
./bin/music-inbox doctor
```

The installer asks for the inbox root, browser-cookie preference, and whether to remove the temporary MP3 after a confirmed Music import. It stores the answers in `~/.config/music-inbox/config.env` with owner-only permissions.

## Dependencies

The worker will require `yt-dlp`, `ffmpeg`, `ffprobe`, and a JavaScript runtime such as Deno for YouTube challenge handling. `music-inbox doctor` detects common Homebrew and MacPorts locations.

Use one package manager consistently. The upcoming installer will prefer the package manager already installed on the Mac, and will ask before installing any dependencies.

## Development

```bash
zsh tests/test-config.zsh
```

Next milestones: a queue worker, Apple Music integration, launchd setup, and mocked end-to-end tests.
