[日本語](./README.md) / [English](./README.md) / [中文](./README.zh.md) / [한국어](./README.ko.md)

# Voice recipe

사람은 먼저 이 README를 읽고, 다음으로 [SETUP.ko.md](SETUP.ko.md)를 읽으세요. AI에는 [docs/output.ko.md](docs/output.ko.md), [docs/input.ko.md](docs/input.ko.md), [docs/aizuchi.ko.md](docs/aizuchi.ko.md) 및 [tests/](tests/)를 제공하세요.

Mac에서 Claude Code나 Pi에 음성 레이어를 추가하는 레시피: 음성 입력, 즉각적인 응답, 음성 요약, 그리고 사용자가 보고 있는 자리에서만 재생되는 기능을 제공합니다.

## 한국어

다국어 음성 출력(영어·중국어·한국어)은 [docs/output.ko.md](docs/output.ko.md)의 "일본어 이외의 음성"을 참조하세요.

### 할 수 있는 기능

1. **즉답** — 사용자가 말을 한 직후에 인사, 감사, 사과, 감정 등의 짧은 정형 응답을 출력합니다. 그 외에는 침묵합니다.
2. **요약해서 읽기** — 에이전트의 긴 답변을 음성으로 듣기 좋게 짧게 요약하여 AivisSpeech가 한 문장씩 읽습니다.
3. **현재 보고 있는 세션에서만 출력** — tmux로 여러 세션이 열려 있어도, 현재 표시 중인 세션 외에는 무음 상태를 유지합니다.

**음성 입력** — 자세한 내용과 설정 절차는 [docs/input.ko.md](docs/input.ko.md)와 [SETUP.ko.md](SETUP.ko.md)를 참조하세요. 즉답 분류기는 [docs/aizuchi.ko.md](docs/aizuchi.ko.md)를 참조하세요.

### 준비물

