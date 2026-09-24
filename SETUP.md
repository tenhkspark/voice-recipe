# 導入手順（入力と出力）

人でも AI でも、上から順にやれば同じ音声環境になる。材料はこの Mac（macOS 27.0 26A428、arm64）の実物。推測で埋めていない。分からない行は「不明」。

鍵・家のホスト名・実アドレスは書かない。設定の雛形はプレースホルダ。

---

## 1. 入れるもの

音声の入出力で実際に使っているものだけ。`/Applications`・Homebrew・MacPorts・pip / venv の実物。

| 何 | この Mac の版 | 置き場 | 入手 |
|---|---|---|---|
| マイク（作者のおすすめ） | a USB wireless microphone。Mac 上の名前は `the USB receiver`（`system_profiler SPAudioDataType`: Manufacturer: the manufacturer、USB、48kHz、Default Input Device） | USB 受信機を Mac に接続 | USB microphone のワイヤレスマイク。USB 受信機でつなぐ。作者はこれを使っている |
| Hammerspoon | 1.1.1（6936） | `/Applications/Hammerspoon.app`。brew cask では未インストール。ログイン項目 | https://www.hammerspoon.org/ ／ https://github.com/Hammerspoon/hammerspoon |
| iTerm2 | 実アプリ 3.7.2。Homebrew Caskroom 登録 3.6.11（版が異なる） | `/Applications/iTerm.app` | https://iterm2.com/ |
| tmux | 3.6b | `/opt/local/bin/tmux`（MacPorts。Homebrew の formula には無い） | https://github.com/tmux/tmux |
| ffmpeg | 8.1 | `/opt/local/bin/ffmpeg`（MacPorts。voicein がこの絶対パスを直書き） | https://ffmpeg.org/ |
| Python 3.9.6 | CLT | `/usr/bin/python3`。`voicein.py` の shebang と hook の `/usr/bin/python3` | Apple Command Line Tools |
| Python 3.12.14 | Homebrew `python@3.12` | `/opt/homebrew/bin/python3.12`。Aizuchi と mlx-lm の venv の土台 | https://www.python.org/ ／ `brew install python@3.12` |
| uv | 0.12.9 | `/opt/homebrew/bin/uv` | https://github.com/astral-sh/uv |
| Node | v24.19.0 | nvm `~/.nvm/versions/node/v24.19.0`。Pi 用 | https://nodejs.org/ |
| jq | 1.7.1-apple | `/usr/bin/jq`。hook の JSON 読み | macOS 付属 |
| Claude Code | 2.1.281 | `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.281` | https://docs.claude.com/en/docs/claude-code |
| Pi | 0.87.1 | `pi` = `@earendil-works/pi-coding-agent` | `npm i -g @earendil-works/pi-coding-agent` |
| whisper.cpp | 1.9.1（commit `2ca53bb`、Metal ON） | `~/.local/stt/whisper.cpp`、実行ファイル `build/bin/whisper-cli` | https://github.com/ggml-org/whisper.cpp |
| Whisper モデル | `ggml-large-v3-turbo.bin` 1.5G | `~/.local/stt/models/ggml-large-v3-turbo.bin` | 下記 4 節 |
| AivisSpeech Engine | 1.2.0 | `~/.config/voice/aivis/macOS-arm64/run`。`/Applications` に AivisSpeech.app は無い | https://github.com/Aivis-Project/AivisSpeech-Engine/releases/tag/1.2.0 |
| 声「an AivisHub voice model」 | モデル 1.0.0、AIVMX UUID `<model-uuid>` | `~/Library/Application Support/AivisSpeech-Engine/Models/`。Calm の speaker_id = `1310138977` | https://hub.aivis-project.com/aivm-models/<model-uuid> |
| onnxruntime（即答） | 1.30.0 | `project/voice/aizuchi/.venv`（Python 3.12.14） | pip。同じ venv に numpy 2.5.3、tokenizers 0.22.2、sentencepiece 0.2.2、huggingface_hub 0.36.2、protobuf 7.36.2 |
| mlx-lm（任意の要約） | 0.31.3（mlx 0.32.2） | `tools/voice/output/.venv-mlx`。ログイン自動起動はしない | https://github.com/ml-explore/mlx-lm ／ `pip install mlx-lm` |
| コード本体 | project | `~/project/tools/voice/input/voicein.py`、`~/project/tools/voice/output/voice.py`、`~/project/project/voice/aizuchi/` | このリポジトリ群 |

