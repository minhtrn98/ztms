# ======================================
# Restore local Redis docker container from an already-downloaded RDB dump.
# Does NOT touch the staging server — just replays dump-stg.rdb from
# redis.backupFolder (see clone-redis-stg.ps1) into the local container. See
# redis/restore-redis-dev.ps1 for the dev counterpart -- both are thin
# wrappers around Invoke-TmsRedisRestore in Redis.psm1.
# Reads redis settings from tms.config.json — run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Redis.psm1") -Force

$config = Get-TmsConfig
Invoke-TmsRedisRestore -Config $config -Environment "stg"
