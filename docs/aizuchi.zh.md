[日本語](./aizuchi.md) / [English](./aizuchi.md) / [中文](./aizuchi.zh.md) / [한국어](./aizuchi.ko.md)

# 如何制作 Aizuchi

将短句拆分为意图，并仅针对问候、感谢、道歉、情感进行即时响应的分类器制作流程。本文不包含已训练好的权重。流程为：获取基础模型，使用自己的 LLM 生成示例，并进行自主训练。数字为作者实测值（2026-09-24，记录于 `progress-aizuchi.md`（原 `(internal record)`）・`progress-aizuchi-wire.md`・`(internal record)`・`runall-first.md` 以及 `aizuchi/` 中的文件数量）。未进行测量的部分不予列出。

> 注意：Aizuchi 的基础模型是仅面向日语的模型（sbintuitions/modernbert-ja-130m）。虽然也用英语、中文和韩语进行了训练，但这些语言的准确率低于日语，尤其是韩语。按 `smoke-dictation` 测试（每种语言 50 条，阈值 0.38），应响应的发言漏检情况为：日语 2/50（4%）、英语 2/50（4%）、中文 4/50（8%）、韩语 10/50（20%）。所有语言的误触发均为 0/600。建议需要使用日语以外语言时，改用多语言基础模型重新训练。

合格的标准依据为 [tests/aizuchi/](../tests/aizuchi/)（`smoke.tsv` 252 行、`smoke-dictation.tsv` 800 行、`speak_intents.txt`）。`speak_intents.txt` 是 `aizuchi/speak_intents.txt` 的固定副本，其余同名的测试 TSV 文件也与作者侧的文件保持字节一致。

---

# 中文

## 1. 要做什么

```
单句语音（ja / en / zh / ko）
  → 分类器（54 个意图 + none）
  → 置信度低于阈值，或为 none → 静音
  → 意图不在 speak_intents.txt 的 32 个范围内，或回复为空 → 静音
  → 在范围内 → 选择该语言的一条固定回复，传递给播放端
```

这与正式回复（Agent 的长回复）走的是不同的路径。即使分类失败，也不会停止已转文字的正文内容，只是缺少即时响应。

语音输出应按回复语言选择对应的声音，例如在设置表中配置 `ja → voice_ja`、`en → voice_en`、`zh → voice_zh`、`ko → voice_ko`。如果不按语言分流，其他语言的文本会交给日语声音朗读，发音可能会崩坏。注意：这只是语言与声音的设置示例；当前 `voice.py` 仍使用固定的 AivisSpeech `speaker_id`，失败时回退到 `say -v Kyoko`，不会自动按语言切换。详见 [output.md「日本語以外の声」](output.md#日本語以外の声英語中国語韓国語)。

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

阈值选取原则是在 dev 集上选择 `none` 误报（false positive）较小的一个。初始的判定阈值为 **0.5**。在当时的参数搜索（sweep）中，0.3 的结果为准确率 0.9621 / 误报 0.0167，0.4 为 0.9621 / 0.0083，0.5 和 0.6 为 0.9394 / 0.0000，因此选择了 0.5。之后为减少口述测试（dictation）的漏报，曾将阈值调整为 **0.38**；该阈值下的 int8 实测为 dictation 误报 0/600、漏报 18/200，smoke 意图准确率 0.9697、`none` 误报 0/120。当前 `project/voice/aizuchi/onnx/threshold.txt` 的值为 **0.30**，这些 0.38 的结果不代表当前设置。详情请参阅 `progress-aizuchi.md` 中的 negtest 记录。

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

dev 的 none 误报率略高于 1%。合格线是以 smoke 测试集为准（§7）。int8 漏掉的 6 个案例并非误判为其他意图，而是因为分值低于阈值而被归为 `none`（例如：“おやすみなさい” → none 0.483，韩语“이제 잘게” → none 0.381）。

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

首次采用的阈值为 0.5。之后口述测试曾使用 **0.38**；当前 `project/voice/aizuchi/onnx/threshold.txt` 配置为 **0.30**。测量结果应注明对应阈值，并与首次测量区分；变更阈值时需同时观察 dev 的误触发（误爆）和 smoke 测试。

`[tests/](../tests/README.zh.md)` 中的 `run-all` 不会发出声音。其中 2 项即时响应测试会将 `tests/aizuchi/` 的 TSV 文件发送到常驻 Socket（若无则使用 `AIZUCHI_SERVE` 和 `AIZUCHI_MODEL` 建立临时 Socket）。模型本体不包含在测试中。若无 Socket，则这两项测试判定为不合格。

| 材料 | 合格标准 |
|---|---|
| `smoke.tsv`（阳性 132 ＋ none 120） | 意图正确率 ≥ 0.9，且将 none 误判为其他意图的比例 ≤ 0.01 |
| `smoke-dictation.tsv`（silent 600 ＋ reply 200） | 不应响应的行被误判为 32 种意图之一的比例在合格线内；应响应的行未响应的比例也在合格线内。若 `expect` 不为 silent / reply 则判定为不合格 |

是否响应取决于预测意图是否包含在 `speak_intents.txt` 中。在 dictation 测试中，即使预测意图与正确意图不同，只要属于 32 种意图之一，即视为“已响应”。

作者 int8 常驻，首次 `run-all`（2026-09-24 18:51，无声；当时文档记录阈值为 0.38）结果：

| 项目 | 结果 |
|---|---|
| smoke | 合格。126/132 = 0.9545，none 误触发 0/120 |
| dictation | 不合格。无声时的误触发在合格标准内；回复的漏响应未达标 |

smoke 测试失败的案例包括：低于阈值的 `none`（如“晚安”、英文 “Good morning”、韩语就寝）以及 1 例将 surprise 误判为 sad 的情况。dictation 测试的漏响应包括：问候语被判定为 `none` 的情况，以及首次测试（阈值 0.5、旧白名单含 30 种意图）的记录；当时也存在“承知”、“わかりました”被判定为 ack（不在白名单内）的例子。随后将 ack 和 input-wait 加入白名单并扩展为 32 种意图，dictation 测试阶段使用的阈值为 0.38。该阶段的实测结果为：dictation 误触发 0/600，漏响应 18/200（包含修正后的遗留问题）。

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

### 按语言分流到对应的声音

将 Aizuchi 回复中的 `lang` 与语音播放端所选的引擎／声音设置键对应起来。键名示例：`ja → voice_ja`、`en → voice_en`、`zh → voice_zh`、`ko → voice_ko`。实际键名应符合所用的语音设置。如果没有分流，例如英语、中文或韩语由日语声音朗读，发音可能会失真。

要在不播放声音的情况下确认分流，请依据 `tests/fixtures/lang-route.tsv` 中四种语言的句子和预期键，运行 `VOICE_PY=/path/to/voice.py python3 tests/test_lang_route.py`。该测试调用 `--select-voice-key <句子>` 路径，只将选中的键输出到标准输出，并设置 `VOICE_NO_PLAY=1`，逐一精确核对四个结果。测试不会播放声音。
