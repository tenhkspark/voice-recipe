# 音声環境の作り方 仕様書（AI エージェント向け）

Mac 1 台で動く「聞く・即答・要約・喋る」音声環境を、初見の AI エージェントが同じ形で組めるための仕様。鍵・実アドレス・外部サービスの音声ファイルには依存しない（各自の用意に置き換える）。

## 1. 構成と流れ

```
音声入力(PTT→文字)
   ├─→ Aizuchi（即答: 定型返事か none を数 ms で判定）→ 鳴らす
   └─→ 本返事（エージェントの返答本文）
         → 要約 LLM（長文を耳向けに短縮、80字超の時）
         → AivisSpeech（1 文ずつ合成）→ 再生
         （作り置きパック: 文面が一致したら音声ファイルを即再生）
```

この構成に外部の有料 TTS（ElevenLabs 等）は要らない。合成はすべて利用者の Mac の AivisSpeech で完結する。

- **聞く**: プッシュトゥートークのみ。押下で録音、離すと whisper.cpp で文字化し置換表（誤認識→正表記）を適用する。PTT 経路では voicein が認識文を標準出力し、Hammerspoon がその文字列を前面入力欄へ直接タイプする。常時リッスン・ウェイクワードは持たない
- **即答 Aizuchi**: 発話→55 意図を ONNX int8 常駐サーバで ~5ms で判定し、確信度が閾値未満なら `none` とする。none なら何もしない。分類器は `modernbert-ja-130m` 土台の CLS＋線形ヘッド（126MB int8、常駐 RSS 約 389 MiB、起動約 0.27 秒。tokenizers 単体化後の実測）
- **要約 LLM**: 標準は macOS 標準のオンデバイス LLM（Foundation Models）。OpenAI 互換の接続先にも切替可（`summarizer: apple|openai|off`）。どちらも失敗したら原文の先頭 2 文で済ませる
- **声 AivisSpeech**: ローカル TTS エンジン（話者は設定の `speaker_id`）。合成が全滅した時だけ `say` にフォールバック

## 2. つなぎ目

### hook の入力（stdin の JSON）

| 発火 | 呼び方 |
|---|---|
| Claude Code Stop | `voice-reply.sh` → `voice.py reply --seat <席名>`。transcript_path が CC 形式（`message.role` が user/assistant の行がある JSONL）の時だけ通す。本文＝直前の user 発言より後の assistant 本文。80 字超は要約 |
| Claude Code Notification | `voice-notify.sh` → `voice.py hook`。「<席>、確認待ち」のみ |
| Pi 拡張 | `voice.ts`。応答完了は `agent_settled`（自動継続が無い確定時点）、確認待ちは `ui_prompt_start`(kind=confirm)、非対話時は `tool_execution_end`(isError) → 同じ `voice.py reply --seat`。本文は assistant 全文を CC 形式の一時 JSONL にして transcript_path 経由で渡す |
| 手動 | `voice.py say "テキスト"`（stdin 可）、`read`（last.txt 全文・席ゲート貫通）、`test`（試聴） |

門の重要な選別: Grok 等の非 CC エージェントが `~/.claude/settings.json` の hook を踏んでも、transcript が CC 形式でなければ exit 0 で黙る。role 判定はファイル全体から（冒頭のメタ行が 40 行を超えても通す）。

### ソケット形式（Aizuchi 常駐）

- UNIX ソケット（例 `~/.config/voice/aizuchi.sock`）。1 接続・発話 1 行ごとに 1 行 JSON を返す
- 応答: `{"intent": str, "score": float, "id": str, "reply": str, "lang": str}`。`id`/`reply` が空なら「合成対象の返事文」を指す。none・閾値未満は `intent:"none"`・空 id/reply
- サーバ側推論例外は `{"intent":"error","error":...}` で返る。PTT クライアントはエラー応答や発話許可外の意図を鳴らさず、ローカル推論にも切り替えない。失敗しても通常 PTT の認識本文は標準出力へ継続して返す（踏んだ穴 7.2 参照）

