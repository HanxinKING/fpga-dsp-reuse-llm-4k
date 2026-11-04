# 公开部署与本设计的对照

本设计的重点是低 DSP 占用、完整 7B/9B 部署和 PS/PL 交互协同。下表保留其他方案的模型、平台、量化及较高吞吐结果，用于说明各方案的目标和代价。跨模型数据可比较报告资源数量，不能据此推导同任务加速比或模型质量优劣。

## 最直接的嵌入式FPGA对照

| 方案 | 模型与平台 | 量化 / 运行条件 | DSP | LUT | BRAM36 / URAM | 解码 token/s |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 本设计 7B | Qwen2.5-7B / ZU19EG | W4A24；双 DDR；1 输入 / 64 输出 | 157 | 42,332 | 140 / 2 | 8.4136 |
| 本设计 9B | Qwen3.5-9B / ZU19EG | 混合主干；32K；250 MHz；展示结果 | 157 | 104,860 | 173.5 / 15 | 4.86 |
| Hummingbird 双核 | LLaMA3-8B / ZCU104 | W4、KV8；双 DDR；32 / 32 | 362 | 约 66,000 | 133 / 40 | 8.6 |
| Hummingbird 单核 | LLaMA3-8B / KV260 | W4、KV8；单 DDR；32 / 32 | 179 | 约 26,000 | 59 / 18 | 4.8 |
| Li 等 DATE 2025 | LLaMA2-7B / KV260 | W4；单 DDR；原文容量上限 1K | 291 | 约 78,000 | 36.5 / 10 | 4.9 |
| LlamaF | TinyLlama-1.1B / ZCU102 | W8A8；step=64 | 约 528 | 约 164,000 | 约 223 / 未列 | 1.478 |

来源：Hummingbird 原文表 V 与实验设置 [S1]；Li 原文表 I/II [S2]；LlamaF 原文表 III/VI [S3]。LlamaF 资源由原文器件总量与占比取近似值；Hummingbird 单 IP 的资源表不混作其双核整机结果。各论文的系统边界、负载和精度合同仍有差异。

### 能体现本设计优势的数字

相对 Hummingbird ZCU104，7B 主展示配置报告的 DSP 少 **56.63%**、LUT 少 **35.86%**、FF 少 **42.03%**、URAM 少 **95.00%**；输出速度数值为其 **97.83%**。BRAM36 为 140 对 133，增加 **5.26%**，一起列出。这里最清楚的结论是：以更少的乘法与逻辑资源达到接近量级的短上下文解码吞吐。

用“报告 DSP 数 / 报告 token/s”作描述性指标，本设计 7B 为 **18.66**，Hummingbird ZCU104 为 **42.09**，本设计数值低约 **55.67%**。该比值仍受模型、精度、带宽和负载影响，不是可跨平台通用的硬件效率证明。

相对 Hummingbird KV260，主展示配置 DSP 数少约 **12.29%**，但本设计使用双 DDR 且 LUT、BRAM 更大。因此这里强调共享阵列的 DSP 规模，不宣称在单 DDR、相同资源和相同模型下取得同样的速度优势。

相对 Li 等的 7B 部署，本设计主展示配置报告的 DSP 少约 **46.05%**，同时工程提供 Linux/视觉/会话扩展。对方在单 DDR 与 4GB 容量约束下的工作仍有独立价值，不能把双 DDR 优势说成纯算术优化收益。

相对 LlamaF，主展示配置 DSP 数少约 **70.27%**，运行的模型规模也更大。LlamaF 是较早的 TinyLlama、GQMV 加速路线；本设计可强调覆盖完整语言推理与混合架构，但不能由模型参数更多直接推导准确率更高。

## HBM和其他模型路线

| 方案 | 原文对象与条件 | 公开资源或性能 | 本设计可强调的差异 |
| --- | --- | --- | --- |
| FlightLLM [S4] | U280；LLaMA2-7B 等；混合精度和稀疏 | 表3：6345 DSP、574K LUT、1252 BRAM、792 URAM；U280 为实机，VHK158 为仿真 | 157 DSP、普通双 DDR，不依赖 HBM；绝对吞吐不宣称胜出 |
| EdgeLLM [S5] | VCU128 CPU-FPGA；混合 FP16×INT4/FP16、结构稀疏 | 原文为 HBM 异构加速与端到端映射 | 更小计算阵列、板载 PS 外设和网页应用；未从缺失原表补造资源数字 |
| LightMamba [S6] | VCK190；Mamba2-2.7B；W4A4 | 表4：228 DSP、107K LUT、912 BRAM、61 URAM、7.21 token/s | 主展示 7B/9B 均为 157 DSP；9B 适配全注意力与 GDN 混合结构 |
| TerEffic [S7] | U280；三值模型；片上或 HBM 辅助 | 表4：整机 3041 DSP；760K–781K LUT；矩阵核心用 LUT | 保留常规 7B/9B 量化部署路径和较小整体资源；不将其三值矩阵核心误写为整机零 DSP |
| FAST-Prefill [S8] | U280；Llama/Qwen；4K–128K；batch=1 | 目标为长上下文稀疏 prefill 与 TTFT | 本设计资料覆盖连续生成、PS 视觉与会话交互；prefill 与 decode 不混为速度排名 |

