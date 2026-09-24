[日本語](./input.md) / [中文](./input.zh.md) / [한국어](./input.ko.md)

# SPEC-input — 如何构建语音输入

读者为用户 AI Agent。阅读本文后，即可构建出与当前 Mac 语音输入同等质量的系统（PTT → whisper.cpp → 替换 → 即时回应 Aizuchi → 前台输入）。数值基于 2026-09-24 时的实际情况。不进行推测填充。未知项标注为“不明”。在进行即时回应的发话过程中，由于同步播放尚未结束，正文的 stdout 可能不会返回，从而导致输入延迟。

不涉及密钥、个人替换表内容及实际主机信息（仅提供格式及作为设备所需的常量）。常驻监听/唤醒词已于 2026-09-07 移除（决定 D182）。主路径仅为 PTT。

参考实体（路径以 `$HOME/project` 为根）：

- `$HOME/project/tools/voice/input/voicein.py`（命令 `voicein`，`$HOME/.local/bin/voicein` 为指向此处的 symlink）
- 同目录下的 `glossary.txt` / `replace.txt` / `mishear-candidates.tsv`
- `$HOME/.hammerspoon/init.lua`（热键与输入。设计文档中提到的 `input/hammerspoon-init.lua` 正本副本并不存在于磁盘上）
- `$HOME/.local/stt/whisper.cpp/build/bin/whisper-cli`（whisper.cpp 1.9.1，commit `2ca53bb45e38748d07b310eeb36245a7157ac882`，`GGML_METAL=ON`）
- `$HOME/.local/stt/models/ggml-large-v3-turbo.bin`（1.5G，ggml Whisper large-v3-turbo）
- `/opt/local/bin/ffmpeg`（MacPorts ffmpeg 8.1）
- `$HOME/project/project/voice/aizuchi/serve.py` 与 `speak_intents.txt`
- 即时回应的播放由 `$HOME/project/tools/voice/output/voice.py` 的 `speak` 执行（涉及席位、安静时间、queue.lock）

---

## 1 结构与流程

不进行外部传输。识别使用本地 whisper.cpp。替换表使用本地文件。即时回答使用本地 UNIX Socket。LLM 修正默认为关闭。

```
按住右 Option（或 microphone button / CLI）
  → Hammerspoon startRec
      → voice.py stop（立即停止语音播放 = barge-in）
      → voicein --ptt start
          → ffmpeg avfoundation 16 kHz / 1ch / wav
          → 将 RMS 写入无缓冲的 /tmp/voicein-ptt.level
      → 屏幕下方中央的波形 Pill
松开（或按第二次按钮 / 90 秒上限）
  → voicein --ptt stop
      → 向 ffmpeg 发送 SIGINT，最多等待 5 秒
      → 如果 wav 小于 24000 字节则为空（误按）
      → whisper-cli（ja，使用 --prompt 传入 glossary）
      → 如果幻听集合为 HALLUC 则为空
      → table_fix（斜杠归一化 → replace.txt）
      → 追加至口述日志（即使失败也不丢弃正文）
      → 如果不为空则执行 aizuchi_reply（同步播放。在播放结束前不进行下一步）
      → 将正文输出至 stdout（末尾不换行）
  → voicein 结束后，Hammerspoon 将 stdout 通过 keyStrokes 输入到当前窗口
      → 仅 硬件按钮路径后追加 Enter
```

角色分配：

| 组件 | 角色 |
|---|---|
| Hammerspoon | 按键监听、录音开始/停止、波形显示、向当前窗口输入、停止语音播放 |
| `voicein.py` | 录音进程、识别、幻听过滤、替换、日志、Aizuchi 查询 |
| whisper-cli | 16 kHz wav → 日语文本 |
| `replace.txt` | 误识别形式 → 正确写法（确定性替换。不破坏正文） |
| `glossary.txt` | whisper 的 initial prompt（词汇提示 + 标点符号风格） |
| `mishear-candidates.tsv` | 上下文相关的误识别存放处。不进行无条件替换 |
| `aizuchi/serve.py` | 1 行文本 → 1 行 JSON（intent / score / reply） |
| `voice.speak` | 即时回答播放。通过席位、安静时间、等待队列控制 |

