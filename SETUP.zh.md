[日本語](./SETUP.md) / [English](./SETUP.md) / [中文](./SETUP.zh.md) / [한국어](./SETUP.ko.md)

# 导入步骤（输入与输出）

无论是人工还是 AI，只要按顺序操作，就能获得相同的音频环境。材料是这台 Mac（macOS 27.0 26A428, arm64）的实机数据。未进行推测填充。无法确定的行标注为“不明”。

不填写密钥、主机名及实际地址。配置模板使用占位符。

---

## 1. 包含内容

仅包含音频输入/输出中实际使用的内容。包括 `/Applications`、Homebrew、MacPorts、pip / venv 的实体。

| 项目 | 本台 Mac 的版本 | 位置 | 获取方式 |
|---|---|---|---|
| 麦克风（作者推荐） | a USB wireless microphone。在 Mac 上的名称为 `the USB receiver`（`system_profiler SPAudioDataType`: Manufacturer: the manufacturer、USB、48kHz、Default Input Device） | 将 USB 接收机连接至 Mac | USB microphone 无线麦克风。通过 USB 接收机连接。作者正在使用此设备 |
| Hammerspoon | 1.1.1（6936） | `/Applications/Hammerspoon.app`。未通过 brew cask 安装。设为登录项 | https://www.hammerspoon.org/ ／ https://github.com/Hammerspoon/hammerspoon |
| iTerm2 | 实际应用 3.7.2。Homebrew Caskroom 注册版本为 3.6.11（版本不一致） | `/Applications/iTerm.app` | https://iterm2.com/ |
| tmux | 3.6b | `/opt/local/bin/tmux`（MacPorts。Homebrew formula 中没有） | https://github.com/tmux/tmux |
| ffmpeg | 8.1 | `/opt/local/bin/ffmpeg`（MacPorts。voicein 直接硬编码了此绝对路径） | https://ffmpeg.org/ |
| Python 3.9.6 | CLT | `/usr/bin/python3`。用于 `voicein.py` 的 shebang 和 hook 中的 `/usr/bin/python3` | Apple Command Line Tools |
| Python 3.12.14 | Homebrew `python@3.12` | `/opt/homebrew/bin/python3.12`。Aizuchi 和 mlx-lm venv 的基础 | https://www.python.org/ ／ `brew install python@3.12` |
| uv | 0.12.9 | `/opt/homebrew/bin/uv` | https://github.com/astral-sh/uv |
| Node | v24.19.0 | nvm `~/.nvm/versions/node/v24.19.0`。用于 Pi | https://nodejs.org/ |
| jq | 1.7.1-apple | `/usr/bin/jq`。用于 hook 的 JSON 读取 | macOS 自带 |
| Claude Code | 2.1.281 | `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.281` | https://docs.claude.com/en/docs/claude-code |
| Pi | 0.87.1 | `pi` = `@earendil-works/pi-coding-agent` | `npm i -g @earendil-works/pi-coding-agent` |
| whisper.cpp | 1.9.1（commit `2ca53bb`，Metal ON） | `~/.local/stt/whisper.cpp`，可执行文件 `build/bin/whisper-cli` | https://github.com/ggml-org/whisper.cpp |
| Whisper 模型 | `ggml-large-v3-turbo.bin` 1.5G | `~/.local/stt/models/ggml-large-v3-turbo.bin` | 见下文第 4 节 |
| AivisSpeech Engine | 1.2.0 | `~/.config/voice/aivis/macOS-arm64/run`。`/Applications` 中没有 AivisSpeech.app | https://github.com/Aivis-Project/AivisSpeech-Engine/releases/tag/1.2.0 |
| 声线「an AivisHub voice model」 | 模型 1.0.0，AIVMX UUID `<model-uuid>` | `~/Library/Application Support/AivisSpeech-Engine/Models/`。Calm 的 speaker_id = `1310138977` | https://hub.aivis-project.com/aivm-models/<model-uuid> |
| onnxruntime（快速响应） | 1.30.0 | `project/voice/aizuchi/.venv`（Python 3.12.14） | pip。同一 venv 中还有 numpy 2.5.3、tokenizers 0.22.2、sentencepiece 0.2.2、huggingface_hub 0.36.2、protobuf 7.36.2 |
| mlx-lm（可选摘要） | 0.31.3（mlx 0.32.2） | `tools/voice/output/.venv-mlx`。不在登录时自动启动 | https://github.com/ml-explore/mlx-lm ／ `pip install mlx-lm` |
| 代码本体 | project | `~/project/tools/voice/input/voicein.py`、`~/project/tools/voice/output/voice.py`、`~/project/project/voice/aizuchi/` | 这些仓库 |

