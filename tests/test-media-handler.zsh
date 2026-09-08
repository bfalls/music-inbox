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
  print -r -- "MUSIC_INBOX_MUSIC_STAGING=$TEST_ROOT/music-staging"
  print -r -- 'MUSIC_INBOX_BROWSER='
  print -r -- 'MUSIC_INBOX_CLEANUP_AFTER_IMPORT=yes'
  print -r -- 'MUSIC_INBOX_TRANSCRIPTION_ENABLED=yes'
  print -r -- 'MUSIC_INBOX_WHISPER_MODEL=base'
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
  print '[[ -n "${OSA_LOG:-}" ]] && print -r -- "$*" >> "$OSA_LOG"'
  print '[[ "${OSA_FAIL_IMPORT:-}" == yes && " $* " == *" set importedTracks to add "* ]] && exit 1'
  print 'if [[ " $* " == *" every user playlist "* ]]; then print exists; fi'
} > "$TEST_ROOT/mock-bin/osascript"
{
  print '#!/bin/zsh'
  print 'output="${@: -1}"'
  print 'mkdir -p "${output:h}"'
  print ': > "$output"'
} > "$TEST_ROOT/mock-bin/ffmpeg"
{
  print '#!/bin/zsh'
  print '[[ "${1:-}" == --help ]] && { print "usage: whisper-cli -m FNAME [options]"; exit 0; }'
  print '[[ -n "${WHISPER_LOG:-}" ]] && print -r -- "$*" >> "$WHISPER_LOG"'
  print 'prefix=""; formats=()'
  print 'while (( $# )); do'
  print '  case "$1" in'
  print '    -of) shift; prefix="$1" ;;'
  print '    -otxt) formats+=(txt) ;;'
  print '    -osrt) formats+=(srt) ;;'
  print '    -ovtt) formats+=(vtt) ;;'
  print '  esac'
  print '  shift'
  print 'done'
  print '[[ -n "$prefix" ]] || exit 1'
  print 'for format in "${formats[@]}"; do : > "$prefix.$format"; done'
} > "$TEST_ROOT/mock-bin/whisper-cli"
chmod 755 "$TEST_ROOT/mock-bin/yt-dlp" "$TEST_ROOT/mock-bin/osascript" "$TEST_ROOT/mock-bin/ffmpeg" "$TEST_ROOT/mock-bin/whisper-cli"

MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" source "$PROJECT_DIR/lib/music-inbox.zsh"
source "$PROJECT_DIR/lib/request.zsh"
source "$PROJECT_DIR/lib/queue.zsh"
source "$PROJECT_DIR/lib/media.zsh"
source "$PROJECT_DIR/lib/worker.zsh"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" music_inbox_load_config
PATH="$TEST_ROOT/mock-bin:$PATH"
mkdir -p "$MUSIC_INBOX_MODEL_DIR"
: > "$MUSIC_INBOX_WHISPER_MODEL_PATH"

note="$MUSIC_INBOX_QUEUED/Media Test.md"
{
  print 'URL: https://youtu.be/fake-video'
  print 'playlist: Coding Focus'
  print 'create-playlist: yes'
} > "$note"
music_inbox_with_worker_lock music_inbox_process_queued_note "$note" music_inbox_handle_media

[[ -f "$MUSIC_INBOX_DONE/Media Test.md" ]]
result_note="$MUSIC_INBOX_DONE/Media Test - result.md"
[[ -f "$result_note" ]]
rg -q 'Title: A / Video: Title' "$result_note"
rg -q '^\- Total time: ' "$result_note"
rg -q '^\- Step timings:$' "$result_note"
rg -q 'Download and convert audio:' "$result_note"
[[ -z "$(find "$MUSIC_INBOX_MEDIA" -type f -name '*.mp3' -print -quit)" ]]
[[ -z "$(find "$MUSIC_INBOX_MUSIC_STAGING" -type f -name '*.mp3' -print -quit)" ]]
[[ "$(find "$MUSIC_INBOX_STATE/completed" -type f | wc -l | tr -d ' ')" == 1 ]]
print 'ok - downloads locally, imports through Music automation, records completion, and cleans the MP3 only after success'

failed_import_note="$MUSIC_INBOX_QUEUED/Failed Import.md"
print 'URL: https://youtu.be/failed-import' > "$failed_import_note"
if OSA_FAIL_IMPORT=yes music_inbox_with_worker_lock music_inbox_process_queued_note "$failed_import_note" music_inbox_handle_media; then
  print -u2 'expected Music import failure'
  exit 1
fi
[[ -f "$MUSIC_INBOX_FAILED/Failed Import.md" ]]
rg -q 'import copy was retained at:' "$MUSIC_INBOX_FAILED/Failed Import - error.md"
rg -q '^\- Total time: ' "$MUSIC_INBOX_FAILED/Failed Import - error.md"
rg -q 'Import into Apple Music: .*\(interrupted\)' "$MUSIC_INBOX_FAILED/Failed Import - error.md"
retained_staging_mp3="$(find "$MUSIC_INBOX_MUSIC_STAGING" -type f -name '*.mp3' -print -quit)"
retained_local_mp3="$(find "$MUSIC_INBOX_MEDIA" -type f -name '*.mp3' -print -quit)"
[[ -n "$retained_staging_mp3" && -z "$retained_local_mp3" ]]
print 'ok - retains only the Music-visible import copy after an import failure'
rm -f -- "$retained_staging_mp3"

: > "$TEST_ROOT/osascript.log"
whisper_log="$TEST_ROOT/whisper.log"
transcript_note="$MUSIC_INBOX_QUEUED/Transcript Only.md"
{
  print 'URL: https://youtu.be/transcript-only'
  print 'import-to-music: no'
  print 'transcribe: yes'
  print 'translate: yes'
  print 'transcript-format: txt,srt'
} > "$transcript_note"
OSA_LOG="$TEST_ROOT/osascript.log" WHISPER_LOG="$whisper_log" music_inbox_with_worker_lock music_inbox_process_queued_note "$transcript_note" music_inbox_handle_media

[[ -f "$MUSIC_INBOX_DONE/Transcript Only.md" ]]
[[ -f "$MUSIC_INBOX_DONE/Transcript Only - transcript.txt" ]]
[[ -f "$MUSIC_INBOX_DONE/Transcript Only - transcript.srt" ]]
[[ -f "$MUSIC_INBOX_DONE/Transcript Only - translation.txt" ]]
[[ -f "$MUSIC_INBOX_DONE/Transcript Only - translation.srt" ]]
[[ ! -s "$TEST_ROOT/osascript.log" ]]
rg -q -- '-tr' "$whisper_log"
transcript_result="$MUSIC_INBOX_DONE/Transcript Only - result.md"
rg -q 'Imported to Music: no' "$transcript_result"
rg -Fq '[Transcript Only - transcript.txt](<Transcript Only - transcript.txt>)' "$transcript_result"
rg -Fq "Path: \`$MUSIC_INBOX_DONE/Transcript Only - transcript.txt\`" "$transcript_result"
[[ "$MUSIC_INBOX_RESULT_NOTE" == "$transcript_result" ]]
[[ " ${(j: :)MUSIC_INBOX_COMPLETED_FILES} " == *" $MUSIC_INBOX_DONE/Transcript Only - transcript.txt "* ]]
[[ -z "$(find "$MUSIC_INBOX_MEDIA" -type f -print -quit)" ]]
print 'ok - creates transcript-only outputs without calling Music automation and cleans local working audio'