入力デバイスは `ffmpeg -f avfoundation -list_devices true -i ""` の音声側番号を `VOICEIN_DEV` に書く（この Mac は `:0` = the USB receiver）。

`voicein` の入口: `~/.local/bin/voicein` → `~/project/tools/voice/input/voicein.py`。

音声入力の操作の正本は `~/.hammerspoon/init.lua`（tools/voice の外）。入れ方・許可・現行の 2 つの入力と削除済み経路は 7 節。

システム pip（CLT 3.9）にも onnxruntime 1.19.2 がある。即答と TTS はそれを見ていない。

---

## 2. macOS の許可

場所はすべて **システム設定 → プライバシーとセキュリティ**。付けたあと、そのアプリを終了して開き直す。入力監視とアクセシビリティは反映に **ログアウトまたは再起動** が要ることがある（この位置で一度 Hammerspoon を終了して開き直す。それでも eventtap が死ぬならログアウト）。

| 項目 | 場所 | 誰に | 何のため |
|---|---|---|---|
| マイク | プライバシーとセキュリティ → マイク | Hammerspoon。手で `voicein` を叩くときは iTerm2 とターミナル | ffmpeg の avfoundation 録音。失敗文は「マイク権限 or デバイス番号」 |
| アクセシビリティ | プライバシーとセキュリティ → アクセシビリティ | Hammerspoon。手で実行する場合は iTerm2 とターミナル | 前面アプリへ `hs.eventtap.keyStrokes` で貼る |
| 入力監視 | プライバシーとセキュリティ → 入力監視 | Hammerspoon | 右 Option の flagsChanged |

この Mac の ffmpeg が見ている音声デバイス:

- `[0] the USB receiver`（`VOICEIN_DEV` 既定 `:0`）
- `[1] BlackHole 2ch`

---

## 3. whisper.cpp とモデル

```sh
mkdir -p ~/.local/stt/models
git clone https://github.com/ggml-org/whisper.cpp.git ~/.local/stt/whisper.cpp
cd ~/.local/stt/whisper.cpp
cmake -B build -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_BUILD_EXAMPLES=ON
cmake --build build --config Release -t whisper-cli
./models/download-ggml-model.sh large-v3-turbo ~/.local/stt/models
```

モデル URL（スクリプトの `src`）: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin`。

voicein が読む固定パス:

- 実行ファイル `~/.local/stt/whisper.cpp/build/bin/whisper-cli`
- モデル `~/.local/stt/models/ggml-large-v3-turbo.bin`
- 認識引数: `-l ja -nt --no-prints`、`--prompt` に `glossary.txt`

ffmpeg 録音: `-f avfoundation -i :0 -ar 16000 -ac 1`。PTT 時は RMS レベルを `/tmp/voicein-ptt.level` に直書き。

---

## 4. AivisSpeech のエンジンと声

この Mac は GUI アプリを入れず、エンジン単体。

1. https://github.com/Aivis-Project/AivisSpeech-Engine/releases/tag/1.2.0 から `AivisSpeech-Engine-macOS-arm64-1.2.0.7z.001` を取る（203MB）。
2. 7-Zip で展開する。今の PATH に `7z` / `7zz` は無い（展開済みの `run` だけがある）。GUI の AivisSpeech（https://aivis-project.com/speech/ ）から入れる方法でも同じエンジンになる。
3. 実行ファイルを `~/.config/voice/aivis/macOS-arm64/run` に置く。
4. 起動引数（実測の LaunchAgent）: `--host 127.0.0.1 --port 10101 --disable_sentry`。
5. 声: AivisHub の [an AivisHub voice model](https://hub.aivis-project.com/aivm-models/<model-uuid>) から **AIVMX** をダウンロード（約 241MB、ACML 1.0）。
6. ファイルを `~/Library/Application Support/AivisSpeech-Engine/Models/` に置く。この Mac のファイル名は `<model-uuid>.aivmx`。
7. **エンジンを再起動する**（モデル追加の反映。LaunchAgent なら次節の kickstart）。初回は BERT キャッシュの取得でネットが要る。
8. `curl -s http://127.0.0.1:10101/speakers` で `"name": "an AivisHub voice model"` と style `"Calm"` id `1310138977` を確認。
9. ユーザー辞書（任意・冪等）: `python3 ~/project/tools/voice/output/register-dict.py`。

