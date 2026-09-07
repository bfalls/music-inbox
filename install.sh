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
DEFAULT_LOCAL_ROOT="$HOME/Library/Application Support/music-inbox"
TRANSCRIPTION_ONLY=false
[[ "${1:-}" == --transcription-only ]] && TRANSCRIPTION_ONLY=true

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

looks_like_synced_path() {
  case "$1" in
    *"Mobile Documents"*|*"Dropbox"*|*"OneDrive"*|*"Google Drive"*|*"Obsidian"*) return 0 ;;
    *) return 1 ;;
  esac
}

existing_root="$DEFAULT_ROOT"
existing_local_root="$DEFAULT_LOCAL_ROOT"
existing_cleanup=yes
existing_browser=brave
existing_transcription=no
existing_model=base
existing_formats=txt
if [[ -r "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  existing_root="${MUSIC_INBOX_ROOT:-$existing_root}"
  existing_local_root="${MUSIC_INBOX_LOCAL_ROOT:-$existing_local_root}"
  existing_cleanup="${MUSIC_INBOX_CLEANUP_AFTER_IMPORT:-$existing_cleanup}"
  existing_browser="${MUSIC_INBOX_BROWSER:-$existing_browser}"
  existing_transcription="${MUSIC_INBOX_TRANSCRIPTION_ENABLED:-$existing_transcription}"
  existing_model="${MUSIC_INBOX_WHISPER_MODEL:-$existing_model}"
  existing_formats="${MUSIC_INBOX_TRANSCRIPT_FORMATS:-$existing_formats}"
fi

if [[ "$TRANSCRIPTION_ONLY" == true ]]; then
  print "Music Inbox transcription setup"
else
  print "Music Inbox setup"
fi
music_inbox_acceleration_summary
print "This creates a folder-based inbox and a private configuration file."
print

if [[ "$TRANSCRIPTION_ONLY" == true ]]; then
  inbox_root="$existing_root"
  local_root="$existing_local_root"
  cleanup="$existing_cleanup"
  browser="$existing_browser"
else
  inbox_root="$(prompt_with_default 'Inbox root folder' "$existing_root")"
  local_root="$(prompt_with_default 'Local-only folder for models, logs, and temporary media' "$existing_local_root")"
  cleanup="$(prompt_with_default 'Remove temporary MP3 after a confirmed Music import? (yes/no)' "$existing_cleanup")"
  browser="$(prompt_with_default 'Browser for yt-dlp cookies (leave blank for none)' "$existing_browser")"
fi
transcription="$(prompt_with_default 'Enable local transcription? (yes/no)' "$existing_transcription")"
whisper_model="$existing_model"
formats="$existing_formats"
if [[ "${transcription:l}" == yes ]]; then
  print "Use a multilingual model (for example: tiny, base, small) for Russian and other non-English languages."
  print "English-only models end in .en (for example: base.en)."
  whisper_model="$(prompt_with_default 'Whisper model' "$existing_model")"
  formats="$(prompt_with_default 'Transcript formats (comma-separated: txt,srt,vtt)' "$existing_formats")"
fi

case "${cleanup:l}" in
  yes|no) ;;
  *) print -u2 "Please answer yes or no for cleanup."; exit 2 ;;
esac
case "${transcription:l}" in
  yes|no) ;;
  *) print -u2 "Please answer yes or no for transcription."; exit 2 ;;
esac
if looks_like_synced_path "$local_root"; then
  print -u2 "Warning: that local-data folder looks like a synced location. Models and temporary media should stay on this Mac."
  if ! confirm "Use this location anyway?"; then
    print "No changes made. Choose a non-synced local-data folder and run setup again."
    exit 2
  fi
fi
if [[ ! "$whisper_model" =~ '^(tiny|tiny.en|base|base.en|small|small.en|medium|medium.en|large-v[1-3]|large-v[1-3]-turbo|turbo)$' ]]; then
  print -u2 "Unsupported Whisper model name: $whisper_model"
  print -u2 "Choose tiny, base, small, medium, large-v3, turbo, or an English-only .en variant."
  exit 2
fi

mkdir -p "$CONFIG_DIR" "$inbox_root/1 Drafts" "$inbox_root/2 Queued" \
  "$inbox_root/3 Processing" "$inbox_root/4 Done" "$inbox_root/5 Failed" \
  "$local_root/media" "$local_root/state/models" "$APP_DIR" "$BIN_DIR"
