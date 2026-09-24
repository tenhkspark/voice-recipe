[日本語](./output.md) / [中文](./output.zh.md) / [한국어](./output.ko.md)

# 음성 환경 구축 방법 사양서 (AI 에이전트용)

Mac 1대만으로 구동되는 「듣기·즉시 응답·요약·말하기」 음성 환경을, 처음 접하는 AI 에이전트가 동일한 형태로 구축할 수 있도록 하기 위한 사양입니다. 키(Key), 실제 주소, 외부 서비스의 음성 파일에는 의존하지 않습니다 (각자 준비한 것으로 대체해야 합니다).

## 1. 구성 및 흐름

```
음성 입력(PTT→텍스트)
   ├─→ Aizuchi(즉답: 정형 응답인지 none인지 수 ms 내에 판정) → 재생
   └─→ 본 응답(에이전트의 답변 본문)
         → 요약 LLM(긴 문장을 듣기 편하게 단축, 80자 초과 시)
         → AivisSpeech(한 문장씩 합성) → 재생
         (캐싱 팩: 문구가 일치하면 음성 파일을 즉시 재생)
```

이 구성에는 외부 유료 TTS(ElevenLabs 등)가 필요하지 않습니다. 합성은 모두 사용자의 Mac에 설치된 AivisSpeech로 완결됩니다.

- **듣기**: 푸시 투 톡(PTT) 전용입니다. 누르면 녹음, 떼면 whisper.cpp로 텍스트화한 뒤 치환표(오인식→정정 표기)를 적용합니다. PTT 경로에서는 voicein이 인식된 문장을 표준 출력(stdout)하고, Hammerspoon이 해당 문자열을 전면 입력창에 직접 타이핑합니다. 상시 리스닝 및 웨이크 워드 기능은 지원하지 않습니다.
- **즉답 Aizuchi**: 발화 → 55 의도를 ONNX int8 상주 서버에서 ~5ms 내에 판정하며, 신뢰도가 임계값 미만이면 `none`으로 처리합니다. `none`이면 아무것도 하지 않습니다. 분류기는 `modernbert-ja-130m` 기반의 CLS + 선형 헤드(126MB int8, 상주 RSS 약 389 MiB, 기동 약 0.27초. tokenizers 단독화 후 실측치)를 사용합니다.
- **요약 LLM**: 기본값은 macOS 표준 온디바이스 LLM(Foundation Models)입니다. OpenAI 호환 엔드포인트로 전환도 가능합니다(`summarizer: apple|openai|off`). 두 방식 모두 실패할 경우 원문의 앞 2문장으로 대체합니다.
- **목소리 AivisSpeech**: 로컬 TTS 엔진(화자는 설정의 `speaker_id`). 합성이 완전히 실패했을 때만 `say`로 폴백(fallback)합니다.

## 2. 연결 지점

### hook 입력 (stdin JSON)

| 트리거 | 호출 방식 |
|---|---|
| Claude Code Stop | `voice-reply.sh` → `voice.py reply --seat <席名>`。transcript_path가 CC 형식(message.role이 user/assistant인 행이 포함된 JSONL)인 경우에만 실행. 본문 = 직전 user 발언 이후의 assistant 본문. 80자 초과 시 요약 |
| Claude Code Notification | `voice-notify.sh` → `voice.py hook`。"<seat>, 확인 대기 중"만 출력 |
| Pi 확장 | `voice.ts`。응답 완료는 `agent_settled`(자동 지속이 없는 확정 시점), 확인 대기는 `ui_prompt_start`(kind=confirm), 비대화 시에는 `tool_execution_end`(isError) → 동일하게 `voice.py reply --seat` 호출. 본문은 assistant 전체 내용을 CC 형식의 임시 JSONL로 만들어 transcript_path를 통해 전달 |
| 수동 | `voice.py say "텍스트"` (stdin 가능), `read` (last.txt 전체 내용·seat gate 통과), `test` (테스트 재생) |

게이트의 중요한 선별: Grok 등 CC 이외의 에이전트가 `~/.claude/settings.json`의 hook을 실행하더라도, transcript가 CC 형식으로 되어 있지 않으면 exit 0로 종료하며 아무 작업도 하지 않음. role 판정은 파일 전체를 대상으로 함 (파일 시작 부분의 메타 행이 40행을 초과하더라도 허용).

### 소켓 형식 (Aizuchi 상주)

- UNIX 소켓 (예: `~/.config/voice/aizuchi.sock`). 1 연결/발화당 1줄의 JSON을 반환
- 응답: `{"intent": str, "score": float, "id": str, "reply": str, "lang": str}`. `intent:"none"`이면 빈 id/reply는 답변이 없다는 뜻이다. 그 외 의도에서 두 값이 비어 있으면 정형 답변 후보가 없다는 뜻이며, 클라이언트는 재생을 건너뛴다. none 또는 임계값 미만인 경우 `intent:"none"`, 빈 id/reply 반환
- 서버 측 추론 예외는 `{"intent":"error","error":...}`로 반환됨. PTT 클라이언트는 에러 응답이나 발화 허용되지 않은 의도(intent)를 재생하지 않으며, 로컬 추론으로 전환하지도 않음. 실패하더라도 일반적인 PTT 인식 본문은 표준 출력(stdout)으로 계속 반환함 (함정 7.2 참조)

