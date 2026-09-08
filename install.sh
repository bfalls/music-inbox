#!/bin/zsh
# Interactive local setup. It writes only user configuration, inbox folders,
# and a user-local copy of the CLI. It never installs packages without asking.

set -euo pipefail

PROJECT_DIR="${0:A:h}"
CONFIG_DIR="$HOME/.config/music-inbox"
CONFIG_FILE="$CONFIG_DIR/config.env"
APP_DIR="$HOME/Library/Application Support/music-inbox"
BIN_DIR="/usr/local/bin"
DEFAULT_ROOT="$HOME/Music Inbox"
DEFAULT_LOCAL_ROOT="$HOME/Library/Application Support/music-inbox"
TRANSCRIPTION_ONLY=false
MODEL_OVERRIDE=''
while (( $# )); do
  case "$1" in
    --transcription-only)
      TRANSCRIPTION_ONLY=true
      ;;
    --model)
      [[ -n "${2:-}" ]] || { print -u2 'Usage: install.sh [--transcription-only] [--model <name>]'; exit 2; }
      MODEL_OVERRIDE="$2"
      shift
      ;;
    -h|--help)
      print 'Usage: install.sh [--transcription-only] [--model <name>]'
      exit 0
      ;;
    *)
      print -u2 "Unknown option: $1"
      print -u2 'Usage: install.sh [--transcription-only] [--model <name>]'
      exit 2
      ;;
  esac
  shift
done

source "$PROJECT_DIR/lib/music-inbox.zsh"
source "$PROJECT_DIR/lib/templates.zsh"
source "$PROJECT_DIR/lib/ui.zsh"

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
existing_remote_components=ejs:github
existing_template_style=standard
existing_transcription=no
existing_model=base
existing_formats=txt
if [[ -r "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
  existing_root="${MUSIC_INBOX_ROOT:-$existing_root}"
  existing_local_root="${MUSIC_INBOX_LOCAL_ROOT:-$existing_local_root}"
  existing_cleanup="${MUSIC_INBOX_CLEANUP_AFTER_IMPORT:-$existing_cleanup}"
  existing_browser="${MUSIC_INBOX_BROWSER:-$existing_browser}"
  existing_remote_components="${MUSIC_INBOX_YTDLP_REMOTE_COMPONENTS:-$existing_remote_components}"
  existing_template_style="${MUSIC_INBOX_TEMPLATE_STYLE:-$existing_template_style}"
  existing_transcription="${MUSIC_INBOX_TRANSCRIPTION_ENABLED:-$existing_transcription}"
  existing_model="${MUSIC_INBOX_WHISPER_MODEL:-$existing_model}"
  existing_formats="${MUSIC_INBOX_TRANSCRIPT_FORMATS:-$existing_formats}"
fi

if [[ "$TRANSCRIPTION_ONLY" == true ]]; then
  music_inbox_ui_heading 'Music Inbox - transcription setup'
else
  music_inbox_ui_heading 'Music Inbox - setup'
fi
music_inbox_acceleration_summary
music_inbox_ui_info 'Creates a folder-based inbox and a private configuration file.'
print

if [[ "$TRANSCRIPTION_ONLY" == true ]]; then
  inbox_root="$existing_root"
  local_root="$existing_local_root"
  cleanup="$existing_cleanup"
  browser="$existing_browser"
  remote_components="$existing_remote_components"
  template_style="$existing_template_style"
else
  inbox_root="$(prompt_with_default 'Inbox root folder' "$existing_root")"
  local_root="$(prompt_with_default 'Local-only folder for models, logs, and temporary media' "$existing_local_root")"
  cleanup="$(prompt_with_default 'Remove temporary MP3 after a confirmed Music import? (yes/no)' "$existing_cleanup")"
  browser="$(prompt_with_default 'Browser for yt-dlp cookies (leave blank for none)' "$existing_browser")"
  remote_components="$existing_remote_components"
  suggested_template_style="$existing_template_style"
  [[ "$inbox_root" == *obsidian* ]] && suggested_template_style=obsidian
  template_style="$(prompt_with_default 'Request template style (obsidian or standard)' "$suggested_template_style")"
fi
if [[ -n "$MODEL_OVERRIDE" || ( "$TRANSCRIPTION_ONLY" == true && "${existing_transcription:l}" == yes ) ]]; then
  # An explicit transcription command should not make an already configured
  # installation ask the same setup question again.
  transcription=yes
else
  transcription="$(prompt_with_default 'Enable local transcription? (yes/no)' "$existing_transcription")"
fi
whisper_model="$existing_model"
formats="$existing_formats"
if [[ -n "$MODEL_OVERRIDE" ]]; then
  whisper_model="$MODEL_OVERRIDE"
  music_inbox_ui_info "Using requested transcription model: $whisper_model"
elif [[ "${transcription:l}" == yes ]]; then
  existing_model_path="$local_root/state/models/ggml-${existing_model}.bin"
  if [[ "${existing_transcription:l}" == yes && -r "$existing_model_path" ]]; then
    music_inbox_ui_info "Using existing transcription model: $existing_model"
  else
    print "Use a multilingual model (for example: tiny, base, small) for languages other than English."
    print "English-only models end in .en (for example: base.en)."
    whisper_model="$(prompt_with_default 'Whisper model' "$existing_model")"
  fi
fi

case "${cleanup:l}" in
  yes|no) ;;
  *) print -u2 "Please answer yes or no for cleanup."; exit 2 ;;