启动方式：

1. 启动 Hammerspoon（通过 reload 加载 `init.lua`。启动时会显示“voicein PTT 运行中（按住右 Option）”）。
2. `voicein` 在 PATH 中，且指向 `voicein.py`。
3. 存在 `whisper-cli` 和 `ggml-large-v3-turbo.bin`。
4. ffmpeg 位于 `/opt/local/bin/ffmpeg`（代码中硬编码了此路径）。
5. 若要播放即时回答，`aizuchi/serve.py` 需开启 Socket。登录时的 `tools/sessions/autostart.sh` 会检查是否存在 `pgrep -f '[a]izuchi/serve.py'`，若不存在则使用 venv 的 python 以 `start_new_session=True` 启动。若已存在则不执行任何操作。
6. macOS 权限：麦克风（ffmpeg）、输入监听（右 Option 的 eventtap）、辅助功能（keyStrokes / Cmd+V）。

手动测试入口（除 PTT 外）：

```
voicein                 # 开始录音 → 按 Enter 停止 → pbcopy。stderr 显示耗时
voicein --paste         # 进一步通过 Cmd+V 输入到当前窗口（System Events。需要辅助功能权限）
voicein --no-fix        # 跳过替换
voicein --no-aizuchi    # 不进行即时回答
voicein --model NAME    # 绝对路径，或 ggml-NAME.bin 的缩写
voicein --file wav      # 不录音，直接处理现有 wav
voicein --keep          # 不删除录音 wav
voicein --ptt start|stop
voicein --listen        # 兼容/诊断用参数。由于已移除常驻监听功能，会带理由直接退出
```

`--llm` 是在替换后通过术语修正 LLM 的实验开关。默认为关闭。`tools/llm` 已移除，`llm_common` 的 import 采用 fail-open 模式（函数返回 None）。即使修正阶段失败，正文也会保留。

环境变量：

| 名称 | 默认值 | 含义 |
|---|---|---|
| `VOICEIN_DEV` | `:0` | avfoundation 的 `-i`（视频为空 + 音频设备 0） |
| `VOICEIN_FIX_MODEL` | 空 | 使用 `--llm` 时的模型名。为空则使用 localllm 的 current |
| `AIZUCHI_SOCK` | `$HOME/.config/voice/aizuchi.sock` | 即时应答 Socket |
| `VOICE_REPLY_SEAT` | 空时使用当前显示的 tmux 席位 | `voice.speak` 使用的席位 |

PTT 临时文件：`/tmp/voicein-ptt.wav`、`/tmp/voicein-ptt.pid`、`/tmp/voicein-ptt.level`。`ptt_start` 会先删除这 3 个文件。`ptt_stop` 不会删除 pid 文件（朗读侧会检查对应进程是否仍存在）。

---

## 2 录音与分段

分段并非使用 VAD。人在按键期间产生的为一个完整的 wav。将该 wav 完整地传递给 whisper。

ffmpeg 通用命令：

```
/opt/local/bin/ffmpeg -hide_banner -loglevel error -nostdin
  -f avfoundation -i $VOICEIN_DEV
  -ar 16000 -ac 1 -y <wav>
```

stdin 为 `DEVNULL`。这是为了防止在按下 Enter 停止的 CLI 环境中，ffmpeg 吞掉 Enter 键导致的事故。停止方式为 `SIGINT`（正常关闭）。如果 5 秒内未结束，则执行 `kill`。

仅针对 PTT 添加的额外滤镜（每 0.1 秒写入一次 RMS，用于波形显示）：

```
-af asetnsamples=1600,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=/tmp/voicein-ptt.level:direct=1
```

`asetnsamples=1600` 在 16 kHz 下代表 0.1 秒。如果不使用 `direct=1`，ametadata 会进行 4 KB 缓冲，导致录音期间的电平文件为空。PTT 的 ffmpeg 使用 `start_new_session=True`（作为 Hammerspoon 的子进程分离，避免随父进程一起退出）。