### 설정 키 (config.json 주요 부분)

- `mode`: `off | earcon | summary | full` (기본값 summary = 요약해서 읽기)
- `seat`: 고정 좌석명. 비어 있을 경우 "현재 표시 중인 tmux 좌석"과 일치할 때만 알림이 울림 (4장 참조)
- `quiet_hours`: `[시작, 종료]` (기본값 23:30–08:00). 완전 뮤트
- `night_brief_hours`: 야간에는 알림을 울리되 짧게 출력 (기본값 30자·1문장). quiet 설정 범위 밖에서만 적용됨
- `summarizer`: `apple | openai | off`, `summarizer_base`: OpenAI 호환 URL
- `speaker_id` (AivisSpeech 음성. 변경 불가), `speech-styles.json` (purpose별 속도·간격·볼륨만 변경 가능)
- `pack`: 미리 만들어둔 음성 팩 (enabled・model・voice・lang). `model`은 팩의 생성 원천, `voice`는 음성 디렉토리를 가진 생성 원천의 화자 ID (AivisSpeech처럼 음성 필드를 사용하지 않는 모델은 빈칸). 현재 manifest에는 `eleven_v3`, `eleven_multilingual_v2`, `aivis-aida`의 ok 행이 있음. 프레이즈는 NFKC 정규화 후 문장 부호와 공백을 제거하여 대조하며, 일치할 경우 음성을 즉시 재생함. 인덱스에는 읽기 보정 전후의 표기를 등록함

## 3. 요약 지침 및 금지 사항

작가의 환경에서는 요약에 자체 제작한 Gemma 4를 사용하고 있다. 가중치는 `gemma-4-26B-A4B-NVFP4-lmfp8`이며, 공개 레시피는 https://github.com/tenhkspark/gemma4-spark (DGX Spark에서 `serve.sh up` 실행, :8890에서 OpenAI 호환 API 제공)이다. 요약 1건당 약 1.7초가 소요된다. Spark가 없는 사용자는 Apple의 모델(macOS 표준 온디바이스 LLM) / MLX의 Gemma 4 E4B(아래 안 2의 지침) / 임의의 OpenAI 호환 엔드포인트로 대체할 수 있다.

원칙: **주어를 바꾸지 말 것(화자는 어시스턴트) ・ 요청을 임의로 추가하지 말 것 ・ 표나 경로를 읽지 말 것**. 어시스턴트가 "하겠습니다"라고 말한 것을 사용자에 대한 요청으로 바꾸는 것이 최악의 실패 사례다. 원문 끝에 질문이 있는 경우에만 그것을 마지막에 남긴다.

Gemma 26B용 (`voice.py`의 SUMMARY_PROMPT, OpenAI 호환 API 요청 시 temperature 0.2, max_tokens 400):

```
次の文章は AI アシスタントがユーザーに返した返事。耳で聞いて分かるように、
要点だけを日本語の話し言葉で2〜3文、合計120字以内にまとめて。
表・箇条書き・コード・パス・記号は読み上げず、中身を言葉にする。
元の返事に依頼や質問がある時だけ、その内容を最後に入れる。無ければ作らない。
話し手はアシスタント。主語を変えない。
アシスタントがやると言ったことをユーザーへの依頼や質問に変えない。
まとめた文だけを出力する。

# 返事
{text}
# まとめ
```

小型モデル（Gemma 4 E4B 4bit 等）用の案 2（同じ試料 10 件で「欠け 0・主語 0・作り足し 0」を達成。字数超過 2/10 のみ）:

```
次の文章は AI アシスタントがユーザーに返した返事。耳で聞いて分かる話し言葉で、120字から250字にまとめて。250字を超えてはいけない。改行や箇条書きにしない。
残すのは次だけ。表の行は全部読まない。
- 結論。
- 数字を出すなら、その理由も同じ文で。
- 誰が何をやるか。名前と作業を言い、番号で呼ばない。
- 残るものと消えるもの。
- 原文の最後に質問が一つあるときだけ、最後にそれだけ。
原文に無い質問、命令、選択肢は足さない。話し手はアシスタント。主語を変えない。パスと記号は読まない。まとめた文だけを出力する。

# 返事
{text}
# まとめ
```

주의: 사고(thinking) 기능의 On/Off는 `voice.py`의 요약 요청 시 지정하지 않는다. mlx-lm의 기본값은 사고 On 상태이므로, 사고 기능을 끄려면 연결 대상 서버의 실행 설정(예: `--chat-template-args {"enable_thinking":false}`)에서 지정해야 한다. 이는 서버 측에서 해당 설정을 지원하고 실행 설정이 적용된 경우에만 해당된다. 실측 기록에 따르면, 기능을 끄지 않으면 사고 과정에서 `max_tokens` 300을 모두 사용해 버려 본문이 비어 있게 된다. 너무 짧게 만들라는 지시(180자 이내, 4문장 이내)는 요점이 누락되는 현상이 실측되었으므로 사용하지 않는다. 품질 측정 방식은 실측 기록 10건을 바탕으로 '요점 누락·주어 바뀜·요청 내용 추가·글자 수'를 카운트한다(summ-compare 방식).

