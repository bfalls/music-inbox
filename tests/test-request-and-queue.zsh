#!/bin/zsh

set -euo pipefail
export LC_ALL=C
PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/music-inbox-request-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config" "$TEST_ROOT/inbox/2 Queued"
print -r -- "MUSIC_INBOX_ROOT=$TEST_ROOT/inbox" > "$TEST_ROOT/config/config.env"
print -r -- "MUSIC_INBOX_LOCAL_ROOT=$TEST_ROOT/local" >> "$TEST_ROOT/config/config.env"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" source "$PROJECT_DIR/lib/music-inbox.zsh"
source "$PROJECT_DIR/lib/request.zsh"
source "$PROJECT_DIR/lib/queue.zsh"
source "$PROJECT_DIR/lib/worker.zsh"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" music_inbox_load_config

note="$MUSIC_INBOX_QUEUED/Podcast.md"
{
  print '# A harmless title'
  print 'URL: https://youtu.be/example'
  print 'playlist: Coding Focus'
  print 'create-playlist: no'
  print 'transcribe: no'
  print 'This ordinary Markdown line is ignored.'
} > "$note"
music_inbox_parse_request "$note"
[[ "$MUSIC_INBOX_REQUEST_URL" == 'https://youtu.be/example' ]]
[[ "$MUSIC_INBOX_REQUEST_PLAYLIST" == 'Coding Focus' ]]
[[ "$MUSIC_INBOX_REQUEST_CREATE_PLAYLIST" == no ]]
print 'ok - parses known fields and ignores ordinary Markdown'

no_playlist="$MUSIC_INBOX_QUEUED/No Playlist.md"
{
  print 'URL: https://youtu.be/no-playlist'
  print 'create-playlist: yes'
} > "$no_playlist"
music_inbox_parse_request "$no_playlist"
[[ "$MUSIC_INBOX_REQUEST_CREATE_PLAYLIST" == no ]]
print 'ok - ignores create-playlist without a playlist'

bad_note="$MUSIC_INBOX_QUEUED/Bad.md"
print 'playlist: Missing URL' > "$bad_note"
if music_inbox_parse_request "$bad_note"; then
  print -u2 'expected missing URL to fail'
  exit 1
fi
[[ "$MUSIC_INBOX_REQUEST_ERROR" == 'Missing required field: URL' ]]
print 'ok - rejects malformed requests before processing'

MUSIC_INBOX_REQUEST_TRANSCRIBE=yes
if music_inbox_request_preflight; then
  print -u2 'expected unavailable transcription to fail preflight'
  exit 1
fi
[[ "$MUSIC_INBOX_REQUEST_ERROR" == *'install-transcription'* ]]
print 'ok - checks requested capabilities before download'

ready_note="$MUSIC_INBOX_QUEUED/Ready.md"
print 'URL: https://youtu.be/ready' > "$ready_note"
test_handler() {
  [[ -f "$1" && "$1" == "$MUSIC_INBOX_PROCESSING"/* ]]
}
music_inbox_with_worker_lock music_inbox_process_queued_note "$ready_note" test_handler
[[ -f "$MUSIC_INBOX_PROCESSING/Ready.md" ]]
[[ ! -d "$MUSIC_INBOX_WORKER_LOCK" ]]
print 'ok - claims a valid request under a single-worker lock'

transcript_note="$MUSIC_INBOX_QUEUED/Needs Whisper.md"
{
  print 'URL: https://youtu.be/needs-whisper'
  print 'transcribe: yes'
} > "$transcript_note"
if music_inbox_with_worker_lock music_inbox_process_queued_note "$transcript_note" test_handler; then
  print -u2 'expected a missing transcription capability to fail the queue pipeline'
  exit 1
fi
[[ -f "$MUSIC_INBOX_FAILED/Needs Whisper.md" ]]
rg -q 'install-transcription' "$MUSIC_INBOX_FAILED/Needs Whisper — error.md"
print 'ok - fails unavailable capabilities before a handler can download media'

claimed="$(music_inbox_claim_note "$note")"
[[ -f "$claimed" && ! -e "$note" ]]
failed="$(music_inbox_fail_note "$claimed" 'Example failure for testing.')"
[[ -f "$failed" ]]
error_note="$MUSIC_INBOX_FAILED/Podcast — error.md"
[[ -f "$error_note" ]]
rg -q 'Example failure for testing.' "$error_note"
print 'ok - claims notes safely and writes a companion failure note'

MUSIC_INBOX_REQUEST_URL='https://youtu.be/completed'
MUSIC_INBOX_REQUEST_PLAYLIST='Coding Focus'
music_inbox_mark_request_completed
duplicate_message="$(music_inbox_duplicate_problem)"
[[ "$duplicate_message" == *'already completed'* ]]
print 'ok - records only completed requests as duplicates'
