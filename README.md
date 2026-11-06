# DSP复用低资源大模型部署

基于 AMD Zynq UltraScale+ ZU19EG，结合双 DDR 与共享计算，完成大模型本地推理及 PS/PL 交互。此版本的 9B 上下文为 **32K（32768）**。

| 模型 | 上下文 | 核心频率 | 整机 DSP | URAM | 输出速度 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Qwen2.5-7B | 4096 | 约 300.12 MHz | 157 | 2 | 8.4136 token/s |
| Qwen3.5-9B | 32768 | 250 MHz | 157 | 15 | 4.86 token/s |

输出速度为相应展示记录，容量与长上下文质量分别验证。跨模型及平台对比保留各自测试条件。

## 项目与对比

- [部署对比表](docs/comparisons.md)：保留 Hummingbird、Jetson 及其他公开部署路线的资源、性能和条件。
- [版本资源表](docs/versions.md)：单 DDR、双 DDR 与 9B 配置。
- [系统概述](docs/architecture.md)：PS、PL 与外设分工。
- [7B 概述](docs/qwen7b.md)与 [9B 概述](docs/qwen9b.md)。

## 工程入口

- [PL 与 IP](src/pl/README.md)：受保护核心及公开集成接口。
- [PS 程序](src/ps/README.md)：匹配可执行文件、通信及应用组件。
- [版本身份](data/version.json)：上下文、ABI 与文件哈希。
- [简化协作记录](report/ai_collaboration.md)及 [工作流](skill/README.md)。

在仓库根目录运行 `python build/check_package.py` 可核对文件。完整模型权重和板端依赖按相应运行配置准备。