误触处理：如果 PTT 产生的 wav **小于 24000 字节**（在 16 kHz 16-bit mono 下为 **0.75 秒**），则静默丢弃。CLI 的 `record()` 在 **小于 1000 字节**时会结束（此时需怀疑麦克风权限或 `VOICEIN_DEV` 设置）。

热键（`$HOME/.hammerspoon/init.lua`）：

- **按住选定的修饰键** = 开始录音；松开 = 识别并输入。按键码需在当前环境的 Hammerspoon 中确认。**不要输入 Enter**。
- **分配给设备的按键** = 切换（Toggle）。第 1 次按下开始，第 2 次按下识别、输入并执行 **Enter**。设置 0.5 秒消抖（Debounce）。识别期间的连续点击将被忽略。起点标志位为 `recSource="button"`。
- **90 秒**内自动停止（不输入 Enter）。
- **Cmd+Ctrl+.** = `voice.py stop`（停止语音朗读而非停止输入）。

如果使用麦克风上的物理按键进行录音操作，请先在实机上确认 USB 设备的 VendorID/ProductID 及发送的事件，然后仅为目标设备分配按键。在重映射（Remap）会失效的环境中，需在 Hammerspoon 启动时及设备连接后重新应用。务必确认不会影响键盘本体上的同类按键。

右侧 Option 键的“看门狗”（每 1 秒一次）：如果 eventtap 断开则重启。当**正在录音但 alt 键状态未立起**时，自动停止。该看门狗仅在 `recSource=="ptt"` 时运行。如果将其应用于按钮触发，录音可能会在 1 秒内中断。在休眠/唤醒时也要重建 eventtap。

回调函数仅进行标志位判定，将开始/停止操作交给 `hs.timer.doAfter(0, ...)` 处理。将 eventtap / timer 挂载在全局变量 `VoiceinPTT` 上（若使用局部变量，会被 GC 回收导致监控失效）。

波形小部件（Waveform Pill）：尺寸 150×34，位于屏幕下方 90 px 处，居中。电平值通过读取文件末尾 400 字节中的 `RMS_level=` 获取。显示逻辑为将 `(db + 48) / 36` 裁剪至 0.04..1（将 **-48 dB 〜 -12 dB** 映射为 0..1）。右侧为最新数据，上下对称填充。每 0.1 秒替换一次多段线（Polyline）的一个元素（如果单独更新 12 根柱状条会导致本体卡顿，从而错过按键松开事件）。吉祥物图像 `input/indicator.png` **不在磁盘上**。如果图像不存在，则仅显示波形。

录音开始时，异步 spawn `voice.py stop`。在说话瞬间停止朗读，防止朗读的回声混入输入信号。

朗读侧（`voice.py`）的口述静音属于输入流程的一部分：

- 路径 B：`/tmp/voicein-ptt.pid` 对应的进程确实存在，且 comm 以 `ffmpeg` 开头。
- 宽限期：从 `/tmp/voicein-ptt.level` 的 mtime 起，在 `post_rec_grace_sec`（设置默认值为 **30**）秒内不启动自动发话。文件不存在或时钟异常时，按允许发话处理。
- 手动 `read` / `test` 不受影响。观测点为 `last.kind=skip-dictating`。

实际音频设备编号因环境而异。查看方式：

```
/opt/local/bin/ffmpeg -f avfoundation -list_devices true -i ""
```

2026-07-31 的实测记录中，音频设备为 `[0] the USB receiver`（与 `voicein.py` 中默认值 `:0` 的注释一致）。其他时点的环境也记录过 `[1] BlackHole 2ch`；但本文核对时无法取得设备列表，因此当前编号和连接状态未确认。请通过上述命令确认编号。

---

## 3 识别（模型、参数、语言）

