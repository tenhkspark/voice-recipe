[日本語](./README.md) / [English](./README.md) / [中文](./README.zh.md) / [한국어](./README.ko.md)

# 합격 기준 (무음)

재생하지 않습니다. `afplay`와 `say`는 테스트에서 대체합니다. 음성 파일은 포함되어 있지 않습니다.

재료 (텍스트만):

- `fixtures/` … Stop의 전사문 샘플 (Claude Code 형식 및 그 외 형식)
- `aizuchi/smoke.tsv` … 의도 분류 정답. 정답률 0.9 이상, `none` 오탐률 0.01 이하
- `aizuchi/smoke-dictation.tsv` … 받아쓰기. 울리면 안 되는 경우의 오탐률 1% 이하, 울려야 하는 경우의 미탐률 10% 이하
- `aizuchi/speak_intents.txt` … 즉시 응답해도 되는 의도. 받아쓰기에서 울리는 경우는 여기 있는 의도에만 해당

## 환경 변수

| 변수 | 사용 테스트 | 기본값 |
| --- | --- | --- |
| `VOICE_PY` | test_paths / e2e | 필수. test_paths에서는 `--voice`로도 전달 가능. 이 작업 트리에는 인접한 `../voice.py`가 없음 |
| `VOICE_REPLY` | e2e | 없음 (Stop 응답 스크립트. 파일이 없으면 SKIP) |
| `VOICE_IN` | e2e | 없음 (`voicein.py`. 없으면 맞장구(aizuchi) 테스트는 SKIP) |
| `VOICE_TEST_SEAT` | test_paths | `seat-a` (소리가 나도 되는 좌석) |
| `VOICE_TEST_OTHER_SEAT` | test_paths / e2e | `other-seat` |
| `VOICE_TEST_FOREIGN_SEAT` | test_paths | `other-session` (자기소개를 해서는 안 되는 다른 세션) |
| `VOICE_E2E_SEAT` | e2e | `test`. 이 이름일 때만 기록 표시가 `t`인지 확인 |
| `VOICE_TEST_CWD` | test_paths / e2e | `/tmp/voice-proj` |
| `AIZUCHI_DIR` | run-all | `tests/aizuchi` (smoke 및 speak_intents) |
| `AIZUCHI_PYTHON` | run-all | `python3` |
| `AIZUCHI_SOCK` | run-all | 없음. 기존 상주 소켓을 사용할 때만 지정 |
| `AIZUCHI_SERVE` | run-all | 없음. `AIZUCHI_MODEL`에 맞춰 임시 소켓을 실행 |
| `AIZUCHI_MODEL` | run-all | 없음 (모델 본체는 포함되어 있지 않음) |

좌석명 `test`는 표시 `t`를 사용하는 계약입니다. 구현에서는 이 문자열일 때 표시를 남깁니다. 머신 고유의 좌석명은 넣지 않습니다.

## 실행 방법

경로는 구현 파일이 있는 위치에 맞춰 조정하세요. 아래는 예시입니다.

```sh
cd /path/to/voice-recipe

# 경로만 (voice.py)
VOICE_PY=/path/to/voice.py python3 tests/test_paths.py

# Stop부터 맞장구까지. 소리는 스텁(stub)으로 대체
VOICE_PY=/path/to/voice.py \
VOICE_REPLY=/path/to/voice-reply.sh \
VOICE_IN=/path/to/voicein.py \
  sh tests/e2e_silent.sh

# 4개 항목. 하나가 실패해도 끝까지 실행하며, 실패가 있으면 종료 코드 1
VOICE_PY=/path/to/voice.py \
VOICE_REPLY=/path/to/voice-reply.sh \
VOICE_IN=/path/to/voicein.py \
AIZUCHI_SOCK=/path/to/aizuchi.sock \
AIZUCHI_PYTHON=/path/to/python \
  sh tests/run-all.sh
```

상주 프로세스가 없으면 smoke의 두 항목은 FAIL이 됩니다 (실행하려면 `AIZUCHI_SERVE`와 `AIZUCHI_MODEL`을 설정해 임시 소켓을 시작합니다). `test_paths.py`와 `e2e_silent.sh`도 단독 실행 시 같은 환경 변수를 읽습니다. 맞장구(aizuchi) 테스트는 가짜 UNIX 소켓을 바인드하므로, 실행 환경에서 UNIX 소켓을 만들 수 있어야 합니다.

`run-all.sh`의 출력은 `항목, 결과, 상세 내역` 및 실패한 라인으로 구성됩니다 (smoke는 상위 12개).

## 언어별 음성 선택 (무음)

일반 `run-all.sh`는 일본어 환경용입니다. 언어 분기를 확인할 때만 `RUN_LANG_ROUTE=1`을 설정하세요.

```sh
VOICE_PY=/path/to/voice.py RUN_LANG_ROUTE=1 sh tests/run-all.sh
```

단독 실행: `VOICE_PY=/path/to/voice.py python3 tests/test_lang_route.py`. `VOICE_PY`는 `--select-voice-key <문장>`을 받아 소리를 재생하지 않고 선택한 음성 설정 키를 한 줄로 출력해야 합니다. 테스트는 `VOICE_NO_PLAY=1`도 설정하고 `lang-route.tsv`의 네 문장 각각에서 키가 정확히 일치하는지 확인합니다.
