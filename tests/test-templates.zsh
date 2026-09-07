#!/bin/zsh

set -euo pipefail
export LC_ALL=C
PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/music-inbox-template-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
source "$PROJECT_DIR/lib/templates.zsh"

source_template="$PROJECT_DIR/templates/Default Music Request.md"
drafts="$TEST_ROOT/1 Drafts"
state="$TEST_ROOT/state"
canonical="$drafts/Default Music Request.md"

music_inbox_install_default_request_template "$source_template" "$drafts" "$state" >/dev/null
[[ -f "$canonical" && -f "$state/templates/default-music-request.sha256" ]]
print 'ok - creates and records a managed template'

print '<!-- user customization -->' >> "$canonical"
music_inbox_install_default_request_template "$source_template" "$drafts" "$state" >/dev/null
[[ -f "$drafts/Default Music Request v3.md" ]]
rg -q 'user customization' "$canonical"
print 'ok - preserves customized template and adds a versioned copy'

fresh_drafts="$TEST_ROOT/fresh/1 Drafts"
fresh_state="$TEST_ROOT/fresh/state"
music_inbox_install_default_request_template "$source_template" "$fresh_drafts" "$fresh_state" >/dev/null
new_source="$TEST_ROOT/Default Music Request v4.md"
sed 's/music-inbox-template-version: 3/music-inbox-template-version: 4/' "$source_template" > "$new_source"
music_inbox_install_default_request_template "$new_source" "$fresh_drafts" "$fresh_state" >/dev/null
rg -q 'music-inbox-template-version: 4' "$fresh_drafts/Default Music Request.md"
[[ ! -e "$fresh_drafts/Default Music Request v4.md" ]]
print 'ok - updates an unchanged managed template in place'
