[日本語](./README.md) / [English](./README.en.md) / [中文](./README.zh.md) / [한국어](./README.ko.md)

# Acceptance criteria (silent)

No audio is played. `afplay` and `say` are replaced by test stubs. No audio files are included.

## Language-specific voice selection

The normal `run-all.sh` targets the author's Japanese environment and skips language routing. Set `RUN_LANG_ROUTE=1` to include the silent routing check:

```sh
VOICE_PY=/path/to/voice.py RUN_LANG_ROUTE=1 sh tests/run-all.sh
```

Run it alone with `VOICE_PY=/path/to/voice.py python3 tests/test_lang_route.py`. `VOICE_PY` must accept `--select-voice-key <text>`, choose a voice setting key without playback, and print that key alone on stdout. The test also sets `VOICE_NO_PLAY=1` and checks the four exact expected keys in `fixtures/lang-route.tsv`.

The fixture columns are `lang`, `text`, and `voice_key`. Update the expected keys when the implementation's voice setting names change.
