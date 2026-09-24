[日本語](./output.md) / [English](./output.md) / [中文](./output.zh.md) / [한국어](./output.ko.md)

# 语音环境搭建规范书（面向 AI Agent）

旨在让初次接触的 AI Agent 能够以相同的方式，在单台 Mac 上构建出具备“听、即时响应、摘要、语音合成”功能的语音环境。本规范不依赖特定的密钥、实际地址或外部服务的音频文件（请替换为各自准备的内容）。

## 1. 架构与流程

```
语音输入 (PTT→文本)
   ├─→ Aizuchi（即时响应：在数毫秒内判定为固定回复或 none）→ 播放
   └─→ 正式回复（智能体的回复正文）
         → 摘要 LLM（当长度超过 80 字时，将长句缩短为适合听觉的长度）
         → AivisSpeech（逐句合成）→ 播放
         （预制包：若文本一致，则直接播放预存的音频文件）
```

此架构不需要外部付费 TTS（如 ElevenLabs 等）。所有合成均在用户本地的 Mac 上通过 AivisSpeech 完成。

- **听**: 仅支持 Push-to-Talk（按键通话）。按下时录音，松开后通过 whisper.cpp 进行转写，并应用替换表（将误识别结果修正为正确文本）。在 PTT 路径中，voicein 会将识别出的文本输出到标准输出，Hammerspoon 则直接将该字符串输入到当前活动输入框中。不具备常驻监听或唤醒词功能。
- **即时响应 Aizuchi**: 发话后 → 通过常驻的 ONNX int8 服务器在 ~5ms 内判定意图 55；若置信度低于阈值，则判定为 `none`。若是 `none` 则不执行任何操作。分类器基于 `modernbert-ja-130m` 的 CLS + 线性层（126MB int8，常驻 RSS 约 389 MiB，启动约 0.27 秒。基于 tokenizer 单独运行的实测数据）。
- **摘要 LLM**: 默认使用 macOS 标准的端侧 LLM (Foundation Models)。也可切换至 OpenAI 兼容的接口（`summarizer: apple|openai|off`）。若两者均失败，则直接使用原文的前两句。
- **声音 AivisSpeech**: 本地 TTS 引擎（发言人为配置中的 `speaker_id`）。仅在合成完全失败时才会回退（fallback）到 `say` 命令。

## 2. 接缝

### hook 的输入（stdin 的 JSON）

| 触发条件 | 调用方式 |
|---|---|
| Claude Code Stop | `voice-reply.sh` → `voice.py reply --seat <席名>`。仅当 transcript_path 为 CC 格式（包含 `message.role` 为 user/assistant 行的 JSONL）时才处理。正文 = 直前 user 发言之后的 assistant 正文。超过 80 字则进行摘要。 |
| Claude Code Notification | `voice-notify.sh` → `voice.py hook`。仅发送 “<席名>，等待确认”。 |
| Pi 扩展 | `voice.ts`。响应完成为 `agent_settled`（无自动后续的确定时刻），等待确认为 `ui_prompt_start`(kind=confirm)，非交互模式为 `tool_execution_end`(isError) → 同样调用 `voice.py reply --seat`。正文将 assistant 全文转换为 CC 格式的临时 JSONL，并通过 transcript_path 传递。 |
| 手动 | `voice.py say "文本"`（支持 stdin）、`read`（读取 last.txt 全文并穿透席位限制）、`test`（试听） |

关键的过滤机制：即使 Grok 等非 CC Agent 触发了 `~/.claude/settings.json` 中的 hook，如果 transcript 不是 CC 格式，程序也会以 exit 0 静默退出。role 判定是基于整个文件的（即使开头的元数据行超过 40 行也会正常处理）。

### Socket 形式（Aizuchi 常驻）

