# Voice recipe

Mac 上の AI 席（Claude Code または Pi）に、音声入力・即答・要約読み上げ・表示中の席だけ鳴らす音声層を足すレシピです。中身は [SPEC.md](SPEC.md)・[SPEC-input.md](SPEC-input.md)・[SETUP.md](SETUP.md)・[tests/](tests/) です。出力はこの `SPEC.md` をあなたの AI に渡し、`tests/` が全部通るまで作らせてください。入力は `SPEC-input.md` と `SETUP.md` です。

A recipe to give Claude Code or Pi a voice layer on a Mac: voice input, instant replies, spoken summaries, and playback only on the seat you are looking at. This repo is [SPEC.md](SPEC.md), [SPEC-input.md](SPEC-input.md), [SETUP.md](SETUP.md), and [tests/](tests/). Give `SPEC.md` to your AI and have it build until every test in `tests/` passes. For input, give it `SPEC-input.md` and `SETUP.md`.

## 日本語

### 何ができるか

1. **即答** — こちらが話した直後に、挨拶・感謝・謝罪・感情などの短い定形返事を鳴らす。それ以外は黙る。
2. **要約して読む** — エージェントの長い返事を耳向けに短くし、AivisSpeech が 1 文ずつ読む。
3. **見ている席だけ鳴る** — tmux で複数席があっても、今表示している席以外は無音。

**音声入力** — [SPEC-input.md](SPEC-input.md) と [SETUP.md](SETUP.md) をあなたの AI に渡せば、PTT（右 Option）と任意のハードウェアボタンを使う入力環境が組める。マイクを録り、whisper.cpp で文字にし、置換表で直して前面のアプリへ入れる。音声認識経路はローカルで動きます。認識後は挨拶・感謝・謝罪・感情などの定形意図だけ即答に渡し、判定に失敗しても入力本文はそのまま続く。要約・書き換えの接続先は別設定で、外部サーバーも指定できます。USB microphone 受信機ボタンはトグルで、2 回目に認識結果を入力して Enter 送信します。右 Option は押している間だけ録音し、Enter は送りません。

### 要るもの