umask 077
{
  print -r -- "MUSIC_INBOX_ROOT=${(q)inbox_root}"
  print -r -- "MUSIC_INBOX_LOCAL_ROOT=${(q)local_root}"
  print -r -- "MUSIC_INBOX_CLEANUP_AFTER_IMPORT=${(q)cleanup}"
  print -r -- "MUSIC_INBOX_BROWSER=${(q)browser}"
  print -r -- "MUSIC_INBOX_TRANSCRIPTION_ENABLED=${(q)transcription}"
  print -r -- "MUSIC_INBOX_WHISPER_MODEL=${(q)whisper_model}"
  print -r -- "MUSIC_INBOX_TRANSCRIPT_FORMATS=${(q)formats}"
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

mkdir -p "$APP_DIR/bin" "$APP_DIR/lib"
cp -R "$PROJECT_DIR/bin/." "$APP_DIR/bin/"
cp -R "$PROJECT_DIR/lib/." "$APP_DIR/lib/"
chmod 755 "$APP_DIR/bin/music-inbox"
ln -sfn "$APP_DIR/bin/music-inbox" "$BIN_DIR/music-inbox"

missing_tools=()
base_tools=()
[[ "$TRANSCRIPTION_ONLY" == false ]] && base_tools=(yt-dlp ffmpeg ffprobe deno)
for tool in "${base_tools[@]}"; do
  music_inbox_find_tool "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
done
if [[ "${transcription:l}" == yes ]] && ! music_inbox_find_whisper >/dev/null 2>&1; then
  missing_tools+=(whisper)
fi

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
        packages=()
        (( ${missing_tools[(I)yt-dlp]} )) && packages+=(yt-dlp)
        (( ${missing_tools[(I)ffmpeg]} || ${missing_tools[(I)ffprobe]} )) && packages+=(ffmpeg)
        (( ${missing_tools[(I)deno]} )) && packages+=(deno)
        (( ${missing_tools[(I)whisper]} )) && packages+=(whisper-cpp)
        brew install "${packages[@]}"
      else
        # MacPorts' yt-dlp port brings ffmpeg and its EJS runtime support.
        packages=()
        (( ${missing_tools[(I)yt-dlp]} || ${missing_tools[(I)ffmpeg]} || ${missing_tools[(I)ffprobe]} )) && packages+=(yt-dlp)
        (( ${missing_tools[(I)deno]} )) && packages+=(deno)
        (( ${missing_tools[(I)whisper]} )) && packages+=(whisper)
        sudo port install "${packages[@]}"
      fi
    else
      print "Skipped dependency installation. Run: music-inbox doctor"
    fi
  fi
fi

if [[ "${transcription:l}" == yes ]]; then
  mkdir -p "$local_root/state/models"
  model_path="$local_root/state/models/ggml-${whisper_model}.bin"
  # Approximate download size; leave 1 GiB free for audio conversion and output.
  typeset -A model_mib=(
    tiny 75 tiny.en 75 base 142 base.en 142 small 466 small.en 466
    medium 1500 medium.en 1500 large-v1 2900 large-v2 2900 large-v3 3100
    large-v3-turbo 1600 turbo 1600
  )
  required_kib=$(( (${model_mib[$whisper_model]:-3100} + 1024) * 1024 ))
  free_kib="$(music_inbox_disk_free_kib "$local_root")"
  print
  print "Transcription model: $whisper_model (about ${model_mib[$whisper_model]:-3100} MiB download)"
  print "Free disk space: $(( free_kib / 1024 )) MiB; recommended minimum: $(( required_kib / 1024 )) MiB"
  if [[ ! -r "$model_path" ]]; then
    if (( free_kib < required_kib )); then
      print -u2 "Warning: available space is below the recommended amount."
    fi
    if confirm "Download this model now?"; then
      command -v curl >/dev/null 2>&1 || { print -u2 "curl is required to download the model."; exit 1; }
      temporary_model="$model_path.partial.$$"
      if ! curl --fail --location --retry 3 --output "$temporary_model" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${whisper_model}.bin"; then
        rm -f -- "$temporary_model"
        print -u2 "Model download failed; no incomplete model was activated."
        exit 1
      fi
      mv -f -- "$temporary_model" "$model_path"
      print "Downloaded: $model_path"
    else
      print "Skipped model download. Requests that ask for transcription will fail early with recovery instructions."
    fi
  else
    print "Model already present: $model_path"
  fi
fi

print
print "Installed command: $BIN_DIR/music-inbox"
print "Configuration: $CONFIG_FILE"
print "Inbox root: $inbox_root"
print "Local-only data: $local_root"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  print "Add $BIN_DIR to your shell PATH to run music-inbox from anywhere."
fi
print "Next: music-inbox doctor"
