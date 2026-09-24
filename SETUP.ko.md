[日本語](./SETUP.md) / [English](./SETUP.md) / [中文](./SETUP.zh.md) / [한국어](./SETUP.ko.md)

# 도입 절차 (입력 및 출력)

사람이든 AI든, 위에서부터 순서대로 따라 하면 동일한 오디오 환경이 구축된다. 재료는 이 Mac (macOS 27.0 26A428, arm64) 실물이다. 추측으로 채우지 않았다. 모르는 항목은 "불명"으로 표시했다.

키, 집의 호스트 이름, 실제 주소는 작성하지 않는다. 설정 템플릿은 플레이스홀더를 사용한다.

---

## 1. 포함되는 항목

오디오 입출력에서 실제로 사용 중인 것만 포함합니다. `/Applications`·Homebrew·MacPorts·pip / venv의 실물입니다.

| 항목 | 이 Mac의 버전 | 위치 | 입수 방법 |
|---|---|---|---|
| 마이크 (작성자 추천) | a USB wireless microphone. Mac 상의 이름은 `the USB receiver` (`system_profiler SPAudioDataType`: Manufacturer: the manufacturer, USB, 48kHz, Default Input Device) | USB 수신기를 Mac에 연결 | USB microphone 무선 마이크. USB 수신기로 연결. 작성자가 사용 중. |
| Hammerspoon | 1.1.1 (6936) | `/Applications/Hammerspoon.app`. brew cask로는 미설치. 로그인 항목에 등록 | https://www.hammerspoon.org/ ／ https://github.com/Hammerspoon/hammerspoon |
| iTerm2 | 실제 앱 3.7.2. Homebrew Caskroom 등록 버전 3.6.11 (버전이 다름) | `/Applications/iTerm.app` | https://iterm2.com/ |
| tmux | 3.6b | `/opt/local/bin/tmux` (MacPorts. Homebrew formula에는 없음) | https://github.com/tmux/tmux |
| ffmpeg | 8.1 | `/opt/local/bin/ffmpeg` (MacPorts. voicein이 이 절대 경로를 직접 작성함) | https://ffmpeg.org/ |
| Python 3.9.6 | CLT | `/usr/bin/python3`. `voicein.py`의 shebang 및 hook의 `/usr/bin/python3` | Apple Command Line Tools |
| Python 3.12.14 | Homebrew `python@3.12` | `/opt/homebrew/bin/python3.12`. Aizuchi와 mlx-lm venv의 기반 | https://www.python.org/ ／ `brew install python@3.12` |
| uv | 0.12.9 | `/opt/homebrew/bin/uv` | https://github.com/astral-sh/uv |
| Node | v24.19.0 | nvm `~/.nvm/versions/node/v24.19.0`. Pi용 | https://nodejs.org/ |
| jq | 1.7.1-apple | `/usr/bin/jq`. hook의 JSON 읽기용 | macOS 기본 포함 |
| Claude Code | 2.1.281 | `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.281` | https://docs.claude.com/en/docs/claude-code |
| Pi | 0.87.1 | `pi` = `@earendil-works/pi-coding-agent` | `npm i -g @earendil-works/pi-coding-agent` |
| whisper.cpp | 1.9.1 (commit `2ca53bb`, Metal ON) | `~/.local/stt/whisper.cpp`, 실행 파일 `build/bin/whisper-cli` | https://github.com/ggml-org/whisper.cpp |
| Whisper 모델 | `ggml-large-v3-turbo.bin` 1.5G | `~/.local/stt/models/ggml-large-v3-turbo.bin` | 아래 4절 참조 |
| AivisSpeech Engine | 1.2.0 | `~/.config/voice/aivis/macOS-arm64/run`. `/Applications`에 AivisSpeech.app은 없음 | https://github.com/Aivis-Project/AivisSpeech-Engine/releases/tag/1.2.0 |
| 목소리 「an AivisHub voice model」 | 모델 1.0.0, AIVMX UUID `<model-uuid>` | `~/Library/Application Support/AivisSpeech-Engine/Models/`. Calm의 speaker_id = `1310138977` | https://hub.aivis-project.com/aivm-models/<model-uuid> |
| onnxruntime (즉답) | 1.30.0 | `project/voice/aizuchi/.venv` (Python 3.12.14) | pip. 같은 venv에 numpy 2.5.3, tokenizers 0.22.2, sentencepiece 0.2.2, huggingface_hub 0.36.2, protobuf 7.36.2 |
| mlx-lm (선택 사항, 요약용) | 0.31.3 (mlx 0.32.2) | `tools/voice/output/.venv-mlx`. 로그인 시 자동 실행하지 않음 | https://github.com/ml-explore/mlx-lm ／ `pip install mlx-lm` |
| 코드 본체 | project | `~/project/tools/voice/input/voicein.py`, `~/project/tools/voice/output/voice.py`, `~/project/project/voice/aizuchi/` | 이 저장소들 |

