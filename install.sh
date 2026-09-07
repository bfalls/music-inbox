#!/bin/zsh
# Interactive local setup. It writes only user configuration, inbox folders,
# and a user-local copy of the CLI. It never installs packages without asking.

set -euo pipefail

PROJECT_DIR="${0:A:h}"
CONFIG_DIR="$HOME/.config/music-inbox"
CONFIG_FILE="$CONFIG_DIR/config.env"
APP_DIR="$HOME/.local/share/music-inbox"
BIN_DIR="$HOME/.local/bin"
DEFAULT_ROOT="$HOME/Music Inbox"

source "$PROJECT_DIR/lib/music-inbox.zsh"

prompt_with_default() {
  local prompt="$1" default="$2" answer
  print -nu2 -- "$prompt [$default]: "
  read -r answer
  print -r -- "${answer:-$default}"
}

confirm() {
  local prompt="$1" answer
  print -nu2 -- "$prompt [y/N]: "
  read -r answer
  [[ "${answer:l}" == y || "${answer:l}" == yes ]]
}

existing_root="$DEFAULT_ROOT"
existing_cleanup=yes
existing_browser=brave
if [[ -r "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  existing_root="${MUSIC_INBOX_ROOT:-$existing_root}"
  existing_cleanup="${MUSIC_INBOX_CLEANUP_AFTER_IMPORT:-$existing_cleanup}"
  existing_browser="${MUSIC_INBOX_BROWSER:-$existing_browser}"
fi

print "Music Inbox setup"
print "Architecture: $(uname -m)"
print "This creates a folder-based inbox and a private configuration file."
print

inbox_root="$(prompt_with_default 'Inbox root folder' "$existing_root")"
cleanup="$(prompt_with_default 'Remove temporary MP3 after a confirmed Music import? (yes/no)' "$existing_cleanup")"
browser="$(prompt_with_default 'Browser for yt-dlp cookies (leave blank for none)' "$existing_browser")"

case "${cleanup:l}" in
  yes|no) ;;
  *) print -u2 "Please answer yes or no for cleanup."; exit 2 ;;
esac

mkdir -p "$CONFIG_DIR" "$inbox_root/1 Drafts" "$inbox_root/2 Queued" \
  "$inbox_root/3 Processing" "$inbox_root/4 Done" "$inbox_root/5 Failed" \
  "$inbox_root/media" "$inbox_root/.music-inbox" "$APP_DIR" "$BIN_DIR"
umask 077
{
  print -r -- "MUSIC_INBOX_ROOT=${(q)inbox_root}"
  print -r -- "MUSIC_INBOX_CLEANUP_AFTER_IMPORT=${(q)cleanup}"
  print -r -- "MUSIC_INBOX_BROWSER=${(q)browser}"
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

mkdir -p "$APP_DIR/bin" "$APP_DIR/lib"
cp -R "$PROJECT_DIR/bin/." "$APP_DIR/bin/"
cp -R "$PROJECT_DIR/lib/." "$APP_DIR/lib/"
chmod 755 "$APP_DIR/bin/music-inbox"
ln -sfn "$APP_DIR/bin/music-inbox" "$BIN_DIR/music-inbox"

missing_tools=()
for tool in yt-dlp ffmpeg ffprobe deno; do
  music_inbox_find_tool "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
done

if (( ${#missing_tools} )); then
  print
  print "Missing dependencies: ${(j:, :)missing_tools}"
  managers=()
  command -v brew >/dev/null 2>&1 && managers+=(brew)
  command -v port >/dev/null 2>&1 && managers+=(port)

  if (( ${#managers} == 0 )); then
    print "No supported package manager found. Install Homebrew or MacPorts, then run this installer again."
  else
    preferred="${managers[1]}"
    if (( ${#managers} > 1 )); then
      preferred="$(prompt_with_default 'Package manager to use (brew or port)' "$preferred")"
    fi
    case "$preferred" in
      brew|port) ;;
      *) print -u2 "Unsupported package manager: $preferred"; exit 2 ;;
    esac
    if confirm "Install missing dependencies with $preferred?"; then
      if [[ "$preferred" == brew ]]; then
        brew install yt-dlp ffmpeg deno
      else
        # MacPorts' yt-dlp port brings ffmpeg and its EJS runtime support.
        sudo port install yt-dlp deno
      fi
    else
      print "Skipped dependency installation. Run: music-inbox doctor"
    fi
  fi
fi

print
print "Installed command: $BIN_DIR/music-inbox"
print "Configuration: $CONFIG_FILE"
print "Inbox root: $inbox_root"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  print "Add $BIN_DIR to your shell PATH to run music-inbox from anywhere."
fi
print "Next: music-inbox doctor"