`config.json` の `speaker_id` を `1310138977` にする（次節）。

---

## 5. Python の仮想環境

即答（必須）:

```sh
/opt/homebrew/bin/python3.12 -m venv ~/project/project/voice/aizuchi/.venv
~/project/project/voice/aizuchi/.venv/bin/pip install onnxruntime numpy tokenizers sentencepiece huggingface_hub
```

この Mac の実測版は 1 節の表。常駐は `serve.py`（既定ソケット `~/.config/voice/aizuchi.sock`、モデル `aizuchi/onnx/model-int8.onnx`）。

要約用 mlx-lm（任意。この Mac の本番要約は OpenAI 互換接続先。mlx は手動 `up`）:

```sh
sh ~/project/tools/voice/output/mlx-summ.sh up
```

venv は `tools/voice/output/.venv-mlx`。モデル `mlx-community/gemma-4-e4b-it-4bit`、`127.0.0.1:8091`、思考オフ `--chat-template-args '{"enable_thinking":false}'`。launchd には載せない。

`voice.py` / `voicein.py` 本体は標準ライブラリ。追加の pip は要らない。

---

## 6. 設定ファイル

`~/.config/voice/config.json`。無いキーは `voice.py` の既定で埋まる。実アドレスと鍵は入れない。

雛形:

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

キーの意味:

| キー | 意味 |
|---|---|
| `enabled` | 全体のオンオフ |
| `mode` | `off` / `earcon` / `summary` / `full` |
| `say_rate` | Aivis 失敗時の `say -v Kyoko` の話速 |
| `speaker_id` | Aivis の話者。an AivisHub voice model Calm = 1310138977 |
| `synth_timeout` | 合成の秒数上限 |
| `purposes` | 用途ごとのオンオフ（false はその用途を完全に黙らせる） |
| `quiet_hours` | 自動の通常読み上げと earcon を抑止する時間帯 `[開始, 終了]`。手動 read / test は別 |
| `min_interval_sec` | 連続発話の最短間隔 |
| `post_rec_grace_sec` | 録音終了後、自動発話しない秒数 |
| `rewrite` | `sum_kind == fallback` のとき、要約失敗時に作る先頭文フォールバックを言い換える。`short` の短文や `gemma` 要約成功には適用しない。 |
| `rewrite_skip_under` | この字数未満は rewrite しない |
| `rewrite_timeout` | rewrite 呼び出しの秒数 |
| `dedupe_window_sec` | 同じ文を繰り返さない窓 |
| `night_brief_hours` / `night_brief_cap` | 夜間は短く。quiet の外側だけ効く |
| `pack` | 作り置きクリップ（model / voice / lang） |
| `summarizer` | `apple` / `openai` / `off` |
| `summarizer_base` | OpenAI 互換の接続先 URL。雛形の `127.0.0.1` は同じ Mac 上の要約サーバー用。別ホストのサーバーを使う場合は、その環境で到達可能な URL に置き換える（実ホスト名・アドレスは記載しない） |
| `summary_timeout` | 要約の秒数。コード既定は 6.0 と 15.0 の二箇所。この Mac のファイルは 6.0 |
| `seat` | 空なら表示中の tmux 席だけ鳴らす |

Aivis の接続先は環境変数 `VOICE_AIVIS_BASE`（未設定時 `http://127.0.0.1:10101`）。話し方の速度と間は `tools/voice/output/speech-styles.json`（話者 ID は見ない）。

`~/.config/voice/speakers.json` はエンジンから拾った話者一覧のキャッシュ。手で書かなくてよい。

---

## 7. Hammerspoon（入れ方・許可・init.lua・2 つの現行入力と削除済み経路）

音声入力の操作の正本は **`~/.hammerspoon/init.lua`**（tools/voice の外。この Mac のファイルは 2026-08-25）。`tools/voice/input/hammerspoon-init.lua` は今は無い。Hammerspoon が右 Option と設定したハードウェアボタンを監督し、`~/.local/bin/voicein` を子プロセスとして叩く。常時リッスンは削除済みで、残存コードの説明は下記。

### 入れ方

