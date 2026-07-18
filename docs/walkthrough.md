# 项目演示路线

## 目标

用 5 到 8 分钟展示同一组交易指标如何通过 Doris 离线链路和 Flink SQL 实时链路产出，并在 Doris 中统一对账。

## 建议顺序

1. 查看 [architecture.md](architecture.md)，确认离线链路、实时逻辑加工和 Paimon 并行物化边界。
2. 查看 `sql/mysql/00_business.sql` 与 `data/trade_order_events.jsonl`，确认两条链路使用同一组确定性数据。
3. 运行 Doris 离线 ODS/DWD/DWS/ADS。
4. 运行 Kafka + Flink SQL 作业，查看 Paimon 多层物化结果和 Doris 实时 ADS。
5. 执行 `scripts/compare.ps1`，确认固定日期锚点下的三个统计范围全部 `PASS`。
6. 查看 [pitfall-log.md](pitfall-log.md)，理解本地环境取舍和已知边界。

## 核心命令

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\run-demo.ps1 -Reset
```

## 讲解边界

- 当前实时侧是单个 Flink Statement Set：逻辑视图形成 DWD/DWS/ADS 加工链，Paimon 表是并行物化结果。
- 1 / 7 / 30 日指标是固定日期锚点下的统计范围聚合，不是 Window TVF 事件时间窗口。
- 当前输入为确定性 Kafka 样例事件，不是 MySQL CDC。
- 当前验证重点是指标合同和可复现闭环，不代表生产吞吐、延迟或 SLA。
