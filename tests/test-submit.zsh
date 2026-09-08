#!/bin/zsh

set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/music-inbox-submit-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/config"
{
  print -r -- "MUSIC_INBOX_ROOT=$TEST_ROOT/inbox"
  print -r -- "MUSIC_INBOX_LOCAL_ROOT=$TEST_ROOT/local"
} > "$TEST_ROOT/config/config.env"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" source "$PROJECT_DIR/lib/music-inbox.zsh"
source "$PROJECT_DIR/lib/request.zsh"
source "$PROJECT_DIR/lib/queue.zsh"
source "$PROJECT_DIR/lib/add.zsh"
MUSIC_INBOX_CONFIG="$TEST_ROOT/config/config.env" music_inbox_load_config

osacompile -o "$TEST_ROOT/Music Inbox Request.app" "$PROJECT_DIR/lib/add.applescript"
[[ -x "$TEST_ROOT/Music Inbox Request.app/Contents/MacOS/applet" ]]
print 'ok - builds the native request applet'

[[ "$(music_inbox_add_language_choices)" == *'Russian — ru'* ]]
print 'ok - offers a native pop-up list of Whisper language choices'

# The native dialog uses a non-whitespace separator so its empty Library-only
# playlist value does not shift the later fields while the shell reads them.
library_only_result=$'https://youtu.be/library-only\x1fimport\x1f\x1fno\x1fAuto-detect\x1ftxt'
IFS=$'\x1f' read -r result_url result_mode result_playlist result_create result_language result_formats <<< "$library_only_result"
[[ "$result_url" == 'https://youtu.be/library-only' && "$result_mode" == import ]]
[[ -z "$result_playlist" && "$result_create" == no ]]
[[ "$result_language" == 'Auto-detect' && "$result_formats" == txt ]]
print 'ok - preserves an empty Library-only playlist from the native dialog'

queued_note="$(music_inbox_submit_request 'https://youtu.be/submit-test' import 'Coding Focus' yes)"
[[ -f "$queued_note" && "$queued_note" == "$MUSIC_INBOX_QUEUED"/*.md ]]
rg -q '^URL: https://youtu.be/submit-test$' "$queued_note"
rg -q '^playlist: Coding Focus$' "$queued_note"
rg -q '^create-playlist: yes$' "$queued_note"
! rg -q '^language:' "$queued_note"
! rg -q '^transcript-format:' "$queued_note"
[[ -z "$(find "$MUSIC_INBOX_QUEUED" -maxdepth 1 -name '.music-inbox-request.*' -print -quit)" ]]
print 'ok - submits a clean Apple Music request through an atomic queued-note rename'

# The dialog layer is intentionally separate from queue writing. Stub the
# capability check so this test can exercise a translation request without a
# local Whisper installation.
music_inbox_request_preflight() { return 0; }
translation_note="$(music_inbox_submit_request 'https://youtu.be/translation-test' translation '' no ru txt,srt)"
rg -q '^import-to-music: no$' "$translation_note"
rg -q '^translate: yes$' "$translation_note"
rg -q '^language: ru$' "$translation_note"
rg -q '^transcript-format: txt,srt$' "$translation_note"
print 'ok - submits transcript options without involving Apple Music'
