#!/bin/zsh

# This is the safe front half of every future processing run. The supplied
# handler receives a claimed note only after parsing, capability checks, and
# completed-request duplicate protection have all passed.

music_inbox_process_claimed_note() {
  local processing_note="$1" handler="$2" duplicate_message done_note
	music_inbox_timing_start
	music_inbox_timing_begin_stage 'Validate request'

  if ! music_inbox_parse_request "$processing_note"; then
    music_inbox_fail_note "$processing_note" "$MUSIC_INBOX_REQUEST_ERROR" >/dev/null
    return 1
  fi
  if ! music_inbox_request_preflight; then
    music_inbox_fail_note "$processing_note" "$MUSIC_INBOX_REQUEST_ERROR" >/dev/null
    return 1
  fi
  if duplicate_message="$(music_inbox_duplicate_problem)"; then
    music_inbox_fail_note "$processing_note" "$duplicate_message" >/dev/null
    return 1
  fi
	music_inbox_timing_finish_stage
  MUSIC_INBOX_TRANSCRIPT_OUTPUTS=()
  MUSIC_INBOX_TRANSCRIPT_LABELS=()
  if ! "$handler" "$processing_note"; then
    music_inbox_fail_note "$processing_note" "${MUSIC_INBOX_PROCESS_ERROR:-Media processing failed.}" >/dev/null
    return 1
  fi
  if (( ${#MUSIC_INBOX_TRANSCRIPT_OUTPUTS} )); then
    music_inbox_timing_begin_stage 'Publish transcript files'
    if ! music_inbox_publish_transcript_outputs "$processing_note"; then
      music_inbox_fail_note "$processing_note" "${MUSIC_INBOX_PROCESS_ERROR:-Could not publish transcript output.}" >/dev/null
      return 1
    fi
    music_inbox_timing_finish_stage
  fi
  music_inbox_mark_request_completed
  done_note="$(music_inbox_move_note "$processing_note" "$MUSIC_INBOX_DONE")" || return 1
  MUSIC_INBOX_DONE_NOTE="$done_note"
  music_inbox_write_result_note "$done_note" >/dev/null
  MUSIC_INBOX_COMPLETED_FILES=("$MUSIC_INBOX_DONE_NOTE" "$MUSIC_INBOX_RESULT_NOTE" "${MUSIC_INBOX_TRANSCRIPT_OUTPUTS[@]}")
  return 0
}

music_inbox_process_queued_note() {
  local queued_note="$1" handler="$2" processing_note
  processing_note="$(music_inbox_claim_note "$queued_note")" || return 1
  music_inbox_process_claimed_note "$processing_note" "$handler"
}

music_inbox_with_worker_lock() {
  local worker_exit_status=0
  if ! music_inbox_acquire_worker_lock; then
    print "Another Music Inbox worker is already active."
    return 0
  fi
  "$@" || worker_exit_status=$?
  music_inbox_release_worker_lock
  return "$worker_exit_status"
}
