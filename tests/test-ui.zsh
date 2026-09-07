#!/bin/zsh

set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
NO_COLOR=1 source "$PROJECT_DIR/lib/ui.zsh"

plain_output="$(music_inbox_ui_success 'Ready')"
[[ "$plain_output" == '✓ Ready' ]]
[[ "$plain_output" != *$'\e'* ]]

run_output="$(music_inbox_ui_run 'Checking a command' -- print 'command output')"
[[ "$run_output" == *'Checking a command'* && "$run_output" == *'command output'* ]]

if music_inbox_ui_run 'Expected failure' -- false; then
  print -u2 'expected a failed command to return a non-zero status'
  exit 1
fi

print 'ok - terminal UI degrades cleanly without colour or a TTY'