- **Mac**
- **マイク（作者のおすすめ）** — a USB wireless microphone（USB 受信機。Mac 上の名前は the USB receiver、48 kHz）
- **AivisSpeech**（[公式](https://aivis-project.com/speech/)）と、声のモデル。声は各自 [AivisHub](https://hub.aivis-project.com/) から入れる
- **要約方法の例**（要約器は `apple` / `openai` / `off` から選択可能）
  - 自作 Gemma 4（`gemma-4-26B-A4B-NVFP4-lmfp8`。[tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark) の公開レシピ。OpenAI 互換 API を :8890。要約約 1.7 秒）
  - Apple（macOS のオンデバイス LLM）
  - MLX の Gemma 4 E4B（`mlx-community/gemma-4-e4b-it-4bit`。思考は切る）
  - OpenAI 互換の接続先
- **Claude Code** または **Pi**（席の終わりと確認待ちを hook する）

### あなたの環境別のおすすめ

要約に使う AI は、持っているもので選ぶ。

| 環境 | おすすめ | メモ |
|---|---|---|
| DGX Spark など GPU 機がある | 自作 Gemma 4（[tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark)） | 要約約 1.7 秒。作者の構成 |
| Mac だけ・Apple Intelligence が使える地域 | Apple のモデル | 設定不要 |
| Mac だけ・使えない地域 | MLX の Gemma 4 E4B 4bit（`mlx-community/gemma-4-e4b-it-4bit`、思考オフ、指示は案 2） | 要約約 1.9 秒、常駐約 4.5GB。要点の欠けは案 2 で 0/10 |
| メモリ 8GB の Mac・AI を使わない | ルールによる読み上げ | 下の「8GB の Mac」設定。声は AivisSpeech（常駐約 1GB）か macOS 標準の `say` |
| 既に Ollama／LM Studio／他の OpenAI 互換を立てている | その接続先を指定する | `summarizer` を `openai`、`summarizer_base` に URL |

#### メモリ 8GB の Mac

LLM を使わず、`~/.config/voice/config.json` に次を設定する。`summarizer: "off"` で要約器を呼ばず、`rewrite: false` で書き換えも止める。長い返事は `voice.py` の規則で整形し、表の行やパスなどを除いて先頭の 2 文を読む（1 文だけにする設定キーはありません）。AivisSpeech は常駐約 1GB。さらに軽くする場合は AivisSpeech を使わず、macOS 標準の `say` にフォールバックさせる。Aizuchi は常駐約 0.39GB（(internal) の実測）で、音声入力に `--no-aizuchi` を付けると停止できる。

```json
{
  "mode": "summary",
  "summarizer": "off",
  "rewrite": false
}
```

この設定では長い返事を内容に沿って要約できず、先頭の文だけでは要点を取りこぼすことがある。

作者の構成は、自作 Gemma 4・a USB wireless microphone（Mac 上の名前は the USB receiver、48 kHz）・an AivisHub voice model。

- **Claude Code** — `tools/voice/output/voice-reply.sh` と `voice-notify.sh` を `~/.claude/settings.json` の Stop / Notification hook として登録する。設定例と配置手順は [SETUP.md](SETUP.md) を参照。
- **Pi** — 拡張の実体は `tools/harness/voice-pi.ts`。Pi の拡張ディレクトリへ配置して有効化する手順は [SETUP.md](SETUP.md) を参照。応答完了と複数の確認待ち経路を扱う。

### 使い方

この `SPEC.md` をあなたの AI に渡し、`tests/` が全部通るまで作らせる。音声入力は [SPEC-input.md](SPEC-input.md) と [SETUP.md](SETUP.md) を渡せば、PTT（右 Option）と任意のハードウェアボタンを使う入力環境が組める。

`tests/` の run-all が通る条件:

| 項目 | 通る条件 |
|---|---|
| 経路の試験 | 全件 pass |
| 無音の通し試験 | 全件 pass |
| 即答 smoke | 意図 ≥ 0.9、none 誤爆 ≤ 0.01 |
| 音声入力風の即答 | 無言の誤鳴 ≤ 0.01、返事の取りこぼし ≤ 0.10 |

### 音声データは `project/voice-recipe/` に同梱しない

声も作り置きのクリップも、`project/voice-recipe/` には同梱していません。project 内の別ディレクトリには再生用クリップがあります。AivisSpeech と AivisHub のモデルは各自で入れてください。試験の材料は文字だけです。

### 実測

以下は各記録時点の測定値です。run-all の通過条件は上表、初回測定は修正前の記録で、現行の合否を示すものではありません。

出どころは `e4b-prompt.md`・`summ-compare.md`・`runall-first.md`（2026-09-24）。試料は本物の返事 10 件（本文 300 字以上）。要約は temperature 0.2。

**即答**（run-all 初回、音なし）: smoke 意図 126/132 = 0.9545、none 誤爆 0/120。音声入力風は無言の誤鳴 0/600、返事の取りこぼし 35/200 = 0.1750。経路試験は 19 pass / 8 fail。無音の通し試験は 10 pass。合計 2/4。直し前の数字。

**MLX Gemma 4 E4B**（`mlx-community/gemma-4-e4b-it-4bit`、思考オフ）: 1 件 1.6〜2.9 秒、ピーク約 4.4GB。思考を切らないと要約が空になる。既定の要約指示では、主語のすり替え 0・依頼の作り足し 0・要点の欠け 5・表やパスの読み上げ 1。E4B 向け指示の案 2 が最も近く、欠け・主語・依頼は 0。200 字を超えたのは 2 件（222 字と 241 字）。3 案とも「200 字以内かつ欠け 1 以下かつ主語 0 かつ依頼 0」は同時には満たさなかった。

**OpenAI 互換の Gemma 26B**（同じ 10 件・同じ既定指示）: 主語のすり替え・依頼の作り足し・要点の欠け・表やパスの読み上げは 0。

## English

### What it does

1. **Instant replies** — Right after you speak, it plays a short canned reply for greetings, thanks, apologies, and emotion. Everything else stays silent.
2. **Summarize and speak** — Long agent replies are shortened for the ear. AivisSpeech reads them one sentence at a time.
3. **Only the seat you are looking at plays** — With several tmux seats, seats you are not viewing stay silent.

**Voice input** — Give [SPEC-input.md](SPEC-input.md) and [SETUP.md](SETUP.md) to your AI to build an input stack using push-to-talk (Right Option) and an optional hardware button. It transcribes with whisper.cpp, applies the replacement table, and pastes into the front app. Speech recognition runs locally; summarization and rewriting have separate settings and may use a remote endpoint. Right after transcription, only canned intents such as greetings, thanks, apologies, and emotion are handed to instant replies; if that check fails, the input text still continues. The USB microphone receiver button toggles recording and sends Enter after transcription on the second press. Right Option records only while held and does not send Enter.

### What you need

- **A Mac**
- **Mic (author's pick)** — a USB wireless microphone (USB receiver; the Mac lists it as the USB receiver)
- **AivisSpeech** ([site](https://aivis-project.com/speech/)) and a voice model. Get voices yourself from [AivisHub](https://hub.aivis-project.com/)
- **Summarizer examples** (the setting supports `apple`, `openai`, and `off`)
  - Custom Gemma 4 (`gemma-4-26B-A4B-NVFP4-lmfp8`; public recipe [tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark); OpenAI-compatible API on :8890; about 1.7 s per summary)
  - Apple (on-device LLM on macOS)
  - MLX Gemma 4 E4B (`mlx-community/gemma-4-e4b-it-4bit`; thinking off)
  - An OpenAI-compatible endpoint
- **Claude Code** or **Pi** (hooks for turn-end and “waiting for you”)

### Picks for your setup

Pick the summarizer you already have.

| Setup | Pick | Notes |
|---|---|---|
| A GPU box such as a DGX Spark | Custom Gemma 4 ([tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark)) | About 1.7 s per summary. Author's setup |
| Mac only, Apple Intelligence available in your region | Apple's on-device model | No extra setup |
| Mac only, Apple Intelligence unavailable in your region | MLX Gemma 4 E4B 4bit (`mlx-community/gemma-4-e4b-it-4bit`, thinking off, prompt draft 2) | About 1.9 s per summary, about 4.5 GB resident. Missing points 0/10 with draft 2 |
| 8 GB Mac, no AI | Rule-based reading | See “8 GB Mac” below. AivisSpeech (about 1 GB resident) or macOS `say` |
| Ollama, LM Studio, or another OpenAI-compatible server already running | Point the summarizer at that server | Set `summarizer` to `openai` and `summarizer_base` to its URL |

#### 8 GB Mac

To avoid LLMs, set the following in `~/.config/voice/config.json`. `summarizer: "off"` skips the summarizer, and `rewrite: false` disables rewriting. For long replies, `voice.py` applies rule-based cleanup, removing table rows, paths, and similar formatting, then reads the first two sentences (there is no setting for limiting this to one sentence). AivisSpeech uses about 1 GB resident; for a lighter setup, skip AivisSpeech and use the macOS built-in `say` fallback. Aizuchi uses about 0.39 GB resident (measured in (internal)); pass `--no-aizuchi` to voice input to disable it.

```json
{
  "mode": "summary",
  "summarizer": "off",
  "rewrite": false
}
```

Without an LLM, long replies cannot be summarized by meaning, so reading only their opening sentences may miss key points.

Author's setup: custom Gemma 4, a USB wireless microphone (the Mac lists it as the USB receiver), an AivisHub voice model.

- **Claude Code** — Register `tools/voice/output/voice-reply.sh` and `voice-notify.sh` as Stop / Notification hooks in `~/.claude/settings.json`. See [SETUP.md](SETUP.md) for the config example and installation steps.
- **Pi** — The extension source is `tools/harness/voice-pi.ts`. Install and enable it in Pi's extension directory as described in [SETUP.md](SETUP.md). It handles response completion and multiple confirmation-wait paths.

### How to use it

Give this `SPEC.md` to your AI and have it build until every test in `tests/` passes. For voice input, give it [SPEC-input.md](SPEC-input.md) and [SETUP.md](SETUP.md) to build an input stack using push-to-talk (Right Option) and an optional hardware button.

run-all in `tests/` passes when:

| Suite | Pass bar |
|---|---|
| Path tests | all pass |
| Silent end-to-end | all pass |
| Instant-reply smoke | intent ≥ 0.9, none misfire ≤ 0.01 |
| Dictation-style instant reply | silent false-speak ≤ 0.01, reply miss ≤ 0.10 |

### No audio assets in `project/voice-recipe/`

No voice models or pre-rendered clips are bundled in `project/voice-recipe/`. Other directories in the project contain playback clips. Install AivisSpeech and an AivisHub model yourself. Test fixtures are text only.

### Measured numbers

These are measurements from the cited runs. The pass bars are listed above; the first run is a pre-fix record and does not establish the current result.

Sources: `e4b-prompt.md`, `summ-compare.md`, `runall-first.md` (2026-09-24). Sample: 10 real assistant replies, each 300+ characters. Summaries at temperature 0.2.

**Instant replies** (first run-all, no sound): smoke intent 126/132 = 0.9545, none misfire 0/120. Dictation-style: silent false-speak 0/600, reply miss 35/200 = 0.1750. Path tests 19 pass / 8 fail. Silent end-to-end 10 pass. Total 2/4. These are pre-fix numbers.

**MLX Gemma 4 E4B** (`mlx-community/gemma-4-e4b-it-4bit`, thinking off): 1.6–2.9 s per item, peak about 4.4 GB. With thinking left on, the spoken summary is empty. Default summary prompt: 0 subject swaps, 0 invented requests, 5 missing points, 1 table/path readout. Prompt draft 2 is the closest: 0 missing points, 0 subject swaps, 0 invented requests. Two items ran long (222 and 241 characters). None of the three drafts met all of: ≤200 characters, ≤1 missing point, 0 subject swaps, 0 invented requests.

**OpenAI-compatible Gemma 26B** (same 10 replies, same default prompt): 0 subject swaps, 0 invented requests, 0 missing points, 0 table/path readouts.