esac
case "${transcription:l}" in
  yes|no) ;;
  *) print -u2 "Please answer yes or no for transcription."; exit 2 ;;
esac
case "${template_style:l}" in
  obsidian|standard) template_style="${template_style:l}" ;;
  *) print -u2 "Template style must be obsidian or standard."; exit 2 ;;
esac
if looks_like_synced_path "$local_root"; then
  music_inbox_ui_warning 'That local-data folder looks synced. Models and temporary media should stay on this Mac.'
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
  "$local_root/media" "$local_root/state/models" "$APP_DIR"
if [[ "$TRANSCRIPTION_ONLY" == false ]]; then
  template_source="$PROJECT_DIR/templates/Default Music Request.md"
  [[ "$template_style" == obsidian ]] && template_source="$PROJECT_DIR/templates/Default Music Request (Obsidian).md"
  music_inbox_install_default_request_template "$template_source" \
    "$inbox_root/1 Drafts" "$local_root/state"
fi
umask 077
{
  print -r -- "MUSIC_INBOX_ROOT=${(q)inbox_root}"
  print -r -- "MUSIC_INBOX_LOCAL_ROOT=${(q)local_root}"
  print -r -- "MUSIC_INBOX_CLEANUP_AFTER_IMPORT=${(q)cleanup}"
  print -r -- "MUSIC_INBOX_BROWSER=${(q)browser}"
  print -r -- "MUSIC_INBOX_YTDLP_REMOTE_COMPONENTS=${(q)remote_components}"
  print -r -- "MUSIC_INBOX_TEMPLATE_STYLE=${(q)template_style}"
  print -r -- "MUSIC_INBOX_TRANSCRIPTION_ENABLED=${(q)transcription}"
  print -r -- "MUSIC_INBOX_WHISPER_MODEL=${(q)whisper_model}"
  print -r -- "MUSIC_INBOX_TRANSCRIPT_FORMATS=${(q)formats}"
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

if [[ "$TRANSCRIPTION_ONLY" == false ]]; then
  # /usr/local/bin is the macOS convention for a user-installed CLI. Most Macs
  # already include it in PATH; /etc/paths.d ensures future standard login shells
  # do as well. Administrator approval is only needed for those shared locations.
  if [[ -e "$BIN_DIR/music-inbox" && ! -L "$BIN_DIR/music-inbox" ]]; then
    print -u2 "Refusing to replace existing non-link command: $BIN_DIR/music-inbox"
    print -u2 "Move it aside yourself, then run this installer again."
    exit 1
  fi
  needs_admin=no
  [[ ! -d "$BIN_DIR" || ! -w "$BIN_DIR" ]] && needs_admin=yes
  paths_entry=''
  [[ -r /etc/paths.d/music-inbox ]] && paths_entry="$(< /etc/paths.d/music-inbox)"
  if [[ "$paths_entry" != /usr/local/bin ]]; then
    needs_admin=yes
  fi
  if [[ "$needs_admin" == yes ]]; then
    print
    music_inbox_ui_info 'Administrator permission is required next.'
    print "macOS will ask for your password so Music Inbox can install its command in /usr/local/bin"
    print "and register that standard command location for future Terminal sessions."
    print "The Music Inbox worker, its notes, media, and models will still run only as your user."
    sudo -v
  fi

  music_inbox_ui_heading 'Updating Music Inbox'
  music_inbox_ui_info 'Refreshing installed files and rebuilding the native request window. This may take a moment.'
  mkdir -p "$APP_DIR/bin" "$APP_DIR/lib"
  music_inbox_ui_run 'Refreshing Music Inbox commands' -- cp -R "$PROJECT_DIR/bin/." "$APP_DIR/bin/"
  music_inbox_ui_run 'Refreshing Music Inbox support files' -- cp -R "$PROJECT_DIR/lib/." "$APP_DIR/lib/"
  music_inbox_ui_run 'Refreshing the Music Inbox installer' -- cp "$PROJECT_DIR/install.sh" "$APP_DIR/install.sh"
  chmod 755 "$APP_DIR/install.sh" "$APP_DIR/bin/music-inbox" "$APP_DIR/bin/music-inbox-worker"
  applet_path="$APP_DIR/Music Inbox Request.app"
  rm -rf -- "$applet_path"
  if ! music_inbox_ui_run 'Building the native Music Inbox request window' -- osacompile -o "$applet_path" "$APP_DIR/lib/add.applescript"; then
    print -u2 'Could not build the native Music Inbox request window.'
    exit 1
  fi

  music_inbox_ui_info 'Registering the Music Inbox command for future Terminal sessions.'
  if [[ ! -d "$BIN_DIR" || ! -w "$BIN_DIR" ]]; then
    sudo /bin/mkdir -p "$BIN_DIR"
  fi
  if [[ -w "$BIN_DIR" ]]; then
    ln -sfn "$APP_DIR/bin/music-inbox" "$BIN_DIR/music-inbox"
  else
    sudo /bin/ln -sfn "$APP_DIR/bin/music-inbox" "$BIN_DIR/music-inbox"
  fi
  if [[ ! -d /etc/paths.d || ! -w /etc/paths.d ]]; then
    sudo /bin/mkdir -p /etc/paths.d
  fi
  if [[ -w /etc/paths.d ]]; then
    print -r -- /usr/local/bin > /etc/paths.d/music-inbox
  else
    print -r -- /usr/local/bin | sudo /usr/bin/tee /etc/paths.d/music-inbox >/dev/null
  fi
fi

missing_tools=()
base_tools=()
[[ "$TRANSCRIPTION_ONLY" == false ]] && base_tools=(yt-dlp ffmpeg ffprobe deno)
for tool in "${base_tools[@]}"; do
  music_inbox_find_tool "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
done
if [[ "${transcription:l}" == yes ]]; then
  if existing_whisper="$(music_inbox_find_whisper 2>/dev/null)"; then
    music_inbox_ui_success "Using existing whisper.cpp: $existing_whisper"
  else
    missing_tools+=(whisper)
  fi
fi

if (( ${#missing_tools} )); then
  print
  music_inbox_ui_warning "Missing dependencies: ${(j:, :)missing_tools}"
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
      [[ "$preferred" == port ]] && music_inbox_ui_info 'MacPorts may ask for the same administrator password to install its packages.'
      if [[ "$preferred" == brew ]]; then
        packages=()
        (( ${missing_tools[(I)yt-dlp]} )) && packages+=(yt-dlp)
        (( ${missing_tools[(I)ffmpeg]} || ${missing_tools[(I)ffprobe]} )) && packages+=(ffmpeg)
        (( ${missing_tools[(I)deno]} )) && packages+=(deno)
        (( ${missing_tools[(I)whisper]} )) && packages+=(whisper-cpp)
        music_inbox_ui_run 'Installing required dependencies with Homebrew' -- brew install "${packages[@]}"
      else
        # MacPorts' yt-dlp port brings ffmpeg and its EJS runtime support.
        packages=()
        (( ${missing_tools[(I)yt-dlp]} || ${missing_tools[(I)ffmpeg]} || ${missing_tools[(I)ffprobe]} )) && packages+=(yt-dlp)
        (( ${missing_tools[(I)deno]} )) && packages+=(deno)
        (( ${missing_tools[(I)whisper]} )) && packages+=(whisper)
        music_inbox_ui_info 'Installing required dependencies with MacPorts…'
        sudo port install "${packages[@]}"
        music_inbox_ui_success 'Installed required dependencies with MacPorts'
      fi
    else
      print "Skipped dependency installation. Run: music-inbox doctor"
    fi
  fi
fi

if [[ "${transcription:l}" == yes ]]; then
  mkdir -p "$local_root/state/models"
  model_path="$local_root/state/models/ggml-${whisper_model}.bin"
  # Approximate download size; leave 1 GB free for audio conversion and output.
  typeset -A model_mib=(
    tiny 75 tiny.en 75 base 142 base.en 142 small 466 small.en 466
    medium 1500 medium.en 1500 large-v1 2900 large-v2 2900 large-v3 3100
    large-v3-turbo 1600 turbo 1600
  )
  required_kib=$(( (${model_mib[$whisper_model]:-3100} + 1024) * 1024 ))
  free_kib="$(music_inbox_disk_free_kib "$local_root")"
  download_size="$(music_inbox_human_kib "$(( ${model_mib[$whisper_model]:-3100} * 1024 ))")"
  free_space="$(music_inbox_human_kib "$free_kib")"
  recommended_space="$(music_inbox_human_kib "$required_kib")"
  print
  music_inbox_ui_heading 'Local transcription model'
  music_inbox_ui_key_value 'Model' "$whisper_model (about $download_size download)"
  music_inbox_ui_key_value 'Free space' "$free_space; recommended minimum: $recommended_space"
  if [[ ! -r "$model_path" ]]; then
    if (( free_kib < required_kib )); then
      music_inbox_ui_warning 'Available space is below the recommended amount.'
    fi
    if confirm "Download this model now?"; then
      command -v curl >/dev/null 2>&1 || { print -u2 "curl is required to download the model."; exit 1; }
      temporary_model="$model_path.partial.$$"
      if ! music_inbox_ui_run "Downloading the $whisper_model transcription model" -- curl --fail --location --retry 3 --output "$temporary_model" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${whisper_model}.bin"; then
        rm -f -- "$temporary_model"
        print -u2 "Model download failed; no incomplete model was activated."
        exit 1
      fi
      mv -f -- "$temporary_model" "$model_path"
      music_inbox_ui_success "Saved transcription model to $model_path"
    else
      print "Skipped model download. Requests that ask for transcription will fail early with recovery instructions."
    fi
  else
    music_inbox_ui_success "Transcription model already present: $model_path"
  fi
fi

if [[ "$TRANSCRIPTION_ONLY" == false ]]; then
  print
  music_inbox_ui_heading 'Background service (optional)'
  print "It runs as your user, watches the Queued folder, and processes new request notes automatically."
  print "Choose no to run requests manually with: music-inbox process"
  if confirm "Install and start the background service now?"; then
    "$APP_DIR/bin/music-inbox" install-service
  else
    print "Skipped background service installation. Run: music-inbox install-service"
  fi
fi

music_inbox_ui_heading 'Music Inbox is ready'
music_inbox_ui_key_value 'Command' "$BIN_DIR/music-inbox"
music_inbox_ui_key_value 'Configuration' "$CONFIG_FILE"
music_inbox_ui_key_value 'Inbox root' "$inbox_root"
music_inbox_ui_key_value 'Local data' "$local_root"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  print "This shell has a custom PATH. Standard new macOS Terminal sessions will include $BIN_DIR automatically."
fi
music_inbox_ui_info 'Next: music-inbox doctor'
