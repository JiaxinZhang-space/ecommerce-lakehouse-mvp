# 电商离线 + 实时双链路数仓（本地可复现 MVP）

这是一个本地可复现、可运行、可对账的作品集 MVP：同一组电商交易指标分别通过离线链路和实时链路产出，并在 Doris 中统一查询与验收。

## 项目定位与边界

- 离线链路：MySQL 模拟业务源，Doris 完成 `ODS -> DWD -> DWS -> ADS` 分层加工。
- 实时链路：确定性 Kafka 样例事件进入 Flink SQL，结果沉淀至 Paimon 分层并回写 Doris。
- 验收方式：按 `dt + recent_days` 对齐离线与实时 ADS，逐字段比较 5 个核心交易指标及派生客单价。
- 当前边界：未接入 CDC，未做生产级压测、SLA 或集群容灾验证，不将本地演示结果表述为生产性能。

## 来源与作品集改动

本仓库基于公开项目 [Mrkuhuo/data-warehouse-learning](https://github.com/Mrkuhuo/data-warehouse-learning) 做作品集化复现与增强，保留原始来源和 Artistic License 2.0。详细责任边界见 [NOTICE.md](NOTICE.md) 和 [CONTRIBUTIONS.md](CONTRIBUTIONS.md)。本地最小闭环重点补充：

- MySQL -> Doris 离线数仓链路；
- Kafka -> Flink SQL 逻辑分层、Paimon 多层结果物化与 Doris 实时 ADS；
- 统一指标合同、确定性样例数据与固定日期锚点下的 1 / 7 / 30 日统计范围对账；
- 环境检查、启停、初始化、运行与验收脚本。

实时侧使用一个 Flink Statement Set：DWD、DWS、ADS 通过临时视图形成逻辑加工链，Paimon ODS/DWD/DWS/ADS 作为同一作业的并行物化结果。当前版本不把它描述成逐层读取 Paimon 表的多作业链路。

## 技术栈

- 离线：Doris SQL，`ODS -> DWD -> DWS -> ADS`
- 业务源：MySQL 模拟电商业务库
- 实时：Kafka + Flink SQL，逻辑 `ODS -> DWD -> DWS -> ADS` 加工与 Paimon 并行物化
- 统一查询：Doris

## 本地要求

- Docker Desktop 已启动
- Docker Compose 可用
- 建议内存：16GB+
- 建议空闲磁盘：50GB+
- Doris 严格安装建议 `vm.max_map_count >= 2000000`；本地演示 Compose 使用 `SKIP_CHECK_ULIMIT=true`

本地演示已在较低值下跑通，但生产环境或严格环境验收仍应在管理员终端或 Docker Desktop WSL context 中执行：

```powershell
wsl -d docker-desktop -u root sysctl -w vm.max_map_count=2000000
```

## 启动服务

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-env.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

服务地址：

- Doris FE UI: <http://localhost:8030>
- Flink UI: <http://localhost:8081>

## 跑离线 Doris 链路

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\init-mysql.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\init-doris.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\sync-mysql-to-doris.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\run-offline-doris.ps1
```

MySQL 业务库：

- `ecommerce_oltp.trade_order_events`
- `ecommerce_oltp.sku_info`

离线链路会写入：

- `ods.ods_trade_order_event_offline`
- `dim.dim_sku_info`
- `dwd.dwd_trade_order_detail_inc`
- `dwd.dwd_trade_order_refund_inc`
- `dws.dws_trade_user_order_1d`
- `dws.dws_trade_user_order_nd`
- `dws.dws_trade_user_order_refund_1d`
- `dws.dws_trade_user_order_refund_nd`
- `ads.ads_trade_stats_offline`

## 跑实时 Flink + Paimon 链路

先创建 Kafka topic 并写入确定性样例事件：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\produce-kafka-events.ps1
```

再提交 Flink SQL 作业：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-realtime-paimon.ps1
```

实时链路会写入：

- Paimon: `paimon_catalog.ods.ods_trade_order_event`
- Paimon: `paimon_catalog.dwd.dwd_trade_order_detail_inc`
- Paimon: `paimon_catalog.dwd.dwd_trade_order_refund_inc`
- Paimon: `paimon_catalog.dws.dws_trade_day_window`
- Paimon: `paimon_catalog.ads.ads_trade_stats_realtime`
- Doris: `ads.ads_trade_stats_realtime`

## 对账

等待 Flink UI 中作业进入 `RUNNING`，并确认 Kafka 历史事件消费完成后执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\compare.ps1
```

预期 `compare_status` 全部为 `PASS`。

| recent_days | GMV | 订单数 | 下单用户数 | 退款订单数 | 退款用户数 | 客单价 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 505.50 | 5 | 4 | 2 | 2 | 101.10 |
| 7 | 1078.50 | 9 | 6 | 3 | 3 | 119.83 |
| 30 | 1578.50 | 10 | 7 | 4 | 4 | 157.85 |

## 清理

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\stop.ps1
```

如需清理数据卷：

```powershell
docker compose -f .\docker-compose.yml down -v --remove-orphans
```

## 当前状态

见 [verification-report.md](docs/verification-report.md)、[pitfall-log.md](docs/pitfall-log.md) 和 [walkthrough.md](docs/walkthrough.md)。

## 一键复现

下面命令会依次执行环境检查、双链路构建和自动对账；对账通过后还会校验当前作业确实包含预期的 6 个 sink，并要求 Flink 恰有 1 个 `RUNNING` 作业、9 个 tasks 全部处于 `RUNNING` 或正常 `FINISHED` 状态、最近 2 次 checkpoint 连续成功、基线后至少新完成 1 次 checkpoint、无执行异常且门禁观察期无新增 checkpoint 失败；最后验证 TaskManager Java 进程实际以 `9999:9999` 运行，再以该身份检查 5 个 Paimon bucket 可写，并确认每个 bucket 都有当前作业启动后生成的非空数据文件：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-demo.ps1 -Reset
```

运行态门禁也可以单独执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-flink-paimon.ps1
```

仓库结构和确定性样例数据可以单独做静态校验：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
```
