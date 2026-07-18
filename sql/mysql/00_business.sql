CREATE DATABASE IF NOT EXISTS ecommerce_oltp;
USE ecommerce_oltp;

DROP TABLE IF EXISTS trade_order_events;
DROP TABLE IF EXISTS sku_info;

CREATE TABLE sku_info (
    sku_id BIGINT PRIMARY KEY,
    sku_name VARCHAR(128) NOT NULL,
    category_name VARCHAR(64) NOT NULL,
    brand_name VARCHAR(64) NOT NULL,
    updated_at DATETIME NOT NULL
) ENGINE=InnoDB;

CREATE TABLE trade_order_events (
    event_id BIGINT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    sku_id BIGINT NOT NULL,
    event_time DATETIME NOT NULL,
    dt DATE NOT NULL,
    sku_num INT NOT NULL,
    split_original_amount DECIMAL(16, 2) NOT NULL,
    split_activity_amount DECIMAL(16, 2) NOT NULL,
    split_coupon_amount DECIMAL(16, 2) NOT NULL,
    split_total_amount DECIMAL(16, 2) NOT NULL,
    is_refund TINYINT NOT NULL,
    updated_at DATETIME NOT NULL,
    KEY idx_event_time (event_time),
    KEY idx_dt (dt),
    KEY idx_sku_id (sku_id)
) ENGINE=InnoDB;

INSERT INTO sku_info VALUES
(501, 'Coffee Maker A1', 'home_appliance', 'Northwind', '2026-07-01 00:00:00'),
(502, 'Running Shoes R2', 'sports', 'TrailPro', '2026-07-01 00:00:00'),
(503, 'Cotton T-Shirt C3', 'apparel', 'DailyWear', '2026-07-01 00:00:00'),
(504, 'Noise Cancel Headset H4', 'electronics', 'SoundMax', '2026-07-01 00:00:00'),
(505, 'Kids Building Blocks K5', 'toys', 'FunBox', '2026-07-01 00:00:00'),
(506, 'Office Chair O6', 'furniture', 'WorkWell', '2026-07-01 00:00:00'),
(507, 'Yoga Mat Y7', 'sports', 'TrailPro', '2026-07-01 00:00:00'),
(508, 'Desk Lamp D8', 'home_appliance', 'Northwind', '2026-07-01 00:00:00'),
(509, 'Backpack B9', 'apparel', 'DailyWear', '2026-07-01 00:00:00'),
(510, 'Tablet T10', 'electronics', 'SoundMax', '2026-07-01 00:00:00');

INSERT INTO trade_order_events VALUES
(1, 1001, 1, 501, '2026-07-01 09:10:00', '2026-07-01', 1, 120.00, 0.00, 0.00, 120.00, 0, '2026-07-01 09:10:05'),
(2, 1002, 2, 502, '2026-07-01 09:30:00', '2026-07-01', 1, 95.50, 10.00, 0.00, 85.50, 1, '2026-07-01 09:30:05'),
(3, 1003, 1, 503, '2026-07-01 10:05:00', '2026-07-01', 2, 50.00, 0.00, 10.00, 40.00, 0, '2026-07-01 10:05:05'),
(4, 1004, 3, 504, '2026-07-01 11:20:00', '2026-07-01', 1, 220.00, 20.00, 0.00, 200.00, 0, '2026-07-01 11:20:05'),
(5, 1005, 4, 505, '2026-07-01 14:50:00', '2026-07-01', 3, 75.00, 5.00, 10.00, 60.00, 1, '2026-07-01 14:50:05'),
(6, 1006, 2, 506, '2026-06-30 15:00:00', '2026-06-30', 1, 300.00, 0.00, 0.00, 300.00, 0, '2026-06-30 15:00:05'),
(7, 1007, 5, 507, '2026-06-30 16:30:00', '2026-06-30', 1, 55.00, 0.00, 10.00, 45.00, 1, '2026-06-30 16:30:05'),
(8, 1008, 6, 508, '2026-06-29 10:15:00', '2026-06-29', 1, 88.00, 10.00, 0.00, 78.00, 0, '2026-06-29 10:15:05'),
(9, 1009, 1, 509, '2026-06-29 12:40:00', '2026-06-29', 2, 160.00, 0.00, 10.00, 150.00, 0, '2026-06-29 12:40:05'),
(10, 1010, 7, 510, '2026-06-20 20:00:00', '2026-06-20', 1, 500.00, 0.00, 0.00, 500.00, 1, '2026-06-20 20:00:05');
