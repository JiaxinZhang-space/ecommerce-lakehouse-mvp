SELECT
    o.dt,
    o.recent_days,
    o.order_total_amount AS offline_gmv,
    r.order_total_amount AS realtime_gmv,
    o.order_count AS offline_order_count,
    r.order_count AS realtime_order_count,
    o.order_user_count AS offline_user_count,
    r.order_user_count AS realtime_user_count,
    o.order_refund_count AS offline_refund_count,
    r.order_refund_count AS realtime_refund_count,
    o.order_refund_user_count AS offline_refund_user_count,
    r.order_refund_user_count AS realtime_refund_user_count,
    o.avg_order_amount AS offline_avg_order_amount,
    r.avg_order_amount AS realtime_avg_order_amount,
    CASE
        WHEN r.dt IS NULL THEN 'MISSING_REALTIME'
        WHEN o.order_total_amount = r.order_total_amount
         AND o.order_count = r.order_count
         AND o.order_user_count = r.order_user_count
         AND o.order_refund_count = r.order_refund_count
         AND o.order_refund_user_count = r.order_refund_user_count
         AND o.avg_order_amount = r.avg_order_amount
        THEN 'PASS'
        ELSE 'FAIL'
    END AS compare_status
FROM ads.ads_trade_stats_offline o
LEFT JOIN ads.ads_trade_stats_realtime r
ON o.dt = r.dt AND o.recent_days = r.recent_days
ORDER BY o.recent_days;
