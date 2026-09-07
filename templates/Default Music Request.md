# Music request

<!-- music-inbox-template-version: 2 -->

<!--
Duplicate this note, fill in the URL, then move the copy to `2 Queued`.

Music Inbox reads only the recognized `field: value` lines below. Everything
else in this note is for your own context and is ignored.
-->

URL:

<!-- Example: URL: https://youtu.be/your-video-id -->

<!-- Optional Apple Music playlist. -->
# playlist: Coding Focus

<!-- Set to yes only when the playlist does not exist and you want Music Inbox
to create it. This setting is ignored if playlist is omitted. -->
# create-playlist: no

<!-- Optional local transcription. It must be enabled with
`music-inbox install-transcription` before this request is queued. -->
# transcribe: yes

<!-- Optional spoken-language hint. Omit it to let Whisper detect the language.
Use a multilingual model for non-English languages, e.g. ru for Russian. -->
# language: en

<!-- Optional comma-separated output formats: txt, srt, vtt. -->
# transcript-format: txt,srt

<!-- Translation is planned but is not available yet. Do not enable it. -->
# translate: no
