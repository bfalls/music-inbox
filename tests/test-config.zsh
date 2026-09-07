#!/bin/zsh

set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/music-inbox-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config"
print -r -- "MUSIC_INBOX_ROOT=$TEST_ROOT/inbox" > "$TEST_ROOT/config/config.env"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" source "$PROJECT_DIR/lib/music-inbox.zsh"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" music_inbox_load_config

[[ "$MUSIC_INBOX_QUEUED" == "$TEST_ROOT/inbox/2 Queued" ]]
[[ "$MUSIC_INBOX_DONE" == "$TEST_ROOT/inbox/4 Done" ]]
[[ "$MUSIC_INBOX_LOCAL_ROOT" == "$HOME/Library/Application Support/music-inbox" ]]
[[ "$MUSIC_INBOX_WHISPER_MODEL_PATH" == "$HOME/Library/Application Support/music-inbox/state/models/ggml-base.bin" ]]
model_fixture="$TEST_ROOT/model.bin"
dd if=/dev/zero of="$model_fixture" bs=1536 count=1 2>/dev/null
[[ "$(music_inbox_human_file_size "$model_fixture")" == '1.5 KiB' ]]
MUSIC_INBOX_TRANSCRIPTION_ENABLED=no
if music_inbox_transcription_problem >/dev/null 2>&1; then
  print -u2 "expected disabled transcription to fail its preflight"
  exit 1
fi
print "ok - configuration derives the folder hierarchy from one root"
