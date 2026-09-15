# ======================================
# Sync Redis cache from staging to local docker container. See
# redis/clone-redis-dev.ps1 for the dev counterpart -- both are thin
# wrappers around Invoke-TmsRedisClone in Redis.psm1.
# Reads redis settings from tms.config.json — run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Redis.psm1") -Force

$config = Get-TmsConfig
Invoke-TmsRedisClone -Config $config -Environment "stg"