## 4. 세션 판정

여러 에이전트 세션(tmux 세션)이 있다는 전제:

1. `config.seat`가 설정되어 있으면, **해당 세션에서만** 소리가 발생함
2. 설정이 비어 있으면, 트리거가 발생한 세션(`TMUX_PANE`에서 `tmux display-message -p -t <pane> '#S'`로 확인)이 **현재 표시 중인 클라이언트의 세션**과 일치할 때만 소리가 발생함
3. 세션을 가져올 수 없거나 일치하지 않으면 무음 처리(로그 `kind=seat-skip`). **타겟이 비어 있는 tmux는 다른 세션 이름을 반환**하므로, `TMUX_PANE`가 비어 있으면 입구에서 차단함 (경험했던 문제 7.1)
4. 예외 사항: 수동 `read` / `test` / `--no-play`. 킬 스위치 `CLAUDE_VOICE_MUTE`는 모든 경로에서 무음 처리됨

## 5. 1문장씩 합성 및 실패 시 처리

- 요약문을 문장 단위로 나누어, AivisSpeech로 한 문장을 합성하여 재생을 시작하고, 재생 중에 다음 문장을 합성하여 순차적으로 재생한다 (응답끼리 겹치지 않음. 재생 중에는 락(lock) 유지).
- 미리 만들어둔 팩(pre-made pack)은 정규화된 텍스트가 일치하는 구절의 경우, 음성을 합성하는 대신 즉시 재생한다 (5.5절 참조).
- 문장 중간에 Aivis가 합성 실패한 문장은 **건너뛴다** (목소리가 섞이는 것을 방지). 모든 문장이 실패했을 때만 `say` 폴백(fallback)으로 전체 문장을 읽는다.
- earcon (짧은 신호음): done/read, attention, error에 각각 다른 음을 사용한다. attention/error는 중첩 재생이 가능하며, done은 재생 중일 경우 skip한다.
- 중복 억제 (동일한 마지막 문장은 30분 윈도우 내에서 재생되지 않음) · 간격 게이트 (기본 5초 이내의 두 번째 요청은 음성이 아닌 earcon으로 처리) · 낭독 중에는 자동으로 무음 처리

### 5.5 미리 만들어둔 음성 팩(Pre-made Voice Pack) 제작 방법

미리 만들어둔 팩이란 phrases(응답 문구)의 텍스트를 기반으로 생성한 즉시 응답용 음성입니다. 현재 `project/voice/manifest.tsv`에는 `aivis-aida`의 ok 행이 2,243개 있으며, `eleven_v3`와 `eleven_multilingual_v2` 행도 존재합니다. `voice.py`의 기본 pack은 `eleven_v3`이므로, 사용할 팩은 `model`·`lang`·`voice`가 manifest와 일치하도록 설정해야 합니다. 로컬 생성 예시에서는 AivisSpeech를 사용할 수 있지만, 모든 팩이 AivisSpeech로 제작되었다는 의미는 아닙니다.

제작 방법:

1. phrases.tsv(category / id / ja / en / zh / ko)를 준비합니다. id는 언어 공통입니다.
2. 각 문구를 AivisSpeech API(`POST /synthesize` 등 로컬 HTTP API)를 통해 하나씩 합성하고, mp3 또는 wav 형식으로 `pack/<lang>/<id>.<ext>`에 저장합니다.
3. 합성된 행을 manifest(id·파일·글자 수·화자)에 `ok`로 기록합니다. 재개 시에는 manifest의 ok 행을 건너뜁니다(멱등성 보장).
4. voice.py의 `pack` 설정(enabled·model·voice·lang)으로 불러옵니다. 대조 작업은 NFKC 정규화 후 문장 부호와 공백을 제거하여 수행하며, 읽기 보정 후의 표기도 대상에 포함합니다. 일치하지 않으면 일반적인 문장 단위 합성 단계로 넘어갑니다.

## 6. 즉답 의도 분류 및 학습 데이터 구축 방법

