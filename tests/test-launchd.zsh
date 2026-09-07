#!/bin/zsh

set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/music-inbox-launchd-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config"
test_inbox="$TEST_ROOT/inbox & notes"
{
  print -r -- "MUSIC_INBOX_ROOT=${(q)test_inbox}"
  print -r -- "MUSIC_INBOX_LOCAL_ROOT=$TEST_ROOT/local"
} > "$TEST_ROOT/config/config.env"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" source "$PROJECT_DIR/lib/music-inbox.zsh"
source "$PROJECT_DIR/lib/launchd.zsh"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" music_inbox_load_config

plist="$TEST_ROOT/com.music-inbox.worker.plist"
music_inbox_write_launch_agent_plist "$plist"
plutil -lint "$plist" >/dev/null
rg -q '<string>/usr/local/bin/music-inbox</string>' "$plist"
rg -q 'inbox &amp; notes/2 Queued' "$plist"
rg -q "<string>$MUSIC_INBOX_LOG</string>" "$plist"
print 'ok - generates a valid user LaunchAgent plist with escaped paths'