输入设备：将 `ffmpeg -f avfoundation -list_devices true -i ""` 输出中音频设备对应的编号写入 `VOICEIN_DEV`（此 Mac 为 `:0` = the USB receiver）。

`voicein` 的入口：`~/.local/bin/voicein` → `~/project/tools/voice/input/voicein.py`。

语音输入操作的权威配置是 `~/.hammerspoon/init.lua`（位于 tools/voice 之外）。安装方法、权限、现有的两种输入方式及已删除路径见第 7 节。

系统 pip（CLT 3.9）中也有 onnxruntime 1.19.2。快速响应和 TTS 不使用它。

## 2. macOS 权限设置

所有设置项均位于 **系统设置 → 隐私与安全性**。设置完成后，请退出并重新启动该应用。输入监听（Input Monitoring）和辅助功能（Accessibility）可能需要 **注销或重启** 才能生效（在此步骤中，请尝试先退出并重新启动 Hammerspoon。如果 eventtap 仍然失效，请注销用户）。

| 项目 | 位置 | 授权对象 | 用途 |
|---|---|---|---|
| 麦克风 | 隐私与安全性 → 麦克风 | Hammerspoon。手动运行 `voicein` 时需授权 iTerm2 和终端 | 用于 ffmpeg 的 avfoundation 录音。报错信息通常为“麦克风权限或设备编号错误” |
| 辅助功能 | 隐私与安全性 → 辅助功能 | Hammerspoon。手动运行时需授权 iTerm2 和终端 | 通过 `hs.eventtap.keyStrokes` 向当前活跃应用发送按键 |
| 输入监听 | 隐私与安全性 → 输入监听 | Hammerspoon | 用于监听右侧 Option 键的 flagsChanged 事件 |

此 Mac 上 ffmpeg 所识别的音频设备：

- `[0] the USB receiver`（`VOICEIN_DEV` 默认值 `:0`）
- `[1] BlackHole 2ch`

## 3. whisper.cpp 与模型

```sh
mkdir -p ~/.local/stt/models
git clone https://github.com/ggml-org/whisper.cpp.git ~/.local/stt/whisper.cpp
cd ~/.local/stt/whisper.cpp
cmake -B build -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_BUILD_EXAMPLES=ON
cmake --build build --config Release -t whisper-cli
./models/download-ggml-model.sh large-v3-turbo ~/.local/stt/models
```

模型 URL（脚本中的 `src`）: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin`。

voicein 读取的固定路径：

- 可执行文件 `~/.local/stt/whisper.cpp/build/bin/whisper-cli`
- 模型 `~/.local/stt/models/ggml-large-v3-turbo.bin`
- 识别参数：`-l ja -nt --no-prints`，`--prompt` 使用 `glossary.txt`

ffmpeg 录音：`-f avfoundation -i :0 -ar 16000 -ac 1`。PTT 时将 RMS 电平直接写入 `/tmp/voicein-ptt.level`。

## 4. AivisSpeech 的引擎与声音

这台 Mac 不安装 GUI 应用，仅安装引擎本身。

1. 从 https://github.com/Aivis-Project/AivisSpeech-Engine/releases/tag/1.2.0 下载 `AivisSpeech-Engine-macOS-arm64-1.2.0.7z.001`（203MB）。
2. 使用 7-Zip 解压。当前的 PATH 中没有 `7z` / `7zz`（只有已解压的 `run`）。通过 GUI 版 AivisSpeech（https://aivis-project.com/speech/ ）安装得到的是相同的引擎。
3. 将可执行文件放在 `~/.config/voice/aivis/macOS-arm64/run`。
4. 启动参数（实测的 LaunchAgent）: `--host 127.0.0.1 --port 10101 --disable_sentry`。
5. 声音：从 AivisHub 的 [an AivisHub voice model](https://hub.aivis-project.com/aivm-models/<model-uuid>) 下载 **AIVMX**（约 241MB，ACML 1.0）。
6. 将文件放在 `~/Library/Application Support/AivisSpeech-Engine/Models/`。这台 Mac 上的文件名是 `<model-uuid>.aivmx`。
7. **重启引擎**（以使新增模型生效。如果是 LaunchAgent，请参考下一节的 kickstart）。首次运行时需要联网以获取 BERT 缓存。
8. 通过 `curl -s http://127.0.0.1:10101/speakers` 确认 `"name": "an AivisHub voice model"` 以及 style `"Calm"` id `1310138977`。
9. 用户词典（可选・幂等）：`python3 ~/project/tools/voice/output/register-dict.py`。

