[日本語](./input.md) / [English](./input.md) / [中文](./input.zh.md) / [한국어](./input.ko.md)

# SPEC-input — 음성 입력 구현 방법

독자는 사용자의 AI 에이전트이다. 이 문서를 읽으면 현재 Mac 음성 입력과 동일한 품질(PTT → whisper.cpp → 치환 → 즉각적인 맞장구(Aizuchi) → 전면 타이핑)을 구축할 수 있다. 값은 2026-09-24 시점의 실제 데이터이다. 추측으로 채우지 않는다. 불명확한 부분은 "불명"으로 표기한다. 즉각 응답 대상 발화의 경우, 동기 재생이 끝날 때까지 본문의 stdout이 반환되지 않아 입력이 지연될 수 있다.

키, 개인 치환표의 내용, 실제 호스트는 작성하지 않는다(형식과 장치로서 필요한 상수만 작성). 상시 리스닝/웨이크 워드는 2026-09-07에 제거됨(결정 D182). 주 경로는 PTT뿐이다.

참조 실체 (`$HOME/project`를 루트로 하는 경로):

- `$HOME/project/tools/voice/input/voicein.py` (명령어 `voicein`, `$HOME/.local/bin/voicein`이 이 파일의 symlink임)
- 동일 디렉토리 내 `glossary.txt` / `replace.txt` / `mishear-candidates.tsv`
- `$HOME/.hammerspoon/init.lua` (핫키 및 타이핑. 설계서에 언급된 `input/hammerspoon-init.lua`의 원본 복사본은 디스크에 존재하지 않음)
- `$HOME/.local/stt/whisper.cpp/build/bin/whisper-cli` (whisper.cpp 1.9.1, commit `2ca53bb45e38748d07b310eeb36245a7157ac882`, `GGML_METAL=ON`)
- `$HOME/.local/stt/models/ggml-large-v3-turbo.bin` (1.5G, ggml Whisper large-v3-turbo)
- `/opt/local/bin/ffmpeg` (MacPorts ffmpeg 8.1)
- `$HOME/project/project/voice/aizuchi/serve.py` 및 `speak_intents.txt`
- 즉각 응답 재생은 `$HOME/project/tools/voice/output/voice.py`의 `speak` (자리·정숙 시간·queue.lock)

---

## 1 구성 및 흐름

외부 전송은 하지 않음. 인식은 로컬 whisper.cpp 사용. 치환 테이블은 로컬 파일. 즉답 분류는 로컬 UNIX 소켓. LLM 보정은 기본적으로 OFF.

```
오른쪽 Option 키를 계속 누르고 있음 (또는 USB microphone 버튼 / CLI)
  → Hammerspoon startRec
      → voice.py stop (음성 재생을 즉시 중단 = barge-in)
      → voicein --ptt start
          → ffmpeg avfoundation 16 kHz / 1ch / wav
          → RMS 값을 /tmp/voicein-ptt.level 에 버퍼 없이 기록
      → 화면 하단 중앙의 파형 필(pill)
키를 뗌 (또는 버튼 2회차 입력 / 90초 상한)
  → voicein --ptt stop
      → ffmpeg에 SIGINT 전송, 최대 5초 대기
      → wav 파일이 24000 바이트 미만이면 빈 값 (입력 실패)
      → whisper-cli (ja, glossary를 --prompt로 사용)
      → 환청 집합 HALLUC이면 빈 값
      → table_fix (슬래시 정규화 → replace.txt)
      → 구술 로그에 추가 (실패하더라도 본문은 유지)
      → 빈 값이 아니면 aizuchi_reply (동기 재생. 재생이 끝날 때까지 다음 단계로 진행하지 않음)
      → 본문을 stdout으로 출력 (끝에 개행 없음)
  → voicein 종료 후, Hammerspoon이 stdout을 포커스된 창에 keyStrokes로 입력
      → 하드웨어 버튼 경로인 경우에만 그 뒤에 Enter 입력
```

역할 분담:

| 구성 요소 | 역할 |
|---|---|
| Hammerspoon | 키 모니터링, 녹음 시작/정지, 파형 표시, 포커스 창에 타이핑, 음성 재생 중단 |
| `voicein.py` | 녹음 프로세스, 인식, 환청 제외, 치환, 로그, Aizuchi 질의 |
| whisper-cli | 16 kHz wav → 일본어 텍스트 변환 |
| `replace.txt` | 오인식 형태 → 정식 표기 (결정론적 방식. 본문을 망가뜨리지 않음) |
| `glossary.txt` | whisper의 initial prompt (어휘 힌트 + 문장 부호 스타일) |
| `mishear-candidates.tsv` | 문맥 의존적 오인식 저장소. 무조건적인 치환에는 사용하지 않음 |
| `aizuchi/serve.py` | 1행 텍스트 → 1행 JSON (intent / score / reply) |
| `voice.speak` | 즉답 재생. 자리(seat), 정숙 시간, 대기 순번 등을 고려함 |