二进制文件: `$HOME/.local/stt/whisper.cpp/build/bin/whisper-cli`  
版本: **whisper.cpp 1.9.1**（通过 CLI `--version` 查看）。源码来自 https://github.com/ggml-org/whisper.cpp ，实际 HEAD 为 `2ca53bb`（2026-07-31）。CMake 配置为 `GGML_METAL=ON`、`GGML_METAL_EMBED_LIBRARY=ON`。运行 `whisper-cli` 时不添加 `--no-gpu` 参数（使用 Metal）。CLI 默认开启 flash attention。

模型: `$HOME/.local/stt/models/ggml-large-v3-turbo.bin`（文件名即为 large-v3-turbo，大小 1.5G）。获取方式为 whisper.cpp 自带的 `models/download-ggml-model.sh`（来自 Hugging Face `ggerganov/whisper.cpp` 的 `resolve/main/ggml-*.bin`）。如果使用 `--model foo` 且未指定绝对路径，则会查找 `$HOME/.local/stt/models/ggml-foo.bin`。

`transcribe()` 实际传递的参数（其余为 whisper-cli 默认值）:

```
whisper-cli
  -m <model>
  -l ja
  -f <wav>
  --prompt <glossary.txt 的全文>
  -nt
  --no-prints
```

未显式指定的默认值（`whisper-cli --help` 显示的值）:

| 项目 | 默认值 |
|---|---|
| `--threads` | 4 |
| `--best-of` | 5 |
| `--beam-size` | 5 |
| `--temperature` | 0.00 |
| `--no-speech-thold` | 0.60 |
| `--entropy-thold` | 2.40 |
| `--logprob-thold` | -1.00 |
| `--suppress-nst` | false（不抑制非语音 Token。幻听问题通过 HALLUC 解决） |
| VAD 选项 | 不添加 |

语言**固定为 `ja`**。不使用 `auto`。超时时间为 **120 秒**（PTT / CLI 使用相同的 `transcribe`）。失败时会输出 stderr 末尾的 300 个字符并退出。stdout 的 strip 部分即为识别文本。

`--prompt` 为 glossary 全文。Whisper 会查看 prompt 末尾约 **224 个 Token**。用于标点的自然文必须放在末尾（§4）。

识别以 **CLI 为主**。whisper-server（当时端口为 8178）虽然速度更快，但在 temperature 固定为 0 时会出现词组崩溃的 A/B 测试结果。该服务已随常驻监听冻结功能一同退役。PTT 不使用 server。

实测表明，即使是相同的 ffmpeg 命令，作为终端/launchd 的子进程时音频会损坏，而作为 Hammerspoon 的子进程时音频清晰（macOS 的麦克风处理是以应用为单位的）。PTT 的 ffmpeg 将作为 Hammerspoon → `voicein --ptt start` 的孙子进程运行。

## 4 后处理（幻听排除・整形・词典）

流程为 **识别文本 →（PTT 在此进行 HALLUC 判定）→ 斜杠归一化 → replace.txt（从长键开始）→ 口述日志 →（仅 CLI 可选使用 LLM）→ 响应词 / 输出**。

### 4.1 幻听排除

这是 Whisper 在静音或噪音环境下常见的输出。比较方式为与 `raw.strip().lower()` 进行完全匹配。集合（代码中的 `HALLUC`）：

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

设计思路：包括了在 2 秒静音时实际检测到 `Thank you.` 的情况（2026-07-31），以及由于 YouTube 训练数据导致的结语、订阅提示、预告下一段视频等内容混入语音缓存的实际情况（2026-08-02）。英语部分通过 `lower` 进行归一化处理。日语部分则同时包含带句号和不带句号的情况。为了避免误判，不采用部分匹配（以保护正文中包含“ありがとうございました”的正常发言）。

PTT: 如果是 HALLUC，则 **返回空字符串**（不进行打字也不进行即时回答）。  
CLI: 内容会保留在剪贴板中。仅在即时回答之前，通过 `text.strip().lower() not in HALLUC` 进行过滤，不发送请求（`bc66fc9bf`）。

### 4.2 标点符号与表示方式