1. **의도 압축**: 모든 응답 프레이즈 중 '정형화된 응답이 가능한 것'만 선택한다. 실적상 인사·감사·감정 계열은 전체를 포함하고, 운영 계열은 확인 대기·실행 중·완료 등 짧은 정형 문구로 압축하여 55개 의도로 구성한다.
2. **발화 의도 추가 압축**: 현재 분류 레이블은 55개 의도이며, 발화 허용 리스트는 32개 의도이다. 구두 명령에 포함된 지시나 질문에는 즉답하지 않는다. 허용 리스트(1개 의도당 1행의 텍스트 파일)에 포함된 의도만 발화한다. **파일이 없다면 모든 의도를 발화하는 것이 아니라 공집합으로 처리한다** (7.4절의 시행착오 참고).
3. **학습 데이터는 자신의 LLM으로 생성**: 각 의도에 대해 다국어(ja/en/zh/ko) × 표현 변형(variant)을 적용하여 발화 예시를 생성한다. `none`은 '정형 문구로 대응할 수 없는 발화'를 별도로 생성한다.
4. **생성과 동일한 모델로 검사**: 해당 응답이 자연스러운지 / `none`이 정말로 정형 문구로 대응할 수 없는지 전수 판정한다. 판정에 실패한 예시와 중복을 제거하여 데이터셋을 구성한다. 실제 행수는 `dataset.jsonl` 28,933행, `train.jsonl` 32,560행, `dev.jsonl` 3,645행이다 (train/dev 합계 36,205행으로 약 9:1 비율). 이 파일들 간의 행수 차이의 원인과 생성 전의 정확한 행수는 확인된 실물 데이터만으로는 단정하지 않는다.
5. **학습**: CLS + Linear Head, AdamW 2e-5, 약 3 epoch (130M 클래스 기준 Mac에서 40분 미만). 임계값(threshold)은 dev 세트의 'none 오탐 최소화'를 기준으로 결정한다 (실적 th=0.55, 오탐 0.36%).
6. **ONNX int8 양자화**: export → 동적 양자화(dynamic quantization)를 통해 500MB에서 126MB로 경량화한다. **합격 여부는 고정 테스트(smoke.tsv)를 통해 PyTorch 버전과 동일한 기준** (의도 정답률 ≥0.9, none 오탐 ≤1%)을 만족할 때까지 진행한다. 기준을 통과하지 못하면 int8 적용을 중단한다.
7. **연동**: 일반적인 PTT 인식 경로에서는 텍스트 변환 후 소켓으로 질의하여 즉답을 시도하고, 그 후에 본문을 반환한다. 분류 소켓이나 즉답 처리 과정에서 실패가 발생하더라도 예외를 흡수하여 인식된 본문 반환은 계속된다. 이 설명은 통상적인 PTT 경로의 동작을 의미한다.

## 7. 오늘 빠진 함정 목록

1. **대상 없는 tmux가 엉뚱한 이름을 반환함**（test: `test_hook_names_the_firing_seat`）— `TMUX_PANE`가 비어 있으면 차단
2. **비 CC transcript에서 "본문을 가져올 수 없습니다"라고 말하지 않음**（test: `test_pi_stop_without_transcript_speaks`）— CC 형식 확인을 파일 전체에 대해 수행하며, Pi는 본문을 CC 형식 임시 JSONL로 전달
3. **`--no-play`를 자식 프로세스에 전달하지 않음**（test: `test_hook_no_play_does_not_arm_player`）— spawn하는 `say`에도 옵션 추가
4. **정숙 시간(quiet hours)에 earcon이 울림**（test: `test_quiet_hours_silent`）— quiet 모드에서는 earcon도 비활성화
5. **중복 방지 로직이 로그 컬럼을 잘못 식별함**（test: `test_dedupe_skips_second`）— 비교할 컬럼을 본문으로 고정
6. **명시적 say가 seat gate에서 차단됨**（test: `test_explicit_say_without_seat_speaks`）— 수동 say는 manual로 취급하여 통과
7. **seat 판정 예외 발생 시 무조건 earcon이 울림**（test: `test_hook_error_does_not_play_without_seat`）— 예외 경로에서도 seat 확인
8. **시청(audition) 설정이 무시됨**（test: `test_audition_respects_enabled`）— test 시에도 `speak()`를 거치도록 수정
9. **허용 목록(allowlist) 누락 시 모든 의도(intent)가 울림**（review: review）— 누락 시 빈 집합으로 처리
10. **상주 에러 응답 문제**（review: review）— PTT 클라이언트는 에러 응답이나 허용되지 않은 의도를 울리지 않으며, 로컬 추론으로 전환하지 않음. 실패 시에도 인식된 본문 출력은 계속 유지
11. **fallback 시 입력 행을 유실함**（review: review）— stdin은 한 번만 읽고, 처리되지 않은 부분만 fallback 처리
12. **소형 요약 모델이 사고(thought) 토큰 때문에 빈 결과 출력**（summ-compare）— 사고(thought) 비활성화 지정
13. **너무 짧게 요약하라는 지시가 요점 누락을 유발함**（e4b-prompt 안 3）— 최소 글자 수(120–200자) 지정

## 8. 합격 기준

- `tools/voice/output/tests/` (`test_paths.py` 27개 테스트, `e2e_silent.sh`, `run-all.sh`)를 **모두 통과할 때까지 다시 작성한다**. 소리를 재생하지 않고, `afplay`/`say` 호출 인자를 검사하는 설계 방식
- Aizuchi: smoke 고정 테스트에서 의도 정답률 ≥0.9, `none` 오탐률 ≤1%, `int8` 변환 전후 성적 대조
- 요약: 실제 기록 10건에 대해 요점 누락, 주어 뒤바뀜, 요청 내용 추가가 0이어야 함 (글자 수는 상한선만 존재)
- 실패 보고는 원인을 1줄로 작성한다. 동일한 원인으로 2회 실패할 경우 사람에게 넘긴다.

## 억양을 개선하고 싶은 분들을 위해

규약 걱정 없이 시도할 수 있는 순서:

1. 읽기 사전(`readings.tsv` 형식)을 구축한다. 효과가 가장 크다.
2. AivisSpeech의 말하기 속도, 억양, 피치를 목소리별로 조정한다.
3. AivisHub에서 학습 및 개정이 허용된 목소리를 선택한다.
4. 직접 녹음한 목소리로 추가 학습을 진행한다.