실행 방법:

1. Hammerspoon을 실행한다 (reload 시 `init.lua` 로드. 실행 시 "voicein PTT 가동 중 (오른쪽 Option 누르고 있음)" 메시지 출력).
2. `voicein`이 PATH에 등록되어 있어야 하며, 실체가 `voicein.py`를 가리켜야 한다.
3. `whisper-cli`와 `ggml-large-v3-turbo.bin`이 있어야 한다.
4. ffmpeg가 `/opt/local/bin/ffmpeg`에 있어야 한다 (코드에 해당 경로가 하드코딩되어 있음).
5. 즉답을 출력하려면 `aizuchi/serve.py`가 소켓을 열고 있어야 한다. 로그인 시 실행되는 `tools/sessions/autostart.sh`는 `pgrep -f '[a]izuchi/serve.py'`가 없으면 venv의 python으로 `start_new_session=True` 옵션을 주어 실행한다. 이미 실행 중이면 아무것도 하지 않는다.
6. macOS 권한 설정: 마이크 (ffmpeg), 입력 모니터링 (오른쪽 Option의 eventtap), 접근성 (keyStrokes / Cmd+V).

수동 테스트 명령어 (PTT 제외):

```
voicein                 # 녹음 시작 → Enter로 정지 → pbcopy. stderr에 소요 시간 표시
voicein --paste         # 포커스된 창에 Cmd+V로 붙여넣기 (System Events. 접근성 권한 필요)
voicein --no-fix        # 치환 과정을 건너뜀
voicein --no-aizuchi    # 즉답을 하지 않음
voicein --model NAME    # 절대 경로 또는 ggml-NAME.bin의 약칭
voicein --file wav      # 녹음 없이 기존 wav 사용
voicein --keep          # 녹음 wav를 삭제하지 않음
voicein --ptt start|stop
voicein --listen        # 호환·진단용 인자. 상시 리스닝 기능은 제거되어 사유와 함께 즉시 종료
```

`--llm`은 치환 후 용어 보정을 위해 LLM을 거치는 실험용 스위치다. 기본값은 OFF. `tools/llm`은 제거되었고 `llm_common` import는 fail-open(함수가 None)이다. 보정 단계가 실패해도 본문은 유지된다.

환경 변수:

| 이름 | 기본값 | 의미 |
|---|---|---|
| `VOICEIN_DEV` | `:0` | avfoundation의 `-i` (빈 영상 + 오디오 장치 0) |
| `VOICEIN_FIX_MODEL` | 빈 값 | `--llm` 사용 시 모델명. 비어 있으면 localllm의 current |
| `AIZUCHI_SOCK` | `$HOME/.config/voice/aizuchi.sock` | 즉답 소켓 |
| `VOICE_REPLY_SEAT` | 비어 있으면 표시 중인 tmux 좌석 | `voice.speak`의 좌석 |

임시 파일(PTT): `/tmp/voicein-ptt.wav`, `/tmp/voicein-ptt.pid`, `/tmp/voicein-ptt.level`. `ptt_start`는 먼저 이 3개를 삭제한다. `ptt_stop`은 pid 파일을 삭제하지 않는다(읽어주는 쪽에서 프로세스의 실재 여부를 확인하기 때문).

---

## 2 녹음 및 구분

구분은 VAD가 아니다. 사람이 키를 누르고 있는 동안이 1개의 wav이다. whisper에는 해당 wav 전체를 전달한다.

ffmpeg 공통:

```
/opt/local/bin/ffmpeg -hide_banner -loglevel error -nostdin
  -f avfoundation -i $VOICEIN_DEV
  -ar 16000 -ac 1 -y <wav>
```

stdin은 `DEVNULL`이다. Enter를 입력받아 멈추는 CLI에서 ffmpeg이 Enter를 먹어버리는 사고를 방지한다. 정지는 `SIGINT`(정상 종료). 5초 이내에 끝나지 않으면 `kill`한다.

PTT 전용 추가 필터 (0.1초마다 RMS를 기록. 파형용):

```
-af asetnsamples=1600,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=/tmp/voicein-ptt.level:direct=1
```

`asetnsamples=1600`은 16 kHz 기준 0.1초이다. `direct=1`이 없으면 ametadata가 4 KB를 버퍼링하여 녹음 중인 레벨 파일이 비어 있게 된다. PTT용 ffmpeg은 `start_new_session=True`를 사용한다(Hammerspoon의 자식 프로세스로 분리하여 부모 종료 시 함께 종료되지 않도록 함).