将 `config.json` 中的 `speaker_id` 设置为 `1310138977`（见下一节）。

---

## 5. Python 虚拟环境

快速响应（必选）：

```sh
/opt/homebrew/bin/python3.12 -m venv ~/project/project/voice/aizuchi/.venv
~/project/project/voice/aizuchi/.venv/bin/pip install onnxruntime numpy tokenizers sentencepiece huggingface_hub
```

此 Mac 的实测数据见第 1 节的表格。常驻进程为 `serve.py`（默认 Socket `~/.config/voice/aizuchi.sock`，模型 `aizuchi/onnx/model-int8.onnx`）。

用于摘要的 mlx-lm（可选。此 Mac 的正式摘要使用 OpenAI 兼容接口。mlx 需手动 `up`）：

```sh
sh ~/project/tools/voice/output/mlx-summ.sh up
```

venv 位于 `tools/voice/output/.venv-mlx`。模型为 `mlx-community/gemma-4-e4b-it-4bit`，地址 `127.0.0.1:8091`，关闭思考模式 `--chat-template-args '{"enable_thinking":false}'`。不放入 launchd。

`voice.py` / `voicein.py` 主体使用标准库。无需额外安装 pip 包。

## 6. 配置文件

`~/.config/voice/config.json`。缺失的键将使用 `voice.py` 中的默认值填充。请勿填写实际地址和密钥。

模板：

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

键的含义：

| 键 | 含义 |
|---|---|
| `enabled` | 总开关 |
| `mode` | `off` / `earcon` / `summary` / `full` |
| `say_rate` | Aivis 失败时 `say -v Kyoko` 的语速 |
| `speaker_id` | Aivis 的角色 ID。an AivisHub voice model Calm = 1310138977 |
| `synth_timeout` | 合成的最大秒数 |
| `purposes` | 各用途的开关（设置为 `false` 则完全静音该用途） |
| `quiet_hours` | 抑制自动常规朗读和 earcon 的时间段 `[开始, 结束]`。手动 `read` / `test` 不受影响 |
| `min_interval_sec` | 连续发音的最短间隔 |
| `post_rec_grace_sec` | 录音结束后，不进行自动发音的秒数 |
| `rewrite` | 当 `sum_kind == fallback` 时，对摘要失败时生成的开头句进行重写。不适用于 `short` 短句或 `gemma` 摘要成功的情况。 |
| `rewrite_skip_under` | 低于此字数时不进行 rewrite |
| `rewrite_timeout` | 调用 rewrite 的超时秒数 |
| `dedupe_window_sec` | 防止重复句子的时间窗口 |
| `night_brief_hours` / `night_brief_cap` | 夜间模式下缩短内容。仅在 quiet 范围外生效 |
| `pack` | 预制剪辑（model / voice / lang） |
| `summarizer` | `apple` / `openai` / `off` |
| `summarizer_base` | OpenAI 兼容的连接 URL。模板中的 `127.0.0.1` 用于同一台 Mac 上的摘要服务器。如果使用其他主机的服务器，请替换为该环境下可访问的 URL（请勿填写实际主机名/地址） |
| `summary_timeout` | 摘要的超时秒数。代码默认值在两处分别为 6.0 和 15.0。本 Mac 文件的值为 6.0 |
| `seat` | 若为空，则仅在当前显示的 tmux 会话中播放 |

Aivis 的连接地址由环境变量 `VOICE_AIVIS_BASE` 指定（未设置时为 `http://127.0.0.1:10101`）。语速和停顿由 `tools/voice/output/speech-styles.json` 定义（不参考角色 ID）。

`~/.config/voice/speakers.json` 是从引擎获取的角色列表缓存。无需手动编写。

---

