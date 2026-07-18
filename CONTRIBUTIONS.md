# 作品集改动与责任边界

## 本仓库重点实现

- 使用 Docker Compose 组织 MySQL、Doris、Kafka 与 Flink 本地运行环境
- 实现 `MySQL -> Doris ODS/DIM/DWD/DWS/ADS` 离线链路
- 实现 Kafka + Flink SQL 实时侧的逻辑 `ODS/DWD/DWS/ADS` 加工、Paimon 并行物化与 Doris ADS 写入
- 用确定性样例数据统一离线、实时口径
- 对固定日期锚点下 1 / 7 / 30 日统计范围的 5 个核心指标及客单价做自动对账
- 提供环境检查、初始化、运行、验收和清理脚本
- 记录本地复现边界、工程取舍与踩坑过程

## 不作出的声明

- 不声称独立原创上游教学项目或其完整代码
- 不把本地样例项目表述为生产级电商数仓
- 不声称已接入 MySQL CDC、生产调度平台或分布式对象存储
- 不提供未经压测支持的吞吐、延迟、SLA 或资源规模数字

更多来源说明见 [NOTICE.md](NOTICE.md)。
