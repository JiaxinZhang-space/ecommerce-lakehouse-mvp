Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$compose = @("compose", "-f", "$root/docker-compose.yml", "--profile", "tools")

Write-Host "Waiting for MySQL and Doris..."
docker @compose run --rm --entrypoint sh mysql-client -lc "until mysqladmin ping -hmysql -uroot -proot --silent; do sleep 3; done"
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "MySQL readiness check before synchronization"
docker @compose run --rm --entrypoint sh mysql-client -lc "until mysql -hdoris -P9030 -uroot -e 'select 1' >/dev/null 2>&1; do sleep 5; done"
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Doris readiness check before synchronization"

$odsGenerateSql = @"
SET SESSION group_concat_max_len = 1000000;
SELECT CONCAT(
    'TRUNCATE TABLE ods.ods_trade_order_event_offline; INSERT INTO ods.ods_trade_order_event_offline VALUES ',
    GROUP_CONCAT(
        CONCAT(
            '(',
            event_id, ',',
            order_id, ',',
            user_id, ',',
            sku_id, ',''',
            DATE_FORMAT(event_time, '%Y-%m-%d %H:%i:%s'), ''',''',
            DATE_FORMAT(dt, '%Y-%m-%d'), ''',',
            sku_num, ',',
            split_original_amount, ',',
            split_activity_amount, ',',
            split_coupon_amount, ',',
            split_total_amount, ',',
            is_refund,
            ')'
        )
        ORDER BY event_id
        SEPARATOR ','
    ),
    ';'
) AS load_sql
FROM trade_order_events;
"@

$dimGenerateSql = @"
SET SESSION group_concat_max_len = 1000000;
SELECT CONCAT(
    'TRUNCATE TABLE dim.dim_sku_info; INSERT INTO dim.dim_sku_info VALUES ',
    GROUP_CONCAT(
        CONCAT(
            '(',
            sku_id, ',''',
            REPLACE(sku_name, '''', ''''''), ''',''',
            REPLACE(category_name, '''', ''''''), ''',''',
            REPLACE(brand_name, '''', ''''''),
            ''')'
        )
        ORDER BY sku_id
        SEPARATOR ','
    ),
    ';'
) AS load_sql
FROM sku_info;
"@

$odsLoadSql = $odsGenerateSql | docker @compose run --rm -T mysql-client -hmysql -P3306 -uroot -proot --batch --raw --skip-column-names ecommerce_oltp
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "MySQL ODS extraction"
$dimLoadSql = $dimGenerateSql | docker @compose run --rm -T mysql-client -hmysql -P3306 -uroot -proot --batch --raw --skip-column-names ecommerce_oltp
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "MySQL DIM extraction"

@($odsLoadSql, $dimLoadSql) -join "`n" | docker @compose run --rm -T mysql-client -hdoris -P9030 -uroot
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "Doris ODS/DIM load"

Write-Host "Synced MySQL ecommerce_oltp -> Doris ODS/DIM."
