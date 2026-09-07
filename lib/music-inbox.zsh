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
  : "${MUSIC_INBOX_CLEANUP_AFTER_IMPORT:=yes}"
  : "${MUSIC_INBOX_BROWSER:=}"

  MUSIC_INBOX_DRAFTS="$MUSIC_INBOX_ROOT/1 Drafts"
  MUSIC_INBOX_QUEUED="$MUSIC_INBOX_ROOT/2 Queued"
  MUSIC_INBOX_PROCESSING="$MUSIC_INBOX_ROOT/3 Processing"
  MUSIC_INBOX_DONE="$MUSIC_INBOX_ROOT/4 Done"
  MUSIC_INBOX_FAILED="$MUSIC_INBOX_ROOT/5 Failed"
  MUSIC_INBOX_MEDIA="$MUSIC_INBOX_ROOT/media"
  MUSIC_INBOX_STATE="$MUSIC_INBOX_ROOT/.music-inbox"
  MUSIC_INBOX_LOG="$MUSIC_INBOX_STATE/music-inbox.log"
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
