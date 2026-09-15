# ======================================
# Restore local Redis docker container from an already-downloaded RDB dump.
# Does NOT touch the dev server — just replays dump-dev.rdb from
# redis.backupFolder (see clone-redis-dev.ps1) into the local container. See
# redis/restore-redis-stg.ps1 for the staging counterpart -- both are thin
# wrappers around Invoke-TmsRedisRestore in Redis.psm1.
# Reads redis settings from tms.config.json — run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Redis.psm1") -Force

$config = Get-TmsConfig
Invoke-TmsRedisRestore -Config $config -Environment "dev"
