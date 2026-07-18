SET 'execution.runtime-mode' = 'streaming';
SET 'execution.checkpointing.interval' = '10s';
SET 'execution.attached' = 'false';
SET 'table.local-time-zone' = 'Asia/Shanghai';
SET 'table.exec.sink.not-null-enforcer' = 'ERROR';

CREATE CATALOG paimon_catalog WITH (
    'type' = 'paimon',
    'warehouse' = 'file:/warehouse/paimon'
);

CREATE TEMPORARY TABLE kafka_trade_order_events (
    event_id BIGINT,
    order_id BIGINT,
    user_id BIGINT,
    sku_id BIGINT,
    event_time TIMESTAMP(3),
    dt STRING,
    sku_num INT,
    split_original_amount DECIMAL(16, 2),
    split_activity_amount DECIMAL(16, 2),
    split_coupon_amount DECIMAL(16, 2),
    split_total_amount DECIMAL(16, 2),
    is_refund INT
) WITH (
    'connector' = 'kafka',
    'topic' = 'trade_order_events',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'ecommerce-paimon-trade-stats-v2',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'json',
    'json.ignore-parse-errors' = 'false'
);

CREATE TEMPORARY VIEW recent_days_dim AS
SELECT 1 AS recent_days
UNION ALL
SELECT 7 AS recent_days
UNION ALL
SELECT 30 AS recent_days;

CREATE DATABASE IF NOT EXISTS paimon_catalog.ods;
CREATE DATABASE IF NOT EXISTS paimon_catalog.dwd;
CREATE DATABASE IF NOT EXISTS paimon_catalog.dws;
CREATE DATABASE IF NOT EXISTS paimon_catalog.ads;

CREATE TABLE IF NOT EXISTS paimon_catalog.ods.ods_trade_order_event (
    event_id BIGINT,
    order_id BIGINT,
    user_id BIGINT,
    sku_id BIGINT,
    event_time TIMESTAMP(3),
    dt STRING,
    sku_num INT,
    split_original_amount DECIMAL(16, 2),
    split_activity_amount DECIMAL(16, 2),
    split_coupon_amount DECIMAL(16, 2),
    split_total_amount DECIMAL(16, 2),
    is_refund INT,
    PRIMARY KEY (event_id) NOT ENFORCED
) WITH (
    'bucket' = '1',
    'changelog-producer' = 'input'
);

CREATE TABLE IF NOT EXISTS paimon_catalog.dwd.dwd_trade_order_detail_inc (
    event_id BIGINT,
    order_id BIGINT,
    user_id BIGINT,
    sku_id BIGINT,
    event_time TIMESTAMP(3),
    dt STRING,
    sku_num INT,
    split_original_amount DECIMAL(16, 2),
    split_activity_amount DECIMAL(16, 2),
    split_coupon_amount DECIMAL(16, 2),
    split_total_amount DECIMAL(16, 2),
    is_refund INT,
    PRIMARY KEY (event_id) NOT ENFORCED
) WITH (
    'bucket' = '1',
    'changelog-producer' = 'input'
);

CREATE TABLE IF NOT EXISTS paimon_catalog.dwd.dwd_trade_order_refund_inc (
    event_id BIGINT,
    order_id BIGINT,
    user_id BIGINT,
    event_time TIMESTAMP(3),
    dt STRING,
    refund_count BIGINT,
    PRIMARY KEY (event_id) NOT ENFORCED
) WITH (
    'bucket' = '1',
    'changelog-producer' = 'input'
);

CREATE TABLE IF NOT EXISTS paimon_catalog.dws.dws_trade_day_window (
    dt STRING,
    recent_days BIGINT,
    order_total_amount DECIMAL(16, 2),
    order_count BIGINT,
    order_user_count BIGINT,
    order_refund_count BIGINT,
    order_refund_user_count BIGINT,
    avg_order_amount DECIMAL(16, 2),
    PRIMARY KEY (dt, recent_days) NOT ENFORCED
) WITH (
    'bucket' = '1',
    'changelog-producer' = 'lookup'
);

CREATE TABLE IF NOT EXISTS paimon_catalog.ads.ads_trade_stats_realtime (
    dt STRING,
    recent_days BIGINT,
    order_total_amount DECIMAL(16, 2),
    order_count BIGINT,
    order_user_count BIGINT,
    order_refund_count BIGINT,
    order_refund_user_count BIGINT,
    avg_order_amount DECIMAL(16, 2),
    source_system STRING,
    updated_at TIMESTAMP(3),
    PRIMARY KEY (dt, recent_days) NOT ENFORCED
) WITH (
    'bucket' = '1',
    'changelog-producer' = 'lookup'
);

