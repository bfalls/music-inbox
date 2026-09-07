#!/bin/zsh

set -u

MUSIC_INBOX_CONFIG_DEFAULT="$HOME/.config/music-inbox/config.env"

music_inbox_load_config() {
  local config_file="${MUSIC_INBOX_CONFIG:-$MUSIC_INBOX_CONFIG_DEFAULT}"
  if [[ ! -r "$config_file" ]]; then
    print -u2 "Configuration not found: $config_file"
    print -u2 "Run: ./install.sh"
    return 1
  fi
  source "$config_file"
  : "${MUSIC_INBOX_ROOT:?MUSIC_INBOX_ROOT is required}"
  : "${MUSIC_INBOX_LOCAL_ROOT:=$HOME/Library/Application Support/music-inbox}"
  : "${MUSIC_INBOX_CLEANUP_AFTER_IMPORT:=yes}"
  : "${MUSIC_INBOX_BROWSER:=}"
  : "${MUSIC_INBOX_YTDLP_REMOTE_COMPONENTS:=ejs:github}"
  : "${MUSIC_INBOX_TEMPLATE_STYLE:=standard}"
  : "${MUSIC_INBOX_TRANSCRIPTION_ENABLED:=no}"
  : "${MUSIC_INBOX_WHISPER_MODEL:=base}"
  : "${MUSIC_INBOX_TRANSCRIPT_FORMATS:=txt}"

  MUSIC_INBOX_DRAFTS="$MUSIC_INBOX_ROOT/1 Drafts"
  MUSIC_INBOX_QUEUED="$MUSIC_INBOX_ROOT/2 Queued"
  MUSIC_INBOX_PROCESSING="$MUSIC_INBOX_ROOT/3 Processing"
  MUSIC_INBOX_DONE="$MUSIC_INBOX_ROOT/4 Done"
  MUSIC_INBOX_FAILED="$MUSIC_INBOX_ROOT/5 Failed"
  # Keep large, volatile, and machine-specific data outside a potentially
  # synced inbox (for example, an iCloud-backed Obsidian folder).
  MUSIC_INBOX_MEDIA="$MUSIC_INBOX_LOCAL_ROOT/media"
  MUSIC_INBOX_STATE="$MUSIC_INBOX_LOCAL_ROOT/state"
  MUSIC_INBOX_LOG="$MUSIC_INBOX_STATE/music-inbox.log"
  MUSIC_INBOX_MODEL_DIR="$MUSIC_INBOX_STATE/models"
  : "${MUSIC_INBOX_WHISPER_MODEL_PATH:=$MUSIC_INBOX_MODEL_DIR/ggml-${MUSIC_INBOX_WHISPER_MODEL}.bin}"
}

music_inbox_find_whisper() {
  local tool path
  for tool in whisper-cli whisper; do
    path="$(music_inbox_find_tool "$tool" 2>/dev/null || true)"
    [[ -n "$path" ]] && { print -r -- "$path"; return 0; }
  done
  # Older MacPorts releases install whisper.cpp's historical CLI as `main`.
  [[ -x /opt/local/bin/main ]] && { print -r -- /opt/local/bin/main; return 0; }
  return 1
}

music_inbox_disk_free_kib() {
  # POSIX df output on macOS reports free 1 KiB blocks in the fourth column.
  df -Pk "$1" 2>/dev/null | awk 'NR == 2 { print $4 }'
}

music_inbox_gpu_names() {
  command -v system_profiler >/dev/null 2>&1 || return 0
  system_profiler SPDisplaysDataType 2>/dev/null | \
    awk -F': ' '/(Chipset Model|Model):/ { print $2 }' | awk '!seen[$0]++'
}

music_inbox_acceleration_summary() {
  local architecture="$(uname -m)" gpu_names
  gpu_names="$(music_inbox_gpu_names)"
  print "Architecture: $architecture"
  if [[ -n "$gpu_names" ]]; then
    print "Graphics: ${(j:, :)${(f)gpu_names}}"
  else
    print "Graphics: unable to detect"
  fi
  if [[ "$architecture" == arm64 ]]; then
    print "Transcription acceleration: Apple Silicon detected; Metal acceleration is available when supported by the installed Whisper build."
  else
    print "Transcription acceleration: Intel Mac detected; performance depends on the installed Whisper build and graphics hardware."
  fi
}

music_inbox_transcription_problem() {
  if [[ "${MUSIC_INBOX_TRANSCRIPTION_ENABLED:l}" != yes ]]; then
    print "Transcription is not enabled. Run: music-inbox install-transcription"
    return 1
  fi
  if ! music_inbox_find_whisper >/dev/null 2>&1; then
    print "The local Whisper program is not installed. Run: music-inbox install-transcription"
    return 1
  fi
  if [[ ! -r "$MUSIC_INBOX_WHISPER_MODEL_PATH" ]]; then
    print "The Whisper model is missing: $MUSIC_INBOX_WHISPER_MODEL_PATH. Run: music-inbox install-transcription"
    return 1
  fi
  return 0
}

music_inbox_note_count() {
  find "$1" -maxdepth 1 -type f \( -iname '*.md' -o -iname '*.markdown' \) 2>/dev/null | wc -l | tr -d ' '
}

music_inbox_find_tool() {
  local tool="$1" candidate
  candidate="$(command -v "$tool" 2>/dev/null || true)"
  [[ -n "$candidate" ]] && { print -r -- "$candidate"; return 0; }
  for candidate in "/opt/homebrew/bin/$tool" "/usr/local/bin/$tool" "/opt/local/bin/$tool"; do
    [[ -x "$candidate" ]] && { print -r -- "$candidate"; return 0; }
  done
  return 1
}
