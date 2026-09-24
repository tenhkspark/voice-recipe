[日本語](./aizuchi.md) / [English](./aizuchi.md) / [中文](./aizuchi.zh.md) / [한국어](./aizuchi.ko.md)

# Aizuchi 만드는 법

짧은 발화를 의도별로 나누어 인사, 감사, 사과, 감정만을 즉각 응답하는 분류기를 만드는 절차입니다. 학습된 가중치는 포함되어 있지 않습니다. 베이스 모델을 가져온 뒤, 본인의 LLM으로 예문을 생성하고 직접 학습시키십시오. 숫자는 제작자의 실측치입니다 (2026-09-24, 기록은 `progress-aizuchi.md` (구 `(internal record)`), `progress-aizuchi-wire.md`, `(internal record)`, `runall-first.md` 및 `aizuchi/` 디렉토리 내 파일 개수). 측정되지 않은 부분은 기재하지 않았습니다.

합격 기준은 [tests/aizuchi/](../tests/aizuchi/)입니다 (`smoke.tsv` 252행, `smoke-dictation.tsv` 800행, `speak_intents.txt`). `speak_intents.txt`는 `aizuchi/speak_intents.txt`의 고정 복사본이며, 나머지 동일한 이름의 테스트 TSV 파일들도 제작자 측 파일과 바이트 단위로 일치합니다.

---

# 한국어

## 1. 수행 내용

```
발화 1행 (ja / en / zh / ko)
  → 분류기 (54 의도 + none)
  → 신뢰도가 임계값 미만이거나 none인 경우 → 무음
  → 의도가 speak_intents.txt의 허용된 32개에 포함되지 않거나 응답이 비어 있는 경우 → 무음
  → 존재하는 경우 → 해당 언어의 정형 응답 1개를 선택하여 재생 측으로 전달
```

본 응답(에이전트의 긴 답변)과는 별개의 경로입니다. 분류에 실패하더라도 텍스트로 변환된 본문은 중단되지 않습니다. 즉답만 누락됩니다.

재생되는 32개는 인사, 감사, 사과, 감정에 ack와 input-wait를 더한 집합입니다. 원본은 1행 1의도를 가진 `speak_intents.txt`입니다.

| 구분 | 의도 |
|---|---|
| 인사 | hello, morning, night-sleep, goodbye, otsukare, return-home, leaving, first-meet, reunion, how-are-you, welcome-in |
| 감사·사과·배려 | thanks, apology, care |
| 감정 | joy, moved, surprise, encourage, praise, empathy-here, sad, lonely, worry, relief, angry, calm-down, embarrassed, love, laugh, peaceful |

`how-are-you`(안부)는 이 집합에 포함됩니다. `invite`와 `meetup`은 상황에 따른 응답이 되므로 허용 리스트에서 제외되었습니다. 권유(invite, meetup), 실행 중·질문·기타 운영 의도(doing 등) 및 `none`은 분류되더라도 재생하지 않습니다. 파일을 읽을 수 없을 때, 작성자의 `respond.py`는 빈 집합(아무것도 재생하지 않음)을 반환합니다. 반면, `voicein.py` 코드 내의 폴백(fallback)은 원본과 동일하지 않으며, `invite`와 `meetup`을 포함하고 `how-are-you`를 포함하지 않습니다. 파일이 없거나 비어 있는 경우에는 이 다른 집합이 사용됩니다. 테스트 측 리스트는 원본을 복제한 고정 복사본이며, 원본이 변경되면 동기화합니다.

재생은 분류기에서 `afplay`로 수행하지 않습니다. 자리 비움·정숙 시간·대기 순번 등은 재생 측(작성자는 `voice.py`의 `speak`)으로 전달합니다.

## 2. 의도 설계

처음에는 응답 id를 직접 분류했다. 대상은 491 id(greet 124, emotion 195, ops 172) + `none`을 포함한 492개 클래스였다. greet와 emotion은 전체를 대상으로 했다. ops는 짧은 구어체(`z-ops-*`, 접두사가 없는 짧은 id, 확인 중·대기 중·실행 중·준비 중으로 읽히는 것)만 포함했다.