## 7. Hammerspoon（安装、权限、init.lua、两个现有的输入方式与已删除的路径）

语音输入的控制核心是 **`~/.hammerspoon/init.lua`**（位于 tools/voice 之外。此 Mac 上的文件日期为 2026-08-25）。`tools/voice/input/hammerspoon-init.lua` 目前已不存在。Hammerspoon 负责监听被设置为右 Option 键的硬件按钮，并将其作为子进程调用 `~/.local/bin/voicein`。常驻监听模式已删除，剩余代码说明如下。

### 安装步骤

1. 从 https://www.hammerspoon.org/ 下载并安装 Hammerspoon（本 Mac 版本为 1.1.1，位于 `/Applications/Hammerspoon.app`。未通过 Homebrew cask 安装）。
2. 将 Hammerspoon 添加到登录项。
3. `mkdir -p ~/.hammerspoon ~/.local/bin`
4. 配置主配置文件：将要使用的 Hammerspoon 配置复制到 `~/.hammerspoon/init.lua`（或编写等效内容）。启动时，`hs.ipc.cliInstall(os.getenv("HOME") .. "/.local")` 会将文件放入 `~/.local/bin/hs`。
5. `ln -sf ~/project/tools/voice/input/voicein.py ~/.local/bin/voicein`
6. 在菜单栏选择 Hammerspoon → Reload Config。启动时的警报表示 PTT 已启动。

`init.lua` 中的 Lua 路径示例：`VOICEIN = os.getenv("HOME") .. "/.local/bin/voicein"`。录音显示是通过 Hammerspoon canvas 绘制的波形 Pill，无需图像文件。配置中保留了指定任意 Mascot 图像 `~/project/tools/voice/input/indicator.png` 的部分，但由于该文件目前不存在，将不带图像进行显示。停止朗读需执行 `~/project/tools/voice/output/voice.py stop`。每次开始录音时，都会异步调用 `voice.py stop`（用于中断）。静音快捷键为 Cmd+Ctrl+.（`hs.hotkey.bind({"cmd", "ctrl"}, ".")` → `voice.py stop`）。

### 辅助功能（Accessibility）

为了让 `hs.eventtap.keyStrokes` / `keyStroke` 能够进行前置输入，以及让右侧 Option 键的 `eventtap` 生效，需要**将 Hammerspoon 添加到辅助功能列表中**。

1. 启动一次 Hammerspoon（可能会弹出权限提示对话框）。
2. 在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选 Hammerspoon。
3. 同时为 Hammerspoon 开启麦克风权限（见第 2 节。由于 ffmpeg 是 HS 的子进程，麦克风处理是基于应用层级的）。
4. **退出并重新启动 Hammerspoon**。为了使辅助功能设置生效，可能需要注销用户或重启系统（见第 2 节）。

如果无法获取右侧 Option 键的 `flagsChanged` 事件，请在同一界面下的 **输入监听** 中添加 Hammerspoon，然后重启应用。

### 两种现有的输入方式（init.lua 实例）与已删除的路径

识别完成后，通过 `hs.eventtap.keyStrokes` 直接向前端输入框进行打字。是否按下 Enter 取决于具体的输入路径（见下表）。

| # | 操作 | init.lua 入口 | 录音 | 打字后的 Enter |
|---|---|---|---|---|
| 1 | 仅在按下右 Option 时 | `hs.eventtap`（右 Option 的 `flagsChanged`）→ `startRec` / `stopRec()` | `voicein --ptt start` / `stop`。持续到松开为止。上限 90 秒 | 不按 |
| 2 | 对应的接收器按钮 (F18) | `hs.hotkey.bind({}, "f18")`。切换模式。识别期间的连击会被忽略。0.5 秒防抖 | 第 1 次按下 `startRec("button")`，第 2 次按下 `stopRec(true)` | 按下（等待 150ms 后 `return`） |

**1. 右 Option (PTT)** — 仅在按住时进行录音。回调函数仅处理 Flag 判断，耗时操作通过 `hs.timer.doAfter(0, …)` 处理。需保持监控对象的引用，以防被 GC 回收。

**2. 接收器按钮 = F18** — F18 的来源是 `init.lua` 中的 `hidutil` 重映射（不使用 Karabiner）。

