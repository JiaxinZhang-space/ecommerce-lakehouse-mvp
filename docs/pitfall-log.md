# 踩坑记录

## 2026-07-02 Docker Desktop WSL2 的 `vm.max_map_count`

- 问题场景：Doris BE 启动失败，日志提示 `Please set vm.max_map_count to be 2000000`。
- 排查过程：Doris all-in-one 容器中 BE 启动脚本会检查宿主内核参数；Docker Desktop 重启后该值可能恢复默认。
- 最终方案：

```powershell
wsl -d docker-desktop -u root sysctl -w vm.max_map_count=2000000
```

- 预防建议：每次 Docker Desktop 重启后先跑 `check-env.ps1`。

## 2026-07-02 Doris all-in-one FE meta 半初始化

- 问题场景：Doris 容器运行但 FE 长时间 `UNKNOWN/isReady:false`，BE 日志持续等待 FE heartbeat。
- 排查过程：查看 `/opt/apache-doris/fe/log/fe.log` 和 `doris-meta/image/ROLE`，确认 FE 进程存在但旧容器状态卡住。
- 最终方案：

```powershell
docker compose -f .\docker-compose.yml rm -sf doris
docker compose -f .\docker-compose.yml up -d doris
```

- 预防建议：本项目 Doris 不挂持久卷，首次初始化失败时直接重建容器，比在 FE meta 里手工修复更稳。

## 2026-07-02 Doris BE swap/ulimit 检查

- 问题场景：Doris BE 越过 `vm.max_map_count` 后又提示 `Please disable swap memory before installation`。
- 排查过程：阅读 `/opt/apache-doris/be/bin/start_be.sh`，发现 `SKIP_CHECK_ULIMIT=true` 会跳过本地演示环境不必要的安装前检查。
- 最终方案：在 `docker-compose.yml` 的 Doris 服务中加入：

```yaml
environment:
  SKIP_CHECK_ULIMIT: "true"
```

- 预防建议：作品集本地演示可以跳过该检查；生产环境仍应按 Doris 官方要求配置主机参数。

## 2026-07-02 Paimon 缺 Hadoop 类

- 问题场景：Flink SQL 创建 Paimon catalog 失败：`ClassNotFoundException: org.apache.hadoop.conf.Configuration`。
- 排查过程：Flink 基础镜像不包含 Hadoop runtime；Paimon filesystem catalog 会引用 Hadoop `Configuration`。
- 最终方案：在 Flink 镜像中加入：

```text
org.apache.flink:flink-shaded-hadoop-2-uber:2.8.3-10.0
```

- 预防建议：使用 Paimon filesystem/hive/object-store 方案时，提前确认 Flink classpath 中是否有 Hadoop 相关依赖。

## 2026-07-02 Paimon 本地 bucket 目录创建失败

- 问题场景：Flink checkpoint 时失败：`Mkdirs failed to create file:/warehouse/paimon/.../bucket-0`。
- 排查过程：容器内手动写入 `/warehouse/paimon` 正常，说明不是 Docker volume 权限问题；预创建 bucket 目录后作业可继续。
- 最终方案：在 `start-realtime-paimon.ps1` 中提交 SQL 前预创建 Paimon bucket 目录。
- 预防建议：本地 filesystem catalog 用于演示时，初始化目录可以显式创建，生产环境建议使用更稳定的分布式存储。

## 2026-07-02 Flink JDBC sink 与 Doris MySQL 协议不兼容

- 问题场景：Flink JDBC sink 带主键时生成 MySQL `ON DUPLICATE KEY UPDATE`，Doris 返回语法错误。
- 排查过程：无主键 sink 又不能接收更新流；该链路不适合用通用 JDBC sink 写 Doris 聚合更新结果。
- 最终方案：改用 Apache Doris Flink Connector，通过 Stream Load 写入 Doris：

```sql
WITH (
    'connector' = 'doris',
    'fenodes' = 'doris:8030',
    'benodes' = 'doris:8040',
    'table.identifier' = 'ads.ads_trade_stats_realtime'
)
```

- 预防建议：Doris 实时写入优先选 Doris 官方 connector，不用把 Doris 当普通 MySQL sink。

## 2026-07-02 Docker build 网络抖动

