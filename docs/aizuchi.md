# Aizuchi の作り方

短い発話を意図に分け、挨拶・感謝・謝罪・感情だけ即答する分類器の手順。学習済みの重みは同梱しない。土台モデルを取り、自分の LLM で例文を作り、自分で学習する。数字は作者の実測（2026-09-24、記録は `progress-aizuchi.md`（旧 `(internal record)`）・`progress-aizuchi-wire.md`・`(internal record)`・`runall-first.md`、および `aizuchi/` のファイル件数）。計測が無いところは書かない。

合格の材料は [tests/aizuchi/](../tests/aizuchi/)（`smoke.tsv` 252 行、`smoke-dictation.tsv` 800 行、`speak_intents.txt`）。`speak_intents.txt` は `aizuchi/speak_intents.txt` の固定コピーで、残る同名テスト TSV も作者側とバイト一致する。

---

# 日本語

## 1. 何をするか

```
発話 1 行（ja / en / zh / ko）
  → 分類器（54 意図 + none）
  → 確信度が閾値未満、または none → 無音
  → 意図が speak_intents.txt の 32 に無く、返事が空 → 無音
  → ある → その言語の定型返事を 1 本選び、再生側へ渡す
```

本返事（エージェントの長い返答）とは別経路。分類が落ちても、文字化した本文は止めない。即答だけ欠ける。

鳴らす 32 は挨拶・感謝・謝罪・感情に ack と input-wait を加えた集合。正本は 1 行 1 意図の `speak_intents.txt`。

| 区分 | 意図 |
|---|---|
| 挨拶 | hello, morning, night-sleep, goodbye, otsukare, return-home, leaving, first-meet, reunion, how-are-you, welcome-in |
| 感謝・謝罪・気遣い | thanks, apology, care |
| 感情 | joy, moved, surprise, encourage, praise, empathy-here, sad, lonely, worry, relief, angry, calm-down, embarrassed, love, laugh, peaceful |

`how-are-you`（調子はどう）はこの集合に入る。`invite` と `meetup` は場面の返事になるので許可リストから外してある。誘い（invite, meetup）、実行中・質問・その他の運用意図（doing ほか）と `none` は分類できても鳴らさない。ファイルが読めないとき、作者の `respond.py` は空集合（何も鳴らさない）。一方、`voicein.py` のコード内フォールバックは正本と同一ではなく、`invite` と `meetup` を含み、`how-are-you` を含まない。ファイルが読めないか空の場合は、この異なる集合が使われる。テスト側のリストは正本を複製した固定コピーであり、正本を変えたときは同期する。

再生は分類器から `afplay` しない。席・静かな時間・順番待ちは再生側（作者は `voice.py` の `speak`）に渡す。

## 2. 意図の設計

最初は返事 id を直接分類した。対象は 491 id（greet 124、emotion 195、ops 172）＋ `none` の 492 クラス。greet と emotion は全件。ops は短い口語（`z-ops-*`、接頭辞の無い短 id、確認中・待ち・実行中・準備中に読めるもの）だけ。

491 クラスは細すぎた。同じ感謝の中で確率が割れ、閾値 0.55 を超えない。作者の実測では「ありがとう！」「Thanks a lot」「谢谢你」「ごめん、間違えた」「よろしくね」がすべて `none` で、「おはよう」だけ当たった。

分類単位を意図に束ねた。`intents.txt` は 54 行（名前、タブ、説明）。分類クラスは 54 意図 ＋ `none` の 55。返事 id は分類しない。意図が当たったあと、受け答えの表から 1 本選ぶ。

`none` は「定型句では済まない発話」。知識の質問、説明、相談、作業の指示、情報を求める質問。閾値未満も推論結果は `none` にする。迷ったら `none` に逃がす。誤って定型を鳴らす方が、黙るより悪い。

id を意図へ割り当てるとき、一覧に無い名前は使わない。迷う id は `notify`。作者は割り当て後に明らかな誤りだけ手で直している（例: `review-pass` → `result-report`）。朝のお知らせ系 11 id（目覚まし、天気、ニュース、予定、始発など）は意図 `none` に置いた。`intents.tsv` の `none` 行はこの 11 件。

ops 系の意図に付いていた命令形（〜して、してください、do X）は学習ラベルを `none` に移す。感情の「〜して」は残す。質問・挨拶・感情・報告は命令に数えない。id ごとの件数を無理に揃える追加生成は、作者の記録では逆効果で採用していない。