입력 누락: PTT는 wav가 **24000 바이트 미만**(16 kHz 16-bit mono 기준 **0.75초**)이면 무음으로 간주하고 버린다. CLI의 `record()`는 **1000 바이트 미만**에서 종료된다(마이크 권한이나 `VOICEIN_DEV`를 의심해야 함).

핫키 (`$HOME/.hammerspoon/init.lua`):

- **선택한 수정 키(Modifier Key)를 계속 누르고 있음** = 녹음, 뗌 = 인식 후 타이핑. 키코드는 사용 환경의 Hammerspoon에서 확인한다. **Enter는 입력하지 않는다**.
- **기기에 할당된 키** = 토글. 1회 누름: 시작, 2회 누름: 인식·타이핑·**Enter**. 디바운스(Debounce) 0.5초. 인식 중 연타는 무시한다. 시작 플래그는 `recSource="button"`이다.
- **90초** 후 자동 정지(Enter 없음).
- **Cmd+Ctrl+.** = `voice.py stop` (`voice.py`의 입력이 아닌 낭독을 중단).

마이크 버튼을 녹음 조작에 사용할 경우, USB 기기의 VendorID/ProductID와 송출 이벤트를 실기에서 확인한 후 해당 기기에만 키를 할당한다. 리맵핑이 휘발되는 환경에서는 Hammerspoon 실행 시와 기기 연결 후에 재적용한다. 키보드 본체의 동일한 키에 영향을 주지 않는지 확인한다.

오른쪽 Option 키 감시견 (1초마다): eventtap이 끊겼다면 재시작한다. **녹음 중인데 alt 키가 눌려 있지 않으면** 자동으로 정지한다. 이 감시견은 `recSource=="ptt"`일 때만 동작한다. 버튼 시작 방식에 적용하면 1초 이내에 녹음이 종료될 수 있다. 슬립/잠금 해제 시에도 eventtap을 다시 세운다.

콜백은 플래그 판정만 수행하고, 시작/정지는 `hs.timer.doAfter(0, ...)`로 넘긴다. eventtap / timer는 글로벌 `VoiceinPTT`에 담는다(로컬 변수일 경우 GC가 회수하여 감시가 사라질 수 있음).

파형 필(Waveform Pill): 150×34 크기, 화면 하단에서 90 px 위, 중앙 위치. 레벨은 파일 끝 400 바이트에서 `RMS_level=`을 읽는다. 표시 값은 `(db + 48) / 36`을 0.04..1로 클립한다(**-48 dB ~ -12 dB**를 0..1로 매핑). 오른쪽이 최신이며 상하 대칭으로 채워진다. 폴리라인 요소 1개를 0.1초마다 교체한다(바 12개를 개별 업데이트하면 Hammerspoon이 버벅여 키를 떼는 동작을 놓칠 수 있음). 마스코트 이미지 `input/indicator.png`는 **디스크에 없다**. 이미지가 없으면 파형만 표시된다.

녹음 시작 시 `voice.py stop`을 비동기로 spawn한다. 말하기 시작하는 순간 재생을 멈춰 재생음의 에코가 입력에 섞이지 않게 한다.

읽어주기 쪽(`voice.py`)의 구술 음소거는 입력 기능의 일부다:

- 경로 B: `/tmp/voicein-ptt.pid`의 프로세스가 실제로 존재하고 comm이 `ffmpeg`로 시작한다.
- 유예 시간: `/tmp/voicein-ptt.level`의 mtime으로부터 `post_rec_grace_sec`(설정 기본값 **30**)초 동안 자동 발화를 시작하지 않는다. 파일이 없거나 시계에 이상이 있으면 발화하는 쪽으로 처리한다.
- 수동 `read` / `test`는 통과한다. 관측 지점은 `last.kind=skip-dictating`이다.

실제 오디오 장치 번호는 환경에 따라 다르다. 확인 명령:

```
/opt/local/bin/ffmpeg -f avfoundation -list_devices true -i ""
```

2026-07-31 실측 기록에서는 오디오 `[0] the USB receiver`였다(`voicein.py`의 기본 `:0` 주석과 일치). 다른 시점에는 `[1] BlackHole 2ch`도 기록되어 있지만, 이 문서의 대조 시점에는 장치 목록을 얻지 못해 현재 번호와 연결 상태는 미확인이다. 위 목록으로 번호를 확인한다.

## 3 인식 (모델 · 인자 · 언어)

바이너리: `$HOME/.local/stt/whisper.cpp/build/bin/whisper-cli`  
버전: **whisper.cpp 1.9.1** (CLI `--version`). 소스는 https://github.com/ggml-org/whisper.cpp , 실제 HEAD는 `2ca53bb` (2026-07-31). CMake는 `GGML_METAL=ON`, `GGML_METAL_EMBED_LIBRARY=ON`. `whisper-cli`는 `--no-gpu`를 붙이지 않음 (Metal 사용). flash attention의 CLI 기본값은 true.

