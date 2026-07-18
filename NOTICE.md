# 来源、基准与改动范围

## 上游来源

- 项目：[Mrkuhuo/data-warehouse-learning](https://github.com/Mrkuhuo/data-warehouse-learning)
- 本地复现采用的上游基准提交：`30de2340d76edbf6f0d59405573e9bfac89d4d3c`
- 上游许可证：Artistic License 2.0
- 许可证全文：见根目录 [LICENSE](LICENSE)

本仓库沿用了上游项目的电商领域背景、数仓分层思路和部分指标命名。它不包含上游完整教学仓库、无关模块或 Git 历史，也不把这些内容表述为个人原创。

## 本仓库新增与重组

- MySQL、Doris、Kafka、Flink 的本地 Docker Compose 环境
- 确定性交易样例和统一指标合同
- Doris 离线分层链路
- Flink SQL 逻辑加工、Paimon 多层结果并行物化和 Doris 实时 ADS
- 固定日期锚点下 1 / 7 / 30 日统计范围自动对账
- PowerShell 环境检查、初始化、运行、验收和清理脚本
- 可复现边界、技术取舍和问题记录

## 当前未覆盖

- MySQL CDC
- 基于 Window TVF 的事件时间窗口、迟到数据和乱序测试
- 生产级调度、权限、多租户、SLA、压测和容灾
- Hive Metastore、对象存储或分布式 Paimon Catalog

除文件中另有说明外，本仓库内容按根目录 `LICENSE` 分发。