- UNIX Socket（例如 `~/.config/voice/aizuchi.sock`）。每次连接及每行发言返回一行 JSON
- 响应：`{"intent": str, "score": float, "id": str, "reply": str, "lang": str}`。若 `id`/`reply` 为空，则指代“待合成的回复文本”。若为 none 或低于阈值，则返回 `intent:"none"` 且 `id`/`reply` 为空
- 服务端推理异常将以 `{"intent":"error","error":...}` 形式返回。PTT 客户端不会播放错误响应或非允许意图的提示音，也不会切换到本地推理。即使失败，通常 PTT 的识别文本仍会持续返回至标准输出（参见坑点 7.2）

### 配置键（config.json 的主要部分）

- `mode`: `off | earcon | summary | full`（默认 summary = 摘要阅读）
- `seat`: 固定席位名称。如果为空，则仅在与“当前显示的 tmux 席位”一致时播放（参见第 4 章）
- `quiet_hours`: `[开始, 结束]`（默认 23:30–08:00）。完全静音
- `night_brief_hours`: 夜间会播放但内容较短（默认 30 字 / 1 句）。仅在 quiet 范围之外生效
- `summarizer`: `apple | openai | off`，`summarizer_base`: 与 OpenAI 兼容的 URL
- `speaker_id`（AivisSpeech 的声音。请勿修改），`speech-styles.json`（仅允许根据 purpose 修改速度、停顿和音量）
- `pack`: 预制语音包（enabled・model・voice・lang）。`model` 是语音包的生成源，`voice` 是拥有声音目录的生成源的话者 ID（对于像 AivisSpeech 这样不使用声音栏的模型，则留空）。当前的 manifest 中包含 `eleven_v3`、`eleven_multilingual_v2` 和 `aivis-aida` 的 ok 行。短语会在进行 NFKC 规范化后，去除标点符号和空格进行匹配，如果匹配成功则立即播放语音。索引中会注册读音修正前后的写法。

## 3. 摘要指令与禁令

作者在自己的环境中，使用自制的 Gemma 4 进行摘要。权重为 `gemma-4-26B-A4B-NVFP4-lmfp8`，公开配方见 https://github.com/tenhkspark/gemma4-spark（通过 DGX Spark 运行 `serve.sh up`，并在 :8890 提供 OpenAI 兼容 API）。单条摘要耗时约 1.7 秒。如果没有 Spark，可以使用 Apple 的模型（macOS 标准的端侧 LLM）/ MLX 的 Gemma 4 E4B（见下方方案 2 的指令）/ 或任何 OpenAI 兼容的连接端进行替代。

原则：**不得更改主语（说话人是助手）・不得添加请求・不得读取表格或路径**。最严重的错误是将助手说“我会做”的内容变成对用户的请求。只有当原文末尾有提问时，才将其保留在最后。

Gemma 26B 专用（`voice.py` 中的 SUMMARY_PROMPT，OpenAI 兼容 API 请求参数：temperature 0.2, max_tokens 300）：

```
以下是 AI 助手回复给用户的内容。为了方便听觉理解，
请用日语口语将要点总结为 2~3 句话，总字数控制在 120 字以内。
不要读出表格、列表、代码、路径和符号，而是用语言描述其内容。
仅当原回复中包含请求或提问时，才将其内容放在最后。如果没有，则不要自行添加。
说话人是助手。不要更改主语。
不要将助手承诺要做的事情变成对用户的请求或提问。
仅输出总结后的句子。
```

# 回复
{text}

# 总结
```

针对小型模型（如 Gemma 4 E4B 4bit 等）的方案 2（使用相同的 10 个样本，实现了“无遗漏、无主语缺失、无虚构内容”；仅 2/10 出现字数超限）:

```
以下是 AI 助手回复用户的回答。请将其总结为 120 到 200 字之间、听起来自然的口语化内容。严禁超过 200 字。不要使用换行或列表。
仅保留以下内容。不要读取表格中的所有行。
- 结论。
- 如果出现数字，需在同一句中说明原因。
- 谁要做什么。说明姓名和任务，不要使用编号。
- 保留的内容与删除的内容。
- 仅当原文末尾有一个问题时，才在最后保留该问题。
不要添加原文中没有的问题、命令或选项。说话者为助手。不要更改主语。不要读取路径和符号。仅输出总结后的文本。
```

# 回复
{text}

# 总结
```

