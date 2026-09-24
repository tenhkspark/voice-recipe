[日本語](./input.md) / [中文](./input.zh.md) / [한국어](./input.ko.md)

# SPEC-input — 音声入力の作り方

読者は利用者の AI エージェント。これを読めば、今の Mac 音声入力と同じ質（PTT → whisper.cpp → 置換 → 即答 Aizuchi → 前面へタイプ）を組める。値は 2026-09-24 時点の実物。推測で埋めない。不明は「不明」。即答対象の発話では、同期再生が終わるまで本文の stdout が返らず、入力が遅れることがある。

鍵・個人の置換表の中身・実ホストは書かない（形式と、装置として必要な定数だけ）。常時リッスン／ウェイクワードは 2026-09-07 に撤去済み（決定 D182）。主経路は PTT だけ。

参照実体（パスは `$HOME/project` を根とする）:

- `$HOME/project/tools/voice/input/voicein.py`（コマンド `voicein`、`$HOME/.local/bin/voicein` がここへの symlink）
- 同ディレクトリ `glossary.txt` / `replace.txt` / `mishear-candidates.tsv`
- `$HOME/.hammerspoon/init.lua`（ホットキーとタイプ。設計書が言う `input/hammerspoon-init.lua` の正本コピーはディスクに無い）
- `$HOME/.local/stt/whisper.cpp/build/bin/whisper-cli`（whisper.cpp 1.9.1、commit `2ca53bb45e38748d07b310eeb36245a7157ac882`、`GGML_METAL=ON`）
- `$HOME/.local/stt/models/ggml-large-v3-turbo.bin`（1.5G、ggml Whisper large-v3-turbo）
- `/opt/local/bin/ffmpeg`（MacPorts ffmpeg 8.1）
- `$HOME/project/project/voice/aizuchi/serve.py` と `speak_intents.txt`
- 即答の再生は `$HOME/project/tools/voice/output/voice.py` の `speak`（席・静かな時間・queue.lock）

---

## 1 構成と流れ

外部送信はしない。認識はローカル whisper.cpp。置換表はローカルファイル。即答分類はローカル UNIX ソケット。LLM 補正は既定オフ。

```
右Option押しっぱなし（または microphone button / CLI）
  → Hammerspoon startRec
      → voice.py stop（読み上げを即止める＝barge-in）
      → voicein --ptt start
          → ffmpeg avfoundation 16 kHz / 1ch / wav
          → RMS を /tmp/voicein-ptt.level へ無バッファ書き
      → 画面下中央の波形ピル
離す（またはボタン 2 押し目 / 90 秒上限）
  → voicein --ptt stop
      → ffmpeg に SIGINT、最大 5 秒待つ
      → wav が 24000 バイト未満なら空（押し損ね）
      → whisper-cli（ja、glossary を --prompt）
      → 幻聴集合 HALLUC なら空
      → table_fix（スラッシュ正規化 → replace.txt）
      → 口述ログへ追記（失敗しても本文は落とさない）
      → 空でなければ aizuchi_reply（同期再生。終わるまで次へ進まない）
      → 本文を stdout（末尾改行なし）
  → voicein 終了後、Hammerspoon が stdout を前面へ keyStrokes
      → ハードウェアボタン経路だけ、そのあと Enter
```

役割の分け方:

| 部品 | 役割 |
|---|---|
| Hammerspoon | キー監視、録音の開始/停止、波形、前面へのタイプ、読み上げ停止 |
| `voicein.py` | 録音プロセス、認識、幻聴除外、置換、ログ、Aizuchi 問い合わせ |
| whisper-cli | 16 kHz wav → 日本語テキスト |
| `replace.txt` | 誤認識形 → 正表記（決定的。本文を壊さない） |
| `glossary.txt` | whisper の initial prompt（語彙ヒント＋句読点の文体） |
| `mishear-candidates.tsv` | 文脈依存の誤認識の置き場。無条件置換にはしない |
| `aizuchi/serve.py` | 1 行テキスト → 1 行 JSON（intent / score / reply） |
| `voice.speak` | 即答の再生。席・静かな時間・順番待ちを通す |

起動の仕方:

1. Hammerspoon を起動する（reload で `init.lua` が載る。起動時に「voicein PTT 稼働（右Option押しっぱなし）」と出す）。
2. `voicein` が PATH にあり、実体が `voicein.py` を指す。
3. `whisper-cli` と `ggml-large-v3-turbo.bin` がある。
4. ffmpeg が `/opt/local/bin/ffmpeg` にある（コードがこのパスを直書きしている）。
5. 即答を鳴らすなら `aizuchi/serve.py` がソケットを開いている。ログイン時の `tools/sessions/autostart.sh` は `pgrep -f '[a]izuchi/serve.py'` が居なければ venv の python で `start_new_session=True` 起動する。居れば何もしない。
6. macOS の許可: マイク（ffmpeg）、入力監視（右Option の eventtap）、アクセシビリティ（keyStrokes / Cmd+V）。

手で試す入口（PTT 以外）:

```
voicein                 # 録音開始 → Enter で停止 → pbcopy。stderr に所要秒
voicein --paste         # さらに前面へ Cmd+V（System Events。アクセシビリティが要る）
voicein --no-fix        # 置換を飛ばす
voicein --no-aizuchi    # 即答しない
voicein --model NAME    # 絶対パス、または ggml-NAME.bin の短縮名
voicein --file wav      # 録音せず既存 wav
voicein --keep          # 録音 wav を消さない
voicein --ptt start|stop
voicein --listen        # 互換・診断用引数。常時リッスン実行機能は撤去済みなので理由付きで即終了
```

`--llm` は置換のあとに用語補正 LLM を通す実験スイッチ。既定オフ。`tools/llm` は撤去済みで `llm_common` の import は fail-open（関数が None）。補正段が死んでも本文は残る。

環境変数:

| 名前 | 既定 | 意味 |
|---|---|---|
| `VOICEIN_DEV` | `:0` | avfoundation の `-i`（空の映像 + 音声デバイス 0） |
| `VOICEIN_FIX_MODEL` | 空 | `--llm` 時のモデル名。空なら localllm の current |
| `AIZUCHI_SOCK` | `$HOME/.config/voice/aizuchi.sock` | 即答ソケット |
| `VOICE_REPLY_SEAT` | 空なら表示中の tmux 席 | `voice.speak` の席 |

一時ファイル（PTT）: `/tmp/voicein-ptt.wav`、`/tmp/voicein-ptt.pid`、`/tmp/voicein-ptt.level`。`ptt_start` は先にこの 3 つを消す。`ptt_stop` は pid ファイルを消さない（読み上げ側がプロセス実在を見るため）。

---

## 2 録音と区切り

区切りは VAD ではない。人がキーを押している間が 1 本の wav。whisper にはその wav を丸ごと渡す。

ffmpeg 共通:

```
/opt/local/bin/ffmpeg -hide_banner -loglevel error -nostdin
  -f avfoundation -i $VOICEIN_DEV
  -ar 16000 -ac 1 -y <wav>
```

stdin は `DEVNULL`。Enter 停止の CLI で ffmpeg が Enter を食う事故を防ぐ。停止は `SIGINT`（正常クローズ）。5 秒で終わらなければ `kill`。

PTT だけ追加のフィルタ（0.1 秒ごとに RMS を書く。波形用）:

```
-af asetnsamples=1600,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=/tmp/voicein-ptt.level:direct=1
```

`asetnsamples=1600` は 16 kHz で 0.1 秒。`direct=1` が無いと ametadata が 4 KB バッファし、録音中のレベルファイルが空になる。PTT の ffmpeg は `start_new_session=True`（Hammerspoon の子として切り、親の終了に巻き込まれない）。

押し損ね: PTT は wav が **24000 バイト未満**（16 kHz 16-bit mono で **0.75 秒**）なら無言で捨てる。CLI の `record()` は **1000 バイト未満**で終了する（マイク権限か `VOICEIN_DEV` を疑う）。

ホットキー（`$HOME/.hammerspoon/init.lua`）:

- **選んだ修飾キー押しっぱなし** = 録音、離す = 認識してタイプ。キーコードは使用環境の Hammerspoon で確認する。**Enter は打たない**。
- **機器に割り当てたキー** = トグル。1 押し目開始、2 押し目で認識・タイプ・**Enter**。デバウンス 0.5 秒。認識中の連打は無視。起点フラグ `recSource="button"`。
- **90 秒**で自動停止（Enter なし）。
- **Cmd+Ctrl+.** = `voice.py stop`（入力ではなく読み上げを止める）。

