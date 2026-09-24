[日本語](./README.md) / [English](./README.md) / [中文](./README.zh.md) / [한국어](./README.ko.md)

# 合格の基準（無音）

再生しない。`afplay` と `say` は試験が差し替える。音声ファイルは同梱していない。

材料（文字だけ）:

- `fixtures/` … Stop の transcript 見本（Claude Code 形式と、それ以外の形式）
- `fixtures/lang-route.tsv` … 4 言語の文と、選ばれるべき音声設定キー
- `aizuchi/smoke.tsv` … 意図の正答。正答 0.9 以上、`none` の誤爆 0.01 以下
- `aizuchi/smoke-dictation.tsv` … 口述。鳴らしてはいけない誤鳴 1% 以下、鳴るべきの取りこぼし 10% 以下
- `aizuchi/speak_intents.txt` … 即答してよい意図。dictation の「鳴る」はここだけ

## 環境変数

| 変数 | 使う試験 | 既定 |
| --- | --- | --- |
| `VOICE_PY` | test_paths / e2e | 必須。test_paths は `--voice` でも渡せる。この checkout には隣の `../voice.py` がない |
| `VOICE_REPLY` | e2e | 無し（Stop 口。ファイルが無いケースは SKIP） |
| `VOICE_IN` | e2e | 無し（`voicein.py`。無ければ相槌は SKIP） |
| `VOICE_TEST_SEAT` | test_paths | `seat-a`（鳴ってよい席） |
| `VOICE_TEST_OTHER_SEAT` | test_paths / e2e | `other-seat` |
| `VOICE_TEST_FOREIGN_SEAT` | test_paths | `other-session`（名乗ってはいけない別セッション） |
| `VOICE_E2E_SEAT` | e2e | `test`。この名前のときだけ記録の印が `t` であることを見る |
| `VOICE_TEST_CWD` | test_paths / e2e | `/tmp/voice-proj` |
| `AIZUCHI_DIR` | run-all | `tests/aizuchi`（smoke と speak_intents） |
| `AIZUCHI_PYTHON` | run-all | `python3` |
| `AIZUCHI_SOCK` | run-all | 無し。既存の常駐ソケットを使うときだけ指定する |
| `AIZUCHI_SERVE` | run-all | 無し。`AIZUCHI_MODEL` と揃えて一時ソケットを起動する |
| `AIZUCHI_MODEL` | run-all | 無し（モデル本体は同梱しない） |
| `RUN_LANG_ROUTE` | run-all | 無効。`1` のときだけ言語振り分け試験を追加 |

席名 `test` は印 `t` の契約で、実装がこの文字列のとき印を付ける。マシン固有の席名は入れない。

## 回し方

パスは実装のある場所に合わせる。下は例。

```sh
cd /path/to/voice-recipe

# 経路だけ（voice.py）
VOICE_PY=/path/to/voice.py python3 tests/test_paths.py

# Stop 口から相槌まで。音はスタブ
VOICE_PY=/path/to/voice.py \
VOICE_REPLY=/path/to/voice-reply.sh \
VOICE_IN=/path/to/voicein.py \
  sh tests/e2e_silent.sh

# 4 項目。1 つ落ちても最後まで走り、失敗があれば終了コード 1
VOICE_PY=/path/to/voice.py \
VOICE_REPLY=/path/to/voice-reply.sh \
VOICE_IN=/path/to/voicein.py \
AIZUCHI_SOCK=/path/to/aizuchi.sock \
AIZUCHI_PYTHON=/path/to/python \
  sh tests/run-all.sh
```

常駐が無いとき、smoke の 2 項目は FAIL になる（起動するなら `AIZUCHI_SERVE` と `AIZUCHI_MODEL`）。`test_paths.py` と `e2e_silent.sh` は単体でも同じ環境変数を読む。相槌試験は偽 UNIX ソケットを bind するため、実行環境で UNIX ソケット作成が許可されている必要がある。

`run-all.sh` の出力は `項目、結果、内訳` と、落ちた行（smoke は先頭 12 件）。

## 言語別の声選択（無音）

通常の `run-all.sh` は日本語環境向けのままです。言語振り分けも確認するときだけ、`RUN_LANG_ROUTE=1` を付けます。

```sh
VOICE_PY=/path/to/voice.py RUN_LANG_ROUTE=1 sh tests/run-all.sh
```

単体実行は `VOICE_PY=/path/to/voice.py python3 tests/test_lang_route.py`。`VOICE_PY` は `--select-voice-key <文>` を受け取り、再生せず選択する設定キーを標準出力へ1行返す必要があります。試験は `VOICE_NO_PLAY=1` も設定し、`lang-route.tsv` の4文すべてでキーの完全一致を確認します。