1. https://www.hammerspoon.org/ から Hammerspoon を入れる（この Mac は 1.1.1、`/Applications/Hammerspoon.app`。Homebrew cask では未インストール）。
2. ログイン項目に Hammerspoon を入れる。
3. `mkdir -p ~/.hammerspoon ~/.local/bin`
4. 正本を置く: 利用する Hammerspoon 設定を `~/.hammerspoon/init.lua` へコピーする（または同等の内容を書く）。起動時に `hs.ipc.cliInstall(os.getenv("HOME") .. "/.local")` が `~/.local/bin/hs` を入れる。
5. `ln -sf ~/project/tools/voice/input/voicein.py ~/.local/bin/voicein`
6. メニューバーの Hammerspoon → Reload Config。起動時アラートは PTT の起動を示す。

`init.lua` での Lua パス例: `VOICEIN = os.getenv("HOME") .. "/.local/bin/voicein"`。録音表示は Hammerspoon canvas で描く波形ピルで、画像ファイルは不要。設定には任意のマスコット画像 `~/project/tools/voice/input/indicator.png` を指定する箇所が残るが、このファイルは現在存在しないため画像なしで表示する。読み上げ停止は `~/project/tools/voice/output/voice.py stop`。録音開始のたびに `voice.py stop` を非同期で叩く（割り込み）。黙らせるキーは Cmd+Ctrl+.（`hs.hotkey.bind({"cmd", "ctrl"}, ".")` → `voice.py stop`）。

### 許可（アクセシビリティ）

前面へタイプする `hs.eventtap.keyStrokes` / `keyStroke` と、右 Option の `eventtap` のために **Hammerspoon をアクセシビリティへ入れる**。

1. Hammerspoon を一度起動する（許可ダイアログが出ることがある）。
2. **システム設定 → プライバシーとセキュリティ → アクセシビリティ** で Hammerspoon をオンにする。
3. マイクも Hammerspoon に付ける（2 節。ffmpeg は HS の子なので、マイク処理はアプリ単位）。
4. **Hammerspoon を終了して開き直す**。アクセシビリティの反映にログアウトまたは再起動が要ることがある（2 節）。

右 Option の flagsChanged が取れないときは、同じ画面の **入力監視** に Hammerspoon を足してからアプリを再起動する。

### 2 つの現行入力（init.lua の実物）と削除済み経路

認識が終わると、前面の入力欄へ `hs.eventtap.keyStrokes` で直接タイプする。Enter を打つかは経路による（下表）。

| # | 操作 | init.lua の入口 | 録音 | タイプ後の Enter |
|---|---|---|---|---|
| 1 | 右 Option を押している間だけ | `hs.eventtap`（右 Option の `flagsChanged`）→ `startRec` / `stopRec()` | `voicein --ptt start` / `stop`。離すまで。上限 90 秒 | 打たない |
| 2 | 対応する受信機ボタン（F18） | `hs.hotkey.bind({}, "f18")`。トグル。認識中の連打は無視。0.5 秒デバウンス | 1 押し目 `startRec("button")`、2 押し目 `stopRec(true)` | 打つ（150ms 待って `return`） |

**1. 右 Option（PTT）** — 押している間だけ録る。コールバックは旗の判定だけ、重い処理は `hs.timer.doAfter(0, …)`。監視オブジェクトは GC で消えないよう保持する。

**2. 受信機ボタン＝F18** — F18 の出どころは init.lua の hidutil リマップ（Karabiner は使わない）。

経路: 受信機ボタン → USB 受信機が出すイベント → `/usr/bin/hidutil property` で対象機器だけ F18 に割り当て → `hs.hotkey.bind({}, "f18")`。USB 機器 ID と送出イベントは利用機器で確認する。キーボード本体へ影響しないよう、機器に限定して割り当てる。リマップが揮発する環境では、Hammerspoon 起動時と機器の接続後に再適用する。

**削除済み: 常時リッスン** — init.lua には `VoiceinListen.startDaemon()` が `hs.task.new(VOICEIN, nil, {"--listen"})` で子プロセスを起動する残存コードがある。`VoiceinListen.daemonEnabled` は **`false`**（2026-08-02 凍結）。仮に有効化しても、この Mac の `voicein.py` は `--listen` を渡すと「常時リッスンは 2026-09-07 に削除されました（決定 D182）」で終了するため、現行の入力経路ではない。

