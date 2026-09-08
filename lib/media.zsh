#!/bin/zsh

# Media and Music.app integration. All temporary media stays under
# MUSIC_INBOX_LOCAL_ROOT; request notes remain in the inbox hierarchy.

music_inbox_set_process_error() {
  MUSIC_INBOX_PROCESS_ERROR="$1"
  print -u2 -- "$1"
  return 1
}

music_inbox_safe_filename() {
  local value="$1" safe
  safe="$(print -r -- "$value" | tr -cs 'A-Za-z0-9._-' '_')"
  safe="${safe##_}"
  safe="${safe%%_}"
  [[ -n "$safe" ]] || safe='untitled'
  print -r -- "${safe[1,120]}"
}

music_inbox_yt_dlp_args() {
  local deno
  local -a args
  args=(--no-playlist)
  if [[ -n "$MUSIC_INBOX_BROWSER" ]]; then
    args+=(--cookies-from-browser "$MUSIC_INBOX_BROWSER")
  fi
  deno="$(music_inbox_find_tool deno 2>/dev/null || true)"
  [[ -n "$deno" ]] && args+=(--js-runtimes "deno:$deno")
  [[ -n "$MUSIC_INBOX_YTDLP_REMOTE_COMPONENTS" ]] && args+=(--remote-components "$MUSIC_INBOX_YTDLP_REMOTE_COMPONENTS")
  print -rl -- "${args[@]}"
}

music_inbox_read_video_metadata() {
  local yt_dlp="$1" metadata
  local -a yt_args
  yt_args=("${(@f)$(music_inbox_yt_dlp_args)}")
  metadata="$("$yt_dlp" "${yt_args[@]}" --simulate --print '%(id)s' --print '%(title)s' "$MUSIC_INBOX_REQUEST_URL")" || return 1
  MUSIC_INBOX_VIDEO_ID="${metadata%%$'\n'*}"
  MUSIC_INBOX_VIDEO_TITLE="${metadata#*$'\n'}"
  [[ "$MUSIC_INBOX_VIDEO_TITLE" != "$metadata" ]] || MUSIC_INBOX_VIDEO_TITLE='Untitled video'
  [[ -n "$MUSIC_INBOX_VIDEO_ID" ]] || return 1
}

music_inbox_playlist_preflight() {
  local playlist="$MUSIC_INBOX_REQUEST_PLAYLIST" response
  [[ -n "$playlist" ]] || return 0
  response="$(osascript -e '
on run argv
  set requestedPlaylist to item 1 of argv
  tell application "Music"
    set matchingPlaylists to (every user playlist whose name is requestedPlaylist)
    if (count of matchingPlaylists) > 0 then return "exists"
  end tell
  return "missing"
end run' -- "$playlist")" || return 1
  if [[ "$response" == missing && "$MUSIC_INBOX_REQUEST_CREATE_PLAYLIST" != yes ]]; then
    music_inbox_set_process_error "Playlist '$playlist' does not exist. Correct the name, or set create-playlist: yes."
    return 1
  fi
  return 0
}

music_inbox_import_into_music() {
  local mp3_path="$1" playlist="$MUSIC_INBOX_REQUEST_PLAYLIST" create="$MUSIC_INBOX_REQUEST_CREATE_PLAYLIST"
  osascript -e '
on run argv
  set sourceFile to POSIX file (item 1 of argv)
  set requestedPlaylist to item 2 of argv
  set mayCreate to item 3 of argv
  tell application "Music"
    set importedTracks to add sourceFile
    if requestedPlaylist is not "" then
      set matchingPlaylists to (every user playlist whose name is requestedPlaylist)
      if (count of matchingPlaylists) = 0 then
        if mayCreate is "yes" then
          set targetPlaylist to make new user playlist with properties {name:requestedPlaylist}
        else
          error "Playlist no longer exists: " & requestedPlaylist
        end if
      else
        set targetPlaylist to item 1 of matchingPlaylists
      end if
      if class of importedTracks is list then
        repeat with importedTrack in importedTracks
          duplicate importedTrack to targetPlaylist
        end repeat
      else
        duplicate importedTracks to targetPlaylist
      end if
    end if
  end tell
  return "imported"
end run' -- "$mp3_path" "$playlist" "$create" >/dev/null
}

music_inbox_stage_for_music() {
  local source_path="$1" staging_path base_name suffix=1
  [[ -r "$source_path" ]] || return 1
  mkdir -p "$MUSIC_INBOX_MUSIC_STAGING" || return 1
  base_name="${source_path:t}"
  staging_path="$MUSIC_INBOX_MUSIC_STAGING/$base_name"
  while [[ -e "$staging_path" ]]; do
    staging_path="$MUSIC_INBOX_MUSIC_STAGING/${base_name:r}-$suffix.${base_name:e}"
    (( suffix++ ))
  done
  cp -p "$source_path" "$staging_path" || return 1
  chmod 644 "$staging_path" 2>/dev/null || true
  print -r -- "$staging_path"
}

