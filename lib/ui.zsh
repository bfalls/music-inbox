#!/bin/zsh

# Small, dependency-free terminal presentation helpers. They stay quiet and
# uncoloured when output is redirected, so the CLI remains script-friendly.

music_inbox_ui_init() {
  MUSIC_INBOX_UI_TTY=no
  if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
    MUSIC_INBOX_UI_TTY=yes
  fi

  if [[ "$MUSIC_INBOX_UI_TTY" == yes ]]; then
    MUSIC_INBOX_UI_RESET=$'\e[0m'
    MUSIC_INBOX_UI_DIM=$'\e[2m'
    MUSIC_INBOX_UI_BOLD=$'\e[1m'
    MUSIC_INBOX_UI_BLUE=$'\e[38;5;75m'
    MUSIC_INBOX_UI_GREEN=$'\e[38;5;78m'
    MUSIC_INBOX_UI_YELLOW=$'\e[38;5;221m'
    MUSIC_INBOX_UI_RED=$'\e[38;5;203m'
  else
    MUSIC_INBOX_UI_RESET=''
    MUSIC_INBOX_UI_DIM=''
    MUSIC_INBOX_UI_BOLD=''
    MUSIC_INBOX_UI_BLUE=''
    MUSIC_INBOX_UI_GREEN=''
    MUSIC_INBOX_UI_YELLOW=''
    MUSIC_INBOX_UI_RED=''
  fi
}

music_inbox_ui_init

music_inbox_ui_heading() {
  print
  print -r -- "${MUSIC_INBOX_UI_BOLD}${MUSIC_INBOX_UI_BLUE}$1${MUSIC_INBOX_UI_RESET}"
}

music_inbox_ui_info() {
  print -r -- "${MUSIC_INBOX_UI_BLUE}•${MUSIC_INBOX_UI_RESET} $1"
}

music_inbox_ui_success() {
  print -r -- "${MUSIC_INBOX_UI_GREEN}✓${MUSIC_INBOX_UI_RESET} $1"
}

music_inbox_ui_warning() {
  print -u2 -r -- "${MUSIC_INBOX_UI_YELLOW}!${MUSIC_INBOX_UI_RESET} $1"
}

music_inbox_ui_error() {
  print -u2 -r -- "${MUSIC_INBOX_UI_RED}✗${MUSIC_INBOX_UI_RESET} $1"
}

music_inbox_ui_key_value() {
  local label="$1" value="$2"
  printf '%s%-14s%s %s\n' "$MUSIC_INBOX_UI_DIM" "$label" "$MUSIC_INBOX_UI_RESET" "$value"
}

# Run a non-interactive command with a minimal spinner when attached to a
# terminal. Output is shown on failure; redirected invocations remain plain.
music_inbox_ui_run() {
  local label="$1" temporary pid rc=0 frame=1
  local -a frames
  shift
  [[ "${1:-}" == -- ]] && shift
  frames=('◜' '◠' '◝' '◞' '◡' '◟')

  if [[ "$MUSIC_INBOX_UI_TTY" != yes ]]; then
    music_inbox_ui_info "$label"
    "$@"
    return
  fi

  temporary="$(mktemp "${TMPDIR:-/tmp}/music-inbox.XXXXXX")" || {
    music_inbox_ui_info "$label"
    "$@"
    return
  }
  "$@" >"$temporary" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[2K%s%s%s %s' "$MUSIC_INBOX_UI_BLUE" "${frames[$frame]}" "$MUSIC_INBOX_UI_RESET" "$label"
    (( frame = frame % ${#frames} + 1 ))
    sleep 0.12
  done
  if wait "$pid"; then
    printf '\r\033[2K'
    music_inbox_ui_success "$label"
  else
    rc=$?
    printf '\r\033[2K'
    music_inbox_ui_error "$label"
    [[ -s "$temporary" ]] && cat "$temporary" >&2
  fi
  rm -f -- "$temporary"
  return "$rc"
}