- **Mac**
- **마이크 (작성자 추천)** — a USB wireless microphone (USB 수신기. Mac 상의 이름은 the USB receiver, 48 kHz)
- **AivisSpeech** ([공식](https://aivis-project.com/speech/)) 및 음성 모델. 음성은 각자 [AivisHub](https://hub.aivis-project.com/)에서 가져올 것
- **요약 방법 예시** (요약기는 `apple` / `openai` / `off` 중에서 선택 가능)
  - 자체 제작 Gemma 4 (`gemma-4-26B-A4B-NVFP4-lmfp8`. [tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark)의 공개 레시피. OpenAI 호환 API를 :8890으로 사용. 요약에 약 1.7초 소요)
  - Apple (macOS 온디바이스 LLM)
  - MLX 기반 Gemma 4 E4B (`mlx-community/gemma-4-e4b-it-4bit`. 사고 과정(thinking)은 끔)
  - OpenAI 호환 엔드포인트
- **Claude Code** 또는 **Pi** (세션 종료 및 확인 대기 상태를 hook 하기 위함)

### 환경별 추천

요약에 사용할 AI는 보유하고 있는 환경에 맞춰 선택하세요.

| 환경 | 추천 | 메모 |
|---|---|---|
| DGX Spark 등 GPU 장비가 있는 경우 | 자체 제작 Gemma 4 ([tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark)) | 요약 약 1.7초. 제작자의 구성 |
| Mac 전용 · Apple Intelligence 사용 가능 지역 | Apple 모델 | 별도 설정 불필요 |
| Mac 전용 · 사용 불가능 지역 | MLX Gemma 4 E4B 4bit (`mlx-community/gemma-4-e4b-it-4bit`, 사고 모드 OFF, 지시문은 안 2 사용) | 요약 약 1.9초, 상주 메모리 약 4.5GB. 요점 누락은 안 2 사용 시 0/10 |
| 메모리 8GB Mac · AI를 사용하지 않는 경우 | 규칙 기반 읽어주기 | 아래의 「8GB Mac」 설정 참고. 음성은 AivisSpeech(상주 메모리 약 1GB) 또는 macOS 표준 `say` |
| 이미 Ollama / LM Studio / 기타 OpenAI 호환 서버를 실행 중인 경우 | 해당 연결 대상 지정 | `summarizer`를 `openai`로, `summarizer_base`에 URL 입력 |

#### 메모리 8GB Mac

LLM을 사용하지 않고, `~/.config/voice/config.json`에 다음과 같이 설정한다. `summarizer: "off"`로 요약기를 호출하지 않도록 하고, `rewrite: false`로 재작성도 중단한다. 긴 답변은 `voice.py`의 규칙에 따라 정렬되며, 표의 행이나 경로 등을 제외하고 앞의 2문장을 읽는다 (1문장만 읽도록 하는 설정 키는 없다). AivisSpeech는 약 1GB의 메모리를 상주 점유한다. 더 가볍게 만들려면 AivisSpeech를 사용하지 않고 macOS 표준 `say` 명령어로 폴백(fallback)하도록 설정한다. Aizuchi는 약 0.39GB((internal) 실측치)를 상주 점유하며, 음성 입력 시 `--no-aizuchi`를 붙이면 중지할 수 있다.

```json
{
  "mode": "summary",
  "summarizer": "off",
  "rewrite": false
}
```

이 설정에서는 긴 답변을 내용에 맞춰 요약할 수 없으므로, 앞부분의 문장만으로는 요점을 놓칠 수 있다.

작성자는 일본어 전용인 AivisSpeech를 사용합니다. 작성자의 구성은 자체 호스팅 Gemma 4, a USB wireless microphone (Mac 상의 이름은 the USB receiver, 48 kHz), 아이다 시게루(an AivisHub voice model)입니다.

- **Claude Code** — `tools/voice/output/voice-reply.sh`와 `voice-notify.sh`를 `~/.claude/settings.json`의 Stop / Notification hook으로 등록하세요. 설정 예시와 설치 절차는 [SETUP.ko.md](SETUP.ko.md)를 참조하세요.
- **Pi** — 확장 프로그램 코드는 `tools/harness/voice-pi.ts`입니다. Pi 확장 디렉터리에 설치하고 활성화하는 방법은 [SETUP.ko.md](SETUP.ko.md)를 참조하세요. 응답 완료와 여러 확인 대기 경로를 처리합니다.

### 사용법

구축 사양은 [docs/output.ko.md](docs/output.ko.md), 음성 입력은 [docs/input.ko.md](docs/input.ko.md), 즉답 분류기는 [docs/aizuchi.ko.md](docs/aizuchi.ko.md)를 참조하세요. 이 파일들과 `tests/`를 AI에 제공하세요.

`tests/`의 run-all이 통과하는 조건:

| 항목 | 통과 조건 |
|---|---|
| 경로 테스트 | 전건 pass |
| 무음 통과 테스트 | 전건 pass |
| 즉답 smoke | 의도 ≥ 0.9, none 오탐 ≤ 0.01 |
| 음성 입력 스타일 즉답 | 무언 오작동 ≤ 0.01, 응답 누락 ≤ 0.10 |

### 음성 데이터는 `project/voice-recipe/`에 포함하지 않음

음성 모델과 미리 렌더링한 클립은 `project/voice-recipe/`에 포함되어 있지 않습니다. project의 다른 디렉터리에 재생용 클립이 있습니다. AivisSpeech와 AivisHub 모델은 각자 설치하세요. 테스트 픽스처는 텍스트뿐입니다.

### 실측

다음은 각 기록 시점의 측정값입니다. run-all 통과 조건은 위 표와 같으며, 최초 측정은 수정 전 기록으로 현재의 합격 여부를 나타내는 것은 아닙니다.

출처는 `e4b-prompt.md`·`summ-compare.md`·`runall-first.md` (2026-09-24)입니다. 샘플은 실제 에이전트 답변 10건(각 본문 300자 이상)이며, 요약 temperature는 0.2였습니다.

**즉답** (최초 run-all, 소리 없음): smoke 의도 126/132 = 0.9545, none 오탐 0/120. 음성 입력 방식에서는 무음 오발화 0/600, 응답 누락 35/200 = 0.1750이었습니다. 경로 테스트는 19 pass / 8 fail, 무음 종단 간 테스트는 10 pass였습니다. 합계 2/4이며, 수정 전 수치입니다.

**MLX Gemma 4 E4B** (`mlx-community/gemma-4-e4b-it-4bit`, 사고 기능 끔): 항목당 1.6~2.9초, 최대 메모리 약 4.4GB. 사고 기능을 끄지 않으면 요약이 비게 됩니다. 기본 요약 지시문에서는 주어 바뀜 0건, 요청 추가 0건, 요점 누락 5건, 표/경로 읽기 1건이었습니다. E4B용 지시문 초안 2가 가장 나았으며, 요점 누락·주어 바뀜·요청 추가가 모두 0건이었습니다. 200자를 넘은 항목은 2건(222자, 241자)이었습니다. 세 초안 모두 '200자 이내, 요점 누락 1건 이하, 주어 바뀜 0건, 요청 추가 0건'을 동시에 만족하지 못했습니다.

**OpenAI 호환 Gemma 26B** (동일한 10건, 동일한 기본 지시문): 주어 변경, 요청 추가, 요점 누락, 표나 경로 읽기는 모두 0입니다.