标点符号并非由 ffmpeg 的静音检测决定。如果 glossary 仅包含以逗号分隔的单词列表，即使是相同的音频，标点符号也会全部消失（2026-08-01 实测）。如果在末尾添加带有标点符号的自然句，标点符号就会全部恢复。实际的末尾示例（保留此句作为格式）：

```
句読点。以下は、句読点を正しく付けた日本語の口述です。今日は、金利の見通しをまとめます。まず、結論から言います。
```

“くとうてん”的三种乱码形式（駆読点、苦読点、苦闘点）需通过 `replace.txt` 还原为“句読点”。

### 4.3 glossary.txt（仅格式）

1 个文件，UTF-8。列出以逗号分隔的术语，并在末尾加上上述带有标点的自然语言句子。由于内容是用户的词汇，请勿在此处复制。添加的内容越多，whisper 就越倾向于使用该写法。如果术语表引导向英文写法，可能会在后续替换步骤之前出现混杂英文的情况。

`transcribe()` 在不进行 try 的情况下打开 glossary。如果文件不存在，整个识别过程将会崩溃。

### 4.4 replace.txt（仅格式）

```

# 注释
误识别形<TAB>正确写法
```

忽略空行、以 `#` 开头或不含制表符的行。使用首个制表符进行分割（即使右侧仍留有制表符，也归为正确写法一侧）。按 **键（Key）的字符长度降序** 进行应用（例如“Claude Code”优先于“Claude”）。使用子字符串的 `str.replace`。不复制个人行。由于是机械化处理且不考虑上下文，不包含与现有词汇冲突的替换。

### 4.5 斜杠命令 (Slash Commands)

通过语音说“スラッシュ クリア” → `/clear`。目标 8 个词（代码中的 `_SLASH_CMDS`）：

`クリア` `モデル` `エフォート` `コンパクト` `フック` `コンフィグ` `ヘルプ` `リワインド`  
→ `/clear` `/model` `/effort` `/compact` `/hooks` `/config` `/help` `/rewind`

在 `table_fix` 的开头，仅删除命令词之前的分隔符并进行紧凑化处理：

```
SLASH_SEP_RE = スラッシュ?[\s　、。，．・･]*(?=(?:クリア|モデル|...))
```

替换后的表中，只要有一行紧凑格式即可（为了保险，保留空格格式或中点格式也可以）。新命令需满足：(1) 在 `_SLASH_CMDS` 中添加一个片假名词；(2) 在 `replace.txt` 中添加一行紧凑格式。如果“斜杠”后面没有紧跟命令词，则不会触发。

旧的运营方式（在表中列出紧凑、空格、中点这 3 种格式）因为标点符号的恢复导致出现了“スラッシュ、モデル”这种情况而失效。在 8 个命令 × 分隔符变体 × 词首 2 种格式 = 176 种组合中，仅能捕捉到 17 种 3 种格式的注册（通过穷举实测）。

### 4.6 mishear-candidates.tsv（仅格式）

上下文相关/多义词的存放处。优先将那些如果进行无条件替换就会破坏真实词汇（与现有词汇冲突）的内容放在这里。如果决定提升，则移至 `replace.txt`，并将状态列改为“已提升”。

```
误识别形式<TAB>意图词<TAB>上下文备注<TAB>日期<TAB>状态(候选/已提升/已拒绝)
```

代码不读取此文件。仅作为训练用的账本。

### 4.7 口述日志

`table_fix` 必须通过。即使失败也不丢弃正文（fail open）。

- 位置: `$HOME/.config/voicein/dictation/YYYY-MM.tsv`
- 列: `ts`（ISO8601，秒，带时区） / `source`（`ptt` | `cli` | `unknown`） / `raw` / `fixed` / `rules_hit`（`bad=>good`，以逗号分隔）
- 新文件首行: `# ts\tsource\traw\tfixed\trules_hit`
- 将 TAB 和换行符压缩为一个空格。如果 `raw` 为空则不写入。

### 4.8 LLM 修正（默认关闭）

