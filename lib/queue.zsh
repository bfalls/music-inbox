#!/bin/zsh

# Queue operations keep state local and use directory creation as an atomic
# single-worker lock. Queue notes themselves may live in a synced folder.

music_inbox_acquire_worker_lock() {
  MUSIC_INBOX_WORKER_LOCK="$MUSIC_INBOX_STATE/worker.lock"
  mkdir -p "$MUSIC_INBOX_STATE"
  mkdir "$MUSIC_INBOX_WORKER_LOCK" 2>/dev/null
}

music_inbox_release_worker_lock() {
  [[ -n "${MUSIC_INBOX_WORKER_LOCK:-}" && -d "$MUSIC_INBOX_WORKER_LOCK" ]] && rmdir "$MUSIC_INBOX_WORKER_LOCK"
}

music_inbox_format_duration() {
  local total="${1:-0}"
  integer hours minutes seconds
  (( total < 0 )) && total=0
  hours=$(( total / 3600 ))
  minutes=$(( (total % 3600) / 60 ))
  seconds=$(( total % 60 ))
  if (( hours > 0 )); then
    print -r -- "${hours}h ${minutes}m ${seconds}s"
  elif (( minutes > 0 )); then
    print -r -- "${minutes}m ${seconds}s"
  else
    print -r -- "${seconds}s"
  fi
}

music_inbox_timing_start() {
  typeset -ga MUSIC_INBOX_TIMING_STAGES
  MUSIC_INBOX_TIMING_STARTED="$(date +%s)"
  MUSIC_INBOX_TIMING_ACTIVE_LABEL=''
  MUSIC_INBOX_TIMING_ACTIVE_STARTED=''
  MUSIC_INBOX_TIMING_STAGES=()
}

music_inbox_timing_finish_stage() {
  local finished elapsed
  [[ -n "${MUSIC_INBOX_TIMING_ACTIVE_LABEL:-}" ]] || return 0
  finished="$(date +%s)"
  elapsed=$(( finished - MUSIC_INBOX_TIMING_ACTIVE_STARTED ))
  MUSIC_INBOX_TIMING_STAGES+=("${MUSIC_INBOX_TIMING_ACTIVE_LABEL}"$'\t'"$elapsed")
  MUSIC_INBOX_TIMING_ACTIVE_LABEL=''
  MUSIC_INBOX_TIMING_ACTIVE_STARTED=''
}

music_inbox_timing_begin_stage() {
  music_inbox_timing_finish_stage
  MUSIC_INBOX_TIMING_ACTIVE_LABEL="$1"
  MUSIC_INBOX_TIMING_ACTIVE_STARTED="$(date +%s)"
}

music_inbox_write_timing_summary() {
  local finished total entry label elapsed
  [[ -n "${MUSIC_INBOX_TIMING_STARTED:-}" ]] || return 0
  finished="$(date +%s)"
  total=$(( finished - MUSIC_INBOX_TIMING_STARTED ))
  print -r -- "- Total time: $(music_inbox_format_duration "$total")"
  if (( ${#MUSIC_INBOX_TIMING_STAGES} )) || [[ -n "${MUSIC_INBOX_TIMING_ACTIVE_LABEL:-}" ]]; then
    print -- '- Step timings:'
    for entry in "${MUSIC_INBOX_TIMING_STAGES[@]}"; do
      label="${entry%%$'\t'*}"
      elapsed="${entry#*$'\t'}"
      print -r -- "  - $label: $(music_inbox_format_duration "$elapsed")"
    done
    if [[ -n "${MUSIC_INBOX_TIMING_ACTIVE_LABEL:-}" ]]; then
      elapsed=$(( finished - MUSIC_INBOX_TIMING_ACTIVE_STARTED ))
      print -r -- "  - $MUSIC_INBOX_TIMING_ACTIVE_LABEL: $(music_inbox_format_duration "$elapsed") (interrupted)"
    fi
  fi
}

music_inbox_safe_note_destination() {
  local directory="$1" source="$2" stem extension candidate number=1
  stem="${${source:t}%.*}"
  extension="${source:e}"
  candidate="$directory/${source:t}"
  while [[ -e "$candidate" ]]; do
    candidate="$directory/${stem} (${number}).${extension}"
    (( number++ ))
  done
  print -r -- "$candidate"
}

music_inbox_move_note() {
  local source="$1" directory="$2" destination
  [[ -f "$source" ]] || return 1
  mkdir -p "$directory"
  destination="$(music_inbox_safe_note_destination "$directory" "$source")"
  mv "$source" "$destination" || return 1
  print -r -- "$destination"
}

music_inbox_claim_note() {
  music_inbox_move_note "$1" "$MUSIC_INBOX_PROCESSING"
}

music_inbox_request_key() {
  print -r -- "url=$MUSIC_INBOX_REQUEST_URL"
  print -r -- "playlist=$MUSIC_INBOX_REQUEST_PLAYLIST"
}

music_inbox_request_hash() {
  local key
  key="$(music_inbox_request_key)"
  if command -v shasum >/dev/null 2>&1; then
    print -rn -- "$key" | shasum -a 256 | awk '{print $1}'
  else
    print -rn -- "$key" | openssl dgst -sha256 -r | awk '{print $1}'
  fi
}

music_inbox_duplicate_problem() {
  local hash
  hash="$(music_inbox_request_hash)"
  [[ -e "$MUSIC_INBOX_STATE/completed/$hash" ]] || return 1
  print "This URL has already completed for this playlist. Change the request or remove the completed-state entry deliberately."
  return 0
}

music_inbox_mark_request_completed() {
  local hash
  hash="$(music_inbox_request_hash)"
  mkdir -p "$MUSIC_INBOX_STATE/completed"
  print -r -- "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MUSIC_INBOX_STATE/completed/$hash"
}

music_inbox_write_error_note() {
  local failed_note="$1" message="$2" destination
  destination="$(music_inbox_safe_note_destination "$MUSIC_INBOX_FAILED" "${${failed_note:t}%.*} - error.md")"
  {
    print '# Music Inbox request could not run'
    print
    print "$message"
    print
	  music_inbox_write_timing_summary
	  print
    print 'Fix the issue, then move the original request note back to `2 Queued`.'
  } > "$destination"
  MUSIC_INBOX_ERROR_NOTE="$destination"
  print -r -- "$destination"
}

music_inbox_fail_note() {
  local processing_note="$1" message="$2" failed_note
  failed_note="$(music_inbox_move_note "$processing_note" "$MUSIC_INBOX_FAILED")" || return 1
  music_inbox_write_error_note "$failed_note" "$message" >/dev/null
  MUSIC_INBOX_FAILED_NOTE="$failed_note"
  print -r -- "$failed_note"
}
