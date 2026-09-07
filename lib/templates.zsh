#!/bin/zsh

# Shipped templates can be refreshed safely without overwriting user edits.
# The manifest records only the exact template checksum that Music Inbox last
# placed in the canonical Drafts location.

music_inbox_template_hash() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    openssl dgst -sha256 -r "$file" | awk '{print $1}'
  fi
}

music_inbox_template_version() {
  local file="$1" version
  version="$(sed -n 's/.*music-inbox-template-version: *\([0-9][0-9]*\).*/\1/p' "$file" | head -n 1)"
  [[ -n "$version" ]] || return 1
  print -r -- "$version"
}

music_inbox_install_default_request_template() {
  local source="$1" drafts_dir="$2" state_dir="$3"
  local canonical manifest source_hash current_hash managed_hash version candidate suffix=2
  canonical="$drafts_dir/Default Music Request.md"
  manifest="$state_dir/templates/default-music-request.sha256"
  source_hash="$(music_inbox_template_hash "$source")" || return 1
  version="$(music_inbox_template_version "$source")" || return 1
  mkdir -p "$drafts_dir" "${manifest:h}"

  if [[ ! -e "$canonical" ]]; then
    cp "$source" "$canonical"
    print -r -- "$source_hash" > "$manifest"
    print "Created draft template: $canonical"
    return 0
  fi

  current_hash="$(music_inbox_template_hash "$canonical")" || return 1
  managed_hash=''
  [[ -r "$manifest" ]] && managed_hash="$(< "$manifest")"
  if [[ "$current_hash" == "$source_hash" ]]; then
    print -r -- "$source_hash" > "$manifest"
    print "Draft template is current: $canonical"
    return 0
  fi
  if [[ -n "$managed_hash" && "$current_hash" == "$managed_hash" ]]; then
    cp "$source" "$canonical"
    print -r -- "$source_hash" > "$manifest"
    print "Updated unchanged draft template: $canonical"
    return 0
  fi

  candidate="$drafts_dir/Default Music Request v${version}.md"
  while [[ -e "$candidate" ]]; do
    candidate="$drafts_dir/Default Music Request v${version} (${suffix}).md"
    (( suffix++ ))
  done
  cp "$source" "$candidate"
  print "Preserved customized draft template; added: $candidate"
}
