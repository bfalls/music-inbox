#!/bin/zsh

set -euo pipefail
export LC_ALL=C
PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/music-inbox-media-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/inbox/2 Queued" "$TEST_ROOT/mock-bin"
{
  print -r -- "MUSIC_INBOX_ROOT=$TEST_ROOT/inbox"
  print -r -- "MUSIC_INBOX_LOCAL_ROOT=$TEST_ROOT/local"
  print -r -- 'MUSIC_INBOX_BROWSER='
  print -r -- 'MUSIC_INBOX_CLEANUP_AFTER_IMPORT=yes'
} > "$TEST_ROOT/config/config.env"

{
  print '#!/bin/zsh'
  print 'if [[ " $* " == *" --simulate "* ]]; then'
  print '  print fake-video'
  print '  print "A / Video: Title"'
  print '  exit 0'
  print 'fi'
  print 'output=""'
  print 'while (( $# )); do'
  print '  if [[ "$1" == --output ]]; then shift; output="$1"; fi'
  print '  shift'
  print 'done'
  print 'mp3="$(print -r -- "$output" | sed "s/%(ext)s/mp3/")"'
  print 'mkdir -p "${mp3:h}"'
  print ': > "$mp3"'
} > "$TEST_ROOT/mock-bin/yt-dlp"
{
  print '#!/bin/zsh'
  print 'print exists'
} > "$TEST_ROOT/mock-bin/osascript"
{
  print '#!/bin/zsh'
  print 'exit 0'
} > "$TEST_ROOT/mock-bin/ffmpeg"
chmod 755 "$TEST_ROOT/mock-bin/yt-dlp" "$TEST_ROOT/mock-bin/osascript" "$TEST_ROOT/mock-bin/ffmpeg"

MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" source "$PROJECT_DIR/lib/music-inbox.zsh"
source "$PROJECT_DIR/lib/request.zsh"
source "$PROJECT_DIR/lib/queue.zsh"
source "$PROJECT_DIR/lib/media.zsh"
source "$PROJECT_DIR/lib/worker.zsh"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" music_inbox_load_config
PATH="$TEST_ROOT/mock-bin:$PATH"

note="$MUSIC_INBOX_QUEUED/Media Test.md"
{
  print 'URL: https://youtu.be/fake-video'
  print 'playlist: Coding Focus'
  print 'create-playlist: yes'
} > "$note"
music_inbox_with_worker_lock music_inbox_process_queued_note "$note" music_inbox_handle_media

[[ -f "$MUSIC_INBOX_DONE/Media Test.md" ]]
result_note="$MUSIC_INBOX_DONE/Media Test — result.md"
[[ -f "$result_note" ]]
rg -q 'Title: A / Video: Title' "$result_note"
[[ -z "$(find "$MUSIC_INBOX_MEDIA" -type f -name '*.mp3' -print -quit)" ]]
[[ "$(find "$MUSIC_INBOX_STATE/completed" -type f | wc -l | tr -d ' ')" == 1 ]]
print 'ok - downloads locally, imports through Music automation, records completion, and cleans the MP3 only after success'
