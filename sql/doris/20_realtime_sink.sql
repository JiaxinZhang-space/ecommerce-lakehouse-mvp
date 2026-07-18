DROP TABLE IF EXISTS ads.ads_trade_stats_realtime;
CREATE TABLE ads.ads_trade_stats_realtime
(
    dt DATE,
    recent_days BIGINT,
    order_total_amount DECIMAL(16, 2),
    order_count BIGINT,
    order_user_count BIGINT,
    order_refund_count BIGINT,
    order_refund_user_count BIGINT,
    avg_order_amount DECIMAL(16, 2),
    source_system VARCHAR(64),
    updated_at DATETIME
)
ENGINE=OLAP
UNIQUE KEY(dt, recent_days)
DISTRIBUTED BY HASH(dt) BUCKETS 1
PROPERTIES ("replication_allocation" = "tag.location.default: 1");