仅在使用了 `--llm` 且未指定 `--no-fix` 时生效。连接地址在代码中为 `http://127.0.0.1:8090`（OpenAI 兼容的 localllm）。通过 3 秒的 alive 检测，如果服务不可用则返回原文。必须设置 `think=False`。如果输出长度不在原文的 0.5 到 2.0 倍范围内，则返回原文。移除 `<think>...</think>` 标签。在移除 `tools/llm` 后，由于 import 失败，将始终返回原文。设计文档中残留的 “gemma4:12b / 127.0.0.1:11434” 是旧版写法，当前代码使用的是 8090 端口。由于在实际应用中确认了会破坏正文内容，因此默认行为改为使用替换表。

## 5 输出（粘贴・应答词）

### 5.1 粘贴

PTT / 按钮：Hammerspoon 将 `voicein --ptt stop` 的 **stdout 通过 `hs.eventtap.keyStrokes`** 输出。不使用剪贴板。仅在 exit 0 且 stdout 不为空时执行输入。若为空或返回非 0，则显示“...”提示符 0.8 秒。仅按钮路径会在 `usleep(150000)` 后 `return`。按下右 Option 键或达到 90 秒上限时不会执行 Enter。

CLI：将全文传递给 `pbcopy`，并同时输出到 stdout（此处包含末尾换行符）。`--paste` 使用：

```
osascript -e 'tell application "System Events" to keystroke "v" using command down'
```

用于常驻监听的 `VoiceinListen.typeFile`（正文文件、nonce 轨迹、前台 bundleID 白名单、Enter 前的重新检查）仍保留在 `init.lua` 中，但由于 `--listen` 会立即退出，因此不会从主路径中调用。

### 5.2 传递给 Aizuchi

在文本转写完成后，不丢弃正文直接进行查询。忽略所有失败。

1. 如果文本为空或不存在 Socket 文件，则 return。
2. 使用 UNIX Stream，**超时时间 0.2 秒**。
3. 发送的 1 行内容：`" ".join(text.split()) + "\n"`（空格归一化）。
4. 接收：直到换行符。如果缓冲区超过 100,000 字节，则 return。
5. 接收 1 行 JSON。包含 `intent` 和 `reply`。
6. 仅当 `intent` 属于“应答集合”且 `reply` 不为空时，执行 `voice.speak(reply, purpose="done")`。
7. 如果 `VOICE_REPLY_SEAT` 为空，先填入 `voice.current_client_seat()` 再进行 speak。

应答集合的正本位于 `$HOME/project/project/voice/aizuchi/speak_intents.txt`（除 `#` 和空行外，每行一个意图）。2026-09-24 30:

```
hello morning night-sleep goodbye otsukare return-home leaving
first-meet reunion how-are-you welcome-in care thanks apology
joy moved surprise encourage praise empathy-here sad lonely
worry relief angry calm-down embarrassed love laugh peaceful
```

包含问候、感谢、道歉、情感。不应答指令、提问或 `none`。如果文件无法读取或为空，则使用 `voicein` 内的备用集合。备用集合包含 31 个词，与正本有所不同（§6）。

Socket 端协议（`serve.py`）：每连接发送一行话，则每行返回一行 JSON。

```
{"intent": str, "score": float, "id": str, "reply": str, "lang": str}
none / 低于阈值: intent=none, reply=""
异常: {"intent": "error", "error": "..."}
```

分类模型为 `aizuchi/onnx/model-int8.onnx`，使用 `CPUExecutionProvider`，包含 tokenizer，`max_length=96`。阈值文件 `onnx/threshold.txt` 的值为 **0.5**（若不存在则代码默认值为 0.5）。低于阈值则判定为 `none`。`reply` 的语言从 `reply_map.tsv`（`intent<TAB>lang<TAB>text<TAB>id`）中获取，若无则默认为 `ja`，并随机选择一条。