マイクのボタンを録音操作に使う場合は、USB 機器の VendorID/ProductID と送出イベントを実機で確認してから、対象機器だけにキーを割り当てる。リマップが揮発する環境では、Hammerspoon 起動時と機器の接続後に再適用する。キーボード本体の同種キーへ影響しないことを確認する。

右 Option の固着番犬（1 秒ごと）: eventtap が切れていたら再起動する。**録音中なのに alt が立っていない**とき自動停止する。この番犬は `recSource=="ptt"` のときだけ動かす。ボタン起点にかけると 1 秒以内に録音が死ぬ。スリープ／ロック解除でも eventtap を立て直す。

コールバックは旗の判定だけにし、開始/停止は `hs.timer.doAfter(0, ...)` に逃がす。eventtap / timer はグローバル `VoiceinPTT` に載せる（ローカル変数だと GC が回収して監視が消える）。

波形ピル: 150×34、画面下から 90 px、中央。レベルはファイル末尾 400 バイトから `RMS_level=` を読む。表示は `(db + 48) / 36` を 0.04..1 にクリップ（**-48 dB 〜 -12 dB** を 0..1）。右が最新、上下対称の塗り。ポリライン 1 要素を 0.1 秒ごとに差し替える（バーを 12 本個別更新すると本体が詰まり、キー離しを取り逃す）。マスコット画像 `input/indicator.png` は **ディスクに無い**。画像が無いときは波形だけになる。

録音開始で `voice.py stop` を非同期 spawn する。話し始めの瞬間に読み上げを止め、読み上げのエコーが入力に混ざるのを防ぐ。

読み上げ側（`voice.py`）の口述ミュートは入力の一部:

- 経路 B: `/tmp/voicein-ptt.pid` のプロセスが実在し、comm が `ffmpeg` で始まる。
- 猶予: `/tmp/voicein-ptt.level` の mtime から `post_rec_grace_sec`（設定の既定 **30**）秒は自動発話を始めない。ファイル無し・時計異常は喋る側へ倒す。
- 手動 `read` / `test` は貫通。観測点 `last.kind=skip-dictating`。

実機の音声デバイス番号は環境で変わる。確認:

```
/opt/local/bin/ffmpeg -f avfoundation -list_devices true -i ""
```

2026-07-31 の実測記録では音声 `[0] the USB receiver`（`voicein.py` の既定 `:0` のコメントと一致）。別時点の環境では `[1] BlackHole 2ch` も記録されているが、この文書の照合時点ではデバイス一覧を取得できず、現在の番号・接続状態は未確認。番号はこの一覧で確認する。

---

## 3 認識（モデル・引数・言語）

バイナリ: `$HOME/.local/stt/whisper.cpp/build/bin/whisper-cli`  
バージョン: **whisper.cpp 1.9.1**（CLI `--version`）。ソースは https://github.com/ggml-org/whisper.cpp 、実体の HEAD は `2ca53bb`（2026-07-31）。CMake は `GGML_METAL=ON`、`GGML_METAL_EMBED_LIBRARY=ON`。`whisper-cli` は `--no-gpu` を付けない（Metal 使用）。flash attention の CLI 既定は true。

モデル: `$HOME/.local/stt/models/ggml-large-v3-turbo.bin`（ファイル名どおり large-v3-turbo、サイズ 1.5G）。入手口は whisper.cpp 付属 `models/download-ggml-model.sh`（Hugging Face `ggerganov/whisper.cpp` の `resolve/main/ggml-*.bin`）。`--model foo` で絶対パスでなければ `$HOME/.local/stt/models/ggml-foo.bin` を探す。

`transcribe()` が実際に渡す引数（これ以外は whisper-cli の既定）:

```
whisper-cli
  -m <model>
  -l ja
  -f <wav>
  --prompt <glossary.txt の全文>
  -nt
  --no-prints
```

明示していない既定（`whisper-cli --help` の表示値）:

| 項目 | 既定 |
|---|---|
| `--threads` | 4 |
| `--best-of` | 5 |
| `--beam-size` | 5 |
| `--temperature` | 0.00 |
| `--no-speech-thold` | 0.60 |
| `--entropy-thold` | 2.40 |
| `--logprob-thold` | -1.00 |
| `--suppress-nst` | false（非発話トークン抑制は付けない。幻聴は HALLUC で落とす） |
| VAD オプション | 付けない |

言語は **`ja` 固定**。`auto` にしない。タイムアウトは **120 秒**（PTT / CLI とも同じ `transcribe`）。失敗は stderr 末尾 300 文字を出して終了。stdout の strip が認識文。

`--prompt` は glossary 全文。whisper はプロンプト末尾 roughly **224 トークン**を見る。句読点用の自然文は必ず末尾に置く（§4）。

認識は **CLI 第一**。whisper-server（当時 port 8178）は速度は上がったが、temperature 0 固定で語群が崩れた A/B がある。常時リッスン凍結と一緒に退役。PTT は server を使わない。

同一の ffmpeg コマンドでも、ターミナル／launchd の子だと壊れた音、Hammerspoon の子だと明瞭な音になる実測がある（macOS のマイク処理はアプリ単位）。PTT の ffmpeg は Hammerspoon → `voicein --ptt start` の孫にする。

---

## 4 後処理（幻聴除外・整形・辞書）

順は **認識文 →（PTT はここで HALLUC 判定）→ スラッシュ正規化 → replace.txt（長いキーから）→ 口述ログ →（CLI だけ任意で LLM）→ Aizuchi / 出力**。

### 4.1 幻聴除外

無音・雑音で whisper が出す定番。比較は `raw.strip().lower()` の完全一致。集合（コードの `HALLUC`）:

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

考え方: 無音 2 秒で `Thank you.` が出た実測（2026-07-31）と、YouTube 学習由来の締め・登録・次動画が口述バッファに混入した実測（2026-08-02）。英語は lower で吸収する。日本語は句点あり／なしを両方入れる。文の一部分一致では落とさない（「ありがとうございました」が本文に含まれる普通の発話を守る）。

PTT: HALLUC なら **空文字を返す**（タイプも即答もしない）。  
CLI: クリップボードには残る。即答の直前だけ `text.strip().lower() not in HALLUC` で送らない（`bc66fc9bf`）。

### 4.2 句読点と表記

句読点は ffmpeg の無音では決まらない。glossary がカンマ区切りの単語リストだけだと、同一音声でも句読点がゼロになる（2026-08-01 実測）。末尾に句読点つき自然文を足すと全復活する。実物の末尾（この 1 文を形式として残す）:

```
句読点。以下は、句読点を正しく付けた日本語の口述です。今日は、金利の見通しをまとめます。まず、結論から言います。
```

「くとうてん」の化け 3 形（駆読点・苦読点・苦闘点）は `replace.txt` で「句読点」へ戻す。

### 4.3 glossary.txt（形式だけ）

1 ファイル、UTF-8。カンマ区切りの用語を並べ、末尾に上記の句読点つき自然文を置く。中身は利用者の語彙なのでここへ写さない。足すほど whisper がその表記へ寄る。用語集が英字表記へ誘導すると、後段の置換前に英字混じりが出ることがある。

`transcribe()` は glossary を try 無しで開く。ファイルが無いと認識全体が落ちる。

### 4.4 replace.txt（形式だけ）

```
# コメント
誤認識形<TAB>正表記
```

空行・`#` 始まり・タブ無しは無視。タブは先頭 1 個で分割（右側にタブが残っても正表記側）。適用は **キーの文字数が長い順**（「クロードコード」を「クロード」より先）。部分文字列の `str.replace`。個人の行は写さない。機械的で文脈を見ないので、実在語と衝突する読み替えは載せない。

### 4.5 スラッシュコマンド

音声で「スラッシュ クリア」→ `/clear`。対象 8 語（コードの `_SLASH_CMDS`）:

`クリア` `モデル` `エフォート` `コンパクト` `フック` `コンフィグ` `ヘルプ` `リワインド`  
→ `/clear` `/model` `/effort` `/compact` `/hooks` `/config` `/help` `/rewind`

`table_fix` の先頭で、コマンド語の直前の区切りだけを消して詰め形にする:

```
SLASH_SEP_RE = スラッシュ?[\s　、。，．・･]*(?=(?:クリア|モデル|...))
```

置換後の表には詰め形 1 行があれば足りる（保険で空白形・中黒形が残っていてよい）。新コマンドは (1) `_SLASH_CMDS` にカタカナ 1 語 (2) `replace.txt` に詰め形 1 行。コマンド語が続かない「スラッシュ、つまり斜線」は発火しない。

旧運用（詰め・空白・中黒の 3 形を表に列挙）は、句読点復活で「スラッシュ、モデル」が生まれて破れた。8 コマンド × 区切り変種 × 語頭 2 形 = 176 通りのうち、3 形登録は 17 通りしか拾えなかった（赤化で実測）。

### 4.6 mishear-candidates.tsv（形式だけ）

文脈依存・多義の置き場。無条件置換すると本当の語を壊すもの（実在語との衝突）を先にここへ置く。昇格したら `replace.txt` へ移し、状態列を「昇格済み」にする。

```
誤認識形<TAB>意図した語<TAB>文脈メモ<TAB>日付<TAB>状態(候補/昇格済み/却下)
```

コードは読まない。学習用の台帳。

### 4.7 口述ログ

`table_fix` が必ず通す。失敗しても本文は落とさない（fail open）。

- 場所: `$HOME/.config/voicein/dictation/YYYY-MM.tsv`
- 列: `ts`（ISO8601、秒、タイムゾーン付き） / `source`（`ptt` | `cli` | `unknown`） / `raw` / `fixed` / `rules_hit`（`bad=>good` のカンマ区切り）
- 新規ファイルの先頭行: `# ts\tsource\traw\tfixed\trules_hit`
- TAB・改行は空白 1 個へ潰す。raw が空なら書かない。

### 4.8 LLM 補正（既定オフ）

`--llm` かつ `--no-fix` でないときだけ。接続先はコード上 `http://127.0.0.1:8090`（OpenAI 互換 localllm）。alive を 3 秒で見て、死んでいれば原文。think=False 必須。出力長が原文の 0.5〜2.0 倍の外なら原文。`<think>...</think>` は削る。`tools/llm` 撤去後は import 失敗で常に原文。設計書に残る「gemma4:12b / 127.0.0.1:11434」は旧記述で、今のコードは 8090。実地で本文破壊が確認されたので既定は置換表。

---

## 5 出力（貼り付け・Aizuchi）

### 5.1 貼り付け

PTT / ボタン: Hammerspoon が `voicein --ptt stop` の **stdout を `hs.eventtap.keyStrokes`**。クリップボードを使わない。exit 0 かつ非空のときだけ打つ。空や非 0 はピル「・・・」を 0.8 秒。ボタン経路だけ `usleep(150000)` のあと `return`。右 Option と 90 秒上限は Enter しない。

CLI: `pbcopy` に全文を渡し、stdout にも出す（ここは末尾改行あり）。`--paste` は

```
osascript -e 'tell application "System Events" to keystroke "v" using command down'
```

常時リッスン用の `VoiceinListen.typeFile`（本文ファイル、nonce 証跡、前面 bundleID の許可リスト、Enter 直前の再検査）は init.lua に残っているが、`--listen` が即終了するので主経路からは呼ばれない。

### 5.2 Aizuchi への受け渡し

文字化の直後、本文を落とさずに問い合わせる。失敗は全部握りつぶす。

1. テキストが空、またはソケットファイルが無ければ return。
2. UNIX ストリーム、**タイムアウト 0.2 秒**。
3. 送る 1 行: `" ".join(text.split()) + "\n"`（空白正規化）。
4. 受け: 改行まで。バッファが 100000 バイトを超えたら return。
5. JSON 1 行。`intent` と `reply`。
6. `intent` が鳴らす集合に入り、かつ `reply` が非空のときだけ `voice.speak(reply, purpose="done")`。
7. `VOICE_REPLY_SEAT` が空なら `voice.current_client_seat()` を入れてから speak。

鳴らす集合の正本は `$HOME/project/project/voice/aizuchi/speak_intents.txt`（`#` と空行以外、1 行 1 意図）。2026-09-24 の 30:

```
hello morning night-sleep goodbye otsukare return-home leaving
first-meet reunion how-are-you welcome-in care thanks apology
joy moved surprise encourage praise empathy-here sad lonely
worry relief angry calm-down embarrassed love laugh peaceful
```

挨拶・感謝・謝罪・感情。指示・質問・none は鳴らさない。ファイルが読めない／空なら voicein 内の退避集合。退避は 31 語で、正本と差がある（§6）。

ソケット側プロトコル（`serve.py`）: 1 接続に発話を 1 行ずつ送ると、各行へ 1 行 JSON。

```
{"intent": str, "score": float, "id": str, "reply": str, "lang": str}
none / 閾値未満: intent=none, reply=""
例外: {"intent": "error", "error": "..."}
```

分類モデルは `aizuchi/onnx/model-int8.onnx`、CPUExecutionProvider、tokenizer 同梱、`max_length=96`。閾値ファイル `onnx/threshold.txt` の値は **0.5**（無ければコード既定 0.5）。閾値未満は none。reply は `reply_map.tsv`（`intent<TAB>lang<TAB>text<TAB>id`）から発話言語、無ければ ja、ランダム 1 本。

voicein は `afplay` も `respond.py` も呼ばない。再生は `voice.speak` だけ。PTT 直後は `post_rec_grace_sec`（既定 30）で `skip-dictating` になり、即答が席判定の前に黙ることがある。これは入力側では外していない。

`--no-aizuchi` で問い合わせ自体をしない。

---

## 6 踏みやすい穴

実測で踏んだもの。同じ装置を組むとき先に潰す。

1. ffmpeg に stdin を渡すと CLI の Enter を ffmpeg が食う。`-nostdin` と `stdin=DEVNULL`。
2. ametadata の既定 4 KB バッファで、録音中のレベルファイルが空。`direct=1`。
3. canvas のバーを 12 本個別更新すると Hammerspoon が詰まり、キー離しを取り逃す。ポリライン 1 本。
4. `hs.timer` / `hs.eventtap` をローカル変数に置くと GC が回収する。グローバル台に固定。
5. 「録音中なのに右 Option 非押下」番犬をボタン起点にかけると、トグル録音が 1 秒以内に死ぬ。`recSource` で分ける。
6. glossary が単語リストだけだと句読点がゼロ。末尾に句読点つき自然文。
7. スラッシュの揺れを表に 1 形ずつ足す運用は、上流（句読点）が変わった瞬間に破れる。正規化して詰め形 1 本。
8. LLM 補正は用語を直す以上に本文を壊す。既定は置換表。失敗したら原文。
9. YouTube 由来の締め・登録・Thank you. が無音で混入する。HALLUC 完全一致で捨てる。部分一致にしない。
10. 同一 ffmpeg でも、ターミナル／launchd 配下は壊れた音、Hammerspoon 配下は明瞭。PTT は HS の子。
11. whisper-server 化は遅延を削っても品質が落ちた。PTT は CLI。高速化の前に A/B。
12. 常時リッスンを止めるなら、フラグだけでなく全起動経路（末尾の `doAfter` 無条件 start など）がフラグを見る。
13. 口述ミュートを listen 常駐のフラグ書きに依存すると、listen 凍結と同時に「話している最中に読み上げが始まる」。録音プロセスと level の mtime を見る。
14. `ptt_stop` は pid ファイルを消さない。ファイル有無だけ見ると録音終了後も永久ミュート。comm が ffmpeg かまで見る。PID 再利用対策。
15. 録音終了後の認識・タイプ・確認中はプロセスが居ない。`post_rec_grace_sec` 30 が無いと、その間に自動発話が始まる。逆に即答もこの窓で `skip-dictating` になる。
16. `anullsrc` や wav 注入は `-re` 無しだと実時間にならない。テストが歪む。
17. TCC の「有効」表示が遅れて、トグルと逆に見えることがある。実測（押して文字が出るか）が正。
18. `VOICEIN_DEV` の番号は機の差。既定値は `:0` だが、`VOICEIN_DEV` で上書きしないと別マイクへ刺さらない。list_devices で確認して指定する。
19. CLI 経路は HALLUC をクリップボードへ残す。PTT は空。即答スキップと入力スキップを混同しない。
20. `speak_intents.txt` 正本 30 と voicein 退避集合は一致していない。正本だけにある: `how-are-you`。退避だけにある: `invite` `meetup`。ファイルが読める限り正本が勝つ。
21. `input/hammerspoon-init.lua`・`slash_test.py`・`replace-stats.py`・`indicator.png` は README / 設計書が指すが、今のディスクには無い（テストと正本コピーは撤去済み）。init.lua は `$HOME/.hammerspoon/init.lua` が生きている実体。
22. `--listen` を「ある」と実装すると、入口の無い常駐が起動する。今は理由付きで即終了させる。
23. avfoundation の `-i` は `:N`（映像空、音声 N）。`N` だけだと映像デバイスを掴みに行く。
24. glossary 欠落は認識全体の例外。replace.txt 欠落は置換スキップで本文は残す。非対称。