### 設定キー（config.json の主要部）

- `mode`: `off | earcon | summary | full`（既定 summary = 要約して読む）
- `seat`: 固定席名。空なら「表示中の tmux 席」と一致した時だけ鳴る（4 章参照）
- `quiet_hours`: `[開始, 終了]`（既定 23:30–08:00）。完全ミュート
- `night_brief_hours`: 夜間は鳴らすが短く（既定 30 字・1 文）。quiet の外側だけ効く
- `summarizer`: `apple | openai | off`、`summarizer_base`: OpenAI 互換の URL
- `speaker_id`（AivisSpeech の声。変更しない）、`speech-styles.json`（purpose 別の速度・間・音量のみ変更可）
- `pack`: 作り置き音声パック（enabled・model・voice・lang）。`model` はパックの生成元、`voice` は声ディレクトリを持つ生成元の話者 ID（AivisSpeech のように声欄を使わないモデルでは空欄）。現行 manifest には `eleven_v3`、`eleven_multilingual_v2`、`aivis-aida` の ok 行がある。フレーズは NFKC 正規化後に句読点と空白を除いて照合し、一致すれば音声を即再生する。索引には読み補正前後の表記を登録する

## 3. 要約の指示と禁止

作者の環境では、要約に自作の Gemma 4 を使っている。重みは `gemma-4-26B-A4B-NVFP4-lmfp8`、公開レシピは https://github.com/tenhkspark/gemma4-spark（DGX Spark で `serve.sh up`、OpenAI 互換 API を :8890 で提供）。要約 1 件 約 1.7 秒。Spark が無い人は、Apple のモデル（macOS 標準のオンデバイス LLM）／MLX の Gemma 4 E4B（下の案 2 の指示）／任意の OpenAI 互換接続先のどれかで代えられる。

原則: **主語を変えない（話し手はアシスタント）・依頼を作り足さない・表やパスを読まない**。アシスタントが「やります」と言ったことをユーザーへの依頼に変えるのが最悪の失敗。原文末尾に質問がある時だけそれを最後に残す。

Gemma 26B 用（`voice.py` の SUMMARY_PROMPT、OpenAI 互換 API 要求の温度 0.2・max_tokens 300）:

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
次の文章は AI アシスタントがユーザーに返した返事。耳で聞いて分かる話し言葉で、120字から200字にまとめて。200字を超えてはいけない。改行や箇条書きにしない。
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

注意: 思考のオン・オフは `voice.py` の要約要求では指定しない。mlx-lm の既定は思考オンなので、思考を切る場合は接続先サーバの起動設定（例: `--chat-template-args {"enable_thinking":false}`）で指定する。これはサーバ側がその設定をサポートし、起動設定が適用された場合に限る。実測記録では切らないと max_tokens 300 を思考が使い切り、本文が空になった。短くしすぎる指示（180 字以内・4 文以内）は要点の欠けを戻す実測があり使わない。品質の測り方は実記録 10 件で「要点の欠け・主語のすり替え・依頼の作り足し・字数」を数える（summ-compare 方式）。

## 4. 席の判定

複数エージェント席（tmux セッション）がある前提:

1. `config.seat` が設定されていれば、**その席の発火だけ**鳴る
2. 空なら、発火元の席（`TMUX_PANE` から `tmux display-message -p -t <pane> '#S'`）が**今表示中のクライアントの席**と一致する時だけ鳴る
3. 席が取れない・不一致は無音（ログ kind=seat-skip）。**ターゲット空の tmux は別席の名前を返す**ので、`TMUX_PANE` が空なら門で落とす（踏んだ穴 7.1）
4. 貫通する例外: 手動 `read` / `test` / `--no-play`。キルスイッチ `CLAUDE_VOICE_MUTE` は全経路無音

## 5. 1 文ずつの合成と失敗時