- 问题场景：构建 Flink 镜像时 Maven jar 下载中途 EOF 或超时。
- 排查过程：网络失败发生在大 jar 下载阶段，单个 `RUN` 串行下载会导致整层重来。
- 最终方案：Dockerfile 中每个 connector 独立 `RUN curl --retry ...`，提高缓存命中率，失败后只重试失败层。
- 预防建议：本地作品集项目下载大依赖时拆分 Docker layer，并优先使用 `repo.maven.apache.org`。

## 2026-07-02 Kafka 样例事件重复生产导致指标翻倍

- 问题场景：实时链路的 `SUM(split_total_amount)` 是基于 Kafka 事件流计算的，如果多次向同一个 topic 追加同一批样例事件，GMV 会被重复累加。
- 排查过程：离线链路来自 MySQL 确定性表，实时链路来自 Kafka topic；两者要对账，实时 topic 也必须是确定性输入。
- 最终方案：`produce-kafka-events.ps1` 先删除并重建 `trade_order_events` topic，再写入样例 JSONL。
- 预防建议：本地演示用的 Kafka topic 要么每次重置，要么事件必须设计成可去重并在 DWD 层显式去重。

## 2026-07-18 独立拆仓前的真实性审计

- 问题场景：原文档把单个 Statement Set 的多层结果并行物化写成了 Paimon ODS 到 ADS 的逐层读取链路；fixture 有空白行并启用了 JSON 静默吞错；退款数按事件行累加；对账没有校验客单价。
- 排查过程：逐项比对 Flink SQL、Doris SQL、JSONL、架构文档和对账脚本，并在独立目录执行静态检查。
- 最终方案：明确“逻辑视图链 + Paimon 并行物化”；删除无效 Watermark，关闭 JSON 静默吞错，把非空约束策略从 `DROP` 改为 `ERROR` 并增加 fixture 校验；退款订单数按 `order_id` 去重；对账补充退款用户数和客单价两侧明细及失败退出码。
- 预防建议：公开页面中的每一条链路箭头、指标名称和 PASS 字段都必须能在 SQL 中找到直接对应；本地演示边界与生产能力分开描述。

## 2026-07-18 Doris 冷启动时 FE 先于 BE 可用

- 问题场景：从空数据卷启动后，Doris 的 MySQL 协议已经能执行 `SELECT 1`，但首个建表语句失败：`ERROR 1105 (HY000) at line 8: replication num is 1, available backend num is 0`。旧脚本未检查原生命令退出码，仍输出“tables are ready”并返回 0。
- 排查过程：稳定运行 11 分钟的容器可以执行同一份初始化和离线 SQL，并正确产出三行离线 ADS；随后在 2026-07-18 15:58:28 从 `docker compose down -v` 开始冷启动，15:58:48 提交初始化，复现出 FE 可查询但 BE 尚未注册为 `Alive=true` 的时序窗口。
- 最终方案：`init-doris.ps1` 同时等待 FE 协议和 `SHOW BACKENDS` 中至少一个 `Alive=true` 后再执行 DDL；所有调用 Docker/MySQL/Flink/Kafka 的 PowerShell 脚本在每次原生命令后立即检查 `$LASTEXITCODE`，失败时抛出包含操作名称和退出码的异常。
- 预防建议：服务端口或简单查询可用不等于存储节点已具备建表条件；冷启动验收必须从空卷运行，且自动化脚本不得用成功提示覆盖非零退出码。

## 2026-07-18 对账展示与判定使用了不同快照

- 问题场景：旧 `compare.ps1` 先执行一次表格查询用于展示，再执行第二次机器可读查询用于判定；实时 Sink 恰好在两次查询之间完成写入时，屏幕显示 `MISSING_REALTIME`，脚本却返回全部通过。
- 排查过程：在首次完整复验的第 3 次轮询中稳定捕获到“展示仍缺实时数据、紧接着判定通过”的矛盾输出。
- 最终方案：只执行一次 `--batch --raw --skip-column-names` 查询，将同一批行解析成结构化对象；同一快照同时负责逐指标输出和 PASS/FAIL 判定。
- 预防建议：自动验收中的展示、判定和归档必须来自同一次查询快照，尤其不能在异步 Sink 正在收敛时重复查询后混用结果。