### 고급 사용자용: 학습을 통한 성능 향상

학습을 진행할 때는 직접 녹음한 목소리나 학습 이용이 명시적으로 허용된 데이터셋 및 음성을 사용해야 하며, 각 소재의 라이선스를 반드시 확인하시기 바랍니다. 음성 합성 서비스의 출력물을 학습 소재로 사용하는 절차는 다루지 않습니다.

## 더 나은 억양을 원하는 분들을 위해

라이선스 문제를 피할 수 있는 단계별 순서는 다음과 같습니다:

1. 발음 사전(`readings.tsv` 형식)을 개선합니다. 이것이 가장 큰 효과를 냅니다.
2. 각 음성별로 AivisSpeech의 속도, 억양, 피치를 조절합니다.
3. AivisHub에서 학습이나 수정이 허용되는 음성을 선택합니다.
4. 직접 녹음한 음성으로 파인튜닝(Fine-tune)합니다.

### 고급: 학습을 통해 더욱 개선하기

각 라이선스를 확인한 후, 학습을 명시적으로 허용하는 본인의 녹음 데이터, 데이터셋 또는 음성을 사용하세요. 이 가이드는 음성 합성 서비스의 출력물을 학습 자료로 사용하지 않습니다.

## 일본어 이외의 목소리 (영어 · 중국어 · 한국어)

저자(일본어)는 AivisSpeech를 사용하고 있지만, AivisSpeech는 일본어 전용이다. 영어 · 중국어 · 한국어에서는 이와 유사한 역할을 하는 것을 사용한다.

### 실제 동작 현황

확인 대상은 `tools/voice/output/voice.py`, `tools/voice/input/voicein.py`, `project/voice/aizuchi/serve.py`, `project/voice/aizuchi/reply_map.tsv`입니다.

- 답변 본문 및 요약은 `voice.py`가 설정된 `speaker_id`를 사용하여 로컬 AivisSpeech API(기본값 `127.0.0.1:10101`)로 전송하여 재생합니다. 현재 음성 선택에는 언어 판별 기능이 없으며, AivisSpeech를 사용할 수 없는 경우 항상 `/usr/bin/say -v Kyoko`로 폴백(fallback)됩니다. 따라서 영어, 중국어, 한국어 본문도 언어별로 음성을 전환하지 않고 일본어 화자 ID/Kyoko로 재생됩니다.
- Aizuchi는 입력 문자의 범위를 보고 가나→ja, 한글→ko, 한자→zh, 그 외→en으로 판별합니다. 해당 언어의 답변 후보가 없는 경우에만 ja로 돌아갑니다. `reply_map`의 `text`를 선택한 후 `voicein.py`는 해당 문자열을 `voice.speak()`에 전달할 뿐, `lang`을 음성 선택에 사용하지 않습니다. 답변 클립의 ID가 있더라도 `voice.py`의 팩 매칭 설정 및 manifest와 일치해야 하며, Aizuchi 자체가 언어별 음성을 선택하는 것은 아닙니다.

### 선택지와 권장 사항