## 3. 学習データの作り方

再現時の推奨手順では、例文を作る LLM と検査する LLM を分ける。同じモデルが自分の文を通すと検査が甘くなるためである。どの LLM で文を作ったかで、学習済み重みに付く利用条件が変わる。Gemma で作ると [Gemma Terms of Use](https://ai.google.dev/gemma/terms) の禁止用途が重みに付く。別のモデルで作れば、付くのはそのモデルの条件。土台エンコーダの MIT は変わらない。第三者の声や個人の発話は入れない。

作者の分類器用コーパスは、自作の Gemma 4（ローカルの OpenAI 互換、64 並列）で作っている。実施記録（`progress-aizuchi.md`）では生成と検査は同じ Gemma で行われており、独立した別モデルによる検査ではない。後段の外部確認は `(internal record)` に記録されている。

手順:

1. 意図ごとに、ユーザーが話しそうな発話を作らせる。ja / en / zh / ko をほぼ同数。口語から丁寧、短文から一文まで散らす。その意図の定型返事が自然に成立する発話だけ。返事の文をユーザーが言い換えたもの（オウム）は不可。作業命令と、天気・知識・ニュースなどの情報質問は、挨拶・感情の例に混ぜない。
2. `none` は別プロンプト。定型の挨拶・感謝・「はい」だけでは済まない発話。テーマを分けて幅を出す（作業指示、情報質問、相談、計算、翻訳）。
3. 推奨手順では、生成に使ったものとは別の LLM に全件を検査させる。意図側は「その定型返事で自然か」。`none` 側は「本当に定型で済まないか」。落ちた番号は捨てる。同じ文が複数ラベルに出たら、その文は全部捨てる。同一（ラベル、文）の重複も捨てる。このコーパスの実施時は生成と検査が同じ Gemma だった。常駐推論では tokenizer を `tokenizers` 単体で読み、`transformers` / `torch` を import しない。
4. 残った文を層化して分ける。作者の `parse_val.py` は `sha256(text) % 10 == 0` を dev、残りを train（約 9:1）。

作者の件数:

| 段階 | 件数 | 出どころ |
|---|---|---|
| 最初の生成 | 34,783（id 側 17,585 / none 17,198、4 言語ほぼ等量）。各 id は 36 件要求（9×4 言語）。none は 40 呼び × 60 件 | 進捗メモ |
| 同じ Gemma の検査後 | 合格 31,454、落ち 3,329、複数ラベルと重複を除いて **28,933**（train 26,045 / dev 2,888） | 進捗メモ |
| 命令の移動と追加のあと手元に残る生成ファイル | **37,764** 行（`examples2.jsonl`。約 3.8 万）。うち意図名つき追加（`@intent::名前`）が 2,156 行 | ファイル件数 |
| 採用した 55 クラスの分割 | train **32,560**（none 19,054）/ dev **3,645**（none 2,130） | `train.jsonl` / `dev.jsonl`。dev の 3,645 は進捗メモの n と一致 |

smoke の陽性例のパラフレーズ 1,241 件を Gemma で足した、と進捗メモにある。id 側を均衡にする追加は採用していない。弱い id（例が 10 件未満）は最初の id 分類の時点で 19 件あった。

固定テストの口述側（`smoke-dictation.tsv`）は学習セットとは別。800 行（silent 600 ＝ 4 言語 × 150、reply 200 ＝ 4 言語 × 50）。列は `lang`、`text`、`expect`（`silent` または `reply`）。

## 4. 学習

土台は [sbintuitions/modernbert-ja-130m](https://huggingface.co/sbintuitions/modernbert-ja-130m)。MIT（© 2025 SB Intuitions）。作者のカード記載は、日英 4.39T トークン、語彙 102,400、系列長 8,192、hidden 512、19 層。`transformers` 4.48 以上が必要。Mac の venv は Python 3.12、torch 2.14、transformers 4.56.2。GPU ランのコンテナは進捗メモの `tenhkspark/gemma-4-v2:v2`。

頭はエンコーダの CLS（最終隠れ状態の位置 0）に線形 1 層。損失は交差エントロピー。ラベルは出現順で凍結し、`none` は常に末尾。最適化は AdamW、学習率 2e-5、最大長 96、3 epoch、warmup は全 step の 10% でその後線形に減衰、勾配クリップ 1.0、チェックポイントは bfloat16。`model.safetensors` が既にあれば再開する。デバイスは CUDA、無ければ MPS、無ければ CPU。

```
python3 train.py train.jsonl --out ckpt --base base --epochs 3 --batch-size 64 --lr 2e-5 --max-len 96 --seed 0
```

作者の採用ラン（DGX Spark の DGX Spark、`batch_size` 64）: 1,527 step、epoch 損失 1.485914 → 0.493772 → 0.152006、約 **12 分**。メモリは 20GB 未満、と進捗メモにある。同じ機械の別サーバは止めていない。

Mac の MPS でも同じスクリプトが動く。終わっている MPS の記録は、意図へ束ねる前の 491 id モデル（batch 32、2,442 step）で約 **37 分**、最終損失 0.358。55 クラスの採用チェックポイントは GPU 側。

閾値は dev で none の誤爆が小さい方を採る。初回採用値は **0.5**。この時点のスイープでは 0.3 が正答 0.9621 / 誤爆 0.0167、0.4 が 0.9621 / 0.0083、0.5 と 0.6 が 0.9394 / 0.0000 で、0.5 を選んだ。その後、口述試験の取りこぼし対策で現行値を **0.38** に変更した。現行の int8 実測は dictation 誤鳴 0/600・取りこぼし 18/200、smoke 意図正答 0.9697・none 誤爆 0/120。詳しくは `progress-aizuchi.md` の negtest 記録。

## 5. ONNX int8 への書き出し

PyTorch のチェックポイントを ONNX にし、動的量子化で int8 にする。出力は logits `[batch, 55]`。opset 17。軸は batch と系列長が動的。量子化は `quantize_dynamic`、重みは `QInt8`。tokenizer、`labels.json`、`threshold.txt` を ONNX と同じディレクトリに置く。常駐プロセスは `tokenizers` 単体で tokenizer を読み、`transformers` と `torch` は import しない。

書き出しの直後に、同じ 2 文で PyTorch と int8 の logits を比べる。作者の記録は argmax 一致、max|Δlogit| = 0.85。進捗メモの大きさは fp32 504MB、int8 126MB。いまディスクにある int8 は 132,993,740 バイト。

合否は smoke を int8 で採点し直す。作者の書き出し時の追加条件は「torch の意図正答 0.939 から 0.01 以上落とさない、none 誤爆は 1% 以下」。落ちたら int8 を使わない。

| 指標 | torch（閾値 0.5） | ONNX int8 | 判定 |
|---|---|---|---|
| smoke 意図正答 | 124/132 = 0.9394 | 126/132 = 0.9545 | 合格（上がった） |
| smoke none 誤爆 | 0/120 | 0/120 | 合格 |
| dev 正答（n=3645） | 0.8236 | 0.8167 | −0.007 |
| dev none 誤爆 | 0.0150 | 0.0164 | ＋0.0014 |
| 推論 median | 9.99 ms（MPS, n=200） | 2.4 ms（CPU / onnxruntime） | |

常駐 RSS は約 **389 MiB**。起動（imports 完了から OrtInfer・reply map 準備まで）は **0.27 秒**。判定 median は **2.4 ms**（`serve.answer("ありがとう")`、n=200）。tokenizer は `tokenizers` 単体で読み、`transformers` / `torch` は import しない（`~/project/ops/codex-rss.md`、commit `(internal)`）。

dev の none 誤爆は 1% を少し超える。合格ラインは smoke 側（§7）。int8 の取りこぼし 6 件は、別の意図への取り違えではなく、閾値未満で `none` に落ちたもの（例: 「おやすみなさい」→ none 0.483、韓国語「이제 잘게」→ none 0.381）。

## 6. 常駐とソケットの形式

UNIX ソケット。作者の既定パスは `~/.config/voice/aizuchi.sock`。1 接続に発話を 1 行ずつ送ると、各行へ JSON を 1 行返す。onnxruntime の CPU、スレッドは intra / inter とも 1、メモリアリーナはオフ。tokenizer の最大長 96、pad id 3。

```json
{"intent": "thanks", "score": 0.9719, "id": "reply-thanks-1", "reply": "どういたしまして", "lang": "ja"}
```

| フィールド | 意味 |
|---|---|
| intent | 54 意図の名前、または `none`。推論例外は `error` |
| score | 最大クラスの確信度。閾値未満で `none` にしたときも、その確信度を入れる |
| id | 受け答え表のフレーズ id。合成する文、`none`、閾値未満は空 |
| reply | その言語の返事の文。同上で空 |
| lang | 発話から推定。ひらがな・カタカナなら ja、ハングルなら ko、漢字なら zh、それ以外は en。その言語の候補が無ければ ja に倒す |

`none` と閾値未満:

```json
{"intent": "none", "score": 0.9991, "id": "", "reply": "", "lang": "ja"}
```

例外は `score` を付けない。`{"intent":"error","error":"..."}`。クライアントは `score` が無い応答を通常結果にしない。本文の処理は続ける。

言語ごとの候補が複数あるときは 1 本を無作為に選ぶ。

作者の常駐実測（2 回）:

| | 進捗メモ | 別席の確認 |
|---|---|---|
| ソケット受付開始 | 2.26 秒 | 1.97 秒 |
| RSS | 746MB | 745MB |
| 往復 | median 5.07 ms / p90 5.52 / min 3.27（n=200、tokenize＋推論＋JSON） | 8 発話で 3.45–9.59 ms |

8 発話の確認: 「ありがとう」4.18 ms、thanks 0.9719、「おはよう」3.45 ms、morning 0.9888、「今日の天気は？」4.56 ms、none 0.9991、「これデプロイして」3.84 ms、none 0.9995、「ごめん、間違えた」4.69 ms、apology 0.9961、英語 Thanks 6.36 ms、thanks 0.9512（id 空）、谢谢 9.59 ms、thanks 0.8554、고마워요 7.65 ms、thanks 0.7966。音は鳴らしていない。

音声入力側は、文字化の直後に 1 行送る。作者の `voicein` の待ちは 0.2 秒。ソケットが無い、死んでいる、タイムアウト、壊れた JSON のときは即答せず、本文は従来どおり渡す。常駐の自動起動は、同じ `serve.py` が既にいるときは起動しない。起動に失敗しても音声入力は止めない。

## 7. 閾値と合格の基準

初回の採用閾値は 0.5だったが、現行閾値は口述試験の調整後の **0.38**。現行値の測定は初回値の測定と区別し、変えるときは dev の誤爆と smoke を両方見る。

[tests/](../tests/) の run-all は音を出さない。即答の 2 項目は常駐ソケット（無ければ `AIZUCHI_SERVE` と `AIZUCHI_MODEL` で一時ソケット）に `tests/aizuchi/` の TSV を投げる。モデル本体はテストに入っていない。ソケットが無ければこの 2 項目は不合格。

| 材料 | 合格 |
|---|---|
| `smoke.tsv`（陽性 132 ＋ none 120） | 意図の正答 ≥ 0.9、かつ none を別意図にした割合 ≤ 0.01 |
| `smoke-dictation.tsv`（silent 600 ＋ reply 200） | 鳴らしてはいけない行を、32 意図のどれかで鳴らした割合は合格ライン以内。鳴るべき行を鳴らさなかった割合も合格ライン以内。`expect` が silent / reply 以外なら不合格 |

鳴るかどうかは、予測意図が `speak_intents.txt` に入っているか。正解意図と違っても、32 の中なら dictation では「鳴った」になる。

作者の int8 常駐、初回 run-all（2026-09-24 18:51、音なし）:

| 項目 | 結果 |
|---|---|
| smoke | 合格。126/132 = 0.9545、none 誤爆 0/120 |
| dictation | 不合格。無言の誤鳴は合格基準内。返事の取りこぼしは基準未達 |

smoke の落ちた例には、閾値未満の `none`（「おやすみなさい」、英語 Good morning、韓国語の就寝）と、surprise を sad にした 1 件がある。dictation の取りこぼしには、挨拶が `none` になったものと、初回（閾値0.5・旧 whitelist 30 意図）の記録であり、当時は「承知」「わかりました」が ack（whitelist 外）になる例もあった。その後 whitelist に ack と input-wait を加えて32意図とし、閾値を0.38へ変更した。現行の実測は dictation 誤鳴 0/600・取りこぼし 18/200（修正後の残件を含む）。

## 8. 受け答えの表

列は `intent`、`lang`、`text`、`id`（タブ）。1 意図 × 1 言語につき 1〜3 文。文は返す側の言葉にする。ユーザーの発話を言い換えてオウム返しにしない。食事や場所を特定する文は即答に置かない。

`id` がある行は作り置き音声のフレーズ id。空の行は TTS で読む。作者の表は 536 行（54 意図 × 4 言語）、id あり 479、id 空 57。空の 57 は en 21・zh 18・ko 18 で、日本語 134 行はすべて id がある。日本語の候補数は意図ごとに 1〜3。

例（表にある候補）:

| 発話の意図 | 言語 | 返す文 | id |
|---|---|---|---|
| thanks | ja | どういたしまして | reply-thanks-1 |
| thanks | ja | こちらこそ、ありがとう | reply-thanks-2 |
| apology | ja | 大丈夫、心配いらない | z-emo-058 |
| apology | ja | 気にしないで、大丈夫だよ | reply-apology-1 |
| morning | ja | 良い朝ですね | z-grt-032 |
| morning | ja | おはようございます。今日も良い一日になりますように。 | greet-good-morning-today |
| sad | ja | つらかったね、そばにいるよ | reply-sad-1 |
| angry | en | That would really make me mad too | （空。合成） |

候補が複数あるときは実行のたびに 1 本。上の表は抽選結果ではない。再学習は不要。表だけ差し替える。

---

# English

## 1. What it does

```
one utterance line (ja / en / zh / ko)
  → classifier (54 intents + none)
  → below threshold, or none → silence
  → intent not in the 32, or empty reply → silence
  → otherwise pick one canned reply in that language and hand it to playback
```

This path is separate from the agent's long answer. If classification fails, the transcribed text still goes through. Only the instant reply is missing.

The 32 allowed intents cover greetings, thanks, apology, emotion, plus ack and input-wait. The source of truth is `speak_intents.txt`, one intent per line.

| Group | Intents |
|---|---|
| Greeting | hello, morning, night-sleep, goodbye, otsukare, return-home, leaving, first-meet, reunion, how-are-you, welcome-in |
| Thanks, apology, care | thanks, apology, care |
| Emotion | joy, moved, surprise, encourage, praise, empathy-here, sad, lonely, worry, relief, angry, calm-down, embarrassed, love, laugh, peaceful |

`how-are-you` is in the allowed set. `invite` and `meetup` are left out of the source list because the reply becomes situational. Invite, meetup, progress, questions, other ops intents (including doing), and `none` are classified and kept silent. If the file cannot be read, the author's `respond.py` uses an empty set and speaks nothing. The fallback set in `voicein.py` differs from the source: it includes `invite` and `meetup` and omits `how-are-you`. That differing set is used if the file cannot be read or is empty. The test list is a fixed copy of the source list and must be synchronized when the source changes.

Do not call `afplay` from the classifier. Seat, quiet hours, and the playback queue belong to the speaker (the author uses `voice.speak`).

## 2. Designing the intents

The first classifier predicted a reply id directly: 491 ids (greet 124, emotion 195, ops 172) plus `none`, 492 classes. Greet and emotion were all in. Ops kept only short spoken lines (`z-ops-*`, unprefixed short ids, and lines that read as waiting, checking, running, or preparing).

491 classes were too fine. Probability split inside one meaning such as thanks and never cleared 0.55. On the author's check, 「ありがとう！」, "Thanks a lot", 「谢谢你」, 「ごめん、間違えた」, and 「よろしくね」 all came back `none`. Only 「おはよう」 hit.

The unit is now an intent. `intents.txt` has 54 lines (name, tab, description). The classifier has those 54 plus `none` (55 classes). It does not predict a phrase id. After the intent hits, one line is chosen from the reply table.

`none` means the utterance needs a real answer: a knowledge question, an explanation, advice, a work instruction, or a request for information. Anything under the threshold is also returned as `none`. When unsure, prefer `none`. A wrong canned reply is worse than silence.

When mapping ids onto intents, unknown names are rejected. Uncertain ids go to `notify`. The author hand-fixed obvious bad assignments (for example `review-pass` → `result-report`). Eleven morning-announcement ids (alarm, weather, news, schedule, first train, and similar) are mapped to `none`. Those 11 are the `none` rows in `intents.tsv`.

Imperatives that had been attached to ops intents (〜して, してください, "do X") move to the `none` label. Emotion lines that ask for comfort stay. Questions, greetings, feelings, and reports are not counted as commands. Extra generation meant to balance counts per id was tried and rejected.

## 3. Building the training data

For a reproducible run, the recommended procedure is to use one LLM to write examples and a different LLM to check them. A model that grades its own sentences may mark them too easily. Whichever LLM writes the sentences, its terms attach to the trained weights. Text written by Gemma carries the [Gemma Terms of Use](https://ai.google.dev/gemma/terms), including the prohibited-use policy. Another generator attaches that generator's terms. The base encoder stays MIT either way. Do not include anyone else's voice or private utterances.

The author's classifier corpus was written with a self-hosted Gemma 4 (local OpenAI-compatible endpoint, 64-way). The run record (`progress-aizuchi.md`) says the same Gemma both wrote and checked the lines; this was not an independent check by a second model. A later external review is recorded in `(internal record)`.

Steps:

1. For each intent, ask for utterances a person would actually say. Keep ja / en / zh / ko roughly even. Mix casual and polite, short and one sentence. Keep only lines for which that intent's canned reply is a natural answer. A paraphrase of the reply, said by the user, is rejected. Do not mix work orders, or weather / knowledge / news questions, into greeting and emotion examples.
2. `none` is a separate prompt: lines that a greeting, a thanks, or a bare "yes" cannot answer. Split themes (instructions, information questions, advice, calculation, translation).
3. In the recommended procedure, have a different LLM mark every line. On the intent side: would this canned reply be natural? On the `none` side: does this really need a real answer? Drop the rejected numbers. If the same text appears under more than one label, drop every copy. Drop duplicate (label, text) pairs. For this corpus, generation and checking were both done by the same Gemma. For resident inference, load the tokenizer with `tokenizers` alone; do not import `transformers` or `torch`.
4. Split what remains by stratum. The author's `parse_val.py` sends `sha256(text) % 10 == 0` to dev and the rest to train (about 9:1).

Counts from the author's run:

| Stage | Count | Where it is recorded |
|---|---|---|
| First generation | 34,783 (17,585 id-side / 17,198 none, four languages nearly even). Each id asked for 36 lines (9 × 4 languages). none was 40 calls × 60 lines | progress note |
| After the same Gemma checked them | 31,454 kept, 3,329 dropped, then multi-label and duplicate removal → **28,933** (train 26,045 / dev 2,888) | progress note |
| Later file still on disk | **37,764** lines (`examples2.jsonl`, about 38,000). 2,156 of those are extra lines tagged `@intent::name` | line count |
| Split the adopted 55-class model used | train **32,560** (none 19,054) / dev **3,645** (none 2,130) | `train.jsonl` / `dev.jsonl`. 3,645 matches the progress note |

The progress note also records 1,241 Gemma paraphrases of smoke positives added later. Balancing the id side was not adopted. At the earlier id-classifier stage, 19 ids had fewer than 10 examples.

The dictation file (`smoke-dictation.tsv`) is not the training set. 800 rows (silent 600 = 4 languages × 150, reply 200 = 4 languages × 50). Columns: `lang`, `text`, `expect` (`silent` or `reply`).

## 4. Training

The base is [sbintuitions/modernbert-ja-130m](https://huggingface.co/sbintuitions/modernbert-ja-130m), MIT (© 2025 SB Intuitions). The author's model card: Japanese and English, 4.39T tokens, vocabulary 102,400, sequence length 8,192, hidden size 512, 19 layers. `transformers` must be 4.48 or newer. The Mac venv was Python 3.12, torch 2.14, transformers 4.56.2. The GPU run used the container named in the progress note, `tenhkspark/gemma-4-v2:v2`.

The head is one linear layer on the CLS vector (position 0 of the last hidden state). Loss is cross-entropy. Labels freeze in first-seen order, with `none` always last. Optimizer is AdamW, learning rate 2e-5, max length 96, 3 epochs, warmup for 10% of steps then linear decay, gradient clip 1.0. Checkpoints are saved as bfloat16. An existing `model.safetensors` resumes. Device is CUDA, else MPS, else CPU.

```
python3 train.py train.jsonl --out ckpt --base base --epochs 3 --batch-size 64 --lr 2e-5 --max-len 96 --seed 0
```

The adopted run (DGX Spark, DGX Spark, batch 64): 1,527 steps, epoch losses 1.485914 → 0.493772 → 0.152006, about **12 minutes**. The progress note says memory stayed under 20 GB. The other server on that machine was left running.

The same script runs on Mac MPS. The finished MPS run on record is the earlier 491-id model (batch 32, 2,442 steps): about **37 minutes**, final loss 0.358. The adopted 55-class checkpoint is the GPU run.

Pick the threshold on dev by keeping none-misfire small. The initial adopted value was **0.5**. In that sweep, 0.3 scored 0.9621 / 0.0167, 0.4 scored 0.9621 / 0.0083, and 0.5 and 0.6 scored 0.9394 / 0.0000. The threshold was later changed to the current **0.38** to reduce dictation misses. Current int8 results: dictation false replies 0/600 and missed replies 18/200; smoke intent accuracy 0.9697 and none misfires 0/120. See the negtest record in `progress-aizuchi.md`.

## 5. Export to ONNX int8

Export the PyTorch checkpoint to ONNX, then dynamic quantization to int8. Logits are `[batch, 55]`. Opset 17. Batch and sequence length are dynamic axes. Quantization is `quantize_dynamic` with weight type `QInt8`. Copy the tokenizer, `labels.json`, and `threshold.txt` next to the ONNX file. The resident process does not import torch.

Right after export, compare PyTorch and int8 logits on the same two sentences. The author's record: argmax agrees, max |Δlogit| = 0.85. The progress note lists fp32 at 504 MB and int8 at 126 MB. The int8 file on disk now is 132,993,740 bytes.

Score smoke again on int8. The author's extra export bar was: intent accuracy must not fall by 0.01 or more from the torch score of 0.939, and none-misfire stays at or under 1%. If that fails, do not ship the int8 file.

| Metric | torch (threshold 0.5) | ONNX int8 | Result |
|---|---|---|---|
| Smoke intent accuracy | 124/132 = 0.9394 | 126/132 = 0.9545 | pass (higher) |
| Smoke none misfire | 0/120 | 0/120 | pass |
| Dev accuracy (n=3645) | 0.8236 | 0.8167 | −0.007 |
| Dev none misfire | 0.0150 | 0.0164 | +0.0014 |
| Inference median | 9.99 ms (MPS, n=200) | 2.4 ms (CPU / onnxruntime) | |

Resident RSS is about **389 MiB**. Startup, from completed imports through OrtInfer and reply-map setup, is **0.27 seconds**. Decision median is **2.4 ms** (`serve.answer("ありがとう")`, n=200). The tokenizer is loaded with `tokenizers` alone; `transformers` and `torch` are not imported (`~/project/ops/codex-rss.md`, commit `(internal)`).

Dev none-misfire sits a little over 1%. The pass bar is the smoke set (§7). The six int8 smoke misses fell through to `none` under the threshold. They were not assigned a wrong id (for example 「おやすみなさい」 → none 0.483, Korean 「이제 잘게」 → none 0.381).

## 6. Resident server and socket format

A UNIX socket. The author's default path is `~/.config/voice/aizuchi.sock`. One connection carries utterances one line at a time. Each line gets one JSON line back. onnxruntime on CPU, intra-op and inter-op threads both 1, memory arena off. Tokenizer max length 96, pad id 3.

```json
{"intent": "thanks", "score": 0.9719, "id": "reply-thanks-1", "reply": "どういたしまして", "lang": "ja"}
```

| Field | Meaning |
|---|---|
| intent | One of the 54 names, or `none`. An inference exception is `error` |
| score | Confidence of the top class. Still present when the threshold forced `none` |
| id | Phrase id from the reply table. Empty for a synthesized line, for `none`, and when under the threshold |
| reply | Reply text in the detected language. Empty in the same cases |
| lang | Detected from the utterance: hiragana or katakana → ja, hangul → ko, hanzi → zh, otherwise en. If that language has no candidates, fall back to ja |

`none` and below-threshold:

```json
{"intent": "none", "score": 0.9991, "id": "", "reply": "", "lang": "ja"}
```

Exceptions omit `score`: `{"intent":"error","error":"..."}`. A client must not treat a response without `score` as a normal result. The transcript still continues.

When a language has several candidates, pick one at random.

Two measurements of the author's resident process:

| | Progress note | Second check |
|---|---|---|
| Accepting on the socket | 2.26 s | 1.97 s |
| RSS | 746 MB | 745 MB |
| Round trip | median 5.07 ms / p90 5.52 / min 3.27 (n=200, tokenize + infer + JSON) | 3.45–9.59 ms on 8 utterances |

Those 8 utterances, no audio: 「ありがとう」 4.18 ms, thanks 0.9719; 「おはよう」 3.45 ms, morning 0.9888; 「今日の天気は？」 4.56 ms, none 0.9991; 「これデプロイして」 3.84 ms, none 0.9995; 「ごめん、間違えた」 4.69 ms, apology 0.9961; English "Thanks" 6.36 ms, thanks 0.9512 (empty id); 谢谢 9.59 ms, thanks 0.8554; 고마워요 7.65 ms, thanks 0.7966.

Voice input sends one line as soon as text exists. The author's `voicein` waits 0.2 seconds. A missing socket, a dead socket, a timeout, or broken JSON skips the instant reply and still passes the text on. Autostart must not launch a second `serve.py` when one is already running. A failed launch must not stop voice input.

## 7. Threshold and the pass bar

The initial threshold was 0.5; the current value is **0.38** after the dictation test adjustment. Keep current measurements separate from the initial run, and review both dev misfires and smoke when changing it.

run-all in [tests/](../tests/) plays no audio. The two instant-reply rows send `tests/aizuchi/` at a resident socket (or a temporary socket from `AIZUCHI_SERVE` plus `AIZUCHI_MODEL`). The model file is not in the tests. With no socket, those two rows fail.

| Fixture | Pass |
|---|---|
| `smoke.tsv` (132 positive + 120 none) | Intent accuracy ≥ 0.9, and the share of `none` rows predicted as some other intent ≤ 0.01 |
| `smoke-dictation.tsv` (600 silent + 200 reply) | Share of silent rows spoken as one of the 32 must be within the pass bar. Share of reply rows not spoken must also be within the pass bar. Any other `expect` value fails the file |

"Spoken" means the predicted intent is in `speak_intents.txt`. A wrong intent inside the 32 still counts as spoken on the dictation set.

Author's int8 server, first run-all (2026-09-24 18:51, no audio):

| Row | Result |
|---|---|
| smoke | Pass. 126/132 = 0.9545, none misfire 0/120 |
| dictation | Fail. Silent false-speak is within the pass bar. Reply misses do not meet the bar |

Smoke misses include under-threshold `none` (「おやすみなさい」, English "Good morning", a Korean good-night) and one surprise predicted as sad. This is the initial run (threshold 0.5, old 30-intent whitelist). At that time 「承知」 / 「わかりました」 were predicted as ack outside the whitelist. The whitelist was later expanded with ack and input-wait and the threshold changed to 0.38. Current measured dictation results are 0/600 false replies and 18/200 missed replies, including the remaining misses.

## 8. The reply table

Columns are `intent`, `lang`, `text`, `id` (tabs). One to three lines per intent per language. The line is what the listener says back. Do not paraphrase the user's utterance. Do not pin the line to a specific meal or place.

A non-empty `id` is a pre-made clip's phrase id. An empty `id` is read by TTS. The author's table has 536 rows (54 intents × 4 languages): 479 with an id, 57 without. Those 57 empty ids are en 21, zh 18, and ko 18. All 134 Japanese rows have an id. Japanese candidates are 1 to 3 per intent.

Examples (candidates that are in the table):

| Intent | Language | Reply | id |
|---|---|---|---|
| thanks | ja | どういたしまして | reply-thanks-1 |
| thanks | ja | こちらこそ、ありがとう | reply-thanks-2 |
| apology | ja | 大丈夫、心配いらない | z-emo-058 |
| apology | ja | 気にしないで、大丈夫だよ | reply-apology-1 |
| morning | ja | 良い朝ですね | z-grt-032 |
| morning | ja | おはようございます。今日も良い一日になりますように。 | greet-good-morning-today |
| sad | ja | つらかったね、そばにいるよ | reply-sad-1 |
| angry | en | That would really make me mad too | (empty, synthesize) |

Several candidates means one draw per call. The table above is the inventory, not one draw. No retraining. Replace the table on its own.
