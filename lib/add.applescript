use framework "Foundation"
use framework "AppKit"
use scripting additions

property NSRadioButton : 4
property NSRadioModeMatrix : 0
property NSOnState : 1
property NSWindowStyleMaskTitled : 1
property NSBackingStoreBuffered : 2
property NSModalResponseAbort : -1001
property NSApplicationActivationPolicyRegular : 0
property NSApplicationActivateIgnoringOtherApps : 2
property NSEventModifierFlagCommand : 1048576
property modeMatrixControl : missing value
property languagePopupControl : missing value
property textFormatControl : missing value
property srtFormatControl : missing value
property vttFormatControl : missing value
property playlistNameControl : missing value

on updateTranscriptionControls:sender
	set enableTranscription to ((sender's selectedRow() as integer) is not 0)
	languagePopupControl's setEnabled:enableTranscription
	textFormatControl's setEnabled:enableTranscription
	srtFormatControl's setEnabled:enableTranscription
	vttFormatControl's setEnabled:enableTranscription
end updateTranscriptionControls:

on updatePlaylistNameControl:sender
	set enablePlaylistName to ((sender's titleOfSelectedItem() as text) is "Create new playlist…")
	playlistNameControl's setEnabled:enablePlaylistName
end updatePlaylistNameControl:

on addLabel(view, labelText, x, y, width, height)
	set label to current application's NSTextField's labelWithString:labelText
	label's setFrame:{{x, y}, {width, height}}
	view's addSubview:label
	return label
end addLabel

on addEditMenuItem(editMenu, itemTitle, selectorName, shortcut)
	set menuItem to current application's NSMenuItem's alloc()'s initWithTitle:itemTitle action:selectorName keyEquivalent:shortcut
	if shortcut is not "" then menuItem's setKeyEquivalentModifierMask:NSEventModifierFlagCommand
	editMenu's addItem:menuItem
end addEditMenuItem

on run argv
	set bundlePath to current application's NSBundle's mainBundle()'s bundlePath()
	set appDirectory to bundlePath's stringByDeletingLastPathComponent()
	set stateDirectory to appDirectory's stringByAppendingPathComponent:"state"
	set inputPath to stateDirectory's stringByAppendingPathComponent:"add-request.txt"
	set resultPath to stateDirectory's stringByAppendingPathComponent:"add-result.txt"
	set inputText to current application's NSString's stringWithContentsOfFile:inputPath encoding:4 |error|:(missing value)
	if inputText is missing value then error "Music Inbox could not read the request details. Run music-inbox add again."
	set inputLines to inputText's componentsSeparatedByString:linefeed
	set inputValues to inputLines as list
	if (count of inputValues) < 6 then error "Music Inbox received incomplete request details. Run music-inbox add again."
	set clipboardURL to item 1 of inputValues
	set transcriptionAvailable to item 2 of inputValues
	set translationAvailable to item 3 of inputValues
	set languageMarker to 0
	set playlistMarker to 0
	repeat with rowNumber from 4 to (count of inputValues)
		if item rowNumber of inputValues is "__MUSIC_INBOX_LANGUAGES__" then set languageMarker to rowNumber
		if item rowNumber of inputValues is "__MUSIC_INBOX_PLAYLISTS__" then set playlistMarker to rowNumber
	end repeat
	if languageMarker is 0 or playlistMarker is 0 or playlistMarker <= languageMarker then error "Music Inbox received incomplete request details. Run music-inbox add again."
	set languageChoices to items (languageMarker + 1) thru (playlistMarker - 1) of inputValues
	set playlistChoices to {}
	if playlistMarker < (count of inputValues) then set playlistChoices to items (playlistMarker + 1) thru -1 of inputValues
	if (count of playlistChoices) > 0 and item -1 of playlistChoices is "" then set playlistChoices to items 1 thru -2 of playlistChoices

	current application's NSApplication's sharedApplication()
	-- osascript normally behaves like a command-line process. Promote it to a
	-- regular foreground application so macOS routes keyboard events here.
	current application's NSApp's setActivationPolicy:NSApplicationActivationPolicyRegular
	set mainMenu to current application's NSMenu's alloc()'s initWithTitle:"Music Inbox"
	set editMenu to current application's NSMenu's alloc()'s initWithTitle:"Edit"
	my addEditMenuItem(editMenu, "Cut", "cut:", "x")
	my addEditMenuItem(editMenu, "Copy", "copy:", "c")
	my addEditMenuItem(editMenu, "Paste", "paste:", "v")
	my addEditMenuItem(editMenu, "Select All", "selectAll:", "a")
	set editMenuItem to current application's NSMenuItem's alloc()'s initWithTitle:"Edit" action:(missing value) keyEquivalent:""
	editMenuItem's setSubmenu:editMenu
	mainMenu's addItem:editMenuItem
	current application's NSApp's setMainMenu:mainMenu
	current application's NSApp's activateIgnoringOtherApps:true

	set contentView to current application's NSView's alloc()'s initWithFrame:{{0, 0}, {560, 410}}
	set view to current application's NSView's alloc()'s initWithFrame:{{20, 20}, {520, 370}}
	contentView's addSubview:view
	my addLabel(view, "Video URL", 0, 337, 520, 20)
	set urlField to current application's NSTextField's alloc()'s initWithFrame:{{0, 307}, {520, 24}}
	urlField's setStringValue:clipboardURL
	urlField's setPlaceholderString:"https://youtu.be/..."
	urlField's setEditable:true
	urlField's setSelectable:true
	view's addSubview:urlField

	my addLabel(view, "Create", 0, 273, 250, 20)
	set prototype to current application's NSButtonCell's alloc()'s initTextCell:""
	prototype's setButtonType:NSRadioButton
	set modeMatrix to current application's NSMatrix's alloc()'s initWithFrame:{{0, 188}, {310, 84}} mode:NSRadioModeMatrix prototype:prototype numberOfRows:4 numberOfColumns:1
	modeMatrix's setCellSize:{310, 21}
	set modeTitles to {"Import into Apple Music", "Transcript only", "English translation only", "Transcript and English translation"}
	repeat with rowNumber from 0 to 3
		set cell to modeMatrix's cellAtRow:rowNumber column:0
		cell's setTitle:(item (rowNumber + 1) of modeTitles)
	end repeat
	(modeMatrix's cellAtRow:1 column:0)'s setEnabled:(transcriptionAvailable is "yes")
	(modeMatrix's cellAtRow:2 column:0)'s setEnabled:(translationAvailable is "yes")
	(modeMatrix's cellAtRow:3 column:0)'s setEnabled:(translationAvailable is "yes")
	modeMatrix's selectCellAtRow:0 column:0
	set modeMatrixControl to modeMatrix
	modeMatrix's setTarget:me
	modeMatrix's setAction:"updateTranscriptionControls:"
	view's addSubview:modeMatrix

	my addLabel(view, "Apple Music playlist", 0, 156, 250, 20)
	set playlistPopup to current application's NSPopUpButton's alloc()'s initWithFrame:{{0, 126}, {250, 26}} pullsDown:false
	playlistPopup's addItemsWithTitles:{"Library only", "Create new playlist…"}
	if (count of playlistChoices) > 0 then playlistPopup's addItemsWithTitles:playlistChoices
	playlistPopup's selectItemAtIndex:0
	view's addSubview:playlistPopup
	set playlistField to current application's NSTextField's alloc()'s initWithFrame:{{260, 126}, {260, 24}}
	playlistField's setPlaceholderString:"Name for Create new playlist"
	set playlistNameControl to playlistField
	playlistPopup's setTarget:me
	playlistPopup's setAction:"updatePlaylistNameControl:"
	view's addSubview:playlistField

	my addLabel(view, "Source language", 0, 94, 250, 20)
	set languagePopup to current application's NSPopUpButton's alloc()'s initWithFrame:{{0, 64}, {250, 26}} pullsDown:false
	languagePopup's addItemsWithTitles:languageChoices
	languagePopup's selectItemAtIndex:0
	set languagePopupControl to languagePopup
	view's addSubview:languagePopup

	my addLabel(view, "Transcript formats", 280, 94, 240, 20)
	set textFormat to current application's NSButton's checkboxWithTitle:"Text (.txt)" target:(missing value) action:(missing value)
	textFormat's setFrame:{{280, 65}, {110, 22}}
	textFormat's setState:NSOnState
	set textFormatControl to textFormat
	view's addSubview:textFormat
	set srtFormat to current application's NSButton's checkboxWithTitle:"Subtitles (.srt)" target:(missing value) action:(missing value)
	srtFormat's setFrame:{{390, 65}, {130, 22}}
	set srtFormatControl to srtFormat
	view's addSubview:srtFormat
	set vttFormat to current application's NSButton's checkboxWithTitle:"Web captions (.vtt)" target:(missing value) action:(missing value)
	vttFormat's setFrame:{{280, 40}, {160, 22}}
	set vttFormatControl to vttFormat
	view's addSubview:vttFormat
	my updateTranscriptionControls:modeMatrix
	my updatePlaylistNameControl:playlistPopup

	set cancelButton to current application's NSButton's alloc()'s initWithFrame:{{334, 0}, {82, 26}}
	cancelButton's setTitle:"Cancel"
	cancelButton's setTarget:(current application's NSApp)
	cancelButton's setAction:"abortModal"
	view's addSubview:cancelButton
	set queueButton to current application's NSButton's alloc()'s initWithFrame:{{424, 0}, {96, 26}}
	queueButton's setTitle:"Queue request"
	queueButton's setTarget:(current application's NSApp)
	queueButton's setAction:"stopModal"
	view's addSubview:queueButton

	set panel to current application's NSWindow's alloc()'s initWithContentRect:{{0, 0}, {560, 410}} styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:false
	panel's setTitle:"New Music Inbox request"
	panel's setContentView:contentView
	panel's |center|()
	set runningApplication to current application's NSRunningApplication's currentApplication()
	runningApplication's activateWithOptions:NSApplicationActivateIgnoringOtherApps
	panel's makeKeyAndOrderFront:me
	panel's makeFirstResponder:urlField
	set response to current application's NSApp's runModalForWindow:panel
	panel's orderOut:me
	if response is NSModalResponseAbort then error number -128

	set selectedRow to modeMatrix's selectedRow() as integer
	set modes to {"import", "transcript", "translation", "both"}
	set selectedMode to item (selectedRow + 1) of modes
	set playlistSelection to playlistPopup's titleOfSelectedItem() as text
	set selectedPlaylist to ""
	set mayCreate to "no"
	if playlistSelection is "Create new playlist…" then
		set selectedPlaylist to playlistField's stringValue() as text
		set mayCreate to "yes"
	else if playlistSelection is not "Library only" then
		set selectedPlaylist to playlistSelection
	end if
	set selectedLanguage to languagePopup's titleOfSelectedItem() as text
	set formatList to {}
	if (textFormat's state() as integer) = NSOnState then set end of formatList to "txt"
	if (srtFormat's state() as integer) = NSOnState then set end of formatList to "srt"
	if (vttFormat's state() as integer) = NSOnState then set end of formatList to "vtt"
	set AppleScript's text item delimiters to ","
	set selectedFormats to formatList as text
	-- Use a non-whitespace separator. Shell `read` treats tabs as whitespace and
	-- would otherwise discard an intentionally empty Library-only playlist field.
	set AppleScript's text item delimiters to character id 31
	set resultText to {urlField's stringValue() as text, selectedMode, selectedPlaylist, mayCreate, selectedLanguage, selectedFormats} as text
	set resultString to current application's NSString's stringWithString:resultText
	set wroteResult to resultString's writeToFile:resultPath atomically:true encoding:4 |error|:(missing value)
	if (wroteResult as boolean) is false then error "Could not return the completed request."
end run
