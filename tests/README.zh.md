[日本語](./README.md) / [English](./README.md) / [中文](./README.zh.md) / [한국어](./README.ko.md)

# 合格标准（静音）

不进行播放。`afplay` 和 `say` 将由测试程序替换。不包含音频文件。

材料（仅文本）:

- `fixtures/` … Stop 的 transcript 样本（Claude Code 格式及其他格式）
- `aizuchi/smoke.tsv` … 意图的正确率。正确率至少为 0.9，`none` 的误报率不超过 0.01
- `aizuchi/smoke-dictation.tsv` … 口述。不该响的误报率需 $\le$ 1%，该响的漏报率需 $\le$ 10%
- `aizuchi/speak_intents.txt` … 可以立即响应的意图。dictation 中的“响”仅限于此处

## 环境变量

| 变量 | 使用测试 | 默认值 |
| --- | --- | --- |
| `VOICE_PY` | test_paths / e2e | 必填。test_paths 也可以通过 `--voice` 传递。此 checkout 中不存在相邻的 `../voice.py` |
| `VOICE_REPLY` | e2e | 无（Stop 钩子。若文件不存在则 SKIP） |
| `VOICE_IN` | e2e | 无（`voicein.py`。若不存在则跳过相应的相槌测试） |
| `VOICE_TEST_SEAT` | test_paths | `seat-a`（允许发声的座位） |
| `VOICE_TEST_OTHER_SEAT` | test_paths / e2e | `other-seat` |
| `VOICE_TEST_FOREIGN_SEAT` | test_paths | `other-session`（禁止自报身份的其他会话） |
| `VOICE_E2E_SEAT` | e2e | `test`。仅当此名称时，检查记录标记是否为 `t` |
| `VOICE_TEST_CWD` | test_paths / e2e | `/tmp/voice-proj` |
| `AIZUCHI_DIR` | run-all | `tests/aizuchi`（smoke 和 speak_intents） |
| `AIZUCHI_PYTHON` | run-all | `python3` |
| `AIZUCHI_SOCK` | run-all | 无。仅在使用现有的常驻 Socket 时指定 |
| `AIZUCHI_SERVE` | run-all | 无。与 `AIZUCHI_MODEL` 保持一致并启动临时 Socket |
| `AIZUCHI_MODEL` | run-all | 无（不包含模型本体） |

座位名称 `test` 约定使用标记 `t`，当实现为该字符串时会打上标记。请勿填写机器特定的座位名称。

## 运行方式

请根据实际实现的路径进行调整。示例如下：

```sh
cd /path/to/voice-recipe

# 仅测试路径（voice.py）
VOICE_PY=/path/to/voice.py python3 tests/test_paths.py

# 从 Stop 钩子到相槌。音频播放由静音测试桩代替
VOICE_PY=/path/to/voice.py \
VOICE_REPLY=/path/to/voice-reply.sh \
VOICE_IN=/path/to/voicein.py \
  sh tests/e2e_silent.sh

# 运行 4 项。即使其中一项失败也会继续运行；有失败时退出码为 1
VOICE_PY=/path/to/voice.py \
VOICE_REPLY=/path/to/voice-reply.sh \
VOICE_IN=/path/to/voicein.py \
AIZUCHI_SOCK=/path/to/aizuchi.sock \
AIZUCHI_PYTHON=/path/to/python \
  sh tests/run-all.sh
```

如果没有常驻进程，smoke 的 2 项会失败（若要启动服务，需设置 `AIZUCHI_SERVE` 和 `AIZUCHI_MODEL`）。`test_paths.py` 和 `e2e_silent.sh` 单独运行时也读取相同的环境变量。相槌测试会绑定一个伪 UNIX socket，因此运行环境必须允许创建 UNIX socket。

`run-all.sh` 的输出包含 `项目、结果、详情` 以及失败的行（smoke 测试的前 12 行）。
