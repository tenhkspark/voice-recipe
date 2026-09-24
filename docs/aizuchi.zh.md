[日本語](./aizuchi.md) / [English](./aizuchi.md) / [中文](./aizuchi.zh.md) / [한국어](./aizuchi.ko.md)

# 如何制作 Aizuchi

将短句拆分为意图，并仅针对问候、感谢、道歉、情感进行即时响应的分类器制作流程。作者使用 AivisSpeech（仅支持日语）。本文不包含预训练权重。流程为：获取基础模型，使用自己的 LLM 生成示例，并进行自主训练。数字为作者实测值（2026-09-24，记录于 `progress-aizuchi.md`（原 `(internal record)`）・`progress-aizuchi-wire.md`・`(internal record)`・`runall-first.md` 以及 `aizuchi/` 中的文件数量）。未进行测量的部分不予列出。

合格的标准依据为 [tests/aizuchi/](../tests/aizuchi/)（`smoke.tsv` 252 行、`smoke-dictation.tsv` 800 行、`speak_intents.txt`）。`speak_intents.txt` 是 `aizuchi/speak_intents.txt` 的固定副本，其余同名的测试 TSV 文件也与作者侧的文件保持字节一致。

---

# 中文

## 1. 要做什么

```
单句语音（ja / en / zh / ko）
  → 分类器（54 个意图 + none）
  → 置信度低于阈值，或为 none → 静音
  → 意图不在 speak_intents.txt 的 32 个范围内，且回复为空 → 静音
  → 在范围内 → 选择该语言的一条固定回复，传递给播放端
```

这与正式回复（Agent 的长回复）走的是不同的路径。即使分类失败，也不会停止已转文字的正文内容，只是缺少即时响应。

需要播放的 32 个意图是：问候、感谢、道歉、情感，并加上了 ack 和 input-wait。正式列表是每行一个意图的 `speak_intents.txt`。

| 类别 | 意图 |
|---|---|
| 问候 | hello, morning, night-sleep, goodbye, otsukare, return-home, leaving, first-meet, reunion, how-are-you, welcome-in |
| 感谢・道歉・关心 | thanks, apology, care |
| 情感 | joy, moved, surprise, encourage, praise, empathy-here, sad, lonely, worry, relief, angry, calm-down, embarrassed, love, laugh, peaceful |

`how-are-you`（你好吗）包含在此集合中。`invite` 和 `meetup` 因为属于场景回复，所以已从允许列表中剔除。即使分类出了邀请（invite, meetup）、执行中、提问或其他运营意图（doing 等）以及 `none`，也不会进行播放。当文件无法读取时，作者的 `respond.py` 会返回空集合（不播放任何内容）。另一方面，`voicein.py` 代码内的 fallback 逻辑与正式列表不一致，它包含了 `invite` 和 `meetup`，但不包含 `how-are-you`。如果文件无法读取或为空，则会使用这个不同的集合。测试端的列表是正式列表的固定副本，修改正式列表时需要进行同步。

播放端不会通过分类器调用 `afplay`。坐席、安静时间、排队等待等逻辑由播放端（作者使用的是 `voice.py` 的 `speak`）处理。

## 2. 意图设计

最初阶段直接对回复 id 进行分类。目标是 491 个 id（greet 124、emotion 195、ops 172）加上 `none` 共 492 个类别。greet 和 emotion 包含全部样本。ops 仅包含短句口语（`z-ops-*`、无前缀的短 id、以及能读出“确认中”、“等待中”、“执行中”、“准备中”含义的 id）。

491 个类别过于细碎。在表达相同的感谢意图时，概率会被分散，导致无法超过 0.55 的阈值。根据作者的实测，“ありがとう!”、“Thanks a lot”、“谢谢你”、“ごめん、間違えた”、“よろしくね”全部被误判为 `none`，只有“おはよう”判定正确。

随后将分类单位合并为意图（intent）。`intents.txt` 共 54 行（名称、制表符、描述）。分类类别为 54 个意图 + `none` 共 55 个。不再对回复 id 进行分类。在匹配到意图后，再从对应的对话表（response table）中选择一条回复。

`none` 定义为“无法用固定句式处理的发言”。包括知识问答、解释、咨询、工作指令、寻求信息的提问等。对于低于阈值的推理结果也统一设为 `none`。如果不确定，就归为 `none`。比起错误地触发固定句式，保持沉默（不回应）的影响更小。

在将 id 分配给意图时，不使用列表之外的名称。不确定的 id 统一归为 `notify`。作者仅在分配完成后手动修正明显的错误（例如：`review-pass` → `result-report`）。早晨通知类的 11 个 id（闹钟、天气、新闻、日程、首班车等）被放在了意图 `none` 中。`intents.tsv` 中的 `none` 行即包含这 11 个 id。