영어, 중국어, 한국어 모두 우선 Mac에서 동작하는 로컬 TTS 앱/엔진을 사용한다. 여기서는 [piper-plus](https://github.com/ayutaz/piper-plus)를 공통 후보로 제안한다. 이 프로젝트는 Apple Silicon macOS 바이너리, 로컬 HTTP API, MIT 라이선스를 제공하며, 화자 선택, 속도 조절, 사전 기능 등을 갖추고 있다. 단, 해당 프로젝트에서 공개된 학습 완료 음성은 현재 JA/EN/ZH/ES/FR/PT 6개 언어뿐이며, 한국어의 경우 코드 지원이 곧 학습 완료 음성의 공개를 의미하지는 않는다. 한국어는 후술할 음성 모델의 공개 상황을 확인하고, 사용할 수 있는 모델이 없다면 macOS 기본 음성을 사용한다.

| 언어 | 권장 사항 및 음성 예시 | AivisSpeech와 동일한 역할을 하는 대응 | 상주 메모리(RSS) 기준 |
|---|---|---|---|
| en | piper-plus. 모델 목록에서 영어 모델과 화자를 선택 | 음성 선택, 말하기 속도/억양 설정, HTTP API 제공. 사전/G2P는 언어별 기능 확인 필요 | 공개 자료에 상주 RSS 값 없음. 소형 ONNX 음성(수십 MB급)이라도 실제 RSS는 미측정 |
| zh（보통화） | piper-plus. 중국어 모델 및 화자를 선택 | 위와 동일. 모델 카드를 통해 보통화, 음성, 라이선스 확인 | 위와 동일, 미측정 |
| ko | piper-plus 코드는 한국어를 지원함. 단, 공식 README의 학습 완료 6개 언어 목록에 ko는 포함되지 않음. 한국어 모델의 공개 및 라이선스를 확인할 수 있을 때까지는 최소한의 대안으로 macOS의 Yuna 사용 | API나 사전 등 코드 측 기능과 이용 가능한 한국어 학습 완료 음성은 별개임. 모델을 찾을 수 없다면 엔진으로서 사용할 수 없음 | macOS 표준은 합성 앱 상주 없음. piper-plus는 미측정 |

참고 후보: [Kokoro 82M](https://github.com/hexgrad/kokoro)은 Apache-2.0 라이선스의 소형 모델로 영어와 보통화 음성이 있으며, Apple Silicon용 MLX 구현도 존재하지만, 한국어 음성은 공식 지원 목록에 없다. piper-plus의 코드와 MIT 라이선스는 [공식 README](https://github.com/ayutaz/piper-plus)에서, 이용 가능한 모델은 [사전 학습 모델 목록](https://github.com/ayutaz/piper-plus/blob/dev/docs/guides/development/pretrained-models.md)에서 확인할 수 있다. 모델의 라이선스는 코드와 다르므로 개별적으로 확인해야 한다.

| macOS 표준 음성 | 설정 방법 | 비고 |
|---|---|---|
| 영어 | 시스템 설정 → 손쉬운 사용 → 콘텐츠 말하기(Spoken Content) → 시스템 음성 → 음성 관리(Manage Voices). English 및 Enhanced/Premium 표시를 선택하여 다운로드. 후보 이름은 지역 및 macOS 버전에 따라 다르므로 목록에서 확인(예: Samantha, Alex) | `say -v '?'` 명령어로 이 Mac에 설치된 정확한 음성 이름과 언어를 확인 |
| 중국어 | 동일한 절차로 Chinese (China mainland) / Mandarin 음성을 선택하고, Enhanced/Premium 표시가 있는 음성을 다운로드(예: Ting-Ting zh-CN, Mei-Jia zh-TW, Sin-ji zh-HK) | 중국어는 지역 변체를 선택. 표시 이름은 OS 버전에서 확인 |
| 한국어 | 동일한 절차로 Korean 음성을 선택하고, Enhanced/Premium 표시가 있는 경우 다운로드(예: Yuna ko-KR) | Enhanced 표시 여부는 OS 버전에 따라 다름. 음성 목록에서 실제 확인 필요 |

Apple의 공식 절차는 [추가 음성 관리 및 다운로드](https://support.apple.com/ko-kr/guide/mac-help/mac1142/mac)를 참조한다. macOS 표준 `say`는 로컬 음성 합성의 최소한의 대안으로, 속도 지정은 가능하지만 AivisSpeech와 같은 음성 모델 선택 UI, 억양 조절, 사용자 읽기 사전, TTS 전용 로컬 HTTP API를 한꺼번에 제공하지는 않는다. `say`의 음성은 OS에 설치된 목록을 사용한다. Apple 개발 문서에는 속도, 음성, 읽기 사전 API가 있으나, 여기서 말하는 `say` CLI의 공통 설정으로 이용할 수 있다고 단정할 수는 없다.

### 도입 및 응답 클립 생성

1. [piper-plus 공식 절차](https://github.com/ayutaz/piper-plus)에 따라 macOS Apple Silicon 바이너리를 설치하고, 사용할 언어의 모델을 가져온다. 모델 카드에서 상업적 이용·수정·재배포 조건을 확인한다. 로컬 HTTP API를 실행하여 사용할 voice ID, 언어 코드, 속도·억양 등 공개 API가 수용하는 항목을 확인한다.
2. `project/voice/aizuchi/reply_map.tsv`를 연다. 열은 `intent`, `lang`, `text`, `id`로 구성된다. `lang`이 en / zh / ko인 행의 `text`가 해당 언어로 출력할 응답 문구이다. 문장은 편집하지 않고 그대로 사용하며, `id`는 음성 팩 측의 phrase ID와 매칭시킨다.
3. 응답 문구마다 piper-plus의 로컬 HTTP API에 `text`와 선택한 화자·언어를 전달하여, 반환된 음성을 WAV로 저장한다. 출력 경로는 예시로 `project/voice/audio/<lang>/<id>.wav`로 한다. 동일 ID의 동일 문장을 재생성하면 교체하고, manifest에 `id`·`lang`·모델/voice·파일·`ok`를 기록한다.
4. 실제 `voice.py`는 `project/voice/manifest.tsv`와 `phrases.tsv`의 표기·모델·언어·voice 설정이 일치할 때만 클립을 재생한다. 레시피 사용자가 Aizuchi reply_map 유래의 즉답 클립을 추가할 때는, 기존 음성 팩과 동일한 인덱스 규칙을 사용하거나 문자열을 직접 TTS에 전달한다. 재생 대상은 `speak_intents.txt`에 허용된 intent로 제한된다.

본문이나 요약을 동일한 목소리로 출력하려면, 현재 `voice.py`의 AivisSpeech 전용 `speaker_id`/Kyoko 고정 경로를 해당 TTS의 로컬 API 및 선택한 voice ID에 맞춰 연결해야 한다. 이 문서는 선택 및 도입 사양을 다루며, 현행 코드가 자동으로 다국어 음성으로 전환된다는 의미는 아니다.

### 읽기 사전과 억양

"억양을 개선하고 싶은 사람을 위한" 첫걸음과 마찬가지로, 가장 먼저 읽기 사전을 추가한다. 영어라면 고유 명사 발음 및 약어, 중국어라면 간체자/번체자 읽기와 고유 명사, 한국어라면 외래어·고유 명사·숫자 읽기를 언어별로 기록한다. AivisSpeech의 `readings.tsv`를 다른 엔진에 그대로 등록할 수 있는 것은 아니다. 각 엔진의 사전 형식, G2P/phoneme 지정 방식을 확인해야 하며, piper-plus에서는 [공식 사전/G2P 기능](https://github.com/ayutaz/piper-plus) 또는 직접적인 음소 지정을 사용한다. 사전 기능이 없는 구현체에서는 읽기 방식이 확정된 표기로 전처리한 후 합성한다. macOS `say`는 목소리와 속도를 테스트해 보고, 필요하다면 `[[inpt PHON]]` 등의 음소 지정이나 읽기 사전 API를 조사하되, 모든 언어에서 동일한 표기 방식을 사용할 수 있다고 가정해서는 안 된다.

### 영어

저자(일본인)는 AivisSpeech를 사용하지만, AivisSpeech는 일본어 전용입니다. 영어, 중국어, 한국어의 경우, 유사한 역할을 수행하는 Mac 로컬 음성 합성기(speech synthesizer)를 사용하십시오.

현재 `voice.py`는 언어와 관계없이 설정된 AivisSpeech 스피커 ID를 사용하며, 실패 시 `/usr/bin/say -v Kyoko`로 폴백(fallback)합니다. Aizuchi 분류기는 스크립트(`ja` 가나, `ko` 한글, `zh` 한자, 그 외 `en`)에 따라 응답 텍스트를 선택하지만, `voice.speak()`에는 텍스트만 전달합니다. 즉, 언어별 전용 음성을 선택하지는 않습니다.

추천하는 공통 후보: [piper-plus](https://github.com/ayutaz/piper-plus)입니다. 이 프로젝트는 Apple Silicon macOS, 로컬 HTTP API, MIT 라이선스 코드를 지원합니다. 음성, 운율/속도, 사전/G2P 기능을 제공하지만, 모델 가용성 및 모델 라이선스는 코드 지원과는 별개입니다. 현재 공개된 사전 학습 모델 목록은 6개 언어 중 EN과 ZH를 포함하고 있습니다. 한국어는 코드상으로는 지원되지만, 사용 가능한 사전 학습 음성으로 확립되어 있지는 않습니다. 한국어의 경우, 적절한 라이선스 모델이 없다면 macOS Yuna (ko-KR)를 폴백으로 사용하십시오. 시스템 음성은 '시스템 설정 → 손쉬운 사용 → 음성 콘텐츠 → 시스템 음성 → 음성 관리'에서 설치할 수 있으며, 제공되는 경우 '향상됨/Premium' 다운로드를 선택하십시오. 예시 이름으로는 Samantha/Alex (영어), Ting-Ting (중국어), Yuna (한국어) 등이 있습니다. 설치된 이름은 `say -v '?'` 명령어로 확인할 수 있습니다.

Aizuchi 클립을 만들려면, `project/voice/aizuchi/reply_map.tsv`에서 각 en/zh/ko `text` 행을 가져와 해당 텍스트와 선택한 언어/음성을 로컬 API로 전송하십시오. 그 다음 `id`를 키로 하여 WAV 파일을 저장하고, 보이스 팩 매니페스트(manifest)에 인덱싱합니다. 각 음성 모델 카드의 상업적 이용 및 수정 약관을 확인하십시오. Apple `say`는 기본적인 폴백이며, AivisSpeech와 같은 통합 음성 선택, 운율 제어, 사용자 사전 및 로컬 TTS API를 제공하지 않습니다. 엔진 자체의 사전 또는 음소(phoneme) 구문을 사용하여 언어별 발음 항목을 추가하십시오. `readings.tsv`는 레시피 형식이며, 모든 엔진에서 직접 수용된다는 보장은 없습니다.

### 중국어

작성자(일본어)는 AivisSpeech를 사용하지만, 이는 일본어만 지원합니다. 영어, 중국어, 한국어는 Mac에서 실행되며 유사한 기능을 수행하는 로컬 TTS(Text-to-Speech) 도구를 사용해야 합니다.

현재 `voice.py`는 모든 언어에 설정된 AivisSpeech speaker ID를 사용하며, 실패 시 `/usr/bin/say -v Kyoko`로 고정되어 폴백(fallback)됩니다. Aizuchi는 문자 범위를 기준으로 응답 언어를 선택하지만(가나 ja, 한국어 ko, 한자 zh, 기타 en), 응답 텍스트를 `voice.speak()`에 전달할 뿐 언어 전용 음성을 선택하지는 않습니다.

먼저 [piper-plus](https://github.com/ayutaz/piper-plus)를 확인하는 것을 권장합니다. 공식 설명에 따르면 Apple Silicon macOS를 지원하고 로컬 HTTP API를 제공하며, MIT 라이선스를 채택하고 있으며 속도/운율 및 사전/G2P 기능을 갖추고 있습니다. 현재 출시된 사전 학습된 음성은 EN/ZH 등 6개 언어가 나열되어 있습니다. 한국어는 코드상으로 지원되지만, 이를 근거로 사용 가능한 사전 학습된 음성이 있다고 단정할 수는 없습니다. 중국어의 경우 보통화(Mandarin) 모델을 선택할 것을 권장하며, 음성 모델의 상업적 이용 및 수정 라이선스를 별도로 확인해야 합니다. macOS의 기본적인 대안은 시스템 설정 → 손쉬운 사용 → 콘텐츠 읽어주기 → 시스템 음성 → 음성 관리에서 Enhanced/Premium 음성을 다운로드하는 것입니다. 예를 들어 Ting-Ting(보통화), Mei-Jia(대만 중국어), Sin-ji(광둥어) 등이 있으며, 실제 명칭은 로컬에서 `say -v '?'` 명령어로 확인하시기 바랍니다.

즉시 응답 오디오를 생성할 때는 `project/voice/aizuchi/reply_map.tsv`에서 `lang=zh` 행의 `text` 원문을 가져와 로컬 API와 선택한 음성에 전달하고, WAV 파일을 `id`별로 저장하여 manifest에 등록합니다. 중국어 고유 명사와 다음자(多音字)는 해당 엔진 자체의 발음 사전 또는 음소 매핑을 유지 관리해야 합니다. `readings.tsv`는 모든 엔진에서 공통으로 사용하는 임포트 형식이 아닙니다. macOS `say`는 최소한의 대안일 뿐이며, AivisSpeech와 같은 통합 음성 모델 선택, 운율 조절, 사용자 사전 및 로컬 TTS API 기능을 제공하지 않습니다.

### 한국어

작성자(일본어)는 AivisSpeech를 사용하지만, AivisSpeech는 일본어 전용이다. 영어·중국어·한국어에는 Mac에서 비슷한 역할을 하는 로컬 음성 합성 도구를 사용한다.

현재 `voice.py`는 언어와 관계없이 설정된 AivisSpeech speaker ID를 사용하고, 실패하면 `/usr/bin/say -v Kyoko`로 고정 대체한다. Aizuchi는 문자 종류로 답변 언어(가나 ja, 한글 ko, 한자 zh, 그 외 en)를 고르지만, 답변 텍스트만 `voice.speak()`에 전달하며 언어별 음성을 고르지 않는다.

우선 [piper-plus](https://github.com/ayutaz/piper-plus)를 살펴본다. 공식 문서는 Apple Silicon macOS, 로컬 HTTP API, MIT 코드 라이선스와 속도/운율·사전/G2P 기능을 안내한다. 공개된 사전 학습 음성은 현재 EN/ZH를 포함한 6개 언어로 정리되어 있다. 한국어는 코드 지원만으로 사용 가능한 학습 음성이 있다고 볼 수 없다. 적절한 한국어 음성과 라이선스를 확인할 수 없다면 macOS의 Yuna(ko-KR)를 최소 대안으로 쓴다. 시스템 설정 → 손쉬운 사용 → 읽기 및 말하기 → 시스템 음성 → 음성 관리에서 Enhanced/Premium 표시가 있는 음성을 내려받는다. 실제 설치된 이름은 `say -v '?'`로 확인한다.

Aizuchi 클립은 `project/voice/aizuchi/reply_map.tsv`의 `lang=ko` 행 `text`를 그대로 로컬 API에 보내고, WAV를 `id`별로 저장해 manifest에 등록한다. 외래어·고유명사·숫자 읽기는 각 엔진의 사전이나 음소 표기를 사용한다. `readings.tsv`를 그대로 가져올 수 있다고 가정하지 않는다. macOS `say`는 최소 대안이며 AivisSpeech와 같은 통합 음성 선택, 운율 조절, 사용자 사전, 로컬 TTS API를 제공하지 않는다.

### 답변·요약·즉답의 언어별 음성 라우팅

답변 본문, 요약, 즉답으로 읽을 문장 각각의 언어를 판정하고, 그 언어에 맞는 음성 설정으로 라우팅한다. 일본어 문장은 AivisSpeech를 사용한다. 그 밖의 언어는 언어별로 권장한 Mac 로컬 TTS와 해당 언어의 음성을 우선 사용하고, 쓸 수 있는 로컬 모델이 없으면 macOS 표준 `say`에서 해당 언어의 설치된 음성을 고른다. 영어·중국어·한국어의 후보와 제한은 위의 선택지 표를 따른다. 문장 언어 판정 결과는 음성 키 `ja → voice_ja`, `en → voice_en`, `zh → voice_zh`, `ko → voice_ko`로 연결한다. 이는 본문과 요약에도 적용하며, Aizuchi가 선택한 답변 언어도 같은 규칙으로 음성 선택에 전달한다. 글에 섞인 문자만 보고 무조건 AivisSpeech를 쓰거나, 모든 언어를 하나의 고정 음성으로 보내지 않는다.

실제 연결을 바꾼 뒤에는 소리를 내지 않는 확인 모드로 언어 라우팅을 검사한다. `tests/fixtures/lang-route.tsv`에는 일본어·영어·중국어·한국어 예문과 기대 음성 키가 있고, `tests/test_lang_route.py`는 각 문장을 `--select-voice-key`에 전달해 출력된 키가 기대값과 정확히 같은지 확인한다. `VOICE_NO_PLAY=1`도 설정되므로 음성은 재생되지 않는다. 실행 예: `VOICE_PY=/path/to/voice.py python3 tests/test_lang_route.py`.