모델: `$HOME/.local/stt/models/ggml-large-v3-turbo.bin` (파일명 그대로 large-v3-turbo, 크기 1.5G). 입수처는 whisper.cpp에 포함된 `models/download-ggml-model.sh` (Hugging Face `ggerganov/whisper.cpp`의 `resolve/main/ggml-*.bin`). `--model foo` 사용 시 절대 경로가 아니면 `$HOME/.local/stt/models/ggml-foo.bin`을 탐색함.

`transcribe()`가 실제로 전달하는 인자 (이외에는 whisper-cli 기본값):

```
whisper-cli
  -m <model>
  -l ja
  -f <wav>
  --prompt <glossary.txt의 전체 내용>
  -nt
  --no-prints
```

명시하지 않은 기본값 (`whisper-cli --help` 표시값):

| 항목 | 기본값 |
|---|---|
| `--threads` | 4 |
| `--best-of` | 5 |
| `--beam-size` | 5 |
| `--temperature` | 0.00 |
| `--no-speech-thold` | 0.60 |
| `--entropy-thold` | 2.40 |
| `--logprob-thold` | -1.00 |
| `--suppress-nst` | false (비발화 토큰 억제는 사용하지 않음. 환청은 HALLUC으로 처리) |
| VAD 옵션 | 사용하지 않음 |

언어는 **`ja` 고정**. `auto`로 설정하지 않음. 타임아웃은 **120초** (PTT / CLI 모두 동일한 `transcribe`). 실패 시 stderr 마지막 300자를 출력하고 종료. stdout의 strip된 내용이 인식 문장임.

`--prompt`는 glossary 전체 내용. whisper는 프롬프트 끝부분의 약 **224 토큰**을 참조함. 구두점용 자연문은 반드시 마지막에 배치할 것 (§4).

인식은 **CLI 우선**. whisper-server (당시 port 8178)는 속도는 빨라졌으나, temperature 0 고정으로 인해 어휘 집합이 깨지는 A/B 테스트 결과가 있음. 상시 리슨(Listen) 기능 중단과 함께 퇴역. PTT는 server를 사용하지 않음.

동일한 ffmpeg 명령이라도 터미널/launchd의 자식 프로세스일 때는 소리가 깨지고, Hammerspoon의 자식 프로세스일 때는 소리가 명확해지는 실측 결과가 있음 (macOS의 마이크 처리는 앱 단위로 이루어짐). PTT의 ffmpeg는 Hammerspoon → `voicein --ptt start`의 손자 프로세스로 실행함.

## 4 후처리 (환각 제외 · 정형화 · 사전)

순서는 **인식문 → (PTT는 여기서 HALLUC 판정) → 슬래시 정규화 → replace.txt (긴 키부터) → 구술 로그 → (CLI만 선택적으로 LLM) → 맞장구(Aizuchi) / 출력**이다.

### 4.1 환청 제외

무음이나 잡음이 있을 때 whisper가 흔히 내뱉는 패턴입니다. 비교 방식은 `raw.strip().lower()`의 완전 일치 여부입니다. 집합(코드의 `HALLUC`):

```
thank you.
thank you
ご視聴ありがとうございました。
ご視聴ありがとうございました
ありがとうございました。
おつかれさまでした。
ん
（空文字）
次の動画でお会いしましょう。
次の動画でお会いしましょう
また次の動画でお会いしましょう。
また次の動画でお会いしましょう
チャンネル登録お願いします。
チャンネル登録お願いします
最後までご視聴いただきありがとうございました。
最後までご視聴いただきありがとうございました
```

접근 방식: 무음 2초에서 `Thank you.`가 출력된 실측 사례(2026-07-31)와, YouTube 학습 데이터 유래의 마무리 인사·구독 요청·다음 영상 안내가 구술 버퍼에 혼입된 실측 사례(2026-08-02). 영어는 `lower`로 처리합니다. 일본어는 마침표(。)가 있는 경우와 없는 경우를 모두 포함합니다. 문장의 부분 일치로는 제외하지 않습니다("ありがとうございました"가 본문에 포함된 일반적인 발화는 보호함).

PTT: HALLUC인 경우 **빈 문자열을 반환**합니다(타이핑도, 즉각 응답도 하지 않음).  
CLI: 클립보드에는 남습니다. 즉각 응답 직전에만 `text.strip().lower() not in HALLUC` 조건을 사용하여 전송하지 않습니다(`bc66fc9bf`).

### 4.2 문장 부호 및 표기

문장 부호는 ffmpeg의 무음 구간만으로는 결정되지 않는다. glossary가 쉼표로 구분된 단어 목록뿐이라면, 동일한 음성이라도 문장 부호가 하나도 나타나지 않는다 (2026-08-01 실측). 끝에 문장 부호가 포함된 자연문을 추가하면 모두 복구된다. 실제 예시의 끝부분 (이 문장을 형식으로 남겨둘 것):