music_inbox_write_result_note() {
  local done_note="$1" destination
  destination="$(music_inbox_safe_note_destination "$MUSIC_INBOX_DONE" "${${done_note:t}%.*} — result.md")"
  {
    print '# Music Inbox completed'
    print
    print -r -- "- Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	  music_inbox_write_timing_summary
    print -r -- "- Title: $MUSIC_INBOX_VIDEO_TITLE"
    print -r -- "- Video ID: $MUSIC_INBOX_VIDEO_ID"
    print -r -- "- URL: $MUSIC_INBOX_REQUEST_URL"
    if [[ "$MUSIC_INBOX_REQUEST_IMPORT_TO_MUSIC" == yes ]]; then
      print -- '- Imported to Music: yes'
    else
      print -- '- Imported to Music: no (transcript-only request)'
    fi
    if [[ -n "$MUSIC_INBOX_REQUEST_PLAYLIST" ]]; then
      print -r -- "- Playlist: $MUSIC_INBOX_REQUEST_PLAYLIST"
    fi
    local output
    if (( ${#MUSIC_INBOX_TRANSCRIPT_OUTPUTS} )); then
      for output in "${MUSIC_INBOX_TRANSCRIPT_OUTPUTS[@]}"; do
        print -r -- "- Output file: ${output:t}"
      done
    fi
  } > "$destination"
}

music_inbox_run_whisper() {
  local whisper="$1" wav_path="$2" output_prefix="$3" task="$4" format flag
  local -a formats args
  formats=( ${(s:,:)${MUSIC_INBOX_REQUEST_FORMATS:-$MUSIC_INBOX_TRANSCRIPT_FORMATS}} )
  args=(-m "$MUSIC_INBOX_WHISPER_MODEL_PATH" -f "$wav_path" -of "$output_prefix")
  [[ -n "$MUSIC_INBOX_REQUEST_LANGUAGE" ]] && args+=(-l "$MUSIC_INBOX_REQUEST_LANGUAGE")
  [[ "$task" == translate ]] && args+=(-tr)
  for format in "${formats[@]}"; do
    case "$format" in
      txt) flag=-otxt ;;
      srt) flag=-osrt ;;
      vtt) flag=-ovtt ;;
    esac
    args+=("$flag")
  done
  "$whisper" "${args[@]}" || return 1
  for format in "${formats[@]}"; do
    [[ -r "$output_prefix.$format" ]] || return 1
    MUSIC_INBOX_TRANSCRIPT_OUTPUTS+=("$output_prefix.$format")
    MUSIC_INBOX_TRANSCRIPT_LABELS+=("$task")
  done
}

