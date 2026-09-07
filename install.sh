#!/bin/zsh
# Interactive local setup. It writes only user configuration and inbox folders.

set -euo pipefail

PROJECT_DIR="${0:A:h}"
CONFIG_DIR="$HOME/.config/music-inbox"
CONFIG_FILE="$CONFIG_DIR/config.env"
DEFAULT_ROOT="$HOME/Music Inbox"

prompt_with_default() {
  local prompt="$1" default="$2" answer
  print -n -- "$prompt [$default]: "
  read -r answer
  print -r -- "${answer:-$default}"
}

print "Music Inbox setup"
print "This creates a folder-based inbox and a private configuration file."

inbox_root="$(prompt_with_default 'Inbox root folder' "$DEFAULT_ROOT")"
cleanup="$(prompt_with_default 'Remove temporary MP3 after a confirmed Music import? (yes/no)' yes)"
browser="$(prompt_with_default 'Browser for yt-dlp cookies (leave blank for none)' brave)"

case "${cleanup:l}" in
  yes|no) ;;
  *) print -u2 "Please answer yes or no for cleanup."; exit 2 ;;
esac

mkdir -p "$CONFIG_DIR" "$inbox_root/1 Drafts" "$inbox_root/2 Queued" \
  "$inbox_root/3 Processing" "$inbox_root/4 Done" "$inbox_root/5 Failed" \
  "$inbox_root/media" "$inbox_root/.music-inbox"
umask 077
{
  print -r -- "MUSIC_INBOX_ROOT=$inbox_root"
  print -r -- "MUSIC_INBOX_CLEANUP_AFTER_IMPORT=$cleanup"
  print -r -- "MUSIC_INBOX_BROWSER=$browser"
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

print
print "Created: $CONFIG_FILE"
print "Inbox root: $inbox_root"
print "Run this next to check dependencies:"
print "  $PROJECT_DIR/bin/music-inbox doctor"