입력 장치는 `ffmpeg -f avfoundation -list_devices true -i ""`의 오디오 쪽 번호를 `VOICEIN_DEV`에 기록합니다 (이 Mac은 `:0` = the USB receiver).

`voicein` 진입점: `~/.local/bin/voicein` → `~/project/tools/voice/input/voicein.py`.

음성 입력 조작의 기준은 `~/.hammerspoon/init.lua` (tools/voice 외부)입니다. 설치 방법, 권한, 현재 두 입력 방식 및 삭제된 경로는 7절을 참조하세요.

시스템 pip (CLT 3.9)에도 onnxruntime 1.19.2가 있지만, 즉답과 TTS는 이를 사용하지 않습니다.

## 2. macOS 권한 설정

모든 설정 위치는 **시스템 설정 → 개인정보 보호 및 보안**입니다. 설정을 마친 후에는 해당 앱을 종료하고 다시 실행하세요. 입력 모니터링 및 손쉬운 사용(Accessibility) 설정은 반영을 위해 **로그아웃 또는 재부팅**이 필요할 수 있습니다 (이 단계에서 Hammerspoon을 종료하고 다시 실행해 보세요. 그래도 eventtap이 작동하지 않으면 로그아웃하세요).

| 항목 | 위치 | 대상 | 용도 |
|---|---|---|---|
| 마이크 | 개인정보 보호 및 보안 → 마이크 | Hammerspoon. 수동으로 `voicein`을 실행할 때는 iTerm2 및 터미널 | ffmpeg의 avfoundation 녹음. 실패 시 메시지는 "마이크 권한 또는 디바이스 번호" 확인 |
| 손쉬운 사용 | 개인정보 보호 및 보안 → 손쉬운 사용 | Hammerspoon. 수동으로 실행할 때는 iTerm2 및 터미널 | 포커스된 앱에 `hs.eventtap.keyStrokes`로 텍스트 입력 |
| 입력 모니터링 | 개인정보 보호 및 보안 → 입력 모니터링 | Hammerspoon | 오른쪽 Option 키의 flagsChanged 감지 |

이 Mac의 ffmpeg가 인식하는 오디오 디바이스:

- `[0] the USB receiver` (`VOICEIN_DEV` 기본값 `:0`)
- `[1] BlackHole 2ch`

## 3. whisper.cpp 및 모델

```sh
mkdir -p ~/.local/stt/models
git clone https://github.com/ggml-org/whisper.cpp.git ~/.local/stt/whisper.cpp
cd ~/.local/stt/whisper.cpp
cmake -B build -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_BUILD_EXAMPLES=ON
cmake --build build --config Release -t whisper-cli
./models/download-ggml-model.sh large-v3-turbo ~/.local/stt/models
```

모델 URL (스크립트의 `src`): `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin`.

voicein이 참조하는 고정 경로:

- 실행 파일 `~/.local/stt/whisper.cpp/build/bin/whisper-cli`
- 모델 `~/.local/stt/models/ggml-large-v3-turbo.bin`
- 인식 인자: `-l ja -nt --no-prints`, `--prompt`에 `glossary.txt` 포함