### 固着検知と eventtap の自動復旧

`VoiceinPTT.watchdog`（1 秒ごと）:

- `flagWatcher:isEnabled()` が false なら `flagWatcher:start()`（eventtap 自動復旧）。コンソールに `voicein PTT: eventtap自動復旧`。
- 録音中かつ起点が `"ptt"` かつ今は Option が離れている → `stopRec()`（固着検知。離しイベントを取り逃したときの復帰）。ボタン起点には掛けない（トグル録音を 1 秒で殺す実地バグへの対応。ボタン側の保険は 90 秒上限）。

スリープ／ロック解除（`hs.caffeinate.watcher` の `systemDidWake` / `screensDidUnlock`）でも `flagWatcher` が切れていれば立て直す。

---

## 8. ログイン時の自動起動

ログイン項目は `osascript`（System Events の login item）と `~/Library/LaunchAgents` で見る。管理者の許可が要るコマンドは使わない。

音声関連の LaunchAgent は `local.voice.aivis.plist` と `com.voice.seats.plist`。

LaunchAgent を入れたあとは **一度ログアウトして入り直す**か、その場で `launchctl bootstrap` する。

### Aivis エンジン — `~/Library/LaunchAgents/local.voice.aivis.plist`

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
# モデル追加後の再起動
launchctl kickstart -k gui/$(id -u)/local.voice.aivis
```

この Mac は `launchctl list` で `local.voice.aivis` が稼働。

### Aizuchi と席 — `com.voice.seats`

plist は `~/Library/LaunchAgents/com.voice.seats.plist` → `~/project/tools/sessions/com.voice.seats.plist`。`RunAtLoad` で `autostart.sh`。スクリプト先頭が Aizuchi:

```sh
pgrep -f '[a]izuchi/serve.py' >/dev/null || \
  aizuchi/.venv/bin/python ... start_new_session=True ... aizuchi/serve.py
```

Aizuchi だけ欲しいなら、同じ 1 行を自分のログインスクリプトに載せれば足りる。mlx-lm は載せない。

---

## 9. hook の登録

### Claude Code — `~/.claude/settings.json` に 2 本

Stop と Notification。プロジェクトの `~/project/.claude/settings.json` には voice の hook は無い（権限だけ）。入れる先はユーザーの `~/.claude/settings.json`。

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
            "statusMessage": "voice: 読み上げ"
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
            "statusMessage": "voice: 確認待ち"
          }
        ]
      }
    ]
  }
}
```

既存の `hooks` オブジェクトに足す。ファイル全体を上書きしない。

### Pi 拡張

```sh
mkdir -p ~/.pi/agent/extensions
ln -sf ~/project/tools/pi/extensions/voice.ts ~/.pi/agent/extensions/voice.ts
```

実装の実体は `tools/harness/voice-pi.ts`。実際の配置先とリンク先は各自の checkout に合わせて確認する。

---

## 10. 確認

### tests/（音を出さない）

手順の詳細は [tests/README.md](tests/README.md)。この Mac の実装パスでの例:

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

順: `test_paths.py` → `e2e_silent.sh` → `smoke.tsv` → `smoke-dictation.tsv`。1 つ落ちても最後まで走り、失敗があれば終了コード 1。`afplay` / `say` は試験が差し替える。

通る条件: 経路は全件 pass。無音の通し試験は全件 pass。即答 smoke は意図 ≥ 0.9 かつ none 誤爆 ≤ 0.01。口述風は誤鳴 ≤ 0.01 かつ取りこぼし ≤ 0.10。

同じ 4 項目を、パス固定の本番スクリプトでも回せる: `sh ~/project/tools/voice/output/tests/run-all.sh`。

### 声で「ただいま」

1. Aivis が 10101、Aizuchi ソケット、Hammerspoon が生きている。
2. 表示中の tmux 席で、右 Option を押したまま「ただいま」と言って離す。
3. 文字が前面に入り、即答の意図 `return-home` が `speak_intents.txt` にあるので、返事（「おかえり」など）が Aivis で鳴る。

`quiet_hours` の内側は自動の通常読み上げと earcon が抑止される。手動 read / test は別。録音直後の `post_rec_grace_sec`、席が vis と違う、ソケットが落ちている場合も、通常の返事は鳴らない。