注意：在 `voice.py` 的摘要请求中不要指定思考（thinking）的开关。由于 mlx-lm 的默认设置是开启思考，如果需要关闭思考，必须通过目标服务器的启动配置（例如：`--chat-template-args {"enable_thinking":false}`）来进行指定。这仅限于服务器端支持该设置且启动配置已生效的情况。根据实测记录，如果不关闭思考，思考过程会耗尽 `max_tokens` 300 的配额，导致正文为空。实测发现，过于简短的指令（180 字以内、4 句以内）会导致要点缺失，因此不使用此类指令。质量评估方法是基于 10 份实测记录，统计“要点缺失、主语错误、额外添加请求内容、字数”（summ-compare 方式）。

## 4. 座位判定

假设存在多个代理人座位（tmux 会话）：

1. 如果设置了 `config.seat`，则**仅该座位**会发出声音。
2. 如果为空，则仅当触发源座位（通过 `TMUX_PANE` 执行 `tmux display-message -p -t <pane> '#S'` 获取）与**当前正在显示的客户端座位**一致时，才会发出声音。
3. 无法获取座位或不匹配时保持静音（日志记录 `kind=seat-skip`）。**目标为空的 tmux 会返回其他座位的名称**，因此如果 `TMUX_PANE` 为空，则在入口处拦截（踩坑点 7.1）。
4. 穿透性异常：手动 `read` / `test` / `--no-play`。Kill Switch `CLAUDE_VOICE_MUTE` 会使所有路径保持静音。

## 5. 逐句合成与失败处理

- 将摘要文本按句拆分，使用 AivisSpeech 逐句合成。开始播放当前句后，在播放期间合成下一句并依次播放（确保回复之间不会重叠。播放期间将保持锁定状态）。
- 预制包（Pre-made packs）：对于归一化后文本一致的短语，直接播放已合成的音频，不再进行实时合成（参见 5.5 节）。
- 若 Aivis 在句子中间合成失败，则**跳过该句**（以防止声音混杂）。仅当所有句子都合成失败时，才使用 `say` 作为回退方案播放全文。
- earcon（短促提示音）：针对 done/read、attention、error 使用不同的音效。attention/error 可以叠加播放，done 则在播放过程中跳过。
- 重复抑制（相同的最终句在 30 分钟窗口内不会再次播放）・间隔门控（默认情况下，5 秒内的第二条消息不播放语音，仅播放 earcon）・语音播放期间自动静音。

## 5.1 按文本语言选择声音

对即答、摘要和即时回复正文，先判定实际要朗读的文本所用语言，再把文本交给该语言对应的声音：日语使用 AivisSpeech；其他语言使用该语言推荐的本地 TTS，若没有合适的本地引擎或声音，则使用 macOS 已安装的对应语言系统声音。不得只按输入语言或席位选择声音。多语言文本以本次要朗读的句子为单位判定；即答也按所选回复文本判定。

当前实现状态需如实区分：现行 `voice.py` 的正文与摘要仍使用配置的 AivisSpeech `speaker_id`，合成失败时固定回退到 `/usr/bin/say -v Kyoko`，尚未按语言自动切换。Aizuchi 目前按输入字符范围选择回复语言（假名 ja、韩文 ko、汉字 zh、其他 en；缺少该语言回复时回退 ja），但 `voicein.py` 只将回复文本交给 `voice.speak()`，不会根据 `lang` 选择声音。上述规则是目标规格，不能描述成现有路径已经自动支持。

验证语言到声音的选择时不要播放音频。使用 `tests/fixtures/lang-route.tsv` 中的四种语言和预期 `voice_key`，运行 `tests/test_lang_route.py`；该脚本对每条文本调用 `voice.py --select-voice-key`，设置 `VOICE_NO_PLAY=1`，并检查标准输出的选择结果是否与 fixture 一致。例如：

```sh
VOICE_PY=/绝对路径/到/voice.py python3 tests/test_lang_route.py
```

测试应报告 `summary 4/4`，全过程不调用播放设备。新增或更改语言路由时，需同时更新 fixture，并保持此静默检查可验证。

