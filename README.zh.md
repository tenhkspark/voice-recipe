[日本語](./README.md) / [English](./README.md) / [中文](./README.zh.md) / [한국어](./README.ko.md)

# Voice recipe

面向读者：先阅读本 README，再阅读 [SETUP.md](SETUP.md)。供 AI 使用：请提供 [docs/output.md](docs/output.md)、[docs/input.md](docs/input.md)、[docs/aizuchi.md](docs/aizuchi.md) 以及 [tests/](tests/)。

为 Claude Code 或 Pi 在 Mac 上添加语音层的方案：支持语音输入、即时回复、语音摘要，并且仅在您面前的座位上进行音频回放。

## 简体中文

多语言语音输出（英语、中文、韩语）请参阅 [docs/output.md](docs/output.md) 中的“日语以外的声音”。

### 可以做什么

1. **即时响应** — 在用户说话后立即播放问候、感谢、道歉、情感等简短的固定回复。除此之外保持沉默。
2. **摘要阅读** — 将智能体的长回复缩短为适合听觉的版本，并由 AivisSpeech 逐句朗读。
3. **仅在当前窗口播放** — 即使在使用 tmux 时有多个会话，也只有当前显示的会话会发出声音。

**语音输入** — 详情及构建步骤请参阅 [docs/input.md](docs/input.md) 和 [SETUP.md](SETUP.md)。即时响应分类器的说明请参阅 [docs/aizuchi.md](docs/aizuchi.md)。

### 所需物品