`voicein` 不会调用 `afplay` 或 `respond.py`。播放仅通过 `voice.speak` 进行。在 PTT 结束后，由于处于 `post_rec_grace_sec`（默认 30 秒）的 `skip-dictating` 状态，可能会在席位判定前保持沉默。输入端并未取消此行为。

使用 `--no-aizuchi` 参数可以跳过查询过程。

## 6 容易踩中的坑

实际踩过的坑。搭建相同装置时要提前规避。

1. 向 ffmpeg 传递 stdin 时，ffmpeg 会吞掉 CLI 的 Enter。使用 `-nostdin` 和 `stdin=DEVNULL`。
2. 使用 ametadata 默认的 4 KB 缓冲区时，录音中的 level 文件为空。使用 `direct=1`。
3. 如果单独更新 12 条 canvas 进度条，Hammerspoon 会卡顿并丢失按键释放事件。改用单条 polyline。
4. 将 `hs.timer` / `hs.eventtap` 放在局部变量中会被 GC 回收。需固定在全局作用域。
5. 如果将“录音中但未按下右 Option”的守护进程逻辑绑定在按钮上，切换录音会在 1 秒内失效。改用 `recSource` 进行区分。
6. 如果 glossary 只有单词列表，则完全没有标点符号。需提供末尾带有标点符号的自然句。
7. 在表格中逐一添加斜杠变体（slash variation）的运维方式，在上下文（标点符号）发生变化时会立即失效。应进行归一化，只保留一种紧凑形式。
8. LLM 修正比起修正术语，更容易破坏正文。默认使用替换表。如果失败，则保留原文。
9. 会混入来自 YouTube 风格的“结尾、订阅、Thank you”等无声内容。使用 HALLUC 完全匹配进行丢弃。不要使用部分匹配。
10. 即便是同一个 ffmpeg，在 Terminal / launchd 下音频会损坏，而在 Hammerspoon 下则很清晰。PTT 是 HS 的子进程。
11. 将其 whisper-server 化后，即使削减了延迟，质量也会下降。PTT 保持使用 CLI。在提速之前先做 A/B 测试。
12. 如果要停止常驻监听，不仅要检查 flag，所有启动路径（例如末尾无条件的 `doAfter` start 等）都必须检查 flag。
13. 如果口述静音依赖于 listen 常驻进程的 flag 写入，那么当 listen 冻结时，会发生“在说话过程中开始朗读”的情况。应通过查看录音进程和 level 文件的 mtime 来判断。
14. `ptt_stop` 不会删除 pid 文件。如果只检查文件是否存在，录音结束后会变成永久静音。必须检查 comm 是否为 ffmpeg。需防范 PID 复用。
15. 录音结束后的识别、打字、确认期间没有进程在运行。如果没有 `post_rec_grace_sec` 30 秒的缓冲，自动发话会在该期间开始。反之，即时回答也会在此窗口期内触发 `skip-dictating`。
16. 使用 `anullsrc` 或注入 wav 时，如果不加 `-re` 则不会按实时速率运行。会导致测试失真。
17. TCC 的“已启用”显示可能会延迟，导致看起来与 toggle 状态相反。以实际测量（按下后是否有文字出现）为准。
18. `VOICEIN_DEV` 的编号因设备而异。如果硬编码 `:0`，插到其他麦克风上将无法工作。应通过 `list_devices` 获取。
19. CLI 路径会将 HALLUC 保留在剪贴板中。PTT 则为空。不要混淆“即时回答跳过”和“输入跳过”。
20. `speak_intents.txt` 正本中的 30 个词与 voicein 备用集合不一致。仅在正本中有的：`how-are-you`。仅在备用集合中有的：`invite` `meetup`。只要文件可读，以正本为准。
21. README / 设计文档中提到了 `input/hammerspoon-init.lua`、`slash_test.py`、`replace-stats.py` 和 `indicator.png`，但当前磁盘中并不存在（测试文件和正本副本已被移除）。`init.lua` 的实际生效实体是 `$HOME/.hammerspoon/init.lua`。
22. 如果实现 `--listen` 为“存在”，则会启动一个没有入口的常驻进程。目前采取有理由地立即结束处理。
23. avfoundation 的 `-i` 格式为 `:N`（视频为空，音频为 N）。如果只写 `N`，它会尝试占用视频设备。
24. glossary 缺失会导致整个识别过程异常。replace.txt 缺失则跳过替换并保留正文；两者处理并不对称。

