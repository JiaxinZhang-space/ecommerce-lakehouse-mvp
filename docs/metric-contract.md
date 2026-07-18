# 指标口径

业务日期锚点固定为 `2026-07-01`，用于确保离线链路和实时链路可以稳定对账。`recent_days` 表示该锚点下的 1 / 7 / 30 日统计范围，不代表 Flink Window TVF。

## 数据来源

离线链路：

- MySQL: `ecommerce_oltp.trade_order_events`
- MySQL: `ecommerce_oltp.sku_info`
- Doris: `ods.ods_trade_order_event_offline`
- Doris: `dim.dim_sku_info`
- Doris: `ads.ads_trade_stats_offline`

实时链路：

- Kafka: `trade_order_events`
- Paimon: `paimon_catalog.ods.ods_trade_order_event`
- Paimon: `paimon_catalog.dwd.dwd_trade_order_detail_inc`
- Paimon: `paimon_catalog.dws.dws_trade_day_window`
- Doris: `ads.ads_trade_stats_realtime`

## 核心 ADS 表

表：`ads.ads_trade_stats_offline`、`ads.ads_trade_stats_realtime`

粒度：`dt + recent_days`

周期：

- `recent_days = 1`：`2026-07-01`
- `recent_days = 7`：`2026-06-25` 到 `2026-07-01`
- `recent_days = 30`：`2026-06-02` 到 `2026-07-01`

## 字段口径

| 字段 | 口径 |
|---|---|
| `order_total_amount` | 统计范围内订单实付金额求和，即 GMV |
| `order_count` | 统计范围内去重订单数 |
| `order_user_count` | 统计范围内去重下单用户数 |
| `order_refund_count` | 统计范围内去重退款订单数 |
| `order_refund_user_count` | 统计范围内去重退款用户数 |
| `avg_order_amount` | `order_total_amount / order_count` |

## 预期结果

| recent_days | GMV | 订单数 | 下单用户数 | 退款订单数 | 退款用户数 | 客单价 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 505.50 | 5 | 4 | 2 | 2 | 101.10 |
| 7 | 1078.50 | 9 | 6 | 3 | 3 | 119.83 |
| 30 | 1578.50 | 10 | 7 | 4 | 4 | 157.85 |