CREATE TEMPORARY TABLE doris_ads_trade_stats_realtime (
    dt DATE,
    recent_days BIGINT,
    order_total_amount DECIMAL(16, 2),
    order_count BIGINT,
    order_user_count BIGINT,
    order_refund_count BIGINT,
    order_refund_user_count BIGINT,
    avg_order_amount DECIMAL(16, 2),
    source_system STRING,
    updated_at TIMESTAMP(3),
    PRIMARY KEY (dt, recent_days) NOT ENFORCED
) WITH (
    'connector' = 'doris',
    'fenodes' = 'doris:8030',
    'benodes' = 'doris:8040',
    'auto-redirect' = 'false',
    'table.identifier' = 'ads.ads_trade_stats_realtime',
    'username' = 'root',
    'password' = '',
    'sink.label-prefix' = 'trade_stats_realtime',
    'sink.properties.format' = 'json',
    'sink.properties.read_json_by_line' = 'true'
);

CREATE TEMPORARY VIEW dwd_trade_order_detail_rt AS
SELECT
    event_id,
    order_id,
    user_id,
    sku_id,
    event_time,
    dt,
    sku_num,
    split_original_amount,
    split_activity_amount,
    split_coupon_amount,
    split_total_amount,
    is_refund
FROM kafka_trade_order_events;

CREATE TEMPORARY VIEW dwd_trade_order_refund_rt AS
SELECT
    event_id,
    order_id,
    user_id,
    event_time,
    dt,
    CAST(1 AS BIGINT) AS refund_count
FROM dwd_trade_order_detail_rt
WHERE is_refund = 1;

CREATE TEMPORARY VIEW dws_trade_day_window_rt AS
SELECT
    CAST('2026-07-01' AS STRING) AS dt,
    CAST(r.recent_days AS BIGINT) AS recent_days,
    CAST(SUM(e.split_total_amount) AS DECIMAL(16, 2)) AS order_total_amount,
    CAST(COUNT(DISTINCT e.order_id) AS BIGINT) AS order_count,
    CAST(COUNT(DISTINCT e.user_id) AS BIGINT) AS order_user_count,
    CAST(COUNT(DISTINCT CASE WHEN e.is_refund = 1 THEN e.order_id ELSE NULL END) AS BIGINT) AS order_refund_count,
    CAST(COUNT(DISTINCT CASE WHEN e.is_refund = 1 THEN e.user_id ELSE NULL END) AS BIGINT) AS order_refund_user_count,
    CAST(ROUND(SUM(e.split_total_amount) / COUNT(DISTINCT e.order_id), 2) AS DECIMAL(16, 2)) AS avg_order_amount
FROM dwd_trade_order_detail_rt e
JOIN recent_days_dim r
ON (
    (r.recent_days = 1 AND e.dt = '2026-07-01')
    OR (r.recent_days = 7 AND e.dt BETWEEN '2026-06-25' AND '2026-07-01')
    OR (r.recent_days = 30 AND e.dt BETWEEN '2026-06-02' AND '2026-07-01')
)
GROUP BY r.recent_days;

CREATE TEMPORARY VIEW ads_trade_stats_realtime_rt AS
SELECT
    dt,
    recent_days,
    order_total_amount,
    order_count,
    order_user_count,
    order_refund_count,
    order_refund_user_count,
    avg_order_amount,
    CAST('flink_paimon_realtime' AS STRING) AS source_system,
    LOCALTIMESTAMP AS updated_at
FROM dws_trade_day_window_rt;

BEGIN STATEMENT SET;

INSERT INTO paimon_catalog.ods.ods_trade_order_event
SELECT
    event_id,
    order_id,
    user_id,
    sku_id,
    event_time,
    dt,
    sku_num,
    split_original_amount,
    split_activity_amount,
    split_coupon_amount,
    split_total_amount,
    is_refund
FROM kafka_trade_order_events;

INSERT INTO paimon_catalog.dwd.dwd_trade_order_detail_inc
SELECT
    event_id,
    order_id,
    user_id,
    sku_id,
    event_time,
    dt,
    sku_num,
    split_original_amount,
    split_activity_amount,
    split_coupon_amount,
    split_total_amount,
    is_refund
FROM dwd_trade_order_detail_rt;

INSERT INTO paimon_catalog.dwd.dwd_trade_order_refund_inc
SELECT
    event_id,
    order_id,
    user_id,
    event_time,
    dt,
    refund_count
FROM dwd_trade_order_refund_rt;

INSERT INTO paimon_catalog.dws.dws_trade_day_window
SELECT
    dt,
    recent_days,
    order_total_amount,
    order_count,
    order_user_count,
    order_refund_count,
    order_refund_user_count,
    avg_order_amount
FROM dws_trade_day_window_rt;

INSERT INTO paimon_catalog.ads.ads_trade_stats_realtime
SELECT
    dt,
    recent_days,
    order_total_amount,
    order_count,
    order_user_count,
    order_refund_count,
    order_refund_user_count,
    avg_order_amount,
    source_system,
    updated_at
FROM ads_trade_stats_realtime_rt;

INSERT INTO doris_ads_trade_stats_realtime
SELECT
    CAST(dt AS DATE),
    recent_days,
    order_total_amount,
    order_count,
    order_user_count,
    order_refund_count,
    order_refund_user_count,
    avg_order_amount,
    source_system,
    updated_at
FROM ads_trade_stats_realtime_rt;

END;