```
句読点。以下は、句読点を正しく付けた日本語の口述です。今日は、金利の見通しをまとめます。まず、結論から言います。
```

'くとうてん'의 오타 3가지 형태(駆読点・苦読点・苦闘点)는 `replace.txt`를 통해 '句読点'으로 되돌린다.

### 4.3 glossary.txt（형식만）

1개 파일, UTF-8. 쉼표로 구분된 용어들을 나열하고, 마지막에 위의 문장 부호가 포함된 자연문을 배치한다. 내용은 사용자의 어휘이므로 여기에 복사하지 않는다. 추가할수록 whisper가 해당 표기법을 따르게 된다. 용어집이 영문 표기를 유도할 경우, 후속 치환 단계 이전에 영문이 섞여 나올 수 있다.

`transcribe()`는 glossary를 try 없이 연다. 파일이 없으면 인식 전체가 실패한다.

### 4.4 replace.txt（형식만）

```

# 코멘트
오인식형<TAB>정확한 표기
```

빈 줄, `#`으로 시작하는 줄, 탭이 없는 줄은 무시합니다. 탭은 맨 앞의 1개만 기준으로 분할합니다(오른쪽에 탭이 남아있더라도 정확한 표기 쪽으로 포함). 적용은 **키의 글자 수가 긴 순서대로** 수행합니다('클로드코드'를 '클로드'보다 먼저 처리). 부분 문자열 `str.replace`를 사용합니다. 개인적인 행은 포함하지 않습니다. 기계적으로 처리하며 문맥을 고려하지 않으므로, 실제 존재하는 단어와 충돌하는 치환은 포함하지 않습니다.

### 4.5 슬래시 커맨드

음성으로 "슬래시 클리어" → `/clear`. 대상 8개 단어 (`_SLASH_CMDS` 코드):

`クリア` `モデル` `エフォート` `コンパクト` `フック` `コンフィグ` `ヘルプ` `リワインド`  
→ `/clear` `/model` `/effort` `/compact` `/hooks` `/config` `/help` `/rewind`

`table_fix`의 맨 앞에서, 커맨드 단어 직전의 구분자만 삭제하여 붙여쓰기 형태로 만든다:

```
SLASH_SEP_RE = スラッシュ?[\s　、。，．・･]*(?=(?:クリア|モデル|...))
```

치환 후의 테이블에는 붙여쓰기 1행만 있으면 충분하다 (보험용으로 공백 형태나 가운뎃점 형태가 남아 있어도 무방함). 새 커맨드는 (1) `_SLASH_CMDS`에 가타카나 1단어 (2) `replace.txt`에 붙여쓰기 1행을 등록한다. 커맨드 단어가 이어지지 않는 "슬래시, 즉 사선"은 트리거되지 않는다.

기존 운영 방식(붙여쓰기·공백·가운뎃점의 3가지 형태를 테이블에 나열)은 문장 부호가 부활하면서 "슬래시, 모델"과 같은 패턴이 생겨나 실패했다. 8개 커맨드 × 구분자 변형 × 어두 2가지 형태 = 총 176가지 경우의 수 중, 3가지 형태를 등록하는 방식으로는 17가지만 잡아낼 수 있었다 (레드존 테스트로 실측).

### 4.6 mishear-candidates.tsv (형식만)

문맥 의존적/다의어 저장소. 무조건 치환할 경우 실제 단어와 충돌하여 원래 단어를 망가뜨릴 수 있는 항목을 우선적으로 여기에 배치한다. 승격되면 `replace.txt`로 이동하고, 상태 열을 "승격됨"으로 변경한다.

```
오인식형<TAB>의도한 단어<TAB>문맥 메모<TAB>날짜<TAB>상태(후보/승격됨/기각)
```

코드는 읽지 않는다. 학습용 대장.

### 4.7 구술 로그

`table_fix`를 반드시 통과해야 한다. 실패하더라도 본문은 누락하지 않는다 (fail open).

- 위치: `$HOME/.config/voicein/dictation/YYYY-MM.tsv`
- 컬럼: `ts` (ISO8601, 초, 타임존 포함) / `source` (`ptt` | `cli` | `unknown`) / `raw` / `fixed` / `rules_hit` (`bad=>good` 쉼표 구분)
- 새 파일의 첫 번째 행: `# ts\tsource\traw\tfixed\trules_hit`
- TAB 및 줄바꿈은 공백 1개로 치환한다. `raw`가 비어 있으면 기록하지 않는다.

### 4.8 LLM 교정 (기본값 Off)

