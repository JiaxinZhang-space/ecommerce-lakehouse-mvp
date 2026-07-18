# 独立仓库复现报告

## 验证目标

- 从不包含上游 Git 历史的独立目录启动全部服务
- 跑通 Doris 离线链路
- 跑通 Flink SQL 逻辑加工、Paimon 多层结果物化和 Doris 实时 ADS
- 对固定日期锚点下 1 / 7 / 30 日统计范围的 5 个核心指标及客单价进行自动对账
- 确认仓库无临时 JAR、构建产物、空白 fixture 行或遗留嵌套路径

## 当前状态

独立目录的静态整理、技术问题修正、空数据卷完整复现与提交后 fresh-clone 复验均已完成，可以进入 `v1.0.0` 标签阶段；远端仓库尚未创建。

## 2026-07-18 实测结果

- 独立目录：`D:\Projects\story\tmp\ecommerce-lakehouse-warehouse-standalone-20260718`
- 最终 `run-demo.ps1 -Reset` 开始：`2026-07-18 16:22:40.169`
- 最终 `run-demo.ps1 -Reset` 完成：`2026-07-18 16:25:10.323`
- 总耗时：`150.155` 秒，进程退出码 `0`
- 对账在第 3 次单次快照查询时通过；前两次为实时 Sink 尚未就绪的预期重试
- Flink Job ID：`2309582f0b3a3aec33c026e7fb86a621`
- Flink REST：仅 1 个作业，状态 `RUNNING`，任务数 `9`
- Docker Compose：MySQL、Doris、Kafka、Flink JobManager、Flink TaskManager 均运行；MySQL 与 Doris 为 `healthy`
- fixture：10 条、无空行、字段完整、金额拆分恒等式与退款标志校验通过
- 对账：固定日期锚点下 1 / 7 / 30 日三个统计范围全部 `PASS`

构建供应链验证：

- 先执行 `docker compose build --no-cache`；
- Paimon、Flink Kafka Connector、Flink Shaded Hadoop、Doris Flink Connector 四个 JAR 均完成 SHA-256 校验并输出 `OK`；
- 随后的空卷复验使用该已校验镜像。

本机 `vm.max_map_count` 为 `262144`，低于 Doris 严格安装建议；本地 Compose 使用 `SKIP_CHECK_ULIMIT=true`，本轮仍成功跑通。生产环境或严格验收环境应调整为 `>= 2000000`。

## 提交后 fresh-clone 复验

- 被验证提交：`d0b6111be6da5bfc752b223f76a57ee504184415`
- 新 clone 目录：`D:\Projects\story\tmp\ecommerce-lakehouse-mvp-fresh-clone-20260718`
- 运行开始：`2026-07-18 16:27:58`
- 运行结束：`2026-07-18 16:30:18`
- 退出状态：后台进程正常退出，`run-demo.ps1` 输出 `End-to-end demo passed on attempt 2`
- Flink Job ID：`fad0fe7a3bb479f10fa227d5e94fd2ee`
- Flink REST：仅 1 个作业，状态 `RUNNING`，9 / 9 tasks 运行
- Git：fresh-clone 工作树保持干净

第 1 次单次快照查询发生在实时 Sink 完成前，三行均为 `MISSING_REALTIME`；脚本等待 5 秒后重新取得第 2 个完整快照，三行六项指标全部 `PASS`。每一轮的展示和判定均来自同一次查询，没有再出现双查询竞态。

## 预期指标

| recent_days | GMV | 订单数 | 下单用户数 | 退款订单数 | 退款用户数 | 客单价 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 505.50 | 5 | 4 | 2 | 2 | 101.10 |
| 7 | 1078.50 | 9 | 6 | 3 | 3 | 119.83 |
| 30 | 1578.50 | 10 | 7 | 4 | 4 | 157.85 |

最终单次快照对账：

```text
2026-07-01 recent_days=1  gmv=505.50/505.50   orders=5/5   users=4/4 refunds=2/2 refund_users=2/2 avg_order=101.10/101.10 status=PASS
2026-07-01 recent_days=7  gmv=1078.50/1078.50 orders=9/9   users=6/6 refunds=3/3 refund_users=3/3 avg_order=119.83/119.83 status=PASS
2026-07-01 recent_days=30 gmv=1578.50/1578.50 orders=10/10 users=7/7 refunds=4/4 refund_users=4/4 avg_order=157.85/157.85 status=PASS
```

## 验证命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-demo.ps1 -Reset
```