### 5.5 如何制作预制语音包

预制包（Pre-made pack）是指根据 phrases（回复短语）的内容生成的即时响应语音。目前的 `project/voice/manifest.tsv` 中包含 2,243 条 `aivis-aida` 的 ok 行，同时也包含 `eleven_v3` 和 `eleven_multilingual_v2` 的行。由于 `voice.py` 的默认 pack 为 `eleven_v3`，因此在使用语音包时，需确保 `model`、`lang` 和 `voice` 的设置与 manifest 中的内容一致。在本地生成的示例中可以使用 AivisSpeech，但这并不意味着所有的语音包都是由 AivisSpeech 制作的。

制作步骤：

1. 准备 `phrases.tsv`（category / id / ja / en / zh / ko）。`id` 在各语言间是通用的。
2. 通过 AivisSpeech 的 API（如 `POST /synthesize` 等本地 HTTP API）逐条合成文本，并以 mp3 或 wav 格式导出至 `pack/<lang>/<id>.<ext>`。
3. 将已合成的行作为 `ok` 记录在 manifest（id・文件・字符数・说话人）中。重新开始时，跳过 manifest 中的 `ok` 行（幂等性）。
4. 通过 `voice.py` 的 `pack` 设置（enabled・model・voice・lang）进行加载。匹配过程会在进行 NFKC 归一化后，去除标点符号和空格，并包含读音修正后的文本。如果匹配失败，则回退到常规的逐句合成模式。

## 6. 如何筛选即时回答意图及构建训练数据

1. **筛选意图**：从所有回复短语中仅挑选“可以用固定句式回答的内容”。在实际操作中，问候、感谢、情感类意图全部保留；运营类意图则仅筛选为“等待确认”、“执行中”、“已完成”等简短的固定句式，共计 55 个意图。
2. **进一步筛选触发意图**：现有的分类标签为 55 个意图，而发言许可列表（Speech Permission List）为 30 个意图。对于口述内容中的指示或提问，不进行即时回答。仅对列入许可列表（每行一个意图的文本文件）中的意图进行发言。**如果文件不存在，则不触发所有意图，而是视为空集**（教训见 7.4）。
3. **使用自己的 LLM 构建训练数据**：针对每个意图，生成多语言（ja/en/zh/ko）× 不同表达方式的变体话术。对于 `none` 类别，则单独生成“无法用固定句式回答的话术”。
4. **使用相同的模型进行校验**：对所有样本进行判定：该回复是否自然 / `none` 是否确实无法用固定句式回答。剔除判定失败的样本及重复项后，构建数据集。实际行数为 `dataset.jsonl` 28,933 行，`train.jsonl` 32,560 行，`dev.jsonl` 3,645 行（train/dev 总计 36,205 行，比例约为 9:1）。关于这些文件之间数量差异的由来以及生成前的样本数，不根据已确认的实物进行断定。
5. **训练**：采用 CLS + Linear Head，AdamW 2e-5，训练约 3 个 epoch（如果是 130M 参数规模，在 Mac 上约需 40 分钟）。阈值根据 dev 集上“最小化 `none` 误报”来决定（实际结果为 th=0.55，误报率 0.36%）。
6. **ONNX int8 量化**：通过 export → 动态量化，体积从 500MB 降至 126MB。**判定是否合格的标准是使用固定测试集（smoke.tsv），并需达到与 PyTorch 版本相同的标准**（意图准确率 $\ge$ 0.9，`none` 误报 $\le$ 1%）。如果不达标，则放弃 int8 量化。
7. **集成**：在常规 PTT 识别流程中，文字识别完成后向 Socket 发起查询并尝试即时回答，随后再返回正文。即使分类 Socket 或即时回答处理失败，异常也会被吸收，识别的正文返回流程仍会继续。此说明是指常规 PTT 路径的行为。

## 7. 今日踩过的坑