`--llm`이 설정되어 있고 `--no-fix`가 아닐 때만 실행됩니다. 연결 대상은 코드상 `http://127.0.0.1:8090` (OpenAI 호환 localllm)입니다. 3초 동안 alive 상태를 확인하며, 응답이 없으면 원문을 유지합니다. `think=False` 설정이 필수입니다. 출력 길이가 원문의 0.5~2.0배를 벗어나면 원문을 유지합니다. `<think>...</think>` 태그는 제거합니다. `tools/llm` 제거 후에는 import 실패로 인해 항상 원문이 출력됩니다. 설계서에 남아 있는 "gemma4:12b / 127.0.0.1:11434"는 이전 설정이며, 현재 코드는 8090을 사용합니다. 실제 적용 시 본문이 파괴되는 현상이 확인되었으므로, 기본값은 치환표(replacement table)를 사용합니다.

## 5 출력 (붙여넣기 · 맞장구)

### 5.1 붙여넣기

PTT / 버튼: Hammerspoon이 `voicein --ptt stop`의 **stdout을 `hs.eventtap.keyStrokes`**로 처리합니다. 클립보드를 사용하지 않습니다. exit 0 이면서 비어 있지 않을 때만 입력합니다. 비어 있거나 0이 아니면 칩(pill) "・・・"을 0.8초간 표시합니다. 버튼 경로만 `usleep(150000)` 실행 후 `return` 합니다. 오른쪽 Option 키와 90초 상한선 설정 시에는 Enter를 입력하지 않습니다.

CLI: `pbcopy`에 전체 텍스트를 전달하고, stdout으로도 출력합니다 (이때 끝에 개행 문자가 포함됩니다). `--paste`는 다음과 같습니다.

```
osascript -e 'tell application "System Events" to keystroke "v" using command down'
```

상시 리스닝용 `VoiceinListen.typeFile` (본문 파일, nonce 흔적, 포그라운드 bundleID 허용 목록, Enter 직전 재검사)은 init.lua에 남아 있지만, `--listen`이 즉시 종료되므로 메인 경로에서는 호출되지 않습니다.

### 5.2 Aizuchi로의 전달

텍스트화 직후, 본문을 놓치지 않고 질의한다. 실패는 모두 무시한다.

1. 텍스트가 비어 있거나 소켓 파일이 없으면 return.
2. UNIX 스트림, **타임아웃 0.2초**.
3. 전송할 1행: `" ".join(text.split()) + "\n"` (공백 정규화).
4. 수신: 개행 문자까지. 버퍼가 100000 바이트를 초과하면 return.
5. JSON 1행. `intent`와 `reply`.
6. `intent`가 발화 집합에 포함되고, 동시에 `reply`가 비어 있지 않을 때만 `voice.speak(reply, purpose="done")` 호출.
7. `VOICE_REPLY_SEAT`가 비어 있으면 `voice.current_client_seat()`를 설정한 후 speak.

발화 집합의 원본은 `$HOME/project/project/voice/aizuchi/speak_intents.txt` (`#` 및 빈 줄 제외, 1행 1 의도). 2026-09-24 30:

```
hello morning night-sleep goodbye otsukare return-home leaving
first-meet reunion how-are-you welcome-in care thanks apology
joy moved surprise encourage praise empathy-here sad lonely
worry relief angry calm-down embarrassed love laugh peaceful
```

인사·감사·사과·감정. 지시·질문·none은 발화하지 않는다. 파일을 읽을 수 없거나 비어 있으면 voicein 내의 예비 집합을 사용한다. 예비 집합은 31개 단어로 구성되며 원본과 차이가 있다 (§6).

소켓 측 프로토콜 (`serve.py`): 1개 연결에 발화를 1행씩 보내면, 각 행에 대해 1행의 JSON을 응답한다.

```
{"intent": str, "score": float, "id": str, "reply": str, "lang": str}
none / 임계값 미만: intent=none, reply=""
예외: {"intent": "error", "error": "..."}
```

분류 모델은 `aizuchi/onnx/model-int8.onnx`, CPUExecutionProvider, tokenizer 포함, `max_length=96`. 임계값 파일 `onnx/threshold.txt`의 값은 **0.5** (없으면 코드 기본값 0.5). 임계값 미만은 none 처리한다. reply는 `reply_map.tsv` (`intent<TAB>lang<TAB>text<TAB>id`)에서 발화 언어를 가져오며, 없으면 ja, 랜덤으로 1개를 선택한다.

voicein은 `afplay`나 `respond.py`를 호출하지 않는다. 재생은 `voice.speak`만 사용한다. PTT 직후에는 `post_rec_grace_sec` (기본값 30) 동안 `skip-dictating` 상태가 되어, 자리 판정 전에 즉답을 하지 않고 침묵할 수 있다. 이는 입력 측에서 제외하지 않았다.