ffmpeg 녹음: `-f avfoundation -i :0 -ar 16000 -ac 1`. PTT 시 RMS 레벨을 `/tmp/voicein-ptt.level`에 직접 기록.

## 4. AivisSpeech 엔진과 음성

이 Mac에는 GUI 앱을 설치하지 않고 엔진만 단독으로 설치합니다.

1. https://github.com/Aivis-Project/AivisSpeech-Engine/releases/tag/1.2.0 에서 `AivisSpeech-Engine-macOS-arm64-1.2.0.7z.001`을 다운로드합니다 (203MB).
2. 7-Zip으로 압축을 풉니다. 현재 PATH에 `7z` / `7zz`가 없습니다 (압축 해제된 `run`만 있음). GUI 버전의 AivisSpeech(https://aivis-project.com/speech/ )를 통해 설치해도 동일한 엔진이 사용됩니다.
3. 실행 파일을 `~/.config/voice/aivis/macOS-arm64/run`에 배치합니다.
4. 실행 인자 (실측 LaunchAgent 기준): `--host 127.0.0.1 --port 10101 --disable_sentry`.
5. 음성: AivisHub의 [an AivisHub voice model](https://hub.aivis-project.com/aivm-models/<model-uuid>)에서 **AIVMX**를 다운로드합니다 (약 241MB, ACML 1.0).
6. 파일을 `~/Library/Application Support/AivisSpeech-Engine/Models/`에 배치합니다. 이 Mac에서의 파일명은 `<model-uuid>.aivmx`입니다.
7. **엔진을 재시작합니다** (모델 추가 반영을 위해 필요. LaunchAgent를 사용하는 경우 다음 섹션의 kickstart 참고). 처음 실행 시 BERT 캐시를 가져오기 위해 인터넷 연결이 필요합니다.
8. `curl -s http://127.0.0.1:10101/speakers`를 실행하여 `"name": "an AivisHub voice model"`와 style `"Calm"`, id `1310138977`이 확인되는지 점검합니다.
9. 사용자 사전 (선택 사항·멱등성 보장): `python3 ~/project/tools/voice/output/register-dict.py`.

`config.json`의 `speaker_id`를 `1310138977`로 설정합니다 (다음 섹션).

---

## 5. Python 가상 환경

즉시 실행 (필수):

```sh
/opt/homebrew/bin/python3.12 -m venv ~/project/project/voice/aizuchi/.venv
~/project/project/voice/aizuchi/.venv/bin/pip install onnxruntime numpy tokenizers sentencepiece huggingface_hub
```

이 Mac의 실측 버전은 1절의 표를 참조. 상주 프로세스는 `serve.py` (기본 소켓 `~/.config/voice/aizuchi.sock`, 모델 `aizuchi/onnx/model-int8.onnx`).

요약용 mlx-lm (선택 사항. 이 Mac의 프로덕션 요약은 OpenAI 호환 엔드포인트 사용. mlx는 수동 `up` 필요):

```sh
sh ~/project/tools/voice/output/mlx-summ.sh up
```

venv는 `tools/voice/output/.venv-mlx`. 모델 `mlx-community/gemma-4-e4b-it-4bit`, `127.0.0.1:8091`, 사고(thinking) 모드 OFF `--chat-template-args '{"enable_thinking":false}'`. launchd에는 등록하지 않음.

`voice.py` / `voicein.py` 본체는 표준 라이브러리임. 추가적인 pip 설치는 필요 없음.

## 6. 설정 파일

`~/.config/voice/config.json`. 없는 키는 `voice.py`의 기본값으로 채워집니다. 실제 주소나 키는 입력하지 마세요.

템플릿:

```json
{
  "enabled": true,
  "mode": "summary",
  "say_rate": 220,
  "speaker_id": 1310138977,
  "synth_timeout": 10,
  "purposes": {
    "done": true,
    "attention": true,
    "error": true,
    "read": true
  },
  "quiet_hours": ["02:00", "08:00"],
  "min_interval_sec": 5,
  "post_rec_grace_sec": 30,
  "rewrite": true,
  "rewrite_skip_under": 50,
  "rewrite_timeout": 2.0,
  "dedupe_window_sec": 1800,
  "night_brief_hours": ["23:00", "07:00"],
  "night_brief_cap": 30,
  "pack": {
    "enabled": true,
    "model": "aivis-aida",
    "voice": "",
    "lang": "ja"
  },
  "summarizer": "openai",
  "summarizer_base": "http://127.0.0.1:8091",
  "summary_timeout": 6.0,
  "seat": ""
}
```

키 설명:

| 키 | 의미 |
|---|---|
| `enabled` | 전체 온/오프 |
| `mode` | `off` / `earcon` / `summary` / `full` |
| `say_rate` | Aivis 실패 시 `say -v Kyoko`의 말하기 속도 |
| `speaker_id` | Aivis 화자. an AivisHub voice model Calm = 1310138977 |
| `synth_timeout` | 합성 제한 시간(초) |
| `purposes` | 용도별 온/오프 (`false` 설정 시 해당 용도의 음성 출력 완전 중단) |
| `quiet_hours` | 자동 일반 읽기 및 earcon을 억제하는 시간대 `[시작, 종료]`. 수동 read / test는 별개 |
| `min_interval_sec` | 연속 발화 사이의 최소 간격 |
| `post_rec_grace_sec` | 녹음 종료 후 자동 발화를 하지 않는 유예 시간(초) |
| `rewrite` | `sum_kind == fallback`일 때, 요약 실패 시 생성되는 도입부 문장을 재작성(rewrite)함. `short` 방식의 단문이나 `gemma` 요약 성공 시에는 적용되지 않음. |
| `rewrite_skip_under` | 이 글자 수 미만인 경우 rewrite 하지 않음 |
| `rewrite_timeout` | rewrite 호출 제한 시간(초) |
| `dedupe_window_sec` | 동일 문장 반복을 방지하는 윈도우 시간(초) |
| `night_brief_hours` / `night_brief_cap` | 야간에는 짧게 요약. quiet 시간대 외부에만 적용됨 |
| `pack` | 미리 만들어둔 클립 설정 (`model` / `voice` / `lang`) |
| `summarizer` | `apple` / `openai` / `off` |
| `summarizer_base` | OpenAI 호환 연결 URL. 템플릿의 `127.0.0.1`은 동일 Mac 상의 요약 서버용. 다른 호스트의 서버를 사용하는 경우, 해당 환경에서 접근 가능한 URL로 교체하세요 (실제 호스트명/주소는 기재하지 않음) |
| `summary_timeout` | 요약 제한 시간(초). 코드 기본값은 6.0과 15.0 두 곳에 설정되어 있음. 이 Mac의 파일은 6.0 |
| `seat` | 비어 있으면 현재 표시 중인 tmux 세션에서만 소리가 남 |

Aivis 접속 대상은 환경 변수 `VOICE_AIVIS_BASE`입니다 (미설정 시 `http://127.0.0.1:10101`). 말하기 속도와 간격은 `tools/voice/output/speech-styles.json`에서 설정합니다 (화자 ID는 참조하지 않음).

`~/.config/voice/speakers.json`은 엔진에서 가져온 화자 목록 캐시입니다. 직접 작성할 필요는 없습니다.

---

## 7. Hammerspoon (설치 방법 · 권한 · init.lua · 2개의 현행 입력 및 삭제된 경로)

음성 입력 조작의 원본은 **`~/.hammerspoon/init.lua`** (tools/voice 외부. 이 Mac의 파일은 2026-08-25 기준)입니다. `tools/voice/input/hammerspoon-init.lua`는 현재 존재하지 않습니다. Hammerspoon이 오른쪽 Option으로 설정된 하드웨어 버튼을 감시하며, `~/.local/bin/voicein`을 자식 프로세스로 실행합니다. 상시 청취 기능은 삭제되었으며, 남아 있는 코드에 대한 설명은 다음과 같습니다.

### 설치 방법

1. https://www.hammerspoon.org/ 에서 Hammerspoon을 설치합니다 (이 Mac은 1.1.1 버전, `/Applications/Hammerspoon.app`. Homebrew cask로는 설치하지 않음).
2. 로그인 항목에 Hammerspoon을 추가합니다.
3. `mkdir -p ~/.hammerspoon ~/.local/bin`
4. 설정 파일 배치: 사용할 Hammerspoon 설정을 `~/.hammerspoon/init.lua`로 복사합니다 (또는 동일한 내용을 작성합니다). 실행 시 `hs.ipc.cliInstall(os.getenv("HOME") .. "/.local")`이 `~/.local/bin/hs`를 설치합니다.
5. `ln -sf ~/project/tools/voice/input/voicein.py ~/.local/bin/voicein`
6. 메뉴 바의 Hammerspoon → Reload Config를 클릭합니다. 실행 시 알림은 PTT가 시작되었음을 나타냅니다.

`init.lua`에서의 Lua 경로 예시: `VOICEIN = os.getenv("HOME") .. "/.local/bin/voicein"`. 녹음 표시 화면은 Hammerspoon canvas로 그리는 파형 필(waveform pill)로, 별도의 이미지 파일은 필요하지 않습니다. 설정에는 임의의 마스코트 이미지인 `~/project/tools/voice/input/indicator.png`를 지정하는 부분이 남아 있으나, 현재 이 파일이 존재하지 않으므로 이미지 없이 표시됩니다. 음성 출력 중지는 `~/project/tools/voice/output/voice.py stop`입니다. 녹음이 시작될 때마다 `voice.py stop`을 비동기로 호출합니다 (인터럽트). 음성을 멈추는 키는 Cmd+Ctrl+. 입니다 (`hs.hotkey.bind({"cmd", "ctrl"}, ".")` → `voice.py stop`).

### 권한 (Accessibility)

전면으로 타이핑하는 `hs.eventtap.keyStrokes` / `keyStroke` 및 오른쪽 Option 키의 `eventtap`을 위해 **Hammerspoon을 접근성(Accessibility)에 추가**해야 합니다.

1. Hammerspoon을 한 번 실행합니다 (권한 요청 대화 상자가 나타날 수 있습니다).
2. **시스템 설정 → 개인정보 보호 및 보안 → 접근성**에서 Hammerspoon을 켭니다.
3. 마이크 권한도 Hammerspoon에 부여합니다 (2절 참고. ffmpeg는 HS의 자식 프로세스이므로, 마이크 처리는 앱 단위로 이루어집니다).
4. **Hammerspoon을 종료하고 다시 실행합니다**. 접근성 설정 반영을 위해 로그아웃 또는 재부팅이 필요할 수 있습니다 (2절 참고).

오른쪽 Option 키의 `flagsChanged`를 가져올 수 없는 경우, 동일한 화면의 **입력 모니터링(Input Monitoring)**에 Hammerspoon을 추가한 뒤 앱을 재시작하십시오.

### 2개의 현재 입력 방식 (init.lua 실제 내용) 및 삭제된 경로

인식이 완료되면 전면 입력창에 `hs.eventtap.keyStrokes`를 사용하여 직접 타이핑합니다. Enter를 입력할지 여부는 경로에 따라 다릅니다 (아래 표 참조).

| # | 조작 | init.lua 진입점 | 녹음 | 타이핑 후 Enter |
|---|---|---|---|---|
| 1 | 오른쪽 Option을 누르고 있는 동안만 | `hs.eventtap` (오른쪽 Option의 `flagsChanged`) → `startRec` / `stopRec()` | `voicein --ptt start` / `stop`. 뗄 때까지. 최대 90초 | 입력 안 함 |
| 2 | 대응하는 수신기 버튼 (F18) | `hs.hotkey.bind({}, "f18")`. 토글 방식. 인식 중 연타는 무시. 0.5초 디바운스 | 1회 클릭 `startRec("button")`, 2회 클릭 `stopRec(true)` | 입력함 (150ms 대기 후 `return`) |

**1. 오른쪽 Option (PTT)** — 누르고 있는 동안만 녹음합니다. 콜백은 플래그 판정만 수행하며, 무거운 처리는 `hs.timer.doAfter(0, …)`를 사용합니다. 모니터링 객체는 GC(Garbage Collection)에 의해 삭제되지 않도록 유지해야 합니다.

**2. 수신기 버튼 = F18** — F18의 출처는 `init.lua`의 `hidutil` 리맵(Karabiner는 사용하지 않음)입니다.

경로: 수신기 버튼 → USB 수신기가 발생시키는 이벤트 → `/usr/bin/hidutil property`를 통해 대상 기기에만 F18 할당 → `hs.hotkey.bind({}, "f18")`. USB 기기 ID와 송출 이벤트는 사용하는 기기에 따라 확인해야 합니다. 키보드 본체에 영향을 주지 않도록 특정 기기에만 할당합니다. 리맵이 휘발되는 환경에서는 Hammerspoon 실행 시와 기기 연결 후에 재적용합니다.

**삭제됨: 상시 리슨(Always Listen)** — `init.lua`에는 `VoiceinListen.startDaemon()`이 `hs.task.new(VOICEIN, nil, {"--listen"})`를 통해 자식 프로세스를 실행하는 잔류 코드가 있습니다. `VoiceinListen.daemonEnabled`는 **`false`**입니다 (2026-08-02 동결). 설령 활성화하더라도, 이 Mac의 `voicein.py`는 `--listen` 인자를 전달하면 "상시 리슨 기능은 2026-09-07에 삭제되었습니다 (결정 D182)"라는 메시지와 함께 종료되므로, 현재의 입력 경로가 아닙니다.

### 고착 감지 및 eventtap 자동 복구

`VoiceinPTT.watchdog` (1초마다):

- `flagWatcher:isEnabled()`가 false이면 `flagWatcher:start()` 실행 (eventtap 자동 복구). 콘솔에 `voicein PTT: eventtap자동복구` 출력.
- 녹음 중이고 시작점이 `"ptt"`이며 현재 Option 키가 떨어져 있는 경우 → `stopRec()` 실행 (고착 감지. 키를 떼는 이벤트를 놓쳤을 때의 복구 로직). 버튼 시작점에는 적용하지 않음 (토글 녹음을 1초 만에 종료해 버리는 실제 버그에 대응하기 위함. 버튼 측의 안전장치는 90초 상한 적용).

Sleep/잠금 해제 (`hs.caffeinate.watcher`의 `systemDidWake` / `screensDidUnlock`) 시에도 `flagWatcher`가 꺼져 있으면 다시 실행.

## 8. 로그인 시 자동 실행

로그인 항목은 `osascript` (System Events의 login item) 및 `~/Library/LaunchAgents`에서 확인한다. 관리자 권한이 필요한 명령은 사용하지 않는다.

음성 관련 LaunchAgent는 `local.voice.aivis.plist`와 `com.voice.seats.plist`이다.

LaunchAgent를 추가한 후에는 **로그아웃 후 다시 로그인**하거나, 그 자리에서 `launchctl bootstrap`을 실행한다.

### Aivis 엔진 — `~/Library/LaunchAgents/local.voice.aivis.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.voice.aivis</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/YOUR/path/to/aivis/macOS-arm64/run</string>
    <string>--host</string><string>127.0.0.1</string>
    <string>--port</string><string>10101</string>
    <string>--disable_sentry</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/tmp/voice-aivis.log</string>
  <key>StandardErrorPath</key><string>/tmp/voice-aivis.log</string>
</dict>
</plist>
```

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.voice.aivis.plist
# 모델 추가 후 재시작
launchctl kickstart -k gui/$(id -u)/local.voice.aivis
```

이 Mac은 `launchctl list`에서 `local.voice.aivis`가 실행 중입니다.

### Aizuchi 및 세션 — `com.voice.seats`

plist는 `~/Library/LaunchAgents/com.voice.seats.plist` → `~/project/tools/sessions/com.voice.seats.plist`입니다. `RunAtLoad`를 통해 `autostart.sh`를 실행합니다. 스크립트 시작 부분은 Aizuchi 관련 내용입니다:

```sh
pgrep -f '[a]izuchi/serve.py' >/dev/null || \
  aizuchi/.venv/bin/python ... start_new_session=True ... aizuchi/serve.py
```

Aizuchi만 필요하다면, 동일한 한 줄을 자신의 로그인 스크립트에 추가하는 것만으로 충분합니다. mlx-lm은 포함하지 않습니다.

---

## 9. hook 등록

### Claude Code — `~/.claude/settings.json`에 2개 추가

Stop 및 Notification. 프로젝트의 `~/project/.claude/settings.json`에는 voice hook가 없습니다 (권한만 있음). 설정은 사용자의 `~/.claude/settings.json`에 추가해야 합니다.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR/project/tools/voice/output/voice-reply.sh",
            "timeout": 5,
            "statusMessage": "voice: 읽어주는 중"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR/project/tools/voice/output/voice-notify.sh",
            "timeout": 5,
            "statusMessage": "voice: 확인 대기 중"
          }
        ]
      }
    ]
  }
}
```

기존의 `hooks` 객체에 추가합니다. 파일 전체를 덮어쓰지 마세요.

### Pi 확장

```sh
mkdir -p ~/.pi/agent/extensions
ln -sf ~/project/tools/pi/extensions/voice.ts ~/.pi/agent/extensions/voice.ts
```

구현 실체는 `tools/harness/voice-pi.ts`입니다. 실제 배치 위치와 링크 대상은 각자의 checkout에 맞춰 확인하시기 바랍니다.

---

## 10. 확인

### tests/ (무음 모드)

상세 절차는 [tests/README.ko.md](tests/README.ko.md)를 참조하십시오. 이 Mac의 구현 경로 기준 예시:

```sh
cd ~/project/project/voice-recipe

