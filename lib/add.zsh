#!/bin/zsh

# Native macOS request composer. The AppKit form gathers friendly choices;
# submission still uses the same parser and preflight checks as a Markdown note.

MUSIC_INBOX_ADD_DIR="${${(%):-%N}:A:h}"
MUSIC_INBOX_ADD_APP="$MUSIC_INBOX_ADD_DIR/../Music Inbox Request.app"

music_inbox_add_osascript() {
  osascript "$@"
}

music_inbox_add_music_playlists() {
  music_inbox_add_osascript -e '
tell application "Music"
  set playlistNames to name of every user playlist
end tell
set AppleScript'"'"'s text item delimiters to linefeed
return playlistNames as text'
}

music_inbox_add_language_choices() {
  print -rl -- \
    'Auto-detect' \
    'Afrikaans - af' 'Albanian - sq' 'Amharic - am' 'Arabic - ar' 'Armenian - hy' \
    'Assamese - as' 'Azerbaijani - az' 'Bashkir - ba' 'Basque - eu' 'Belarusian - be' \
    'Bengali - bn' 'Bosnian - bs' 'Breton - br' 'Bulgarian - bg' 'Burmese - my' \
    'Cantonese - yue' 'Catalan - ca' 'Chinese - zh' 'Croatian - hr' 'Czech - cs' \
    'Danish - da' 'Dutch - nl' 'English - en' 'Esperanto - eo' 'Estonian - et' \
    'Faroese - fo' 'Finnish - fi' 'French - fr' 'Galician - gl' 'Georgian - ka' \
    'German - de' 'Greek - el' 'Gujarati - gu' 'Haitian Creole - ht' 'Hausa - ha' \
    'Hawaiian - haw' 'Hebrew - he' 'Hindi - hi' 'Hungarian - hu' 'Icelandic - is' \
    'Indonesian - id' 'Italian - it' 'Japanese - ja' 'Javanese - jw' 'Kannada - kn' \
    'Kazakh - kk' 'Khmer - km' 'Korean - ko' 'Lao - lo' 'Latin - la' 'Latvian - lv' \
    'Lingala - ln' 'Lithuanian - lt' 'Luxembourgish - lb' 'Macedonian - mk' 'Malagasy - mg' \
    'Malay - ms' 'Malayalam - ml' 'Maltese - mt' 'Maori - mi' 'Marathi - mr' \
    'Mongolian - mn' 'Nepali - ne' 'Norwegian - no' 'Nynorsk - nn' 'Occitan - oc' \
    'Pashto - ps' 'Persian - fa' 'Polish - pl' 'Portuguese - pt' 'Punjabi - pa' \
    'Romanian - ro' 'Russian - ru' 'Samoan - sm' 'Sanskrit - sa' 'Serbian - sr' \
    'Shona - sn' 'Sindhi - sd' 'Sinhala - si' 'Slovak - sk' 'Slovenian - sl' \
    'Somali - so' 'Spanish - es' 'Sundanese - su' 'Swahili - sw' 'Swedish - sv' \
    'Tagalog - tl' 'Tajik - tg' 'Tamil - ta' 'Tatar - tt' 'Telugu - te' \
    'Thai - th' 'Tibetan - bo' 'Turkish - tr' 'Turkmen - tk' 'Ukrainian - uk' \
    'Urdu - ur' 'Uzbek - uz' 'Vietnamese - vi' 'Welsh - cy' 'Yiddish - yi' 'Yoruba - yo'
}

music_inbox_submit_request() {
  local url="$1" mode="$2" playlist="${3:-}" create_playlist="${4:-no}" language="${5:-}" formats="${6:-}" destination_dir="${7:-$MUSIC_INBOX_QUEUED}"
  local temporary_note requested_name destination duplicate_message
  mkdir -p "$destination_dir"
  temporary_note="$(mktemp "$destination_dir/.music-inbox-request.XXXXXX")" || {
    print -u2 'Could not prepare a queued request note.'
    return 1
  }
  {
    print '# Music Inbox request'
    print
    print -r -- "URL: $url"
    case "$mode" in
      import)
        [[ -n "$playlist" ]] && print -r -- "playlist: $playlist"
        [[ -n "$playlist" && "$create_playlist" == yes ]] && print 'create-playlist: yes'
        ;;
      transcript)
        print 'import-to-music: no'
        print 'transcribe: yes'
        ;;
      translation)
        print 'import-to-music: no'
        print 'translate: yes'
        ;;
      both)
        print 'import-to-music: no'
        print 'transcribe: yes'
        print 'translate: yes'
        ;;
      *)
        rm -f -- "$temporary_note"
        print -u2 "Unknown request mode: $mode"
        return 2
        ;;
    esac
    [[ "$mode" != import && -n "$language" ]] && print -r -- "language: $language"
    [[ "$mode" != import && -n "$formats" ]] && print -r -- "transcript-format: $formats"
  } > "$temporary_note"

  if ! music_inbox_parse_request "$temporary_note"; then
    rm -f -- "$temporary_note"
    print -u2 "Request is invalid: $MUSIC_INBOX_REQUEST_ERROR"
    return 1
  fi
  if ! music_inbox_request_preflight; then
    rm -f -- "$temporary_note"
    print -u2 "Request cannot run: $MUSIC_INBOX_REQUEST_ERROR"
    return 1
  fi
  if duplicate_message="$(music_inbox_duplicate_problem)"; then
    rm -f -- "$temporary_note"
    print -u2 "Duplicate request: $duplicate_message"
    return 1
  fi
  requested_name="Music request $(date '+%Y-%m-%d %H%M%S').md"
  destination="$(music_inbox_safe_note_destination "$destination_dir" "$requested_name")"
  mv "$temporary_note" "$destination" || {
    rm -f -- "$temporary_note"
    print -u2 'Could not queue the request.'
    return 1
  }
  MUSIC_INBOX_SUBMITTED_NOTE="$destination"
  print -r -- "$destination"
}

