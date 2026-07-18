# 独立仓库复现报告

## 验证目标

- 从不包含上游 Git 历史的独立目录启动全部服务；
- 跑通 Doris 离线物理分层；
- 跑通 Flink SQL 逻辑加工、Paimon 多层结果物化和 Doris 实时 ADS；
- 对固定日期锚点下 1 / 7 / 30 日统计范围的六项指标进行自动对账；
- 同时验证 Flink 作业状态、checkpoint 稳定性和五张 Paimon 表真实落盘；
- 确认仓库无临时 JAR、构建产物、空白 fixture 行或遗留嵌套路径。

## 当前状态

独立目录已完成静态校验、空卷运行、权限修复和运行态门禁验证。修复后的完整提交仍需再从全新 clone 执行一次 `run-demo.ps1 -Reset`；本报告不会把修复前只有 Doris 对账通过的结果写成最终成功。

远端发布状态以 GitHub 仓库为准。

## 已作废的早期验收

提交 `d0b6111be6da5bfc752b223f76a57ee504184415` 曾在独立目录和第一次 fresh clone 中得到：

- Doris offline/realtime ADS 三个统计范围全部 `PASS`；
- Flink REST 短时显示 1 个 `RUNNING` 作业和 9 个 tasks。

后续持续观察发现，该作业实际累计 315 次失败 checkpoint，根因是 Paimon bucket 由 root 创建为 `root:root 755`，而 TaskManager 进程以 `9999:9999` 运行。Doris sink 先写出正确结果掩盖了 Paimon sink 的权限失败。

因此，上述两次记录只能证明业务对账曾短时通过，**不能证明 Flink/Paimon 链路稳定，已从最终验收中作废。**

## 2026-07-18 运行态门禁加固

- `start-realtime-paimon.ps1` 先以 root 初始化 Paimon 目录并 `chown -R 9999:9999`，再以 `9999:9999` 提交 SQL。
- `verify-flink-paimon.ps1` 要求：
  - 恰有 1 个活动中的 `RUNNING` 作业；
  - 作业名包含本项目 5 个 Paimon sink 和 1 个 Doris sink；
  - 共 9 个 tasks，`RUNNING + FINISHED = 9`，异常 task 数为 0；
  - 最近至少 2 次 checkpoint 连续 `COMPLETED`；
  - 记录门禁基线后，至少新完成 1 次 checkpoint；
  - `latest.failed`、root exception、`all-exceptions` 与 exception history 均为空；
  - 门禁观察期 checkpoint failed 计数不增长；
  - 先验证 TaskManager Java 进程实际 UID/GID 为 `9999:9999`，再以该身份对 5 个 Paimon bucket 做真实写入探测；
  - 每个 bucket 至少有一个当前作业启动后生成的非空 `data-*` 文件，旧 volume 中的遗留文件不能代替本轮证据。
- `run-demo.ps1` 只有在 Doris 对账和上述运行态门禁都通过后才返回成功。

Flink 在全部 tasks 就绪前可能出现一次 `Not all required tasks are currently running` 的启动期 trigger failure；它不带 root exception，之后 checkpoint 可连续完成。因此门禁不把生命周期累计失败数机械限定为 0，而是检查最近成功序列、执行异常和观察期新增失败。

## 修复后独立目录实测

- 目录：`D:\Projects\story\tmp\ecommerce-lakehouse-warehouse-standalone-20260718`
- Flink Job ID：`36ff2365d52e431144c24daaf023cfab`
- 作业状态：`RUNNING`
- task 状态：8 个 `RUNNING`，1 个 bounded Values source 正常 `FINISHED`，总计 9 个
- 门禁通过时 completed checkpoint：92
- 启动期失败基线：1；门禁观察期新增失败：0
- root execution exception：无
- Paimon：5 / 5 bucket 可写且均存在由 `flink:flink` 创建的 `data-*` ORC 文件
- Doris：固定 1 / 7 / 30 日统计范围六项指标全部 `PASS`

本轮从空卷启动后，旧版严格门禁因把启动期 trigger failure 计入生命周期失败而主动退出；调整为上述判定语义后，针对同一稳定作业单独执行新门禁并通过。最终发布前仍需由全新 clone 对完整一键脚本进行一次端到端复验。

## 构建供应链验证

- 已执行 `docker compose build --no-cache`；
- Paimon、Flink Kafka Connector、Flink Shaded Hadoop、Doris Flink Connector 四个 JAR 均完成 SHA-256 校验并输出 `OK`；
- 16 个 PowerShell 脚本通过 AST 解析；
- `validate-repo.ps1` 和 `docker compose config --quiet` 通过；
- fixture 为 10 条确定性 JSONL，无空行，字段完整，金额恒等式和退款标志校验通过；
- 仓库无临时 JAR、`.tmp`、`target`、`.env` 或备份 README。

本机 `vm.max_map_count` 为 `262144`，低于 Doris 严格安装建议；本地 Compose 使用 `SKIP_CHECK_ULIMIT=true`。生产环境或严格验收环境应调整为 `>= 2000000`。

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