VOICE_PY=$HOME/project/tools/voice/output/voice.py \
VOICE_REPLY=$HOME/project/tools/voice/output/voice-reply.sh \
VOICE_IN=$HOME/project/tools/voice/input/voicein.py \
AIZUCHI_SOCK=$HOME/.config/voice/aizuchi.sock \
AIZUCHI_PYTHON=$HOME/project/project/voice/aizuchi/.venv/bin/python \
AIZUCHI_DIR=$HOME/project/project/voice/aizuchi \
  sh tests/run-all.sh
```

순서: `test_paths.py` → `e2e_silent.sh` → `smoke.tsv` → `smoke-dictation.tsv`. 하나가 실패하더라도 끝까지 실행되며, 실패가 있을 경우 종료 코드 1을 반환합니다. `afplay` / `say`는 테스트 중에 교체됩니다.

통과 조건: 경로 테스트 전건 pass. 무음 엔드투엔드(e2e) 테스트 전건 pass. 즉답 smoke 테스트는 의도(intent) ≥ 0.9 이고 none 오작동 ≤ 0.01. 받아쓰기 스타일 테스트는 오작동 ≤ 0.01 이고 누락 ≤ 0.10.

동일한 4개 항목을 경로가 고정된 프로덕션 스크립트로도 실행할 수 있습니다: `sh ~/project/tools/voice/output/tests/run-all.sh`.

## 9. 일본어 이외의 음성 (영어, 중국어, 한국어)

제작자(일본어)는 AivisSpeech를 사용하고 있지만, AivisSpeech는 일본어 전용입니다. 영어, 중국어, 한국어에서는 이와 유사한 역할을 하는 도구를 사용합니다. 후보 비교, 현재 `voice.py`의 언어별 동작, 사전 주의 사항은 [docs/output.ko.md의 「일본어 이외의 목소리」](docs/output.ko.md#일본어-이외의-목소리-영어-중국어-한국어)을 참조하십시오.

공통 후보는 [piper-plus](https://github.com/ayutaz/piper-plus)입니다. 공식 절차에서는 Apple Silicon용 배포 바이너리와 로컬 HTTP API를 안내하고 있습니다. 공식 README에 따라 도입하고, API를 `localhost`에만 bind하여 실행합니다. 사용하는 음성 모델은 코드와 별개의 라이선스이므로, 모델 카드를 통해 상업적 이용, 수정, 배포 조건을 확인하십시오. 영어와 보통화(Mandarin)는 공개된 모델의 언어 및 화자 중에서 선택합니다. 한국어는 코드 지원 여부와 배포된 학습 완료 음성을 혼동하지 마십시오. 사용할 수 있는 한국어 모델을 찾을 수 없는 경우에는 macOS 표준 음성을 사용합니다.

macOS 표준 음성 도입은 시스템 설정 → 접근성 → 콘텐츠 읽어주기(Spoken Content) → 시스템 음성 → 음성 관리(Manage Voices)에서 진행합니다. 대상 언어에서 Enhanced/Premium으로 표시되는 음성이 있다면 선택하여 다운로드합니다. 음성 이름은 OS 버전 및 지역에 따라 다르므로 고정하지 말고, 도입 후 `say -v '?'`를 실행하여 영어, 보통화/지역 중국어, 한국어의 음성 이름을 확인하십시오. 예시는 Samantha/Alex, Ting-Ting/Mei-Jia/Sin-ji, Yuna입니다.

즉답 클립을 만들 때는 `project/voice/aizuchi/reply_map.tsv`의 `lang=en|zh|ko`에 해당하는 행에서 `text`를 그대로 추출하여, 선택한 모델의 로컬 API에 언어 및 음성 ID와 함께 전달합니다. 반환된 음성을 `id`별 WAV 파일로 저장하고, manifest에 언어, 모델, 음성, 파일, 상태 `ok`를 기록합니다. 본문의 `text`는 번역하거나 바꾸지 않고 그대로 사용합니다. macOS `say`를 사용하는 경우에는 동일한 문구를 `say -v '<실제 존재하는 음성 이름>' -o <file.aiff> '<text>'`로 저장한 뒤, `afconvert -f WAVE -d LEI16 <file.aiff> <file.wav>`를 통해 WAV로 변환합니다. Aizuchi 즉답은 현재 `lang`을 음성 선택 단계로 전달하지 않으므로, 언어별 음성으로 변경하기 위한 연결 수정이 별도로 필요합니다.

음성 사전은 읽기 성능을 개선하기 위한 첫 단계로서 언어별로 작성합니다. 영어는 고유 명사 및 약어, 중국어는 간체자/번체자 및 다음자(多音字), 한국어는 외래어, 고유 명사, 숫자를 수집하여 선택한 엔진의 사전 형식/G2P/음소 입력에 등록합니다. AivisSpeech용 `readings.tsv`를 그대로 사용할 수 있는 것은 아닙니다. piper-plus의 공개 벤치마크에는 소형 실행 모델의 파일 용량이 38 MB인 사례가 있지만, 상주 RSS는 게재되어 있지 않습니다. RSS는 모델 용량보다 커질 수 있으므로 공식 값은 미확인 상태로 간주하고, Mac의 활성 상태 보기(Activity Monitor)를 통해 모델 로드 후의 수치를 측정합니다. Kokoro 82M은 영어와 보통화용의 별도 후보이지만, 한국어 공식 음성은 없습니다. 자세한 내용은 [Kokoro](https://github.com/hexgrad/kokoro)를 참조하십시오.

### 음성으로 "다다이마(다녀왔어)"

1. Aivis, 10101, Aizuchi 소켓, Hammerspoon이 실행 중이다.
2. 표시 중인 tmux 세션에서 오른쪽 Option을 누른 채로 "다다이마"라고 말하고 뗀다.
3. 텍스트가 포커스되고, 즉답 의도인 `return-home`이 `speak_intents.txt`에 있으므로, Aivis를 통해 대답("오카에리" 등)이 출력된다.

`quiet_hours` 시간대에는 자동 텍스트 읽기 및 earcon이 억제된다. 수동 read / test는 별개다. 녹음 직후의 `post_rec_grace_sec`, 세션이 vis와 다른 경우, 소켓이 다운된 경우에도 일반적인 대답은 출력되지 않는다.