1. **目标为空的 tmux 返回了错误的席位名称**（test: `test_hook_names_the_firing_seat`）— 当 `TMUX_PANE` 为空时直接拦截
2. **非 CC transcript 不会提示“无法获取正文”**（test: `test_pi_stop_without_transcript_speaks`）— 对整个文件进行 CC 格式校验，Pi 通过 CC 格式的临时 JSONL 传递正文
3. **未将 `--no-play` 传递给子进程**（test: `test_hook_no_play_does_not_arm_player`）— 在 spawn 的 `say` 命令中也加上该参数
4. **静音时段 earcon 仍在响**（test: `test_quiet_hours_silent`）— quiet 模式也应禁用 earcon
5. **去重逻辑误判了日志列**（test: `test_dedupe_skips_second`）— 将比较的列固定为正文
6. **显式 say 在席位校验时被拦截**（test: `test_explicit_say_without_seat_speaks`）— 手动 say 应作为 manual 处理并允许通过
7. **席位判定异常时无条件播放 earcon**（test: `test_hook_error_does_not_play_without_seat`）— 异常路径也必须进行席位校验
8. **试听功能无视关闭状态**（test: `test_audition_respects_enabled`）— test 也应通过 `speak()` 进行
9. **白名单缺失导致所有意图都被播放**（review: review）— 缺失时应处理为空集合
10. **常驻错误响应**（review: review）— PTT 客户端不应播放错误响应或未经许可的意图，也不应切换到本地推理。失败时也应继续输出识别到的正文
11. **Fallback 时丢失输入行**（review: review）— stdin 只读取一次，仅对未处理的部分进行 fallback
12. **小型摘要模型因思考 Token 导致输出为空**（summ-compare）— 指定关闭思考（thought）
13. **“过于简短”的指令导致要点缺失**（e4b-prompt 案 3）— 指定字数下限（120–200 字）

## 8. 合格标准

- **必须重构代码，直到通过所有** `tools/voice/output/tests/`（test_paths.py 中的 27 个测试、e2e_silent.sh、run-all.sh）。设计要求不发出声音，而是通过检查 afplay/say 的调用参数进行验证。
- Aizuchi：在 smoke 固定测试中，意图识别准确率 ≥0.9，none 误报率 ≤1%，并对比 int8 转换前后的性能表现。
- 摘要：使用 10 份实际记录进行测试，确保不存在要点缺失、主语混淆或额外添加请求的情况（仅限制字数上限）。
- 失败报告仅限一行原因说明。若因同一原因失败两次，则交由人工处理。

## 给想要提升语调的人

可以放心尝试的步骤顺序：

1. 培养读音词典（`readings.tsv` 格式）。效果最显著
2. 为每个角色调整 AivisSpeech 的语速、抑扬顿挫和音高
3. 在 AivisHub 中选择允许训练或修改的角色
4. 使用自己录制的声音进行追加训练

### 高级进阶：通过训练进一步优化

进行训练时，请使用您自己录制的声音，或明确允许用于训练的数据集/声音，并务必确认每种素材的许可协议（License）。本文不涉及将语音合成服务的输出作为训练素材的操作流程。


## 非日语的声音（英语、中文、韩语）

作者（日语）使用的是 AivisSpeech，但 AivisSpeech 仅支持日语。对于英语、中文和韩语，则使用具有类似功能的工具。

### 实际运行情况

确认对象为 `tools/voice/output/voice.py`、`tools/voice/input/voicein.py`、`project/voice/aizuchi/serve.py`、`project/voice/aizuchi/reply_map.tsv`。

- 回复正文及摘要由 `voice.py` 根据配置中的 `speaker_id` 发送到本地 AivisSpeech API（默认 `127.0.0.1:10101`）并进行播放。当前的语音选择不包含语言判定，如果无法使用 AivisSpeech，则始终回退到 `/usr/bin/say -v Kyoko`。因此，即使是英语、中文或韩语的正文，也不会根据语言切换语音，而是统一使用日语发言人 ID 或 Kyoko 进行播放。
- Aizuchi 通过检查输入字符的范围进行判定：假名 → ja、谚文 → ko、汉字 → zh、其他 → en。仅在没有对应语言的回复候选时才会回退到 ja。在 `reply_map` 选定 `text` 后，`voicein.py` 仅是将该字符串传递给 `voice.speak()`，并不会将 `lang` 用于语音选择。即使存在回复片段的 ID，也必须与 `voice.py` 的包匹配设置及 `manifest` 一致，Aizuchi 本身并不负责选择语言语音。

