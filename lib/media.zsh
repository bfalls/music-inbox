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

music_inbox_write_result_note() {
  local done_note="$1" destination
  destination="$(music_inbox_safe_note_destination "$MUSIC_INBOX_DONE" "${${done_note:t}%.*} — result.md")"
  {
    print '# Music Inbox completed'
    print
    print -r -- "- Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print -r -- "- Title: $MUSIC_INBOX_VIDEO_TITLE"
    print -r -- "- Video ID: $MUSIC_INBOX_VIDEO_ID"
    print -r -- "- URL: $MUSIC_INBOX_REQUEST_URL"
    if [[ -n "$MUSIC_INBOX_REQUEST_PLAYLIST" ]]; then
      print -r -- "- Playlist: $MUSIC_INBOX_REQUEST_PLAYLIST"
    fi
  } > "$destination"
}

music_inbox_handle_media() {
  local processing_note="$1" yt_dlp ffmpeg mp3_path work_base
  MUSIC_INBOX_PROCESS_ERROR=''
  yt_dlp="$(music_inbox_find_tool yt-dlp 2>/dev/null || true)"
  [[ -n "$yt_dlp" ]] || { music_inbox_set_process_error 'yt-dlp is not installed. Run: music-inbox doctor'; return 1; }
  ffmpeg="$(music_inbox_find_tool ffmpeg 2>/dev/null || true)"
  [[ -n "$ffmpeg" ]] || { music_inbox_set_process_error 'ffmpeg is not installed. Run: music-inbox doctor'; return 1; }

  if ! music_inbox_playlist_preflight; then
    [[ -n "$MUSIC_INBOX_PROCESS_ERROR" ]] || music_inbox_set_process_error 'Could not check playlists in Music. Open Music once and allow automation when macOS asks.'
    return 1
  fi
  if ! music_inbox_read_video_metadata "$yt_dlp"; then
    music_inbox_set_process_error 'Could not read the video title and ID with yt-dlp.'
    return 1
  fi

  mkdir -p "$MUSIC_INBOX_MEDIA"
  work_base="$(music_inbox_safe_filename "$MUSIC_INBOX_VIDEO_TITLE")-$(music_inbox_safe_filename "$MUSIC_INBOX_VIDEO_ID")-$(music_inbox_request_hash)"
  mp3_path="$MUSIC_INBOX_MEDIA/$work_base.mp3"
  local -a yt_args
  yt_args=("${(@f)$(music_inbox_yt_dlp_args)}")
  if ! "$yt_dlp" "${yt_args[@]}" --extract-audio --audio-format mp3 --audio-quality 0 \
    --embed-metadata --embed-thumbnail --restrict-filenames --ffmpeg-location "${ffmpeg:h}" \
    --output "$MUSIC_INBOX_MEDIA/$work_base.%(ext)s" "$MUSIC_INBOX_REQUEST_URL"; then
    music_inbox_set_process_error 'yt-dlp could not download or convert this request. The temporary files were retained for inspection.'
    return 1
  fi
  [[ -r "$mp3_path" ]] || { music_inbox_set_process_error "Expected MP3 was not created: $mp3_path"; return 1; }
  if ! music_inbox_import_into_music "$mp3_path"; then
    music_inbox_set_process_error 'Music could not import the MP3. The MP3 was retained locally; open Music and allow automation when macOS asks.'
    return 1
  fi
  if [[ "${MUSIC_INBOX_CLEANUP_AFTER_IMPORT:l}" == yes ]]; then
    rm -f -- "$mp3_path"
  fi
  return 0
}
