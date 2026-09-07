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
print "ok - configuration derives the folder hierarchy from one root"