- 要約文を文ごとに切り、AivisSpeech で 1 文を合成して再生開始し、再生中に次の文を合成して順に再生する（返事同士が重ならない。再生はロック保持中）
- 作り置きパックは正規化後の文面が一致したフレーズの音声を合成の代わりに即再生（5.5 節参照）
- 文の途中で Aivis が失敗した文は**読み飛ばす**（声の混在を防ぐ）。全部失敗した時だけ `say` フォールバックで全文
- earcon（short な合図音）: done/read・attention・error で別の音。attention/error は重ね鳴らし可、done は再生中 skip
- 重複抑止（同じ最終文は 30 分窓で鳴らない）・間隔ゲート（既定 5 秒内の 2 件目は言葉でなく earcon）・口述中は自動無音

### 5.5 作り置き音声パックの作り方

作り置きパックとは、phrases（返事フレーズ）の文面から生成した即答用の音声。現行の `project/voice/manifest.tsv` には `aivis-aida` の ok 行が 2,243 本あり、`eleven_v3` と `eleven_multilingual_v2` の行もある。`voice.py` の既定 pack は `eleven_v3` なので、利用するパックは `model`・`lang`・`voice` が manifest と合うように設定する。ローカル生成の例では AivisSpeech を使えるが、全パックが AivisSpeech 製という意味ではない。

作り方:

1. phrases.tsv（category / id / ja / en / zh / ko）を用意する。id は言語共通
2. 各文面を AivisSpeech の API（`POST /synthesize` 等のローカル HTTP API）で 1 本ずつ合成し、mp3 または wav で `pack/<lang>/<id>.<ext>` に書き出す
3. 合成済みの行を manifest（id・ファイル・文字数・話者）に `ok` として記録する。再開時は manifest の ok 行を飛ばす（冪等）
4. voice.py の `pack` 設定（enabled・model・voice・lang）で読み込む。照合は NFKC 正規化後に句読点・空白を除いて行い、読み補正後の表記も対象。一致しなければ通常の 1 文ずつ合成へ落ちる

## 6. 即答の意図の絞り方と学習データの作り方

1. **意図を絞る**: 全返事フレーズから「定型で済むもの」だけを選ぶ。実績では挨拶・感謝・感情系は全件、運用系は確認待ち・実行中・完了など短い定型に絞り 55 意図
2. **鳴らす意図をさらに絞る**: 現行分類ラベルは 55 意図、発話許可リストは 30 意図。口述に含まれる指示・質問には即答しない。許可リスト（1 意図 1 行のテキストファイル）に載った意図だけ発話。**ファイルが無ければ全意図を鳴らすのではなく空集合に倒す**（踏んだ穴 7.4）
3. **学習データは自分の LLM で作る**: 各意図に多言語（ja/en/zh/ko）×言い方バリアントで発話例を生成。none は「定型句で済まない発話」を別途生成する
4. **生成と同じモデルで検査**: その返事で自然か / none は本当に定型で済まないか、を全例に判定。落ちた例と重複を除いてデータセットにする。現物の行数は `dataset.jsonl` が 28,933 行、`train.jsonl` が 32,560 行、`dev.jsonl` が 3,645 行（train/dev 合計 36,205 行で約 9:1）。これらのファイル間の件数差の由来と生成前の件数は、確認した現物からは断定しない
5. **学習**: CLS＋線形ヘッド、AdamW 2e-5、3 epoch 程度（130M クラスなら Mac で 40 分弱）。閾値は dev の「none 誤爆最小化」で決める（実績 th=0.55、誤爆 0.36%）
6. **ONNX int8 化**: export→動的量子化で 500MB→126MB。**合否は固定テスト（smoke.tsv）で PyTorch 版と同じ基準**（意図正答 ≥0.9・none 誤爆 ≤1%）を満たすまで。落ちたら int8 をやめる
7. **つなぎ込み**: 通常の PTT 認識経路では、文字化後にソケットへ問い合わせて即答を試し、その後に本文を返す。分類ソケットや即答処理が失敗しても例外は吸収され、認識本文の返却は継続する。この説明は通常 PTT 経路の挙動を指す