### 选项与推荐

对于英语、中文和韩语，首先建议使用可在 Mac 上运行的本地 TTS 应用/引擎。这里将 [piper-plus](https://github.com/ayutaz/piper-plus) 作为共同候选方案。该项目提供 Apple Silicon macOS 二进制文件、本地 HTTP API 以及 MIT 代码许可，并具备说话人选择、语速等调节功能以及词典功能。但需要注意的是，该项目目前已发布的预训练语音仅包含 JA/EN/ZH/ES/FR/PT 六种语言，代码支持韩语并不等同于已发布韩语预训练语音。对于韩语，需确认后文提到的语音模型发布情况，若无可用模型，则使用 macOS 自带的声音。

| 语言 | 推荐方案与声音示例 | 与 AivisSpeech 相同的角色 | 常驻内存 (RSS) 预估 |
|---|---|---|---|
| en | piper-plus。从模型列表中选择英语模型和说话人 | 具备声音选择、语速/抑扬顿挫设置、HTTP API。词典/G2P 功能需确认各语言的具体实现 | 公开文档中未提及常驻 RSS 值。即使是小型 ONNX 声音（数十 MB 级），实际 RSS 亦未测量 |
| zh（普通话） | piper-plus。选择中文模型和说话人 | 同上。需通过模型卡片确认普通话、声音及许可 | 同上，未测量 |
| ko | piper-plus 的代码支持韩语。但官方 README 的 6 种预训练语言列表中不包含 ko。在确认韩语模型的发布情况和许可之前，最低限度的替代方案是 macOS 的 Yuna | API 和词典等代码层面的功能，与可用的韩语预训练语音是分离的。如果找不到模型，则无法将其作为引擎使用 | macOS 标准声音无需常驻合成应用。piper-plus 未测量 |

参考候选：[Kokoro 82M](https://github.com/hexgrad/kokoro) 是 Apache-2.0 协议的小型模型，拥有英语和普通话声音，并有针对 Apple Silicon 的 MLX 实现，但官方支持列表中不包含韩语声音。关于 piper-plus 的代码和 MIT 许可，请参阅 [官方 README](https://github.com/ayutaz/piper-plus)；关于可用模型，请参阅 [预训练模型列表](https://github.com/ayutaz/piper-plus/blob/dev/docs/guides/development/pretrained-models.md)。模型的许可与代码许可不同，请分别确认。

| macOS 标准声音 | 安装方法 | 备注 |
|---|---|---|
| 英语 | 系统设置 → 辅助功能 → 朗读内容 (Spoken Content) → 系统声音 → 管理声音 (Manage Voices)。选择 English 以及带有 Enhanced/Premium 标识的声音进行下载。候选名称因地区和 macOS 版本而异，请在列表中确认（例如：Samantha、Alex） | 使用 `say -v '?'` 可以确认当前 Mac 中安装的确切声音名称和语言 |
| 中文 | 按照相同步骤选择 Chinese (China mainland) / Mandarin 的声音，并下载带有 Enhanced/Premium 标识的声音（例如：Ting-Ting zh-CN、Mei-Jia zh-TW、Sin-ji zh-HK） | 中文需选择对应的地区变体。显示名称请根据 OS 版本确认 |
| 韩语 | 按照相同步骤选择 Korean 的声音，如果有 Enhanced/Premium 标识则进行下载（例如：Yuna ko-KR） | 是否显示 Enhanced 标识取决于 OS 版本。请在声音列表中确认实物 |

Apple 的官方步骤请参阅[管理和下载追加声音](https://support.apple.com/zh-cn/guide/mac-help/mh27448/mac)。macOS 标准的 `say` 是本地语音合成的最低限度替代方案，虽然可以指定语速，但它不会像 AivisSpeech 那样提供包含声音模型选择 UI、语调调节、用户自定义词典以及 TTS 专用本地 HTTP API 的完整套件。`say` 的声音使用 OS 已安装的列表。虽然 Apple 的开发文档中提供了语速、声音和朗读词典 API，但不能断定这些可以作为此处提到的 `say` CLI 的通用配置来使用。

### 导入与回复音频片段的制作

1. 按照 [piper-plus 官方步骤](https://github.com/ayutaz/piper-plus) 安装 macOS Apple Silicon 二进制文件，并获取所需语言的模型。请在模型卡（Model Card）中确认商用、修改及再分发的条件。启动本地 HTTP API，确认公开 API 支持的项目，例如所使用的 Voice ID、语言代码、语速、抑扬顿挫等。
2. 打开 `project/voice/aizuchi/reply_map.tsv`。列分别为 `intent`, `lang`, `text`, `id`。其中 `lang` 为 en / zh / ko 的行的 `text` 列，即该语言对应的回复文本。请直接使用原文，不要编辑句子，并将 `id` 与语音包侧的 Phrase ID 对应。
3. 针对每条回复文本，将 `text` 以及选定的说话人与语言发送至 piper-plus 的本地 HTTP API，并将返回的音频保存为 WAV 格式。输出路径示例为 `project/voice/audio/<lang>/<id>.wav`。如果重新生成了相同 ID 的相同句子，则进行替换，并在 manifest 中记录 `id`、`lang`、模型/声音、文件及 `ok` 状态。
4. 实际的 `voice.py` 仅在 `project/voice/manifest.tsv` 与 `phrases.tsv` 的表述、模型、语言及 voice 设置一致时才会播放片段。Recipe 的使用者在添加源自 Aizuchi reply_map 的即时回复片段时，应使用与现有语音包相同的索引规则，或者直接将字符串传递给 TTS。播放对象仅限于 `speak_intents.txt` 中允许的意图。

若要使用相同的声音播放正文或摘要，需要将当前 `voice.py` 中 AivisSpeech 专用的 `speaker_id` / Kyoko 固定路径，根据该 TTS 的本地 API 和选定的 Voice ID 进行适配。本文档仅为选择与导入规范，并不意味着现有代码会自动切换多语言声音。

### 读音词典与语调

与“想要改善语调的人”的第一步相同，首先要添加读音词典。如果是英语，记录专有名词的发音和缩写；如果是中文，记录简体/繁体的读音和专有名词；如果是韩语，则记录外来语、专有名词和数字的读音。AivisSpeech 的 `readings.tsv` 并不一定能直接注册到其他引擎中。需要确认各引擎的词典格式以及 G2P/音素（phoneme）指定方式；在 piper-plus 中，请使用[官方词典/G2P 功能](https://github.com/ayutaz/piper-plus)或直接指定音素。对于没有词典功能的实现，应先将文本预处理为确定的读音写法后再进行合成。对于 macOS `say`，可以测试声音和语速，如有必要，可以研究 `[[inpt PHON]]` 等音素指定方式或读音词典 API，但不要假设所有语言都能使用相同的表示方式。

### 中文

作者（日语）使用 AivisSpeech，但它仅支持日语。当前 `voice.py` 对所有语言都使用配置中的 AivisSpeech speaker ID；失败时固定回退到 `/usr/bin/say -v Kyoko`。Aizuchi 根据字符范围选择回复语言（假名 ja、韩文 ko、汉字 zh、其他 en），但只把回复文本传给 `voice.speak()`，不会按语言选择声音。

推荐候选为 [piper-plus](https://github.com/ayutaz/piper-plus)。官方文档说明其支持 Apple Silicon macOS，提供本地 HTTP API，代码采用 MIT 许可，并有语速/韵律及词典/G2P 功能。已发布的预训练语音列表包含 EN 和 ZH 等六种语言；韩语的代码支持不代表已有可用预训练语音。中文应选择普通话模型，并单独核对声音模型的商业使用和修改许可。macOS 可下载 Enhanced/Premium 系统声音，例如 Ting-Ting（普通话）、Mei-Jia（台湾中文）、Sin-ji（粤语）；实际名称以本机 `say -v '?'` 为准。

制作 Aizuchi 片段时，从 `project/voice/aizuchi/reply_map.tsv` 提取 `lang=zh` 行的 `text` 原文，发送到本地 API，按 `id` 保存 WAV 并登记到 manifest。中文专名和多音字应使用对应引擎的读音词典或音素映射；`readings.tsv` 不保证能被其他引擎直接导入。macOS `say` 是基础替代方案，不提供 AivisSpeech 那样的一体化声音选择、韵律控制、用户词典和本地 TTS API。

### 英语

作者（日语）使用 AivisSpeech，但它仅支持日语。英语、中文和韩语应使用在 Mac 上运行、承担类似功能的本地语音合成工具。

当前 `voice.py` 对所有语言都使用配置的 AivisSpeech speaker ID，失败时固定回退到 `/usr/bin/say -v Kyoko`。Aizuchi 根据字符种类选择回复语言（假名 ja、韩文 ko、汉字 zh、其他 en），但只把回复文本传给 `voice.speak()`，不会选择对应语言的声音。

推荐候选为 [piper-plus](https://github.com/ayutaz/piper-plus)。官方资料介绍了 Apple Silicon macOS、本地 HTTP API、MIT 代码许可，以及语速、韵律和词典/G2P 功能。已公开的预训练语音有 EN/ZH 等六种语言。韩语有代码支持，并不代表已有可用的预训练语音。如果找不到合适且许可明确的韩语模型，可将 macOS 的 Yuna（ko-KR）作为基本替代方案。在系统设置中下载标有 Enhanced/Premium 的声音，并用 `say -v '?'` 确认实际安装的名称。

制作 Aizuchi 音频片段时，原样提取 `project/voice/aizuchi/reply_map.tsv` 中 `lang=en`、`zh`、`ko` 行的 `text`，连同选定的语言和声音发送到本地 API，将 WAV 按 `id` 保存并登记到语音包 manifest。请在各语音模型卡片中确认商业使用和修改条件。Apple `say` 是基本替代方案，不提供 AivisSpeech 那样的一体化声音选择、韵律调整、用户词典和本地 TTS API。读音条目应使用各引擎自己的词典或音素标记；`readings.tsv` 是本配方使用的格式，不保证所有引擎都能直接接受。

### 韩语

作者（日语）使用 AivisSpeech，但 AivisSpeech 仅支持日语。英语、中文和韩语应使用可在 Mac 上运行、承担类似功能的本地语音合成工具。

当前 `voice.py` 不区分语言，一律使用配置中的 AivisSpeech speaker ID；失败时固定回退到 `/usr/bin/say -v Kyoko`。Aizuchi 根据文字种类选择回复语言（假名 ja、韩文 ko、汉字 zh、其他 en），但只把回复文本传给 `voice.speak()`，不会选择对应语言的声音。

可先考虑 [piper-plus](https://github.com/ayutaz/piper-plus)。官方资料介绍了 Apple Silicon macOS、本地 HTTP API、MIT 代码许可，以及语速、韵律和词典/G2P 功能。已公开的预训练语音包括 EN/ZH 在内共六种语言。韩语有代码支持，并不代表已有可用的预训练语音。如果无法确认合适的韩语语音及其许可，可将 macOS 的 Yuna（ko-KR）作为基本替代方案。在系统设置中下载标有 Enhanced/Premium 的声音，并用 `say -v '?'` 确认实际安装的名称。

制作 Aizuchi 音频片段时，将 `project/voice/aizuchi/reply_map.tsv` 中 `lang=ko` 行的 `text` 原样发送到本地 API，将 WAV 按 `id` 保存并登记到 manifest。外来词、专有名词和数字的读音应使用各引擎自己的词典或音素标记。不要假定 `readings.tsv` 可以直接导入。macOS `say` 是基本替代方案，不提供 AivisSpeech 那样的一体化声音选择、韵律调整、用户词典和本地 TTS API。