music_inbox_publish_transcript_outputs() {
  local request_note="$1" output label destination
  integer index
  mkdir -p "$MUSIC_INBOX_DONE"
  for (( index = 1; index <= ${#MUSIC_INBOX_TRANSCRIPT_OUTPUTS}; index++ )); do
    output="$MUSIC_INBOX_TRANSCRIPT_OUTPUTS[$index]"
    label="$MUSIC_INBOX_TRANSCRIPT_LABELS[$index]"
    destination="$(music_inbox_safe_note_destination "$MUSIC_INBOX_DONE" "${${request_note:t}%.*} — $label.${output:e}")"
    mv "$output" "$destination" || {
      music_inbox_set_process_error "Could not place the $label output in 4 Done. It remains at: $output"
      return 1
    }
    MUSIC_INBOX_TRANSCRIPT_OUTPUTS[$index]="$destination"
  done
}

music_inbox_handle_media() {
  local processing_note="$1" yt_dlp ffmpeg whisper mp3_path staging_path wav_path work_base
  MUSIC_INBOX_PROCESS_ERROR=''
  MUSIC_INBOX_TRANSCRIPT_OUTPUTS=()
  MUSIC_INBOX_TRANSCRIPT_LABELS=()
  yt_dlp="$(music_inbox_find_tool yt-dlp 2>/dev/null || true)"
  [[ -n "$yt_dlp" ]] || { music_inbox_set_process_error 'yt-dlp is not installed. Run: music-inbox doctor'; return 1; }
  ffmpeg="$(music_inbox_find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg" ]] || { music_inbox_set_process_error 'ffmpeg is not installed. Run: music-inbox doctor'; return 1; }

  if [[ "$MUSIC_INBOX_REQUEST_IMPORT_TO_MUSIC" == yes ]]; then
    music_inbox_timing_begin_stage 'Check Music playlist'
    if ! music_inbox_playlist_preflight; then
      [[ -n "$MUSIC_INBOX_PROCESS_ERROR" ]] || music_inbox_set_process_error 'Could not check playlists in Music. Open Music once and allow automation when macOS asks.'
      return 1
    fi
    music_inbox_timing_finish_stage
  fi
  music_inbox_timing_begin_stage 'Read video details'
  if ! music_inbox_read_video_metadata "$yt_dlp"; then
    music_inbox_set_process_error 'Could not read the video title and ID with yt-dlp.'
    return 1
  fi
  music_inbox_timing_finish_stage

  mkdir -p "$MUSIC_INBOX_MEDIA"
  work_base="$(music_inbox_safe_filename "$MUSIC_INBOX_VIDEO_TITLE")-$(music_inbox_safe_filename "$MUSIC_INBOX_VIDEO_ID")-$(music_inbox_request_hash)"
  mp3_path="$MUSIC_INBOX_MEDIA/$work_base.mp3"
  local -a yt_args
  yt_args=("${(@f)$(music_inbox_yt_dlp_args)}")
  music_inbox_timing_begin_stage 'Download and convert audio'
  if ! "$yt_dlp" "${yt_args[@]}" --extract-audio --audio-format mp3 --audio-quality 0 \
    --embed-metadata --embed-thumbnail --restrict-filenames --ffmpeg-location "${ffmpeg:h}" \
    --output "$MUSIC_INBOX_MEDIA/$work_base.%(ext)s" "$MUSIC_INBOX_REQUEST_URL"; then
    music_inbox_set_process_error 'yt-dlp could not download or convert this request. The temporary files were retained for inspection.'
    return 1
  fi
  music_inbox_timing_finish_stage
  [[ -r "$mp3_path" ]] || { music_inbox_set_process_error "Expected MP3 was not created: $mp3_path"; return 1; }
  if [[ "$MUSIC_INBOX_REQUEST_IMPORT_TO_MUSIC" == yes ]]; then
    music_inbox_timing_begin_stage 'Import into Apple Music'
    staging_path="$(music_inbox_stage_for_music "$mp3_path")" || {
      music_inbox_set_process_error "Could not prepare the Music import copy in: $MUSIC_INBOX_MUSIC_STAGING"
      return 1
    }
    if ! music_inbox_import_into_music "$staging_path"; then
      # The staging copy is deliberately retained for manual recovery. It is
      # byte-for-byte equivalent to the private working copy, so avoid holding
      # two potentially enormous MP3s after a failed import.
      rm -f -- "$mp3_path"
      music_inbox_set_process_error "Music could not import the MP3. The import copy was retained at: $staging_path"
      return 1
    fi
    rm -f -- "$staging_path"
    music_inbox_timing_finish_stage
  fi
  if [[ "$MUSIC_INBOX_REQUEST_TRANSCRIBE" == yes || "$MUSIC_INBOX_REQUEST_TRANSLATE" == yes ]]; then
    whisper="$(music_inbox_find_whisper 2>/dev/null || true)"
    [[ -n "$whisper" ]] || { music_inbox_set_process_error 'The local Whisper program is unavailable. Run: music-inbox install-transcription'; return 1; }
    wav_path="$MUSIC_INBOX_MEDIA/$work_base-whisper.wav"
    music_inbox_timing_begin_stage 'Prepare audio for transcription'
    if ! "$ffmpeg" -y -i "$mp3_path" -ar 16000 -ac 1 -c:a pcm_s16le "$wav_path"; then
      music_inbox_set_process_error 'ffmpeg could not prepare audio for transcription. The MP3 was retained locally.'
      return 1
    fi
    music_inbox_timing_finish_stage
    if [[ "$MUSIC_INBOX_REQUEST_TRANSCRIBE" == yes ]]; then
      music_inbox_timing_begin_stage 'Create transcript'
      if ! music_inbox_run_whisper "$whisper" "$wav_path" "$MUSIC_INBOX_MEDIA/$work_base-transcript" transcript; then
        music_inbox_set_process_error 'Whisper could not create the transcript. Temporary media was retained locally.'
        return 1
      fi
      music_inbox_timing_finish_stage
    fi
    [[ "$MUSIC_INBOX_REQUEST_TRANSLATE" == yes ]] && music_inbox_timing_begin_stage 'Create English translation'
    if [[ "$MUSIC_INBOX_REQUEST_TRANSLATE" == yes ]] && ! music_inbox_run_whisper "$whisper" "$wav_path" "$MUSIC_INBOX_MEDIA/$work_base-translation" translation; then
      music_inbox_set_process_error 'Whisper could not create the English translation. Temporary media was retained locally.'
      return 1
    fi
	  [[ "$MUSIC_INBOX_REQUEST_TRANSLATE" == yes ]] && music_inbox_timing_finish_stage
  fi
  if [[ "${MUSIC_INBOX_CLEANUP_AFTER_IMPORT:l}" == yes ]]; then
    rm -f -- "$mp3_path" "${wav_path:-}"
  fi
  return 0
}