`--no-aizuchi` 옵션을 사용하면 질의 자체를 수행하지 않는다.

## 6 빠지기 쉬운 함정

실측을 통해 확인한 사항들. 동일한 장치를 구성할 때 미리 방지할 것.

1. ffmpeg에 stdin을 전달하면 CLI의 Enter 입력을 ffmpeg가 가로챈다. `-nostdin`과 `stdin=DEVNULL` 사용.
2. ametadata의 기본 4 KB 버퍼 때문에 녹음 중인 레벨 파일이 비어 있음. `direct=1` 사용.
3. canvas 바를 12개씩 개별 업데이트하면 Hammerspoon이 버벅이며 키 뗌(key release) 이벤트를 놓친다. 폴리라인 1개로 처리.
4. `hs.timer` / `hs.eventtap`을 지역 변수에 두면 GC가 회수해 버린다. 전역 변수 수준으로 고정.
5. "녹음 중인데 오른쪽 Option 미입력" 감시 로직을 버튼 기반으로 만들면, 토글 녹음이 1초 이내에 죽는다. `recSource`로 분리.
6. glossary가 단어 리스트로만 구성되면 구두점이 전혀 없다. 끝에 구두점이 붙은 자연문 형태여야 함.
7. 슬래시 표기법의 변형을 표에 하나씩 추가하는 방식은 상위 단계(구두점 등)가 바뀌는 순간 무너진다. 정규화하여 압축된 형태 1개로 관리.
8. LLM 보정은 용어를 수정하는 것보다 본문을 망가뜨리는 경우가 더 많다. 기본은 치환 테이블(replacement table)을 사용하고, 실패 시 원문 유지.
9. YouTube 유래의 맺음말·구독·Thank you 등이 무음으로 섞여 들어온다. HALLUC 완전 일치 시에만 버릴 것. 부분 일치로 처리하지 말 것.
10. 동일한 ffmpeg라도 터미널/launchd 환경에서는 소리가 깨지고, Hammerspoon 환경에서는 명료하다. PTT는 HS의 자식 프로세스임.
11. whisper-server화는 지연 시간(latency)을 줄여도 품질이 떨어졌다. PTT는 CLI를 사용. 가속화하기 전에 A/B 테스트를 먼저 할 것.
12. 상시 리스닝(always-on listen)을 중단하려면 플래그뿐만 아니라 모든 실행 경로(끝부분의 `doAfter` 무조건 start 등)가 해당 플래그를 확인해야 한다.
13. 구술 뮤트(dictation mute)를 listen 상주 플래그 쓰기에 의존하면, listen이 동결됨과 동시에 "말하는 도중에 낭독이 시작되는" 현상이 발생한다. 녹음 프로세스와 level의 mtime을 확인할 것.
14. `ptt_stop`은 pid 파일을 삭제하지 않는다. 파일 존재 여부만 확인하면 녹음 종료 후에도 영구 뮤트 상태가 된다. comm가 ffmpeg인지까지 확인할 것. PID 재사용 방지 대책 필요.
15. 녹음 종료 후 인식·타이핑·확인 중에는 프로세스가 존재하지 않는다. `post_rec_grace_sec` 30초가 없으면 그 사이에 자동 발화가 시작된다. 반대로 즉답(immediate response) 시에도 이 윈도우 내에서 `skip-dictating`이 된다.
16. `anullsrc`나 wav 주입 시 `-re` 옵션이 없으면 실시간(real-time)으로 동작하지 않는다. 테스트 결과가 왜곡됨.
17. TCC의 "유효(Enabled)" 표시가 늦게 나타나 토글 상태와 반대로 보일 때가 있다. 실측(눌렀을 때 글자가 나오는지)이 정답이다.
18. `VOICEIN_DEV` 번호는 기기마다 다르다. `:0`을 하드코딩하면 다른 마이크를 꽂았을 때 작동하지 않는다. `list_devices`로 가져올 것.
19. CLI 경로는 HALLUC을 클립보드에 남긴다. PTT는 남기지 않는다. 즉답 스킵과 입력 스킵을 혼동하지 말 것.
20. `speak_intents.txt` 원본 30개와 voicein 백업 집합은 일치하지 않는다. 원본에만 있는 것: `how-are-you`. 백업에만 있는 것: `invite`, `meetup`. 파일이 읽히는 한 원본이 우선한다.
21. `input/hammerspoon-init.lua`, `slash_test.py`, `replace-stats.py`, `indicator.png`는 README / 설계서에서 가리키지만 현재 디스크에는 없다(테스트와 정본 사본은 제거됨). 실제 init.lua는 `$HOME/.hammerspoon/init.lua`다.
22. `--listen`을 실제 기능으로 구현하면 진입점이 없는 상주 프로세스가 시작된다. 현재는 사유를 표시하고 즉시 종료한다.
23. avfoundation의 `-i`는 `:N`(영상은 비우고 오디오는 N) 형식이다. `N`만 쓰면 영상 장치를 잡으려 한다.
24. glossary가 없으면 인식 전체가 예외로 실패한다. replace.txt가 없으면 치환만 건너뛰고 본문은 유지된다. 두 동작은 비대칭이다.