491개 클래스는 너무 세분화되어 있었다. 동일한 감사 표현 내에서도 확률이 분산되어 임계값 0.55를 넘지 못했다. 제작자의 실측 결과, "고마워!", "Thanks a lot", "谢谢你", "미안, 잘못 눌렀어", "잘 부탁해"가 모두 `none`으로 분류되었고, "안녕"만 제대로 맞췄다.

분류 단위를 의도로 묶었다. `intents.txt`는 54행(이름, 탭, 설명)으로 구성된다. 분류 클래스는 54개 의도 + `none`을 포함한 55개다. 응답 id를 직접 분류하지 않고, 의도가 맞은 후 응답 표에서 하나를 선택하는 방식이다.

`none`은 "정형 문구만으로 처리할 수 없는 발화"를 의미한다. 지식 질문, 설명, 상담, 작업 지시, 정보를 구하는 질문 등이 해당한다. 임계값 미만인 경우에도 추론 결과는 `none`으로 처리한다. 판단이 모호하면 `none`으로 넘긴다. 잘못된 정형 문구를 출력하는 것이 침묵하는 것보다 더 나쁘기 때문이다.

id를 의도에 할당할 때, 목록에 없는 이름은 사용하지 않는다. 판단이 어려운 id는 `notify`로 지정한다. 제작자는 할당 후 명백한 오류만 수동으로 수정했다(예: `review-pass` → `result-report`). 아침 알림 관련 11개 id(알람, 날씨, 뉴스, 일정, 첫차 등)는 의도 `none`에 배치했다. `intents.tsv`의 `none` 행은 이 11개 항목이다.

ops 계열 의도에 포함되었던 명령형(~해줘, ~해주세요, do X)은 학습 라벨을 `none`으로 옮겼다. 감정 표현의 "~해줘"는 유지한다. 질문, 인사, 감정, 보고는 명령으로 간주하지 않는다. id별 데이터 개수를 억지로 맞추기 위한 추가 생성은 제작자의 기록에 따르면 역효과가 있어 채택하지 않았다.

## 3. 학습 데이터 제작 방법