路径：接收器按钮 → USB 接收器发出的事件 → 通过 `/usr/bin/hidutil property` 仅将目标设备映射为 F18 → `hs.hotkey.bind({}, "f18")`。USB 设备 ID 和发出的事件需根据所使用的设备进行确认。为了不影响键盘本身，仅针对特定设备进行映射。在重映射会失效的环境中，需在 Hammerspoon 启动时及设备连接后重新应用。

**已删除：常时监听 (Always-on Listen)** — `init.lua` 中仍残留有通过 `hs.task.new(VOICEIN, nil, {"--listen"})` 启动 `VoiceinListen.startDaemon()` 子进程的代码。但 `VoiceinListen.daemonEnabled` 已设为 **`false`**（2026-08-02 冻结）。即使将其启用，由于此 Mac 上的 `voicein.py` 在接收到 `--listen` 参数时会提示“常时监听功能已于 2026-09-07 删除（决定 D182）”并退出，因此这不再是现有的输入路径。

### 粘滞检测与 eventtap 的自动恢复

`VoiceinPTT.watchdog`（每 1 秒执行一次）：

- 如果 `flagWatcher:isEnabled()` 为 false，则执行 `flagWatcher:start()`（eventtap 自动恢复）。控制台输出 `voicein PTT: eventtap自动恢复`。
- 如果正在录音、起点为 `"ptt"` 且当前 Option 键已释放 → 执行 `stopRec()`（粘滞检测。用于处理漏掉释放事件时的恢复）。不适用于按钮起点（为了应对 1 秒内杀掉切换录音模式的实际 Bug。按钮端的保险机制为 90 秒上限）。

在休眠/解锁（`hs.caffeinate.watcher` 的 `systemDidWake` / `screensDidUnlock`）时，如果 `flagWatcher` 已断开，也会进行重建。

## 8. 登录时的自动启动

登录项可以通过 `osascript`（System Events 的 login item）和 `~/Library/LaunchAgents` 进行查看。请不要使用需要管理员权限的命令。

音频相关的 LaunchAgent 为 `local.voice.aivis.plist` 和 `com.voice.seats.plist`。

放入 LaunchAgent 后，需要 **重新登录一次**，或者直接使用 `launchctl bootstrap` 进行加载。

### Aivis Engine — `~/Library/LaunchAgents/local.voice.aivis.plist`

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
```

```sh
# 添加模型后的重启
launchctl kickstart -k gui/$(id -u)/local.voice.aivis
```

这台 Mac 通过 `launchctl list` 可以看到 `local.voice.aivis` 正在运行。

### Aizuchi 与席 — `com.voice.seats`

plist 位于 `~/Library/LaunchAgents/com.voice.seats.plist` → `~/project/tools/sessions/com.voice.seats.plist`。通过 `RunAtLoad` 运行 `autostart.sh`。脚本开头为 Aizuchi：

```sh
pgrep -f '[a]izuchi/serve.py' >/dev/null || \
  aizuchi/.venv/bin/python ... start_new_session=True ... aizuchi/serve.py
```

如果只需要 Aizuchi，只需将同样的这一行添加到你自己的登录脚本中即可。不会加载 mlx-lm。

## 9. 注册 hook

### Claude Code — 在 `~/.claude/settings.json` 中添加 2 项

Stop 和 Notification。项目的 `~/project/.claude/settings.json` 中没有 voice 的 hook（只有权限）。请将其添加到用户的 `~/.claude/settings.json` 中。

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
            "statusMessage": "voice: 正在朗读"
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
            "statusMessage": "voice: 等待确认"
          }
        ]
      }
    ]
  }
}
```

请将其添加到现有的 `hooks` 对象中。不要覆盖整个文件。

### Pi 扩展

```sh
mkdir -p ~/.pi/agent/extensions
ln -sf ~/project/tools/pi/extensions/voice.ts ~/.pi/agent/extensions/voice.ts
```

实现的实体是 `tools/harness/voice-pi.ts`。请根据各自的 checkout 情况确认实际的存放路径和链接目标。

## 10. 确认

### tests/（静音模式）

详细步骤请参阅 [tests/README.zh.md](tests/README.zh.md)。此 Mac 实现路径下的示例：

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

执行顺序：`test_paths.py` → `e2e_silent.sh` → `smoke.tsv` → `smoke-dictation.tsv`。即使其中一个失败也会运行到最后，若有失败则返回退出码 1。`afplay` / `say` 会被测试脚本替换。

