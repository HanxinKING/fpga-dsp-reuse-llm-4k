# RTL文件入口

- [32K 顶层 Verilog](q9_32k/hdl/q9_accelerator_ip.v)
- [32K SystemVerilog 接口测试](q9_32k/tests/tb_q9_ip.sv)
- [32K 受保护核心](q9_32k/hdl/q9_core.vp)
- [历史4K顶层](q9_4k/hdl/q9_accelerator_4k_ip.v)
- [历史4K连接封装](q9_4k/hdl/q9_accelerator_4k_impl.sv)

当前 9B 采用 32K 配置。核心文件保持原保护，顶层和连接接口供集成使用。展开文件与已验证 IP 的相应成员内容一致；IP-XACT 引用的接口文档可在原 ZIP 中查看。