## 7 합격 기준

입력 전용인 `slash_test.py` / `listen_test.py`는 현재 트리 내에 없습니다. 합격 여부는 다음에서 확인합니다.

### 7.1 자동 (무음)

`$HOME/project/tools/voice/output/tests/e2e_silent.sh` 중 Aizuchi 행 (가짜 소켓, 재생 스텁, seat `test`, mark `t`):

| 케이스 | 기대 결과 |
|---|---|
| `aizuchi-thanks` ("ありがとう" → intent `thanks` + 비어 있지 않은 reply) | 재생 함수가 호출됨 |
| `aizuchi-none` | 호출되지 않음 |
| `aizuchi-intent-mute` (`deploy` 등 speak 집합 외) | 호출되지 않음 |
| `aizuchi-sock-down` | 호출되지 않음 |

`test_paths.py`의 `test_dictating_skips`: `dictating()`이 참일 때 자동 발화는 `last.kind=skip-dictating`이며, 재생 프로세스가 없음.

즉답 분류기(Classifier) 자체의 수치 (`aizuchi/smoke.tsv` / `smoke-dictation.tsv`, `run-all.sh`): 의도 정확도 ≥ 0.9, none 오탐(False Positive) ≤ 0.01. 구술 스타일은 speak 집합으로의 오발화 ≤ 1%, 응답 누락 ≤ 10%. 이는 분류기 측의 수치임. voicein의 전달은 위의 4개 행을 따름.

`voicein.py`는 `python3 -m py_compile`을 통과함.

슬래시 정규화 (`slash_test.py`가 없으므로 동일한 함수를 직접 호출):

- "슬래시, 모델" → 치환 후 `/model` (쉼표가 있어도 붙여쓰기 형태로 수렴).
- "슬래시, 즉 사선"은 "슬래시"가 남음 (명령어 단어가 이어지지 않음).
- `_SLASH_CMDS`의 8개 단어 모두 공백, 쉼표, 가운뎃점, 붙여쓰기 여부와 상관없이 `/...`로 변환됨.

HALLUC: `Thank you.`와 `ご視聴ありがとうございました。`를 PTT 상응 값으로 빈 값 처리함. 일반 문장은 빈 값으로 처리하지 않음.

`table_fix`는 긴 키를 먼저 배치함 ("클로드코드"가 "클로드"에 의해 잘리지 않도록 함). replace의 개별 행을 사용할 필요 없이 테스트용 짧은 표면으로 충분함.

### 7.2 수동 확인 (실제 마이크 사용. 소리를 낼 경우 자리와 조용한 시간대에 주의)

1. `ffmpeg -f avfoundation -list_devices true -i ""` 명령어로 오디오 번호를 확인하고, `VOICEIN_DEV`를 설정한다.
2. Hammerspoon 실행. 오른쪽 Option 키를 계속 누르고 있으면 녹색 필(pill)이 나타나고, 떼면 "인식 중" 상태가 되며 전면 입력창에 글자가 입력된다. Enter는 입력되지 않는다.
3. 0.5초만 누르고 떼기 → 아무것도 입력되지 않아야 함 (0.75초 임계값).
4. 무음 상태로 2초간 누르기 → "Thank you."가 입력창에 나타나지 않아야 함.
5. "슬래시 클리어" 입력 → `/clear`가 입력창에 나타난다.
6. `$HOME/.config/voicein/dictation/YYYY-MM.tsv` 파일에 `source=ptt` 행이 추가된다. `raw` / `fixed` / `rules_hit`를 포함하여 총 5개 열로 구성된다.
7. 소켓이 활성화된 상태에서 인사를 했을 때, `speak_intents.txt`에 정의된 의도라면 `voice.speak`까지 도달한다 (30초 유예 시간 내에 `skip-dictating`이 발생할 경우, 창이 열린 후 또는 CLI `--file`을 통해 확인). 명령문에서는 소리가 나지 않는다. 소켓을 중단하면 본문 타이핑 기능은 유지되지만, 즉각적인 응답은 불가능하다.
8. 녹음 중에 읽어주기(TTS)를 실행하면 `skip-dictating`(자동 경로)이 작동한다. `voice.py stop`은 시작 시점에 이미 호출된다.
9. `voicein --listen`은 에러와 함께 즉시 종료되며, 데몬처럼 상주하지 않는다.

7.1과 7.2가 모두 충족되면 현재 입력과 같은 수준이다.
