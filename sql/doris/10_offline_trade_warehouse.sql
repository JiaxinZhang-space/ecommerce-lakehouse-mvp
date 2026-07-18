DROP TABLE IF EXISTS dwd.dwd_trade_order_detail_inc;
CREATE TABLE dwd.dwd_trade_order_detail_inc
(
    order_id BIGINT,
    user_id BIGINT,
    sku_id BIGINT,
    sku_name VARCHAR(128),
    category_name VARCHAR(64),
    brand_name VARCHAR(64),
    k1 DATE,
    sku_num INT,
    split_original_amount DECIMAL(16, 2),
    split_activity_amount DECIMAL(16, 2),
    split_coupon_amount DECIMAL(16, 2),
    split_total_amount DECIMAL(16, 2)
)
ENGINE=OLAP
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 1
PROPERTIES ("replication_allocation" = "tag.location.default: 1");

INSERT INTO dwd.dwd_trade_order_detail_inc
SELECT
    o.order_id,
    o.user_id,
    o.sku_id,
    s.sku_name,
    s.category_name,
    s.brand_name,
    o.dt AS k1,
    o.sku_num,
    o.split_original_amount,
    o.split_activity_amount,
    o.split_coupon_amount,
    o.split_total_amount
FROM ods.ods_trade_order_event_offline o
LEFT JOIN dim.dim_sku_info s
ON o.sku_id = s.sku_id;

DROP TABLE IF EXISTS dwd.dwd_trade_order_refund_inc;
CREATE TABLE dwd.dwd_trade_order_refund_inc
(
    order_id BIGINT,
    user_id BIGINT,
    k1 DATE,
    refund_count BIGINT
)
ENGINE=OLAP
DUPLICATE KEY(order_id)
DISTRIBUTED BY HASH(order_id) BUCKETS 1
PROPERTIES ("replication_allocation" = "tag.location.default: 1");

INSERT INTO dwd.dwd_trade_order_refund_inc
SELECT
    order_id,
    user_id,
    dt AS k1,
    1 AS refund_count
FROM ods.ods_trade_order_event_offline
WHERE is_refund = 1;

DROP TABLE IF EXISTS dws.dws_trade_user_order_1d;
CREATE TABLE dws.dws_trade_user_order_1d
(
    user_id BIGINT,
    k1 DATE,
    order_count_1d BIGINT,
    order_num_1d BIGINT,
    order_original_amount_1d DECIMAL(16, 2),
    activity_reduce_amount_1d DECIMAL(16, 2),
    coupon_reduce_amount_1d DECIMAL(16, 2),
    order_total_amount_1d DECIMAL(16, 2)
)
ENGINE=OLAP
UNIQUE KEY(user_id, k1)
DISTRIBUTED BY HASH(user_id) BUCKETS 1
PROPERTIES ("replication_allocation" = "tag.location.default: 1");

INSERT INTO dws.dws_trade_user_order_1d
SELECT
    user_id,
    k1,
    COUNT(DISTINCT order_id) AS order_count_1d,
    SUM(sku_num) AS order_num_1d,
    SUM(split_original_amount) AS order_original_amount_1d,
    SUM(IFNULL(split_activity_amount, 0)) AS activity_reduce_amount_1d,
    SUM(IFNULL(split_coupon_amount, 0)) AS coupon_reduce_amount_1d,
    SUM(split_total_amount) AS order_total_amount_1d
FROM dwd.dwd_trade_order_detail_inc
GROUP BY user_id, k1;

DROP TABLE IF EXISTS dws.dws_trade_user_order_nd;
CREATE TABLE dws.dws_trade_user_order_nd
(
    user_id BIGINT,
    k1 DATE,
    order_count_7d BIGINT,
    order_total_amount_7d DECIMAL(16, 2),
    order_count_30d BIGINT,
    order_total_amount_30d DECIMAL(16, 2)
)
ENGINE=OLAP
UNIQUE KEY(user_id, k1)
DISTRIBUTED BY HASH(user_id) BUCKETS 1
PROPERTIES ("replication_allocation" = "tag.location.default: 1");

INSERT INTO dws.dws_trade_user_order_nd
SELECT
    user_id,
    DATE('2026-07-01') AS k1,
    SUM(IF(k1 BETWEEN DATE('2026-06-25') AND DATE('2026-07-01'), order_count_1d, 0)) AS order_count_7d,
    SUM(IF(k1 BETWEEN DATE('2026-06-25') AND DATE('2026-07-01'), order_total_amount_1d, 0)) AS order_total_amount_7d,
    SUM(IF(k1 BETWEEN DATE('2026-06-02') AND DATE('2026-07-01'), order_count_1d, 0)) AS order_count_30d,
    SUM(IF(k1 BETWEEN DATE('2026-06-02') AND DATE('2026-07-01'), order_total_amount_1d, 0)) AS order_total_amount_30d
FROM dws.dws_trade_user_order_1d
WHERE k1 BETWEEN DATE('2026-06-02') AND DATE('2026-07-01')
GROUP BY user_id;

