# Music request

%% music-inbox-template-version: 2 %%
%% Duplicate this note, fill in the URL, then move the copy to `2 Queued`. %%
%% Music Inbox reads only recognized `field: value` lines. Everything else is ignored. %%

URL: 

%% Example: URL: https://youtu.be/your-video-id %%
%% Optional Apple Music playlist: %%
%% playlist: Coding Focus %%
%% Set this to yes only to create a missing playlist. It is ignored without playlist. %%
%% create-playlist: no %%

%% Set to no to create only transcript or translation files. Music import and playlist settings are skipped. %%
%% At least one of transcribe or translate must be yes. %%
%% import-to-music: no %%

%% Optional local transcription; first run `music-inbox install-transcription`. %%
%% transcribe: yes %%

%% Optional spoken-language hint; omit to auto-detect. %%
%% language: en %%

%% Optional comma-separated output formats: txt, srt, vtt. %%
%% transcript-format: txt,srt %%

%% Optional English translation. It needs a multilingual Whisper model, for example base rather than base.en. %%
%% translate: no %%