这些工作的并行度、存储带宽和目标模型均不同。FlightLLM、EdgeLLM 或三值方案的较高吞吐不应隐去；本设计的主张是以较少资源完成特定 7B/9B 嵌入式系统，而非超越所有云端加速器。

LightMamba 原文的 U280 93 token/s 为仿真结果，不写为实测上板结果。TerEffic 的不同模型规模、片上驻留和卡数决定吞吐，不与 7B/9B 直接排列“快多少”。

## Jetson与通用软件部署

| 已有本地记录 | 输出 token/s | 相对数值 |
| --- | ---: | ---: |
| 9B FPGA 展示结果 | 4.86 | 基准 |
| Jetson ChatLLM / Vulkan，64 输入、64 输出 | 3.94 | FPGA 数值高 23.35% |
| Jetson llama.cpp / Vulkan，64 输入、64 输出 | 4.44 | FPGA 数值高 9.46% |

这组结果来自原设计报告中的用户测试截图和确认值，代表指定软件配置。FPGA 展示值缺少完全相同负载的原始逐 token 记录，因此只保留数值对照，不写成严格加速比。

NVIDIA 官方 [Jetson AI Lab](https://www.jetson-ai-lab.com/archive/benchmarks.html)还列出 TensorRT-LLM、NanoLLM 等路线。Vulkan 测试结果不是 Jetson 性能上限；不能据此声称 FPGA 普遍超过优化 CUDA/TensorRT 实现，也不能在未测整板功耗时宣称能效或成本胜出。

| 路线 | 本项目的优势表达 | 对方同样具备或更强的部分 |
| --- | --- | --- |
| CPU、GPU 上的 llama.cpp / ChatLLM | 自定义整数计算与硬件状态路径、资源可量化、PS/PL 一体化 | 模型生态、跨平台移植、部分硬件上的更高绝对速度 |
| Ollama / 通用网页工作台 | 推理与 FPGA、PS 摄像头、SSD 状态的实际闭环 | 对话、文件、工具和视觉并非本项目独有 |
| 云端模型 API | 文字/图片推理可在本地完成，基础能力不依赖外网 | 云端模型规模、质量、并发与服务运维 |
| 单算子 FPGA 原型 | 本项目资料覆盖 PS 控制、状态恢复、网页、外设及现有板测 | 算子原型可有更强的特定内核性能，不能与完整请求速度混用 |

Agent 的 git clone 等联网动作仍需要网络；离线时本地推理、已有文件访问和可用外设功能按配置运行。“本地运行”不等于未经测量的隐私认证，也不等于所有功能不依赖网络。

## 对外展示建议

主标题强调“低资源完整部署”，主对照使用 Hummingbird ZCU104 与内部 INT24 联合优化。9B 强调混合主干、157 DSP、15 URAM、PS 视觉与状态恢复。Jetson 表保留软件条件，HBM 和三值路线放在完整技术对照中，既说明差异，也保留它们的长处。

可直接引用：“本设计用 157 个整机 DSP 完成 7B/9B 部署。7B 与 Hummingbird ZCU104 的公开数据并列时，DSP 数减少 56.63%，短上下文吞吐数值接近；在相同 DSP 的内部对照中，联合优化提升 64.35%。9B 进一步完成混合注意力、PS 视觉及 SSD 会话的系统集成。”

## 一手来源

- [S1 Hummingbird，表 IV–VI 与 V-A](https://arxiv.org/html/2507.03308v1)
- [S2 Pushing up to the Limit，表 I–II](https://arxiv.org/html/2502.10659v1)
- [S3 LlamaF，表 III 和 VI](https://arxiv.org/html/2409.11424v1)
- [S4 FlightLLM，表 3 与 6.1](https://arxiv.org/html/2401.03868v2)
- [S5 EdgeLLM，作者摘要与部署描述](https://arxiv.org/abs/2407.21325v2)
- [S6 LightMamba，表 IV 与 VI-B](https://arxiv.org/html/2502.15260v1)
- [S7 TerEffic，表 IV 与 V-B](https://arxiv.org/html/2502.16473v2)
- [S8 FAST-Prefill，作者摘要](https://arxiv.org/abs/2602.20515v1)

检索日期：2026-11-05。选定论文版本固定；本表不是全网穷尽排名。公开数据及计算式另存 [external_comparisons.json](../data/external_comparisons.json) 与 [derive_comparisons.py](../build/derive_comparisons.py)。
