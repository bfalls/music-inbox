#!/bin/zsh

MUSIC_INBOX_LAUNCHD_LABEL='com.music-inbox.worker'

music_inbox_launchd_paths() {
  MUSIC_INBOX_LAUNCHD_DOMAIN="gui/$(id -u)"
  MUSIC_INBOX_LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$MUSIC_INBOX_LAUNCHD_LABEL.plist"
}

music_inbox_xml_escape() {
  print -r -- "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

music_inbox_write_launch_agent_plist() {
  local destination="$1" queued log_path escaped_queued escaped_log
  queued="$MUSIC_INBOX_QUEUED"
  log_path="$MUSIC_INBOX_LOG"
  escaped_queued="$(music_inbox_xml_escape "$queued")"
  escaped_log="$(music_inbox_xml_escape "$log_path")"
  mkdir -p "${destination:h}" "$MUSIC_INBOX_STATE"
  {
    print '<?xml version="1.0" encoding="UTF-8"?>'
    print '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    print '<plist version="1.0">'
    print '<dict>'
    print "  <key>Label</key><string>$MUSIC_INBOX_LAUNCHD_LABEL</string>"
    print '  <key>ProgramArguments</key>'
    print '  <array>'
    print '    <string>/usr/local/bin/music-inbox</string>'
    print '    <string>process</string>'
    print '  </array>'
    print '  <key>RunAtLoad</key><true/>'
    print '  <key>WatchPaths</key>'
    print "  <array><string>$escaped_queued</string></array>"
    print '  <key>ProcessType</key><string>Background</string>'
    print "  <key>StandardOutPath</key><string>$escaped_log</string>"
    print "  <key>StandardErrorPath</key><string>$escaped_log</string>"
    print '</dict>'
    print '</plist>'
  } > "$destination"
}

music_inbox_launchd_is_loaded() {
  music_inbox_launchd_paths
  launchctl print "$MUSIC_INBOX_LAUNCHD_DOMAIN/$MUSIC_INBOX_LAUNCHD_LABEL" >/dev/null 2>&1
}

music_inbox_install_service() {
  local temporary_plist replacing=no
  music_inbox_launchd_paths
  temporary_plist="$MUSIC_INBOX_LAUNCHD_PLIST.tmp.$$"
  music_inbox_write_launch_agent_plist "$temporary_plist"
  plutil -lint "$temporary_plist" >/dev/null || { rm -f -- "$temporary_plist"; print -u2 'Generated LaunchAgent plist is invalid.'; return 1; }
  if music_inbox_launchd_is_loaded; then
    replacing=yes
    if ! launchctl bootout "$MUSIC_INBOX_LAUNCHD_DOMAIN/$MUSIC_INBOX_LAUNCHD_LABEL"; then
      rm -f -- "$temporary_plist"
      print -u2 'Could not stop the existing Music Inbox background service. No replacement was installed.'
      return 1
    fi
  fi
  mv -f -- "$temporary_plist" "$MUSIC_INBOX_LAUNCHD_PLIST"
  if ! launchctl bootstrap "$MUSIC_INBOX_LAUNCHD_DOMAIN" "$MUSIC_INBOX_LAUNCHD_PLIST"; then
    print -u2 'Could not start the Music Inbox background service. Run: music-inbox start'
    return 1
  fi
  if [[ "$replacing" == yes ]]; then
    print 'Music Inbox background service refreshed and watching Queued.'
  else
    print 'Music Inbox background service installed and watching Queued.'
  fi
}

music_inbox_start_service() {
  music_inbox_launchd_paths
  [[ -r "$MUSIC_INBOX_LAUNCHD_PLIST" ]] || { print -u2 'Service is not installed. Run: music-inbox install-service'; return 1; }
  if ! music_inbox_launchd_is_loaded; then
    launchctl bootstrap "$MUSIC_INBOX_LAUNCHD_DOMAIN" "$MUSIC_INBOX_LAUNCHD_PLIST"
  fi
  launchctl kickstart -k "$MUSIC_INBOX_LAUNCHD_DOMAIN/$MUSIC_INBOX_LAUNCHD_LABEL"
  print 'Music Inbox background service started.'
}

music_inbox_stop_service() {
  music_inbox_launchd_paths
  if music_inbox_launchd_is_loaded; then
    launchctl bootout "$MUSIC_INBOX_LAUNCHD_DOMAIN/$MUSIC_INBOX_LAUNCHD_LABEL"
    print 'Music Inbox background service stopped.'
  else
    print 'Music Inbox background service is already stopped.'
  fi
}

music_inbox_restart_service() {
  music_inbox_stop_service
  music_inbox_start_service
}

music_inbox_uninstall_service() {
  local trash_dir
  music_inbox_launchd_paths
  music_inbox_stop_service
  if [[ -e "$MUSIC_INBOX_LAUNCHD_PLIST" ]]; then
    trash_dir="$HOME/.Trash/music-inbox-launchagent-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$trash_dir"
    mv "$MUSIC_INBOX_LAUNCHD_PLIST" "$trash_dir/"
    print "Removed LaunchAgent plist to Trash: $trash_dir"
  fi
}

music_inbox_service_status() {
  local state
  music_inbox_launchd_paths
  if music_inbox_launchd_is_loaded; then
    state="$(launchctl print "$MUSIC_INBOX_LAUNCHD_DOMAIN/$MUSIC_INBOX_LAUNCHD_LABEL" 2>/dev/null | sed -n 's/^[[:space:]]*state = //p' | head -n 1)"
    [[ "$state" == running ]] && { print 'Service: Processing a request'; return; }
    print 'Service: Watching Queued'
  elif [[ -e "$MUSIC_INBOX_LAUNCHD_PLIST" ]]; then
    print 'Service: Stopped'
  else
    print 'Service: Not installed'
  fi
}