通过条件：路径测试全部 pass。静音端到端测试全部 pass。即时响应 smoke 测试意图识别度 ≥ 0.9 且 none 误报 ≤ 0.01。口述风格测试误触发 ≤ 0.01 且漏识别 ≤ 0.10。

同样的 4 项测试也可以在路径固定的生产脚本中运行：`sh ~/project/tools/voice/output/tests/run-all.sh`。

## 9. 非日语语音（英语、中文、韩语）

作者（日语）使用的是 AivisSpeech，但 AivisSpeech 仅支持日语。对于英语、中文和韩语，需使用具有类似功能的工具。关于候选方案对比、当前 `voice.py` 的分语言行为以及词典注意事项，请参阅 [docs/output.zh.md 中的“非日语语音”](docs/output.zh.md#非日语的声音英语中文韩语)。

通用的候选方案是 [piper-plus](https://github.com/ayutaz/piper-plus)。官方指南提供了适用于 Apple Silicon 的分发二进制文件和本地 HTTP API。请按照官方 README 进行安装，并将其绑定（bind）至 `localhost` 启动。所使用的语音模型遵循不同的许可协议，请务必阅读模型卡（Model Card）以了解商用、修改及分发的条件。英语和普通话请从已发布的模型语言和说话人中进行选择。韩语方面，请不要混淆代码支持与已分发的预训练语音；如果找不到可用的韩语模型，请使用 macOS 标准语音。

引入 macOS 标准语音的方法为：系统设置 → 辅助功能 → 朗读内容（Read & Speak）→ 系统语音 → 管理语音（Manage Voices）。如果目标语言中有显示为 Enhanced/Premium 的语音，请选择并下载。由于语音名称会因 OS 版本和地区而异，请勿固定名称，安装后请执行 `say -v '?'` 以确认英语、普通话/地区中文及韩语的语音名称。示例包括 Samantha/Alex、Ting-Ting/Mei-Jia/Sin-ji、Yuna。

制作即时响应（Reply）片段时，直接从 `project/voice/aizuchi/reply_map.tsv` 中对应 `lang=en|zh|ko` 的行提取 `text`，并连同语言和语音 ID 一起发送给所选模型的本地 API。将返回的音频保存为每个 `id` 对应的 WAV 文件，并在 manifest 中记录语言、模型、语音、文件及状态 `ok`。正文中的 `text` 不进行翻译或改写，直接使用。如果使用 macOS `say` 命令，请使用 `say -v '<实际存在的语音名称>' -o <file.aiff> '<text>'` 保存，然后通过 `afconvert -f WAVE -d LEI16 <file.aiff> <file.wav>` 转换为 WAV 格式。由于目前的 Aizuchi 即时响应不会将 `lang` 传递给语音选择环节，因此需要另外进行连接修改以实现分语言语音。

语音词典是改善读音的第一步，应按语言分别创建。英语侧重专有名词和缩写，中文侧重简体/繁体及多音字，韩语侧重外来语、专有名词和数字，并将其注册到所选引擎的词典格式/G2P/音素输入中。AivisSpeech 用的 `readings.tsv` 并不一定可以直接使用。在 piper-plus 的公开基准测试中，有一个小型运行模型文件容量为 38 MB 的例子，但未列出常驻 RSS（常驻内存）的大小。由于 RSS 可能大于模型容量，官方数值尚未确认，请在模型加载后通过 Mac 的活动监视器（Activity Monitor）进行测量。Kokoro 82M 是英语和普通话的另一个候选方案，但官方暂无韩语语音。详情请参阅 [Kokoro](https://github.com/hexgrad/kokoro)。

### 用语音说“我回来了”

1. Aivis、10101、Aizuchi socket 以及 Hammerspoon 均处于运行状态。
2. 在当前显示的 tmux 会话中，按住右 Option 键并说出“ただいま”（我回来了），然后松开。
3. 文本进入前台，由于 `speak_intents.txt` 中包含即时响应意图 `return-home`，Aivis 将播放回复（如“欢迎回来”等）。

在 `quiet_hours` 期间，自动的常规朗读和 earcon 将被抑制。手动 read / test 则不受影响。在录音后的 `post_rec_grace_sec` 时间内、当会话与 vis 不一致、或 socket 掉线时，也不会播放常规回复。
