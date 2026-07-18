CREATE DATABASE IF NOT EXISTS ods;
CREATE DATABASE IF NOT EXISTS dwd;
CREATE DATABASE IF NOT EXISTS dim;
CREATE DATABASE IF NOT EXISTS dws;
CREATE DATABASE IF NOT EXISTS ads;

DROP TABLE IF EXISTS ods.ods_trade_order_event_offline;
CREATE TABLE ods.ods_trade_order_event_offline
(
    event_id BIGINT,
    order_id BIGINT,
    user_id BIGINT,
    sku_id BIGINT,
    event_time DATETIME,
    dt DATE,
    sku_num INT,
    split_original_amount DECIMAL(16, 2),
    split_activity_amount DECIMAL(16, 2),
    split_coupon_amount DECIMAL(16, 2),
    split_total_amount DECIMAL(16, 2),
    is_refund TINYINT
)
ENGINE=OLAP
DUPLICATE KEY(event_id)
DISTRIBUTED BY HASH(event_id) BUCKETS 1
PROPERTIES
(
    "replication_allocation" = "tag.location.default: 1"
);

DROP TABLE IF EXISTS dim.dim_sku_info;
CREATE TABLE dim.dim_sku_info
(
    sku_id BIGINT,
    sku_name VARCHAR(128),
    category_name VARCHAR(64),
    brand_name VARCHAR(64)
)
ENGINE=OLAP
UNIQUE KEY(sku_id)
DISTRIBUTED BY HASH(sku_id) BUCKETS 1
PROPERTIES
(
    "replication_allocation" = "tag.location.default: 1"
);
