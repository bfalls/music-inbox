# Contributing to music-inbox

Thanks for helping improve Music Inbox.

## Before opening a pull request

Run the relevant checks from the repository root:

```bash
zsh tests/test-config.zsh
zsh tests/test-request-and-queue.zsh
zsh tests/test-media-handler.zsh
zsh tests/test-launchd.zsh
zsh tests/test-ui.zsh
zsh tests/test-submit.zsh
```

Keep changes focused, update user-facing documentation when behavior changes, and avoid adding personal paths, browser cookies, downloaded media, local configuration, or generated models to commits.
