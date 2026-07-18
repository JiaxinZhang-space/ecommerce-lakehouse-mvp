Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $PSScriptRoot "native-command.ps1")
$composeFile = "$root/docker-compose.yml"
$compose = @("compose", "-f", $composeFile)
$toolsCompose = @("compose", "-f", $composeFile, "--profile", "tools")

docker @compose up -d mysql
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "MySQL container startup"

Write-Host "Waiting for MySQL business database on mysql:3306..."
docker @toolsCompose run --rm --entrypoint sh mysql-client -lc "until mysqladmin ping -hmysql -uroot -proot --silent; do sleep 3; done"
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "MySQL readiness check"

Get-Content "$root/sql/mysql/00_business.sql" -Raw | docker @toolsCompose run --rm -T mysql-client -hmysql -P3306 -uroot -proot
Assert-NativeCommandSucceeded -ExitCode $LASTEXITCODE -Operation "MySQL fixture initialization"

Write-Host "MySQL ecommerce_oltp business tables are ready."