재현 시 권장 절차에서는 예문을 만드는 LLM과 검사하는 LLM을 분리한다. 동일한 모델이 자신이 만든 문장을 검사하면 검사가 느슨해지기 때문이다. 어떤 LLM으로 문장을 만들었느냐에 따라 학습된 가중치(weights)에 붙는 이용 조건이 달라진다. Gemma로 만들면 [Gemma Terms of Use](https://ai.google.dev/gemma/terms)의 금지 용도가 가중치에 적용된다. 다른 모델로 만들면 해당 모델의 조건이 적용된다. 기반 엔코더의 MIT 라이선스는 변하지 않는다. 제3자의 목소리나 개인의 발화는 포함하지 않는다.

저자의 분류기용 코퍼스는 자체 제작한 Gemma 4(로컬 OpenAI 호환, 64 병렬)로 만들고 있다. 실시 기록(`progress-aizuchi.md`)에서는 생성과 검사가 동일한 Gemma로 수행되었으며, 독립된 별도 모델에 의한 검사가 아니다. 후속 외부 확인은 `(internal record)`에 기록되어 있다.

절차:

1. 의도(intent)별로 사용자가 할 법한 발화를 생성시킨다. ja / en / zh / ko를 거의 동일한 비율로 구성한다. 구어체부터 정중한 표현, 단문부터 문장까지 다양하게 구성한다. 해당 의도의 정형 답변(fixed response)이 자연스럽게 성립하는 발화만 포함한다. 답변 문장을 사용자가 바꾸어 말한 것(앵무새 식 반복)은 불가하다. 작업 명령과 날씨·지식·뉴스 등의 정보 질문은 인사·감정 예시에 섞지 않는다.
2. `none`은 별도의 프롬프트를 사용한다. 정형적인 인사·감사·"네"만으로는 해결되지 않는 발화다. 테마를 나누어 범위를 넓힌다(작업 지시, 정보 질문, 상담, 계산, 번역).
3. 권장 절차에서는 생성에 사용한 것과는 다른 LLM에 모든 항목을 검사시킨다. 의도 측은 "그 정형 답변이 자연스러운가"를, `none` 측은 "정말로 정형 답변으로 끝낼 수 없는가"를 확인한다. 탈락한 번호는 버린다. 동일한 문장이 여러 라벨에 걸쳐 나타나면 그 문장은 전부 버린다. 동일한 (라벨, 문장) 중복도 버린다. 이 코퍼스 실시 당시에는 생성과 검사가 동일한 Gemma였다. 상주 추론(resident inference) 시에는 tokenizer를 `tokenizers` 단독으로 로드하며, `transformers` / `torch`를 import 하지 않는다.
4. 남은 문장을 층화(stratified)하여 나눈다. 저자의 `parse_val.py`는 `sha256(text) % 10 == 0`을 dev로, 나머지를 train으로 할당한다(약 9:1).

저자의 건수:

| 단계 | 건수 | 출처 |
|---|---|---|
| 최초 생성 | 34,783 (id 측 17,585 / none 17,198, 4개 언어 거의 균등). 각 id는 36건 요청 (9×4 언어). none은 40회 호출 × 60건 | 진행 메모 |
| 동일 Gemma 검사 후 | 합격 31,454, 탈락 3,329, 다중 라벨 및 중복 제외 시 **28,933** (train 26,045 / dev 2,888) | 진행 메모 |
| 명령 이동 및 추가 후 수중에 남은 생성 파일 | **37,764** 행 (`examples2.jsonl`. 약 3.8만). 이 중 의도명이 붙은 추가분(`@intent::이름`)이 2,156행 | 파일 건수 |
| 채택된 55개 클래스의 분할 | train **32,560** (none 19,054) / dev **3,645** (none 2,130) | `train.jsonl` / `dev.jsonl`. dev의 3,645는 진행 메모의 n과 일치 |

진행 메모에 따르면 smoke의 양성 예시(positive examples) 패러프레이즈 1,241건을 Gemma로 추가했다고 되어 있다. id 측을 균형 있게 맞추기 위한 추가 작업은 채택하지 않았다. 예시가 10건 미만인 약한 id는 최초 id 분류 시점에 19개 있었다.

고정 받아쓰기 테스트(`smoke-dictation.tsv`)는 학습 데이터와 별개다. 총 800행이며, silent 600행(4개 언어 × 150행)과 reply 200행(4개 언어 × 50행)으로 구성된다. 열은 `lang`, `text`, `expect`(`silent` 또는 `reply`)다.

## 4. 학습

베이스 모델은 [sbintuitions/modernbert-ja-130m](https://huggingface.co/sbintuitions/modernbert-ja-130m)입니다. MIT(© 2025 SB Intuitions). 모델 카드에 따르면 일-영 4.39T 토큰, 어휘 사전(vocabulary) 102,400, 시퀀스 길이 8,192, hidden 512, 19개 레이어로 구성되어 있습니다. `transformers` 4.48 이상이 필요합니다. Mac의 venv 환경은 Python 3.12, torch 2.14, transformers 4.56.2를 사용합니다. GPU 런 컨테이너는 진행 상황 메모에 기재된 `tenhkspark/gemma-4-v2:v2`입니다.

헤드(head)는 인코더의 CLS(최종 hidden state의 0번 위치)에 선형(linear) 1개 레이어를 추가했습니다. 손실 함수는 교차 엔트로피(cross-entropy)를 사용합니다. 레이블은 출현 순서대로 고정하며, `none`은 항상 마지막에 위치합니다. 최적화 알고리즘은 AdamW, 학습률(learning rate)은 2e-5, 최대 길이(max length)는 96, 3 epoch, warmup은 전체 step의 10%로 설정 후 선형적으로 감소시키며, 그래디언트 클리핑(gradient clipping)은 1.0, 체크포인트는 bfloat16 형식을 사용합니다. `model.safetensors` 파일이 이미 존재하면 학습을 재개합니다. 디바이스는 CUDA를 우선하며, 없을 경우 MPS, 그 다음은 CPU를 사용합니다.

```
python3 train.py train.jsonl --out ckpt --base base --epochs 3 --batch-size 64 --lr 2e-5 --max-len 96 --seed 0
```

원작자의 학습 런(DGX Spark의 DGX Spark, `batch_size` 64): 1,527 step, epoch 손실 1.485914 → 0.493772 → 0.152006, 약 **12분**. 진행 상황 메모에 따르면 메모리 사용량은 20GB 미만입니다. 동일한 장비의 다른 서버는 중단하지 않은 상태입니다.

Mac의 MPS에서도 동일한 스크립트가 동작합니다. 완료된 MPS 기록을 보면, 의도(intent)로 묶기 전의 491 id 모델(batch 32, 2,442 step) 기준으로 약 **37분**이 소요되었으며, 최종 손실은 0.358이었습니다. 55개 클래스에 대한 학습 체크포인트는 GPU 측에 있습니다.

임계값(threshold)은 dev 데이터셋에서 `none`의 오탐(false positive)이 적은 쪽을 선택합니다. 최초 채택 값은 **0.5**였습니다. 당시 스윕(sweep) 결과 0.3은 정답 0.9621 / 오탐 0.0167, 0.4는 0.9621 / 0.0083, 0.5와 0.6은 0.9394 / 0.0000이었으므로 0.5를 선택했습니다. 이후 구술 시험(dictation) 누락 방지를 위해 현재 값은 **0.38**로 변경되었습니다. 현재 int8 실측 결과, dictation 오탐 0/600 · 누락 18/200, smoke 의도 정답 0.9697 · none 오탐 0/120입니다. 자세한 내용은 `progress-aizuchi.md`의 negtest 기록을 참조하십시오.

## 5. ONNX int8 내보내기

PyTorch 체크포인트를 ONNX로 변환하고, dynamic quantization을 통해 int8로 변환한다. 출력은 logits `[batch, 55]`이며, opset 17을 사용한다. 축(axis)은 batch와 sequence length가 dynamic이다. 양자화는 `quantize_dynamic`을 사용하며, 가중치는 `QInt8`이다. tokenizer, `labels.json`, `threshold.txt`를 ONNX 파일과 동일한 디렉토리에 둔다. 상주 프로세스는 `tokenizers` 단독으로 tokenizer를 로드하며, `transformers`와 `torch`는 import 하지 않는다.

내보내기 직후, 동일한 2개 문장으로 PyTorch와 int8의 logits를 비교한다. 작성자의 기록에 따르면 argmax는 일치하며, max|Δlogit| = 0.85이다. 진행 메모의 크기는 fp32 504MB, int8 126MB이다. 현재 디스크에 있는 int8 파일은 132,993,740 바이트이다.

합격 여부는 smoke 테스트를 int8로 다시 채점하여 결정한다. 작성자가 내보내기 시 설정한 추가 조건은 "torch 의도 정답률 0.939에서 0.01 이상 하락하지 않을 것, none 오탐(false positive)은 1% 이하일 것"이다. 조건을 충족하지 못하면 int8을 사용하지 않는다.

| 지표 | torch (임계값 0.5) | ONNX int8 | 판정 |
|---|---|---|---|
| smoke 의도 정답률 | 124/132 = 0.9394 | 126/132 = 0.9545 | 합격 (상승) |
| smoke none 오탐 | 0/120 | 0/120 | 합격 |
| dev 정답 (n=3645) | 0.8236 | 0.8167 | −0.007 |
| dev none 오탐 | 0.0150 | 0.0164 | ＋0.0014 |
| 추론 median | 9.99 ms (MPS, n=200) | 2.4 ms (CPU / onnxruntime) | |

상주 RSS는 약 **389 MiB**이다. 기동(imports 완료부터 OrtInfer 및 reply map 준비까지) 시간은 **0.27 초**이다. 판정 median은 **2.4 ms**(`serve.answer("ありがとう")`, n=200)이다. tokenizer는 `tokenizers` 단독으로 로드하며, `transformers` / `torch`는 import 하지 않는다 (`~/project/ops/codex-rss.md`, commit `(internal)`).

dev의 none 오탐은 1%를 약간 초과한다. 합격 기준은 smoke 테스트 기준(§7)을 따른다. int8에서 놓친 6건은 다른 의도로 잘못 분류된 것이 아니라, 임계값 미만으로 `none`에 빠진 경우이다 (예: 「おやすみなさい」→ none 0.483, 한국어 「이제 잘게」→ none 0.381).

## 6. 상주 및 소켓 형식

UNIX 소켓. 제작자의 기본 경로는 `~/.config/voice/aizuchi.sock`이다. 1개의 연결에 발화를 한 줄씩 보내면, 각 줄에 대해 JSON을 한 줄씩 반환한다. onnxruntime의 CPU 및 스레드는 intra / inter 모두 1이며, 메모리 아레나(memory arena)는 off 상태이다. tokenizer의 최대 길이는 96, pad id는 3이다.

```json
{"intent": "thanks", "score": 0.9719, "id": "reply-thanks-1", "reply": "どういたしまして", "lang": "ja"}
```

| 필드 | 의미 |
|---|---|
| intent | 54개의 의도(intent) 이름, 또는 `none`. 추론 예외 시 `error` |
| score | 최대 클래스의 확신도(confidence). 임계값 미만이라 `none`으로 처리했을 때도 해당 확신도를 넣는다 |
| id | 응답표의 구절(phrase) id. 합성할 문장, `none`, 임계값 미만일 때는 빈 값 |
| reply | 해당 언어의 응답 문장. 위와 동일하게 빈 값 |
| lang | 발화로부터 추정. 히라가나·가타카나면 ja, 한글이면 ko, 한자면 zh, 그 외에는 en. 해당 언어 후보가 없으면 ja로 처리한다 |

`none` 및 임계값 미만:

```json
{"intent": "none", "score": 0.9991, "id": "", "reply": "", "lang": "ja"}
```

예외 시에는 `score`를 포함하지 않는다. `{"intent":"error","error":"..."}`. 클라이언트는 `score`가 없는 응답을 정상 결과로 처리하지 않는다. 본문 처리는 계속 진행한다.

언어별 후보가 여러 개일 때는 그중 하나를 무작위로 선택한다.

제작자의 상주 실측(2회):

| | 진행 메모 | 별도 세션 확인 |
|---|---|---|
| 소켓 수신 시작 | 2.26 초 | 1.97 초 |
| RSS | 746MB | 745MB |
| 왕복(RTT) | median 5.07 ms / p90 5.52 / min 3.27 (n=200, tokenize+추론+JSON) | 8개 발화 시 3.45–9.59 ms |

8개 발화 확인: 「ありがとう」4.18 ms, thanks 0.9719, 「おはよう」3.45 ms, morning 0.9888, 「今日の天気は？」4.56 ms, none 0.9991, 「これデプロイして」3.84 ms, none 0.9995, 「ごめん、間違えた」4.69 ms, apology 0.9961, 영어 Thanks 6.36 ms, thanks 0.9512 (id 빈 값), 谢谢 9.59 ms, thanks 0.8554, 고마워요 7.65 ms, thanks 0.7966. 소리는 재생하지 않았다.

음성 입력 측은 텍스트 변환 직후에 한 줄을 보낸다. 제작자의 `voicein` 대기 시간은 0.2초이다. 소켓이 없거나, 죽어 있거나, 타임아웃이 발생하거나, JSON이 깨진 경우에는 즉시 응답하지 않고 본문을 기존 방식대로 전달한다. 상주 프로세스의 자동 실행은 동일한 `serve.py`가 이미 실행 중일 때는 실행하지 않는다. 실행에 실패하더라도 음성 입력은 중단하지 않는다.

## 7. 임계값 및 합격 기준

최초 채택 임계값은 0.5였으나, 현재 임계값은 구술 시험 조정 후 **0.38**이다. 현재 값의 측정은 최초 값의 측정과 구분하며, 변경 시에는 dev의 오작동(誤爆)과 smoke를 모두 확인한다.

[tests/](../tests/) 의 run-all은 소리가 나지 않는다. 즉답(即答) 2개 항목은 상주 소켓(없을 경우 `AIZUCHI_SERVE` 및 `AIZUCHI_MODEL`을 이용한 임시 소켓)에 `tests/aizuchi/` 의 TSV를 전송한다. 모델 본체는 테스트에 포함되지 않는다. 소켓이 없으면 이 2개 항목은 불합격 처리된다.

| 자료 | 합격 기준 |
|---|---|
| `smoke.tsv` (양성 132 + none 120) | 의도 정답률 ≥ 0.9 이고, none을 다른 의도로 분류한 비율 ≤ 0.01 |
| `smoke-dictation.tsv` (silent 600 + reply 200) | 소리가 나지 않아야 할 행이 32개 의도 중 하나로 소리가 난 비율이 합격 라인 이내일 것. 소리가 나야 할 행을 놓친 비율도 합격 라인 이내일 것. `expect`가 silent / reply 이외라면 불합격 |

소리 발생 여부는 예측 의도가 `speak_intents.txt`에 포함되어 있는지에 따라 결정된다. 정답 의도와 다르더라도 32개 의도 중 하나라면 dictation에서는 "소리 남"으로 간주한다.

작성자의 int8 상주, 최초 run-all (2026-09-24 18:51, 무음):

| 항목 | 결과 |
|---|---|
| smoke | 합격. 126/132 = 0.9545, none 오작동 0/120 |
| dictation | 불합격. 무언(silent) 상태에서의 오작동은 합격 기준 이내. 응답(reply) 누락은 기준 미달 |

smoke 불합격 사례에는 임계값 미만의 `none`("잘 자요", 영어 Good morning, 한국어 취침 인사)과 surprise를 sad로 분류한 1건이 있다. dictation 누락 사례에는 인사가 `none`이 된 경우와 최초(임계값 0.5, 구 whitelist 30개 의도) 기록이 포함되어 있으며, 당시에는 "알겠습니다", "확인했습니다"가 ack(whitelist 외)로 분류되는 사례도 있었다. 이후 whitelist에 ack와 input-wait를 추가하여 32개 의도로 확장하고, 임계값을 0.38로 변경하였다. 현재 실측치는 dictation 오작동 0/600, 누락 18/200(수정 후 잔여 건 포함)이다.

## 8. 응답 표

열은 `intent`, `lang`, `text`, `id`(탭)로 구성됩니다. 1개의 의도 × 1개의 언어당 1~3개의 문장을 작성합니다. 문장은 응답하는 측의 말투로 작성합니다. 사용자의 발화를 그대로 따라 하는 앵무새식 답변은 피합니다. 식사나 장소를 특정하는 문장은 즉답(immediate response)에 두지 않습니다.

`id`가 있는 행은 미리 만들어둔 음성 프레이즈의 id입니다. 빈 행은 TTS로 읽습니다. 작성된 표는 총 536행(54개 의도 × 4개 언어)이며, id가 있는 행은 479개, id가 빈 행은 57개입니다. 빈 행 57개는 en 21, zh 18, ko 18이며, 일본어 134행은 모두 id가 있습니다. 일본어 후보 수는 의도별로 1~3개입니다.

예시 (표에 있는 후보):

| 발화 의도 | 언어 | 응답 문장 | id |
|---|---|---|---|
| thanks | ja | どういたしまして | reply-thanks-1 |
| thanks | ja | こちらこそ、ありがとう | reply-thanks-2 |
| apology | ja | 大丈夫、心配いらない | z-emo-058 |
| apology | ja | 気にしないで、大丈夫だよ | reply-apology-1 |
| morning | ja | 良い朝ですね | z-grt-032 |
| morning | ja | おはようございます。今日も良い一日になりますように。 | greet-good-morning-today |
| sad | ja | つらかったね、そばにいるよ | reply-sad-1 |
| angry | en | That would really make me mad too | （빈 칸. 합성） |

후보가 여러 개일 경우 실행할 때마다 1개를 선택합니다. 위의 표는 추첨 결과가 아닙니다. 재학습은 필요하지 않으며, 표만 교체하면 됩니다.
