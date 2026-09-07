#!/bin/zsh

# Read a simple, human-editable request note. Only recognized `key: value`
# lines are interpreted; all other Markdown remains safe, explanatory text.

music_inbox_trim() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  print -r -- "$value"
}

music_inbox_reset_request() {
  MUSIC_INBOX_REQUEST_URL=''
  MUSIC_INBOX_REQUEST_PLAYLIST=''
  MUSIC_INBOX_REQUEST_CREATE_PLAYLIST=no
  MUSIC_INBOX_REQUEST_TRANSCRIBE=no
  MUSIC_INBOX_REQUEST_LANGUAGE=''
  MUSIC_INBOX_REQUEST_FORMATS=''
  MUSIC_INBOX_REQUEST_TRANSLATE=no
  MUSIC_INBOX_REQUEST_ERROR=''
}

music_inbox_parse_request() {
  local note="$1" line field value normalized
  typeset -A seen
  music_inbox_reset_request
  [[ -r "$note" ]] || { MUSIC_INBOX_REQUEST_ERROR="Cannot read request note: $note"; return 1; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *:* ]] || continue
    field="$(music_inbox_trim "${line%%:*}")"
    value="$(music_inbox_trim "${line#*:}")"
    normalized="${field:l}"
    case "$normalized" in
      url|playlist|create-playlist|transcribe|language|transcript-format|translate)
        if [[ -n "${seen[$normalized]:-}" ]]; then
          MUSIC_INBOX_REQUEST_ERROR="The '$normalized' field appears more than once."
          return 1
        fi
        seen[$normalized]=1
        ;;
      *) continue ;;
    esac
    case "$normalized" in
      url) MUSIC_INBOX_REQUEST_URL="$value" ;;
      playlist) MUSIC_INBOX_REQUEST_PLAYLIST="$value" ;;
      create-playlist) MUSIC_INBOX_REQUEST_CREATE_PLAYLIST="${value:l}" ;;
      transcribe) MUSIC_INBOX_REQUEST_TRANSCRIBE="${value:l}" ;;
      language) MUSIC_INBOX_REQUEST_LANGUAGE="${value:l}" ;;
      transcript-format) MUSIC_INBOX_REQUEST_FORMATS="${value:l}" ;;
      translate) MUSIC_INBOX_REQUEST_TRANSLATE="${value:l}" ;;
    esac
  done < "$note"

  music_inbox_validate_request
}

music_inbox_validate_request() {
  local format
  [[ -n "$MUSIC_INBOX_REQUEST_URL" ]] || { MUSIC_INBOX_REQUEST_ERROR="Missing required field: URL"; return 1; }
  [[ "$MUSIC_INBOX_REQUEST_URL" == http://* || "$MUSIC_INBOX_REQUEST_URL" == https://* ]] || {
    MUSIC_INBOX_REQUEST_ERROR="URL must begin with http:// or https://"
    return 1
  }
  for field in MUSIC_INBOX_REQUEST_TRANSCRIBE MUSIC_INBOX_REQUEST_TRANSLATE; do
    [[ "${(P)field}" == yes || "${(P)field}" == no ]] || {
      MUSIC_INBOX_REQUEST_ERROR="${field#MUSIC_INBOX_REQUEST_} must be yes or no."
      return 1
    }
  done
  if [[ -n "$MUSIC_INBOX_REQUEST_PLAYLIST" ]]; then
    [[ "$MUSIC_INBOX_REQUEST_CREATE_PLAYLIST" == yes || "$MUSIC_INBOX_REQUEST_CREATE_PLAYLIST" == no ]] || {
      MUSIC_INBOX_REQUEST_ERROR="create-playlist must be yes or no."
      return 1
    }
  else
    # The setting has no meaning without a playlist and is intentionally ignored.
    MUSIC_INBOX_REQUEST_CREATE_PLAYLIST=no
  fi
  if [[ -n "$MUSIC_INBOX_REQUEST_LANGUAGE" && ! "$MUSIC_INBOX_REQUEST_LANGUAGE" =~ '^[a-z]{2,3}(-[a-z]{2})?$' ]]; then
    MUSIC_INBOX_REQUEST_ERROR="language must be a short language tag such as en, ru, or pt-br."
    return 1
  fi
  if [[ -n "$MUSIC_INBOX_REQUEST_FORMATS" ]]; then
    for format in ${(s:,:)MUSIC_INBOX_REQUEST_FORMATS}; do
      [[ "$format" == txt || "$format" == srt || "$format" == vtt ]] || {
        MUSIC_INBOX_REQUEST_ERROR="transcript-format supports txt, srt, and vtt."
        return 1
      }
    done
  fi
  return 0
}

music_inbox_request_preflight() {
  if [[ "$MUSIC_INBOX_REQUEST_TRANSLATE" == yes ]]; then
    MUSIC_INBOX_REQUEST_ERROR="Translation is not available yet. Remove 'translate: yes' or wait for a future release."
    return 1
  fi
  if [[ "$MUSIC_INBOX_REQUEST_TRANSCRIBE" == yes ]]; then
    if ! MUSIC_INBOX_REQUEST_ERROR="$(music_inbox_transcription_problem)"; then
      return 1
    fi
  fi
  return 0
}