## 7 合格标准

目前的目录树中没有仅用于输入的 `slash_test.py` / `listen_test.py`。合格标准如下。

### 7.1 自动（静音）

`$HOME/project/tools/voice/output/tests/e2e_silent.sh` 中的 Aizuchi 行（伪 Socket、播放 Stub、席 `test`、印 `t`）：

| 用例 | 预期 |
|---|---|
| `aizuchi-thanks`（“谢谢” → intent `thanks` + 非空 reply） | 调用播放函数 |
| `aizuchi-none` | 不调用 |
| `aizuchi-intent-mute`（不在 speak 集合中的 `deploy` 等） | 不调用 |
| `aizuchi-sock-down` | 不调用 |

`test_paths.py` 中的 `test_dictating_skips`：当 `dictating()` 为真时，自动发话为 `last.kind=skip-dictating`，且不启动播放进程。

即时响应分类器本身的数值（`aizuchi/smoke.tsv` / `smoke-dictation.tsv`，`run-all.sh`）：意图准确率 $\ge$ 0.9，none 误报 $\le$ 0.01。口述风格对 speak 集合的误触发 $\le$ 1%，回复漏掉 $\le$ 10%。这是分类器侧的指标。voicein 的传递逻辑见上述 4 行。

`voicein.py` 可以通过 `python3 -m py_compile` 编译。

斜杠归一化（由于没有 `slash_test.py`，直接调用相同的函数）：

- “スラッシュ、モデル” → 替换后为 `/model`（即使有逗号也会趋向于紧凑形式）。
- “スラッシュ、つまり斜線” → 保留“斜杠”（因为后面没有跟随命令词）。
- `_SLASH_CMDS` 中的全部 8 个词，无论使用空格、逗号、间隔号还是紧凑形式，都会变为 `/...`。

HALLUC: 将 `Thank you.` 和 `ご視聴ありがとうございました。` 在 PTT 相当的情况下设为空。普通句子不设为空。

`table_fix` 需将长 Key 放在前面（防止“Claude Code”被“Claude”吞掉）。不要使用 replace 的个人行，使用测试用的短表即可。

### 7.2 手动确认（使用实际麦克风。如果发声，请注意周围环境及时间）

1. 使用 `ffmpeg -f avfoundation -list_devices true -i ""` 获取音频编号，并将其与 `VOICEIN_DEV` 相匹配。
2. 启动 Hammerspoon。按住右侧 Option 键，看到绿色药丸图标，松开后显示“正在识别”，文字将出现在前置输入框中。不会自动添加 Enter。
3. 仅按下 0.5 秒并松开 → 不会输入任何内容（0.75 秒阈值）。
4. 在保持静默的情况下按下 2 秒 → 输入框中不会出现 "Thank you."。
5. 输入“スラッシュ クリア” → 输入框中会出现 `/clear`。
6. `$HOME/.config/voicein/dictation/YYYY-MM.tsv` 中会增加 `source=ptt` 的行。包含 `raw` / `fixed` / `rules_hit` 共 5 列。
7. 如果 Socket 处于活动状态且说了问候语，若符合 `speak_intents.txt` 中的意图，则会传递到 `voice.speak`（如果在 30 秒宽限期内执行了 `skip-dictating`，请在窗口打开后或通过 CLI `--file` 进行确认）。指令类句子不会触发语音。停止 Socket 后，正文输入功能依然有效，只是不再具备即时响应能力。
8. 在录音过程中触发语音朗读会进入 `skip-dictating`（自动路径）。`voice.py stop` 在开始时已被调用。
9. `voicein --listen` 会因错误立即退出，不会常驻运行。

如果满足 7.1 和 7.2，则输入质量与当前一致。