DROP TABLE IF EXISTS dws.dws_trade_user_order_refund_1d;
CREATE TABLE dws.dws_trade_user_order_refund_1d
(
    user_id BIGINT,
    k1 DATE,
    order_refund_count_1d BIGINT
)
ENGINE=OLAP
UNIQUE KEY(user_id, k1)
DISTRIBUTED BY HASH(user_id) BUCKETS 1
PROPERTIES ("replication_allocation" = "tag.location.default: 1");

INSERT INTO dws.dws_trade_user_order_refund_1d
SELECT
    user_id,
    k1,
    COUNT(DISTINCT order_id) AS order_refund_count_1d
FROM dwd.dwd_trade_order_refund_inc
GROUP BY user_id, k1;

DROP TABLE IF EXISTS dws.dws_trade_user_order_refund_nd;
CREATE TABLE dws.dws_trade_user_order_refund_nd
(
    user_id BIGINT,
    k1 DATE,
    order_refund_count_7d BIGINT,
    order_refund_count_30d BIGINT
)
ENGINE=OLAP
UNIQUE KEY(user_id, k1)
DISTRIBUTED BY HASH(user_id) BUCKETS 1
PROPERTIES ("replication_allocation" = "tag.location.default: 1");

INSERT INTO dws.dws_trade_user_order_refund_nd
SELECT
    user_id,
    DATE('2026-07-01') AS k1,
    SUM(IF(k1 BETWEEN DATE('2026-06-25') AND DATE('2026-07-01'), order_refund_count_1d, 0)) AS order_refund_count_7d,
    SUM(IF(k1 BETWEEN DATE('2026-06-02') AND DATE('2026-07-01'), order_refund_count_1d, 0)) AS order_refund_count_30d
FROM dws.dws_trade_user_order_refund_1d
WHERE k1 BETWEEN DATE('2026-06-02') AND DATE('2026-07-01')
GROUP BY user_id;

DROP TABLE IF EXISTS ads.ads_trade_stats_offline;
CREATE TABLE ads.ads_trade_stats_offline
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

INSERT INTO ads.ads_trade_stats_offline
WITH order_1d AS (
    SELECT
        1 AS recent_days,
        SUM(order_total_amount_1d) AS order_total_amount,
        SUM(order_count_1d) AS order_count,
        SUM(IF(order_count_1d > 0, 1, 0)) AS order_user_count
    FROM dws.dws_trade_user_order_1d
    WHERE k1 = DATE('2026-07-01')
),
order_nd AS (
    SELECT
        recent_days,
        SUM(order_total_amount) AS order_total_amount,
        SUM(order_count) AS order_count,
        SUM(IF(order_count > 0, 1, 0)) AS order_user_count
    FROM (
        SELECT
            7 AS recent_days,
            order_total_amount_7d AS order_total_amount,
            order_count_7d AS order_count
        FROM dws.dws_trade_user_order_nd
        WHERE k1 = DATE('2026-07-01')
        UNION ALL
        SELECT
            30 AS recent_days,
            order_total_amount_30d AS order_total_amount,
            order_count_30d AS order_count
        FROM dws.dws_trade_user_order_nd
        WHERE k1 = DATE('2026-07-01')
    ) t
    GROUP BY recent_days
),
refund_1d AS (
    SELECT
        1 AS recent_days,
        IFNULL(SUM(order_refund_count_1d), 0) AS order_refund_count,
        SUM(IF(order_refund_count_1d > 0, 1, 0)) AS order_refund_user_count
    FROM dws.dws_trade_user_order_refund_1d
    WHERE k1 = DATE('2026-07-01')
),
refund_nd AS (
    SELECT
        recent_days,
        IFNULL(SUM(order_refund_count), 0) AS order_refund_count,
        SUM(IF(order_refund_count > 0, 1, 0)) AS order_refund_user_count
    FROM (
        SELECT
            7 AS recent_days,
            order_refund_count_7d AS order_refund_count
        FROM dws.dws_trade_user_order_refund_nd
        WHERE k1 = DATE('2026-07-01')
        UNION ALL
        SELECT
            30 AS recent_days,
            order_refund_count_30d AS order_refund_count
        FROM dws.dws_trade_user_order_refund_nd
        WHERE k1 = DATE('2026-07-01')
    ) t
    GROUP BY recent_days
),
orders AS (
    SELECT * FROM order_1d
    UNION ALL
    SELECT * FROM order_nd
),
refunds AS (
    SELECT * FROM refund_1d
    UNION ALL
    SELECT * FROM refund_nd
)
SELECT
    DATE('2026-07-01') AS dt,
    o.recent_days,
    o.order_total_amount,
    o.order_count,
    o.order_user_count,
    IFNULL(r.order_refund_count, 0) AS order_refund_count,
    IFNULL(r.order_refund_user_count, 0) AS order_refund_user_count,
    ROUND(o.order_total_amount / NULLIF(o.order_count, 0), 2) AS avg_order_amount,
    'doris_offline' AS source_system,
    NOW() AS updated_at
FROM orders o
LEFT JOIN refunds r
ON o.recent_days = r.recent_days;
