#!/bin/zsh

# This is the safe front half of every future processing run. The supplied
# handler receives a claimed note only after parsing, capability checks, and
# completed-request duplicate protection have all passed.

music_inbox_process_queued_note() {
  local queued_note="$1" handler="$2" processing_note duplicate_message
  processing_note="$(music_inbox_claim_note "$queued_note")" || return 1

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
  "$handler" "$processing_note"
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