music_inbox_add_request() {
  local clipboard_url transcription_available=no translation_available=no
  local form_result result_file url mode playlist create_playlist language formats playlists
  clipboard_url="$(pbpaste 2>/dev/null || true)"
  [[ "$clipboard_url" == http://* || "$clipboard_url" == https://* ]] || clipboard_url=''
  if music_inbox_transcription_problem >/dev/null 2>&1; then
    transcription_available=yes
    if [[ "$MUSIC_INBOX_WHISPER_MODEL" != *.en && "${MUSIC_INBOX_WHISPER_MODEL_PATH:t}" != *.en.bin ]]; then
      translation_available=yes
    fi
  fi
  playlists="$(music_inbox_add_music_playlists 2>/dev/null || true)"
  [[ -d "$MUSIC_INBOX_ADD_APP" ]] || {
    print -u2 'The Music Inbox request window is not installed. Run ./install.sh again.'
    return 1
  }
  local app_state_dir request_file
  app_state_dir="${MUSIC_INBOX_ADD_APP:h}/state"
  request_file="$app_state_dir/add-request.txt"
  result_file="$app_state_dir/add-result.txt"
  mkdir -p "$app_state_dir" || return 1
  umask 077
  {
    print -r -- "$clipboard_url"
    print -r -- "$transcription_available"
    print -r -- "$translation_available"
    print '__MUSIC_INBOX_LANGUAGES__'
    music_inbox_add_language_choices
    print '__MUSIC_INBOX_PLAYLISTS__'
    [[ -n "$playlists" ]] && print -r -- "$playlists"
  } > "$request_file"
  rm -f -- "$result_file"
  if ! open -W -n "$MUSIC_INBOX_ADD_APP"; then
    rm -f -- "$request_file" "$result_file"
    return 1
  fi
  [[ -s "$result_file" ]] || {
    rm -f -- "$request_file" "$result_file"
    return
  }
  form_result="$(<"$result_file")"
  rm -f -- "$request_file" "$result_file"
  IFS=$'\x1f' read -r url mode playlist create_playlist language formats <<< "$form_result"
  [[ "$language" == 'Auto-detect' ]] && language='' || language="${language##* - }"
  if [[ "$mode" == import ]]; then
    language=''
    formats=''
  fi
  if [[ "$create_playlist" == yes && -z "$(music_inbox_trim "$playlist")" ]]; then
    music_inbox_add_osascript -e 'display dialog "Enter a name for the new playlist." with title "Music Inbox" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1 || true
    return 1
  fi
  # Acquire the same lock as the background worker before creating the note.
  # This prevents either worker from claiming it first, and avoids leaving a
  # request stranded in Processing when another job is already underway.
  if ! music_inbox_acquire_worker_lock; then
    music_inbox_add_osascript -e 'display dialog "Music Inbox is already processing another request. Wait for it to finish, then try again." with title "Music Inbox" buttons {"OK"} default button "OK" with icon caution' >/dev/null 2>&1 || true
    return 1
  fi
  # Place a request made in the native window directly in Processing. That
  # reserves it for this foreground command instead of racing the watcher.
  if ! music_inbox_submit_request "$url" "$mode" "$playlist" "$create_playlist" "$language" "$formats" "$MUSIC_INBOX_PROCESSING" >/dev/null; then
    music_inbox_release_worker_lock
    music_inbox_add_osascript -e 'on run argv
display dialog (item 1 of argv) with title "Music Inbox could not queue this request" buttons {"OK"} default button "OK" with icon caution
end run' "${MUSIC_INBOX_REQUEST_ERROR:-Check the Terminal for details.}" >/dev/null 2>&1 || true
    return 1
  fi
  music_inbox_ui_heading 'Music Inbox processing request'
  music_inbox_ui_info "Request: $MUSIC_INBOX_SUBMITTED_NOTE"
  if ! music_inbox_process_claimed_note "$MUSIC_INBOX_SUBMITTED_NOTE" music_inbox_handle_media; then
    music_inbox_release_worker_lock
    music_inbox_ui_error 'Request failed'
    [[ -n "${MUSIC_INBOX_FAILED_NOTE:-}" ]] && music_inbox_ui_info "Request note: $MUSIC_INBOX_FAILED_NOTE"
    [[ -n "${MUSIC_INBOX_ERROR_NOTE:-}" ]] && music_inbox_ui_info "Error details: $MUSIC_INBOX_ERROR_NOTE"
    return 1
  fi
  music_inbox_release_worker_lock
  music_inbox_ui_heading 'Music Inbox completed'
  local completed_file
  for completed_file in "${MUSIC_INBOX_COMPLETED_FILES[@]}"; do
    music_inbox_ui_success "$completed_file"
  done
}