## 7. 今日踏んだ穴の一覧

1. **ターゲット空の tmux が別席の名前を返す**（test: `test_hook_names_the_firing_seat`）— `TMUX_PANE` 空は門で落とす
2. **非 CC transcript で「本文が取れませんでした」と言わない**（test: `test_pi_stop_without_transcript_speaks`）— CC 形式の確認をファイル全体で行い、Pi は本文を CC 形式一時 JSONL で渡す
3. **`--no-play` を子プロセスへ伝える**（test: `test_hook_no_play_does_not_arm_player`）— spawn する `say` にも付ける
4. **静かな時間に earcon が鳴る**（test: `test_quiet_hours_silent`）— quiet は earcon も消す
5. **重複抑止がログの列を見誤る**（test: `test_dedupe_skips_second`）— 比較する列を本文に固定
6. **明示の say が席ゲートで落ちる**（test: `test_explicit_say_without_seat_speaks`）— 手動 say は manual 扱いで貫通
7. **席判定の例外で無条件に earcon**（test: `test_hook_error_does_not_play_without_seat`）— 例外経路も席を確認
8. **試聴がオフを無視する**（test: `test_audition_respects_enabled`）— test も speak() を通す
9. **許可リスト欠落で全意図が鳴る**（review: review）— 欠落は空集合へ倒す
10. **常駐のエラー応答**（review: review）— PTT クライアントはエラー応答や許可外意図を鳴らさず、ローカル推論へ切り替えない。失敗時も認識本文の出力を継続
11. **フォールバックで入力行を失う**（review: review）— stdin は一度だけ読み、未処理分だけ fallback
12. **小型要約モデルが思考トークンで出力空**（summ-compare）— 思考オフ指定
13. **短くしすぎ指示が要点欠けを戻す**（e4b-prompt 案 3）— 下限字数（120–200 字）を指定

## 8. 合格の基準

- `tools/voice/output/tests/`（test_paths.py 27 テスト・e2e_silent.sh・run-all.sh）を**全部通るまで作り直す**。音は鳴らさず、afplay/say の呼び出し引数を検査する設計
- Aizuchi: smoke 固定テストで意図正答 ≥0.9・none 誤爆 ≤1%、int8 変換前後で成績を照合
- 要約: 実記録 10 件で要点の欠け・主語のすり替え・依頼の作り足しが 0（字数は上限のみ）
- 失敗報告は原因 1 行。同一原因で 2 回失敗したら人間に引き取らせる

## イントネーションを良くしたい人へ

規約の心配なく取り組める順:

1. 読みの辞書（`readings.tsv` 形式）を育てる。効き目が最も大きい
2. AivisSpeech の話速・抑揚・音高を声ごとに調整する
3. AivisHub で、学習や改変が許された声を選ぶ
4. 自分で録った声で追加学習する

### 上級者向け: 学習でさらに良くする

学習材料には、自分で録った声、学習への利用が明示的に許されたデータセットや声（ライセンスを必ず確認）、または利用規約に「出力を学習に使ってよい」と明記された音声サービスの出力を使えます。多くの商用音声合成サービスは、出力を別モデルの学習に使うことを禁じています。使う前に必ず規約を確認してください。

## For anyone who wants better intonation

Here is an order of steps that avoids licensing concerns:

1. Improve the pronunciation dictionary (in `readings.tsv` format). This has the greatest effect.
2. Adjust AivisSpeech speed, intonation, and pitch for each voice.
3. Choose a voice in AivisHub that permits training or modification.
4. Fine-tune with a voice you recorded yourself.

### Advanced: improve it further with training

Training material can include your own recordings; datasets or voices that explicitly permit use for training (always check the license); or output from an audio service whose terms explicitly state that its output may be used for training. Many commercial speech synthesis services prohibit using their output to train a separate model. Always check the terms before using it.