- **Mac**
- **麦克风（作者推荐）** — a USB wireless microphone（USB 接收器。在 Mac 上的名称为 the USB receiver，48 kHz）
- **AivisSpeech**（[官方](https://aivis-project.com/speech/)）及声音模型。声音请自行从 [AivisHub](https://hub.aivis-project.com/) 获取
- **摘要方法示例**（摘要器可选 `apple` / `openai` / `off`）
  - 自制 Gemma 4（`gemma-4-26B-A4B-NVFP4-lmfp8`。[tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark) 的公开配方。OpenAI 兼容 API 在 :8890 提供服务。摘要耗时约 1.7 秒）
  - Apple（macOS 的端侧 LLM）
  - MLX 的 Gemma 4 E4B（`mlx-community/gemma-4-e4b-it-4bit`。关闭思考过程）
  - OpenAI 兼容的连接端点
- **Claude Code** 或 **Pi**（用于 hook 结束状态和等待确认）

### 根据您的环境推荐

用于摘要的 AI 请根据您现有的设备进行选择。

| 环境 | 推荐 | 备注 |
|---|---|---|
| 有 DGX Spark 等 GPU 设备 | 自制 Gemma 4（[tenhkspark/gemma4-spark](https://github.com/tenhkspark/gemma4-spark)） | 摘要耗时约 1.7 秒。作者的配置 |
| 仅有 Mac ・ 可使用 Apple Intelligence 的地区 | Apple 的模型 | 无需设置 |
| 仅有 Mac ・ 不可使用的地区 | MLX 的 Gemma 4 E4B 4bit（`mlx-community/gemma-4-e4b-it-4bit`，关闭思考，指令使用方案 2） | 摘要耗时约 1.9 秒，常驻内存约 4.5GB。若遗漏要点，使用方案 2 时错误率为 0/10 |
| 8GB 内存的 Mac ・ 不使用 AI | 基于规则的朗读 | 参考下方的“8GB Mac”设置。声音使用 AivisSpeech（常驻内存约 1GB）或 macOS 标准的 `say` |
| 已搭建 Ollama / LM Studio / 其他 OpenAI 兼容接口 | 指定该连接地址 | 将 `summarizer` 设为 `openai`，将 `summarizer_base` 设为 URL |

#### 8GB 内存的 Mac

不使用 LLM，在 `~/.config/voice/config.json` 中进行如下设置。通过 `summarizer: "off"` 不调用摘要器，并通过 `rewrite: false` 停止重写。长回复将根据 `voice.py` 的规则进行格式化，并跳过表格行和路径等内容，仅读取前两句（没有仅读取一句话的设置项）。AivisSpeech 常驻内存约 1GB。若需进一步减轻负载，可以不使用 AivisSpeech，而是改用 macOS 标准的 `say` 命令。Aizuchi 常驻内存约 0.39GB（基于 (internal) 的实测值），在语音输入时添加 `--no-aizuchi` 参数可以停止它。

```json
{
  "mode": "summary",
  "summarizer": "off",
  "rewrite": false
}
```

在这种设置下，无法根据内容对长回复进行摘要，仅读取开头两句可能会遗漏要点。

作者的配置为：自制 Gemma 4、a USB wireless microphone（在 Mac 上的名称为 the USB receiver，48 kHz）、an AivisHub voice model。

- **Claude Code** — 将 `tools/voice/output/voice-reply.sh` 和 `voice-notify.sh` 注册为 `~/.claude/settings.json` 中的 Stop / Notification hook。配置示例和部署步骤请参阅 [SETUP.md](SETUP.md)。
- **Pi** — 扩展的实现文件是 `tools/harness/voice-pi.ts`。关于将其部署到 Pi 扩展目录并启用的步骤，请参阅 [SETUP.md](SETUP.md)。它处理响应完成事件和多种等待确认的路径。

### 使用方法

构建规范请参阅 [docs/output.md](docs/output.md)，语音输入请参阅 [docs/input.md](docs/input.md)，即时响应分类器请参阅 [docs/aizuchi.md](docs/aizuchi.md)。请将这些文档与 `tests/` 一并交给 AI。

`tests/` 中的 run-all 通过条件：

| 项目 | 通过条件 |
|---|---|
| 路径测试 | 全部 pass |
| 静音端到端测试 | 全部 pass |
| 即时响应冒烟测试 | 意图 ≥ 0.9，none 误报 ≤ 0.01 |
| 语音输入风格的即时响应 | 无声误触发 ≤ 0.01，响应漏掉 ≤ 0.10 |

### 不要将音频数据包含在 `project/voice-recipe/` 中

无论是声音还是预制的 clip，都没有包含在 `project/voice-recipe/` 中。在 project 内的其他目录中存有用于播放的 clip。请自行放入 AivisSpeech 和 AivisHub 的模型。测试材料仅包含文本。

### 实测

以下是各记录时间点的测量值。run-all 的通过条件见上表，首次测量记录的是修正前的数据，并不代表当前的合格情况。

数据来源为 `e4b-prompt.md`・`summ-compare.md`・`runall-first.md`（2026-09-24）。样本为 10 条真实回复（正文 300 字以上）。摘要生成使用 temperature 0.2。

**即答**（run-all 首次，无声音）: smoke 意图 126/132 = 0.9545，none 误触发 0/120。语音输入风为无声误触发 0/600，回复遗漏 35/200 = 0.1750。路径测试 19 pass / 8 fail。静音端到端测试 10 pass。合计 2/4。修正前的数字。

**MLX Gemma 4 E4B**（`mlx-community/gemma-4-e4b-it-4bit`，关闭思考）: 单条 1.6~2.9 秒，峰值约 4.4GB。如果不开启思考，摘要会为空。在默认摘要指令下，主语替换 0、额外添加请求 0、要点缺失 5、朗读表格或路径 1。针对 E4B 的方案 2 最接近，缺失、主语、请求均为 0。超过 200 字的有 2 件（222 字和 241 字）。三个方案均未能同时满足“200 字以内且缺失 $\le$ 1 且主语 0 且请求 0”。

**OpenAI 兼容的 Gemma 26B**（同样的 10 条样本・同样的默认指令）: 主语替换、额外添加请求、要点缺失、朗读表格或路径均为 0。