对于 ops 类意图中包含的祈使句（“请做...”、“do X”），将其学习标签移至 `none`。但情感类中的“请做...”则予以保留。提问、问候、情感、报告不计入命令句。根据作者的记录，为了强行平衡各 id 样本量而进行的追加生成反而会产生负面效果，因此未采用。

## 3. 如何构建训练数据

在推荐的工作流程中，建议将用于生成例句的 LLM 与用于检查的 LLM 分开。这是因为如果让同一个模型检查自己生成的句子，检查标准会变得过于宽松。根据使用哪个 LLM 生成句子，训练后权重所附带的使用条款也会有所不同。如果使用 Gemma 生成，权重将附带 [Gemma Terms of Use](https://ai.google.dev/gemma/terms) 中的禁止用途条款；如果使用其他模型生成，则附带该模型的条款。底层 Encoder 的 MIT 协议保持不变。不要包含第三方的声音或个人的发言。

作者用于分类器的语料库是使用自制的 Gemma 4（本地 OpenAI 兼容，64 并行）构建的。在实施记录（`progress-aizuchi.md`）中，生成和检查使用的是同一个 Gemma，并非由独立的另一个模型进行检查。后续的外部确认记录在 `(internal record)` 中。

步骤：

1. 针对每个意图（intent），让模型生成用户可能说出的发言。ja / en / zh / ko 的数量几乎相等。涵盖从口语到礼貌用语、从短句到长句的各种形式。仅保留那些能让该意图的固定回复（定型回复）自然成立的发言。用户只是复述回复内容的句子（鹦鹉学舌）是不允许的。工作指令以及关于天气、知识、新闻等信息的提问，不要混入问候和情感类的示例中。
2. `none` 使用不同的提示词（prompt）。指那些无法仅通过固定的问候、感谢或“是”来解决的发言。通过划分主题来增加多样性（工作指令、信息提问、咨询、计算、翻译）。
3. 在推荐流程中，使用与生成时不同的 LLM 对所有条目进行检查。意图侧的检查标准是“该固定回复是否自然”；`none` 侧的检查标准是“是否真的无法用固定回复解决”。未通过的编号直接舍弃。如果同一个句子对应多个标签，则该句子全部舍弃。同时舍弃完全重复的（标签，句子）组合。在构建本语料库时，生成和检查使用的是同一个 Gemma。在常驻推理（resident inference）时，仅使用 `tokenizers` 加载 tokenizer，不 import `transformers` / `torch`。
4. 将剩余的句子进行分层划分。作者使用的 `parse_val.py` 采用 `sha256(text) % 10 == 0` 作为 dev 集，其余作为 train 集（比例约为 9:1）。

作者的数据量：

| 阶段 | 数量 | 来源 |
|---|---|---|
| 初始生成 | 34,783（id 侧 17,585 / none 17,198，4 种语言几乎等量）。每个 id 请求 36 条（9×4 语言）。none 为 40 次调用 × 60 条 | 进度笔记 |
| 使用相同 Gemma 检查后 | 合格 31,454，不合格 3,329，剔除多标签和重复项后为 **28,933**（train 26,045 / dev 2,888） | 进度笔记 |
| 指令迁移与追加后手头的生成文件 | **37,764** 行（`examples2.jsonl`。约 3.8 万）。其中带有意图名称的追加项（`@intent::名称`）为 2,156 行 | 文件数量 |
| 采用的 55 个类别的划分 | train **32,560**（none 19,054）/ dev **3,645**（none 2,130） | `train.jsonl` / `dev.jsonl`。dev 的 3,645 与进度笔记中的 n 一致 |

进度笔记中提到，使用 Gemma 额外添加了 1,241 条 `smoke` 正例的改写（paraphrase）。并未采用为了使 id 侧均衡而进行的追加操作。在最初的 id 分类阶段，弱 id（示例少于 10 条）共有 19 个。

固定测试的口述侧（`smoke-dictation.tsv`）与训练集是分开的。共 800 行（silent 600 = 4 语言 × 150，reply 200 = 4 语言 × 50）。列名为 `lang`、`text`、`expect`（`silent` 或 `reply`）。

## 4. 训练

基础模型是 [sbintuitions/modernbert-ja-130m](https://huggingface.co/sbintuitions/modernbert-ja-130m)。采用 MIT 协议（© 2025 SB Intuitions）。作者的模型卡显示：中日双语 4.39T tokens，词表大小 102,400，序列长度 8,192，hidden size 512，共 19 层。需要 `transformers` 4.48 或更高版本。Mac 上的 venv 环境为 Python 3.12、torch 2.14、transformers 4.56.2。GPU 运行环境使用的容器为进度日志中的 `tenhkspark/gemma-4-v2:v2`。

头部（Head）是在 Encoder 的 CLS（最终隐藏状态的位置 0）上添加的一个线性层。损失函数使用交叉熵（Cross Entropy）。标签按出现顺序冻结，`none` 始终位于末尾。优化器使用 AdamW，学习率为 2e-5，最大长度 96，训练 3 个 epoch，warmup 设置为总步数的 10% 后线性衰减，梯度裁剪（gradient clip）为 1.0，检查点（checkpoint）使用 bfloat16。如果已存在 `model.safetensors` 则从该点恢复。设备优先使用 CUDA，否则使用 MPS，再否则使用 CPU。

```
python3 train.py train.jsonl --out ckpt --base base --epochs 3 --batch-size 64 --lr 2e-5 --max-len 96 --seed 0
```

作者使用的运行环境（DGX Spark 的 DGX Spark，`batch_size` 64）：1,527 step，epoch 损失从 1.485914 → 0.493772 → 0.152006，耗时约 **12 分钟**。进度日志显示显存占用小于 20GB。同一台机器上的其他服务器并未停止运行。

相同的脚本也可以在 Mac 的 MPS 上运行。已完成的 MPS 记录显示：在将意图进行聚合之前的 491 个 id 模型（batch 32，2,442 step）上耗时约 **37 分钟**，最终损失为 0.358。55 个类别的训练检查点保存在 GPU 端。

阈值选取原则是在 dev 集上选择 `none` 误报（false positive）较小的一个。初始的判定阈值为 **0.5**。在当时的参数搜索（sweep）中，0.3 的结果为准确率 0.9621 / 误报 0.0167，0.4 为 0.9621 / 0.0083，0.5 和 0.6 为 0.9394 / 0.0000，因此选择了 0.5。随后，为了防止口述测试（dictation）中的漏报，将当前值修改为 **0.38**。目前的 int8 实测结果为：dictation 误报 0/600，漏报 18/200；smoke 意图准确率 0.9697，`none` 误报 0/120。详情请参阅 `progress-aizuchi.md` 中的 negtest 记录。

## 5. 导出为 ONNX int8

将 PyTorch checkpoint 转换为 ONNX，并通过动态量化（dynamic quantization）转为 int8。输出为 logits `[batch, 55]`。使用 opset 17。batch 和序列长度（sequence length）维度为动态。量化方式使用 `quantize_dynamic`，权重类型为 `QInt8`。将 tokenizer、`labels.json`、`threshold.txt` 放在与 ONNX 相同的目录下。常驻进程仅通过 `tokenizers` 加载 tokenizer，不 import `transformers` 和 `torch`。

导出后，立即使用相同的 2 个句子对比 PyTorch 和 int8 的 logits。作者记录显示 argmax 一致，max|Δlogit| = 0.85。进度笔记大小为 fp32 504MB，int8 126MB。目前磁盘上的 int8 文件大小为 132,993,740 字节。

判定标准是使用 int8 重新对 smoke 测试集进行评分。作者在导出时设定的附加条件为：“torch 意图准确率不得比 0.939 低 0.01 或更多，none 误报率不得超过 1%”。如果未达标，则不使用 int8。

| 指标 | torch（阈值 0.5） | ONNX int8 | 判定 |
|---|---|---|---|
| smoke 意图正确率 | 124/132 = 0.9394 | 126/132 = 0.9545 | 合格（有所提升） |
| smoke none 误报率 | 0/120 | 0/120 | 合格 |
| dev 正确率（n=3645） | 0.8236 | 0.8167 | −0.007 |
| dev none 误报率 | 0.0150 | 0.0164 | ＋0.0014 |
| 推理 median | 9.99 ms（MPS, n=200） | 2.4 ms（CPU / onnxruntime） | |

常驻 RSS 约为 **389 MiB**。启动时间（从完成 imports 到 OrtInfer 和 reply map 准备就绪）为 **0.27 秒**。判定 median 为 **2.4 ms**（`serve.answer("ありがとう")`，n=200）。tokenizer 仅通过 `tokenizers` 加载，不 import `transformers` / `torch`（见 `~/project/ops/codex-rss.md`，commit `(internal)`）。

dev 的 none 误报率略高于 1%。合格线是以 smoke 测试集为准（§7）。int8 漏掉的 6 个案例并非误判为其他意图，而是因为分值低于阈值而被归为 `none`（例如：“おやすみなさい” $\rightarrow$ none 0.483，韩语“이제 잘게” $\rightarrow$ none 0.381）。

## 6. 常驻与 Socket 格式

UNIX Socket。作者默认路径为 `~/.config/voice/aizuchi.sock`。每次连接发送一行语音转文字结果，则每行返回一个 JSON。onnxruntime 使用 CPU，intra / inter 线程数均为 1，关闭 memory arena。tokenizer 最大长度为 96，pad id 为 3。

```json
{"intent": "thanks", "score": 0.9719, "id": "reply-thanks-1", "reply": "どういたしまして", "lang": "ja"}
```

| 字段 | 含义 |
|---|---|
| intent | 54 种意图名称，或 `none`。推理异常时为 `error` |
| score | 最大类别的置信度。即使置信度低于阈值并设为 `none`，也会填入该置信度 |
| id | 应答表中的短语 id。合成用的句子、`none` 或低于阈值时为空 |
| reply | 该语言的应答文本。同上，否则为空 |
| lang | 从语音中推断。如果是平假名/片假名则为 ja，谚文则为 ko，汉字则为 zh，其他为 en。若无该语言候选则 fallback 到 ja |

`none` 及低于阈值时：

```json
{"intent": "none", "score": 0.9991, "id": "", "reply": "", "lang": "ja"}
```

异常时不包含 `score`。格式为 `{"intent":"error","error":"..."}`。客户端不应将没有 `score` 的响应视为正常结果，但应继续处理正文。

当存在多个语言候选时，随机选择其中一个。

作者的常驻实测（2 次）：

| | 进度日志 | 另一台机器确认 |
|---|---|---|
| Socket 开始接收 | 2.26 秒 | 1.97 秒 |
| RSS | 746MB | 745MB |
| 往返时延 | median 5.07 ms / p90 5.52 / min 3.27（n=200，包含 tokenize＋推理＋JSON） | 8 句语音为 3.45–9.59 ms |

8 句语音确认：“ありがとう” 4.18 ms, thanks 0.9719；“おはよう” 3.45 ms, morning 0.9888；“今日の天気は？” 4.56 ms, none 0.9991；“これデプロイして” 3.84 ms, none 0.9995；“ごめん、間違えた” 4.69 ms, apology 0.9961；英语 Thanks 6.36 ms, thanks 0.9512（id 为空）；谢谢 9.59 ms, thanks 0.8554；고마워요 7.65 ms, thanks 0.7966。未播放声音。

语音输入侧在文字化后立即发送一行。作者的 `voicein` 等待时间为 0.2 秒。若 Socket 不存在、已挂掉、超时或 JSON 损坏，则不立即响应，而是按原样传递正文。常驻进程的自动启动逻辑为：若已存在相同的 `serve.py` 则不启动。即使启动失败，也不会停止语音输入。

## 7. 阈值与合格标准

首次采用的阈值为 0.5，但目前的阈值在口述测试调整后为 **0.38**。当前值的测量应与首次测量区分开，变更阈值时需同时观察 dev 的误触发（误爆）和 smoke 测试。

`[tests/](../tests/README.zh.md)` 中的 `run-all` 不会发出声音。其中 2 项即时响应测试会将 `tests/aizuchi/` 的 TSV 文件发送到常驻 Socket（若无则使用 `AIZUCHI_SERVE` 和 `AIZUCHI_MODEL` 建立临时 Socket）。模型本体不包含在测试中。若无 Socket，则这两项测试判定为不合格。

| 材料 | 合格标准 |
|---|---|
| `smoke.tsv`（阳性 132 ＋ none 120） | 意图正确率 ≥ 0.9，且将 none 误判为其他意图的比例 ≤ 0.01 |
| `smoke-dictation.tsv`（silent 600 ＋ reply 200） | 不应响应的行被误判为 32 种意图之一的比例在合格线内；应响应的行未响应的比例也在合格线内。若 `expect` 不为 silent / reply 则判定为不合格 |

是否响应取决于预测意图是否包含在 `speak_intents.txt` 中。在 dictation 测试中，即使预测意图与正确意图不同，只要属于 32 种意图之一，即视为“已响应”。

作者 int8 常驻，首次 `run-all`（2026-09-24 18:51，无声）结果：

| 项目 | 结果 |
|---|---|
| smoke | 合格。126/132 = 0.9545，none 误触发 0/120 |
| dictation | 不合格。无声时的误触发在合格标准内；回复的漏响应未达标 |

smoke 测试失败的案例包括：低于阈值的 `none`（如“晚安”、英文 “Good morning”、韩语就寝）以及 1 例将 surprise 误判为 sad 的情况。dictation 测试的漏响应包括：问候语被判定为 `none` 的情况，以及首次测试（阈值 0.5、旧白名单含 30 种意图）的记录；当时也存在“承知”、“わかりました”被判定为 ack（不在白名单内）的例子。随后将 ack 和 input-wait 加入白名单并扩展为 32 种意图，同时将阈值更改为 0.38。目前的实测结果为：dictation 误触发 0/600，漏响应 18/200（包含修正后的遗留问题）。

## 8. 回复对照表

列为 `intent`、`lang`、`text`、`id`（制表符分隔）。每个“1 意图 × 1 语言”对应 1~3 句。句子应使用回复方的口吻。不要复读或改写用户的发言。对于涉及特定饮食或地点的句子，不要放在即时回答中。

带有 `id` 的行是预录语音的短语 ID。空行则通过 TTS 读取。作者的表共有 536 行（54 意图 × 4 语言），其中有 ID 的 479 行，空 ID 的 57 行。这 57 个空行中，en 为 21、zh 为 18、ko 为 18；日语的 134 行全部都有 ID。每个意图对应的日语候选数量为 1~3 个。

示例（表中的候选内容）:

| 发言意图 | 语言 | 回复内容 | id |
|---|---|---|---|
| thanks | ja | どういたしまして | reply-thanks-1 |
| thanks | ja | こちらこそ、ありがとう | reply-thanks-2 |
| apology | ja | 大丈夫、心配いらない | z-emo-058 |
| apology | ja | 気にしないで、大丈夫だよ | reply-apology-1 |
| morning | ja | 良い朝ですね | z-grt-032 |
| morning | ja | おはようございます。今日も良い一日になりますように。 | greet-good-morning-today |
| sad | ja | つらかったね、そばにいるよ | reply-sad-1 |
| angry | en | That would really make me mad too | （空。合成） |

当存在多个候选时，每次执行随机抽取 1 条。上表并非抽样结果。无需重新训练，只需替换表文件即可。

# 英语

## 1. 功能说明

```
单句语音行 (ja / en / zh / ko)
  → 分类器 (54 个意图 + none)
  → 低于阈值或 none → 静默
  → 意图不在 32 个范围内或回复为空 → 静默
  → 否则在该语言中选择一个预设回复并交给播放器
```

此路径与智能体的长回答是分离的。如果分类失败，转录文本仍会继续处理，只是缺失了即时回复。

允许的 32 个意图涵盖了问候、感谢、道歉、情感，以及确认（ack）和等待输入（input-wait）。事实来源（source of truth）是 `speak_intents.txt`，每行一个意图。

| 分组 | 意图 |
|---|---|
| Greeting | hello, morning, night-sleep, goodbye, otsukare, return-home, leaving, first-meet, reunion, how-are-you, welcome-in |
| Thanks, apology, care | thanks, apology, care |
| Emotion | joy, moved, surprise, encourage, praise, empathy-here, sad, lonely, worry, relief, angry, calm-down, embarrassed, love, laugh, peaceful |

`how-are-you` 包含在允许的集合中。`invite` 和 `meetup` 被排除在源列表之外，因为它们的回复具有情境性。Invite、meetup、progress、questions、其他操作意图（包括执行操作）以及 `none` 会被分类并保持静默。如果无法读取文件，作者的 `respond.py` 会使用空集合且不进行语音输出。`voicein.py` 中的备用集合（fallback set）与源列表不同：它包含了 `invite` 和 `meetup`，但省略了 `how-are-you`。如果文件无法读取或为空，则使用该不同的集合。测试列表是源列表的一个固定副本，当源列表更改时必须进行同步。

不要从分类器中调用 `afplay`。座位（Seat）、静音时段（quiet hours）以及播放队列属于扬声器（Speaker）范畴（作者使用的是 `voice.speak`）。

## 2. 设计意图 (Intents)

第一个分类器直接预测回复 ID：491 个 ID（greet 124, emotion 195, ops 172）加上 `none`，共 492 个类别。Greet 和 emotion 全部保留。Ops 则仅保留简短的口语行（`z-ops-*`、无前缀的短 ID，以及读起来像是等待、检查、运行或准备的行）。

491 个类别过于细碎。概率会在同一个语义内（例如“谢谢”）进行拆分，导致无法突破 0.55 的阈值。经作者检查，「ありがとう！」、“Thanks a lot”、“谢谢你”、“ごめん、間違えた”以及「よろしくね」全都返回了 `none`。只有「おはよう」命中了。

现在的基本单位是意图 (intent)。`intents.txt` 有 54 行（名称、制表符、描述）。分类器包含这 54 个类别加上 `none`（共 55 个类别）。它不再预测短语 ID。在命中意图后，会从回复表中选择一行。

`none` 意味着该话语需要真实的回答：例如知识性问题、解释、建议、工作指令或信息请求。任何低于阈值的预测也会作为 `none` 返回。如果不确定，优先选择 `none`。给出一个错误的预设回复比保持沉默更糟。

在将 ID 映射到意图时，未知的名称会被拒绝。不确定的 ID 会进入 `notify`。作者手动修正了明显的错误分配（例如 `review-pass` → `result-report`）。11 个早间公告 ID（闹钟、天气、新闻、日程、首班车等类似内容）被映射为 `none`。这 11 个就是 `intents.tsv` 中的 `none` 行。

此前附属于 ops 意图的祈使句（〜して, してください, "do X"）已移至 `none` 标签。请求安慰的情绪类语句予以保留。提问、问候、感受和报告不被视为命令。曾尝试通过额外的生成来平衡每个 ID 的计数，但该方案已被放弃。

## 3. 构建训练数据

为了保证运行的可复现性，推荐的流程是使用一个 LLM 编写示例，并使用另一个不同的 LLM 进行检查。如果模型对自己生成的句子进行评分，可能会过于宽松。无论使用哪个 LLM 编写句子，其条款都会附加到训练后的权重中。由 Gemma 编写的文本受 [Gemma 使用条款](https://ai.google.dev/gemma/terms)约束，包括禁止使用政策。其他生成器则会附加该生成器的条款。无论如何，基础编码器（base encoder）保持 MIT 协议。请勿包含他人的声音或私人言论。

作者的分类器语料库是使用自托管的 Gemma 4（本地 OpenAI 兼容端点，64-way）编写的。运行记录 (`progress-aizuchi.md`) 显示，该过程是由同一个 Gemma 编写并检查了这些行；这并非由第二个模型进行的独立检查。随后的外部审查记录在 `(internal record)` 中。

步骤：

1. 对于每个意图（intent），请求生成一个人实际会说的句子。保持 ja / en / zh / ko 的比例大致均衡。混合使用口语和礼貌用语，以及短句和单句。仅保留那些其对应的预设回复（canned reply）为自然回答的行。如果用户说的是回复内容的改写，则予以拒绝。不要将工作指令，或天气 / 知识 / 新闻类问题混入问候和情感示例中。
2. `none` 是一个单独的提示词：即问候、感谢或简单的“是”无法回答的句子。拆分主题（指令、信息查询、建议、计算、翻译）。
3. 在推荐的流程中，让不同的 LLM 标记每一行。在意图（intent）方面：这个预设回复是否自然？在 `none` 方面：这真的需要一个实际的回答吗？丢弃被拒绝的条目。如果同一段文本出现在多个标签下，则丢弃所有副本。丢弃重复的 (label, text) 对。对于本语料库，生成和检查均由同一个 Gemma 完成。对于本地推理（resident inference），仅使用 `tokenizers` 加载 tokenizer；不要导入 `transformers` 或 `torch`。
4. 按层（stratum）拆分剩余内容。作者的 `parse_val.py` 将 `sha256(text) % 10 == 0` 的数据分配给 dev，其余分配给 train（比例约为 9:1）。

作者运行过程中的计数：

| 阶段 | 计数 | 记录位置 |
|---|---|---|
| 首次生成 | 34,783 (17,585 id-side / 17,198 none，四种语言几乎均衡)。每个 id 请求了 36 行 (9 × 4 种语言)。none 为 40 次调用 × 60 行 | progress note |
| 同一个 Gemma 检查后 | 保留 31,454，丢弃 3,329，随后进行多标签和重复项移除 → **28,933** (train 26,045 / dev 2,888) | progress note |
| 磁盘上仍存在的后续文件 | **37,764** 行 (`examples2.jsonl`，约 38,000)。其中 2,156 行是带有 `@intent::name` 标签的额外行 | line count |
| 所采用的 55 类模型拆分结果 | train **32,560** (none 19,054) / dev **3,645** (none 2,130) | `train.jsonl` / `dev.jsonl`。3,645 与 progress note 一致 |

progress note 还记录了后来添加的 1,241 条 Gemma 对 smoke positives 的改写。id 端的平衡并未被采用。在早期的 id-classifier 阶段，有 19 个 id 的示例少于 10 个。

听写文件 (`smoke-dictation.tsv`) 不是训练集。共有 800 行 (silent 600 = 4 种语言 × 150，reply 200 = 4 种语言 × 50)。列名：`lang`, `text`, `expect` (`silent` 或 `reply`)。

## 4. 训练

基础模型是 [sbintuitions/modernbert-ja-130m](https://huggingface.co/sbintuitions/modernbert-ja-130m)，采用 MIT 协议 (© 2025 SB Intuitions)。作者的模型卡片信息：日语和英语，4.39T tokens，词表大小 102,400，序列长度 8,192，隐藏层大小 512，19 层。`transformers` 版本必须为 4.48 或更高。Mac venv 环境使用的是 Python 3.12, torch 2.14, transformers 4.56.2。GPU 运行使用了进度说明中指定的容器 `tenhkspark/gemma-4-v2:v2`。

Head 部分是在 CLS 向量（最后隐藏状态的第 0 个位置）上添加的一个线性层。损失函数为交叉熵（cross-entropy）。标签按首次出现的顺序冻结，`none` 始终排在最后。优化器为 AdamW，学习率为 2e-5，最大长度 96，训练 3 个 epoch，前 10% 的步数进行 warmup，随后进行线性衰减，梯度裁剪（gradient clip）为 1.0。检查点（Checkpoints）以 bfloat16 格式保存。如果存在现有的 `model.safetensors`，则会进行断点续训。设备优先使用 CUDA，否则使用 MPS，最后是 CPU。

```
python3 train.py train.jsonl --out ckpt --base base --epochs 3 --batch-size 64 --lr 2e-5 --max-len 96 --seed 0
```

最终采用的运行记录（DGX Spark, DGX Spark, batch 64）：1,527 步，epoch 损失分别为 1.485914 → 0.493772 → 0.152006，耗时约 **12 分钟**。进度说明显示显存占用保持在 20 GB 以下。该机器上的另一个服务器保持运行状态。

相同的脚本也可以在 Mac MPS 上运行。记录中完成的 MPS 运行是早期的 491-id 模型（batch 32, 2,442 步）：耗时约 **37 分钟**，最终损失为 0.358。最终采用的 55 类检查点是 GPU 运行的结果。

通过在验证集（dev）上保持较低的 `none-misfire`（误报为 none）来选择阈值。最初采用的值为 **0.5**。在当时的搜索中，0.3 的得分为 0.9621 / 0.0167，0.4 的得分为 0.9621 / 0.0083，0.5 和 0.6 的得分为 0.9394 / 0.0000。随后为了减少听写漏掉的情况，阈值被更改为目前的 **0.38**。当前的 int8 测试结果：听写错误回复 0/600，漏掉回复 18/200；smoke 意图准确率为 0.9697，`none` 误报为 0/120。详情请参阅 `progress-aizuchi.md` 中的 negtest 记录。

## 5. 导出为 ONNX int8

将 PyTorch checkpoint 导出为 ONNX，然后进行 int8 动态量化。Logits 维度为 `[batch, 55]`。使用 Opset 17。Batch 和 sequence length 设置为动态轴（dynamic axes）。量化采用 `quantize_dynamic`，权重类型为 `QInt8`。将 tokenizer、`labels.json` 和 `threshold.txt` 复制到 ONNX 文件旁边。运行时进程不导入 torch。

导出后，立即在相同的两个句子上对比 PyTorch 和 int8 的 logits。作者记录：argmax 一致，max |Δlogit| = 0.85。进度说明列出 fp32 为 504 MB，int8 为 126 MB。目前磁盘上的 int8 文件大小为 132,993,740 bytes。

再次对 int8 进行 smoke 测试。作者设定的额外导出标准为：intent accuracy 与 torch 分数（0.939）相比下降不得超过 0.01，且 none misfire 保持在 1% 或以下。如果未达标，则不发布 int8 文件。

| Metric | torch (threshold 0.5) | ONNX int8 | Result |
|---|---|---|---|
| Smoke intent accuracy | 124/132 = 0.9394 | 126/132 = 0.9545 | pass (higher) |
| Smoke none misfire | 0/120 | 0/120 | pass |
| Dev accuracy (n=3645) | 0.8236 | 0.8167 | −0.007 |
| Dev none misfire | 0.0150 | 0.0164 | +0.0014 |
| Inference median | 9.99 ms (MPS, n=200) | 2.4 ms (CPU / onnxruntime) | |

运行时 RSS 约为 **389 MiB**。从完成 import 到 OrtInfer 和 reply-map 设置的启动时间为 **0.27 seconds**。决策中位数（Decision median）为 **2.4 ms** (`serve.answer("ありがとう")`, n=200)。Tokenizer 仅通过 `tokenizers` 加载；未导入 `transformers` 和 `torch` (`~/project/ops/codex-rss.md`, commit `(internal)`)。

Dev none-misfire 略高于 1%。通过标准为 smoke 测试集 (§7)。六个 int8 smoke 错误案例在阈值下都落入了 `none`。它们并没有被分配错误的 id（例如 「おやすみなさい」 → none 0.483，韩语 「이제 잘게」 → none 0.381）。

## 6. 常驻服务与 Socket 格式

一个 UNIX socket。作者默认路径为 `~/.config/voice/aizuchi.sock`。每次连接逐行传输话语（utterances）。每一行都会收到一行 JSON 响应。onnxruntime 运行在 CPU 上，intra-op 和 inter-op 线程数均为 1，关闭 memory arena。Tokenizer 最大长度为 96，pad id 为 3。

```json
{"intent": "thanks", "score": 0.9719, "id": "reply-thanks-1", "reply": "どういたしまして", "lang": "ja"}
```

| 字段 | 含义 |
|---|---|
| intent | 54 个名称之一，或 `none`。推理异常时为 `error` |
| score | 置信度最高的类别得分。当由于阈值限制而强制设为 `none` 时，该字段仍存在 |
| id | 来自 reply 表的短语 id。对于合成行、`none` 以及低于阈值的情况，该字段为空 |
| reply | 检测语言对应的回复文本。在上述相同情况下为空 |
| lang | 从话语中检测：平假名或片假名 → ja，谚文 → ko，汉字 → zh，否则为 en。如果该语言没有候选结果，则回退到 ja |

`none` 及低于阈值的情况：

```json
{"intent": "none", "score": 0.9991, "id": "", "reply": "", "lang": "ja"}
```

异常情况会省略 `score`：`{"intent":"error","error":"..."}`。客户端绝不能将没有 `score` 的响应视为正常结果。转录过程仍会继续。

当一种语言有多个候选结果时，随机选择一个。

作者常驻进程的两项测量数据：

| | 进度记录 | 第二次检查 |
|---|---|---|
| Socket 接收 | 2.26 s | 1.97 s |
| RSS | 746 MB | 745 MB |
| 往返时延 (Round trip) | 中位数 5.07 ms / p90 5.52 / 最小值 3.27 (n=200, tokenize + infer + JSON) | 8 条话语耗时 3.45–9.59 ms |

这 8 条话语（无音频）：「ありがとう」 4.18 ms, thanks 0.9719; 「おはよう」 3.45 ms, morning 0.9888; 「今日の天気は？」 4.56 ms, none 0.9991; 「これデプロイして」 3.84 ms, none 0.9995; 「ごめん、間違えた」 4.69 ms, apology 0.9961; 英语 "Thanks" 6.36 ms, thanks 0.9512 (id 为空); 谢谢 9.59 ms, thanks 0.8554; 고마워요 7.65 ms, thanks 0.7966。

语音输入会在文本生成后立即发送一行。作者的 `voicein` 会等待 0.2 秒。如果出现 Socket 缺失、Socket 挂死、超时或 JSON 损坏，程序会跳过即时回复，但仍会继续传递文本。自启动程序在已有 `serve.py` 运行时不得启动第二个实例。启动失败不得停止语音输入。

## 7. 阈值与通过标准

初始阈值为 0.5；经过听写测试调整后，当前值为 **0.38**。请将当前测量结果与初始运行结果分开，并在更改阈值时同时检查开发误触发（dev misfires）和冒烟测试（smoke）。

在 [tests/](../tests/README.zh.md) 中运行 `run-all` 时不会播放音频。那两行即时回复（instant-reply）会通过驻留套接字（resident socket）或由 `AIZUCHI_SERVE` 加 `AIZUCHI_MODEL` 生成的临时套接字发送 `tests/aizuchi/`。测试目录中不包含模型文件。如果没有套接字，这两行会失败。

| 测试用例 (Fixture) | 通过标准 (Pass) |
|---|---|
| `smoke.tsv` (132 positive + 120 none) | 意图准确率 ≥ 0.9，且 `none` 行被误预测为其他意图的比例 ≤ 0.01 |
| `smoke-dictation.tsv` (600 silent + 200 reply) | 静音行被误识别为 32 种意图之一的比例必须在通过标准内。回复行未识别出的比例也必须在通过标准内。任何其他的 `expect` 值都会导致文件测试失败 |

“已说话（Spoken）”意味着预测的意图存在于 `speak_intents.txt` 中。在听写集（dictation set）中，即使在 32 种意图内预测错误，仍计为“已说话”。

作者的 int8 服务端，首次 `run-all` 结果 (2026-09-24 18:51, 无音频):

| 行 (Row) | 结果 (Result) |
|---|---|
| smoke | Pass. 126/132 = 0.9545, none misfire 0/120 |
| dictation | Fail. 静音行的误识别（false-speak）在通过标准内。回复行的漏识别（misses）未达到标准 |

冒烟测试的漏识别包括低于阈值的 `none`（例如「おやすみなさい」、英文 "Good morning"、韩语的晚安）以及一个被意外预测为“悲伤”的案例。这是初始运行结果（阈值 0.5，旧的 30 意图白名单）。当时「承知」/ 「わかりました」被预测为白名单之外的 ack。随后白名单扩展了 ack 和 input-wait，阈值也更改为 0.38。当前测得的听写结果为 0/600 误识别回复，18/200 漏识别回复（包含剩余的漏识别项）。

## 8. 回复表

列分别为 `intent`、`lang`、`text`、`id`（制表符分隔）。每个语言的每个 intent 占用一到三行。该行内容为监听器（listener）的回应。请勿转述用户的发言。请勿将回复内容固定在特定的餐食或地点上。

非空的 `id` 是预制音频片段的 phrase id。空的 `id` 则由 TTS 读取。作者提供的表格共有 536 行（54 个 intents × 4 种语言）：其中 479 行带有 id，57 行不带 id。这 57 个空 id 分别为 en 21、zh 18 和 ko 18。所有的 134 行日语数据都带有 id。每个 intent 对应的日语候选句为 1 到 3 个。

示例（表中的候选句）：

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

存在多个候选句意味着每次调用时随机抽取一个。上表是库存列表，而非单次抽取结果。无需重新训练。直接替换表格本身即可。