---

## 7 合格の基準

入力専用の `slash_test.py` / `listen_test.py` は今のツリーに無い。合格は次で見る。

### 7.1 自動（音を出さない）

`$HOME/project/tools/voice/output/tests/e2e_silent.sh` のうち Aizuchi 行（偽ソケット、再生スタブ、席 `test`、印 `t`）:

| ケース | 期待 |
|---|---|
| `aizuchi-thanks`（「ありがとう」→ intent `thanks` + 非空 reply） | 再生関数が呼ばれる |
| `aizuchi-none` | 呼ばれない |
| `aizuchi-intent-mute`（`deploy` など speak 集合外） | 呼ばれない |
| `aizuchi-sock-down` | 呼ばれない |

`test_paths.py` の `test_dictating_skips`: `dictating()` が真のとき自動発話は `last.kind=skip-dictating`、再生プロセス無し。

即答分類器そのものの数字（`aizuchi/smoke.tsv` / `smoke-dictation.tsv`、`run-all.sh`）: 意図精度 ≥ 0.9、none 誤爆 ≤ 0.01。口述風は speak 集合への誤鳴 ≤ 1%、返事の取りこぼし ≤ 10%。これは分類器側。voicein の受け渡しは上の 4 行。

`voicein.py` は `python3 -m py_compile` が通る。

スラッシュ正規化（`slash_test.py` が無いので、同じ関数を直に呼ぶ）:

- 「スラッシュ、モデル」→ 置換後 `/model`（読点があっても詰め形へ寄る）。
- 「スラッシュ、つまり斜線」は「スラッシュ」が残る（コマンド語が続かない）。
- `_SLASH_CMDS` の 8 語すべて、空白・読点・中黒・詰めのどれでも `/...` になる。

HALLUC: `Thank you.` と `ご視聴ありがとうございました。` を PTT 相当で空にする。通常文は空にしない。

`table_fix` は長いキーが先（「クロードコード」が「クロード」に食われない）。replace の個人行は使わず、テスト用の短い表でよい。

### 7.2 手確認（実マイク。音を出すなら席と静かな時間に注意）

1. `ffmpeg -f avfoundation -list_devices true -i ""` で音声番号を取り、`VOICEIN_DEV` を合わせる。
2. Hammerspoon 起動。右 Option 押しっぱなしで緑ピル、離すと「認識中」、前面の入力欄に文字。Enter は付かない。
3. 0.5 秒だけ押して離す → 何も打たれない（0.75 秒門）。
4. 無音のまま 2 秒押す → Thank you. が欄に出ない。
5. 「スラッシュ クリア」→ `/clear` が欄に出る。
6. `$HOME/.config/voicein/dictation/YYYY-MM.tsv` に `source=ptt` の行が増える。raw / fixed / rules_hit が 5 列。
7. ソケットが生きていて挨拶を言ったとき、`speak_intents.txt` の意図なら `voice.speak` まで届く（猶予 30 秒で skip-dictating なら、窓が明けてから、または CLI `--file` で確認）。指示の文では鳴らない。ソケットを止めると本文タイプは生き、即答だけ無い。
8. 録音中に読み上げを仕掛けると `skip-dictating`（自動経路）。`voice.py stop` は開始時に既に呼ばれている。
9. `voicein --listen` はエラーで即終了し、常駐しない。

この 7.1 と 7.2 が満たせば、今の入力と同じ質。
