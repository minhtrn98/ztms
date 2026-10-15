# ======================================
# Set the GPS location of a running Android emulator (`adb emu geo fix`).
# One prompt, two ways in:
#   - "lat,lng" (the order Google Maps copies coordinates in) — swapped for
#     geo fix, which wants longitude FIRST;
#   - anything else is a post office search by PostOfficeCode / name in the
#     local RouteDB (android.postOfficeDb, default "RouteDB"), using
#     database.localHost/localUser/localPasswordEnvVar — pick one from the
#     list and its Latitude/Longitude are used.
# The last location is remembered in .android-last-location (gitignored) so
# Enter re-applies it. Picks the running emulator automatically if only one.
# Reads android.emulatorPath from tms.config.json -- run setup\init-config.ps1 first.
# ======================================

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\ProjectMenu.psm1") -Force
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "modules\Android.psm1") -Force

$config = Get-TmsConfig
$null = Get-TmsAndroidEmulatorExe -Config $config   # guard: android.emulatorPath configured
$adbExe = Get-TmsAndroidAdbExe -Config $config
$device = Select-TmsRunningAndroidDevice -AdbExe $adbExe -Prompt "Select an emulator to move"

$inv = [Globalization.CultureInfo]::InvariantCulture

function ConvertTo-SearchText {
    # Lowercase + strip Vietnamese diacritics, matching how PostOffices.SearchValue
    # is stored ("xmc xuyen moc") — keeps the SQL ASCII-only too.
    param([string]$Text)
    $decomposed = $Text.ToLowerInvariant().Replace('đ', 'd').Normalize([Text.NormalizationForm]::FormD)
    -join ($decomposed.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
}

function Find-PostOffice {
    # Returns @{ Lat; Lng; Label } for the picked post office, or $null.
    param([string]$Term)

    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        Write-Host "psql not found on PATH — post office search needs the Postgres client. Enter lat,lng instead." -ForegroundColor Yellow
        return $null
    }
    $db = $config.database
    $dbName = if ($config.android.postOfficeDb) { $config.android.postOfficeDb } else { "RouteDB" }
    $password = Get-TmsSecret -EnvVarName $db.localPasswordEnvVar -PromptMessage "Enter local Postgres password" -Default "postgres"

    $needle = (ConvertTo-SearchText $Term).Trim().Replace("'", "''")
    $sql = @"
select "PostOfficeCode", "PostOfficeName", "Latitude", "Longitude"
from "PostOffices"
where not "IsDeleted"
  and "Latitude" is not null and "Longitude" is not null and ("Latitude" <> 0 or "Longitude" <> 0)
  and ("SearchValue" ilike '%$needle%' or "PostOfficeCode" ilike '%$needle%')
order by lower("PostOfficeCode") = '$needle' desc, "PostOfficeCode" ilike '$needle%' desc, "IsActive" desc, "PostOfficeName"
limit 30;
"@

    $savedEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $env:PGPASSWORD = $password
        $env:PGCLIENTENCODING = "UTF8"
        $rows = & psql -h $db.localHost -U $db.localUser -d $dbName -At -F "`t" -c $sql 2>&1
        $failed = $LASTEXITCODE -ne 0
    } finally {
        [Console]::OutputEncoding = $savedEncoding
        $env:PGPASSWORD = $null
    }
    if ($failed) {
        Write-Host "Post office search failed: $($rows -join ' ')" -ForegroundColor Red
        return $null
    }

    $offices = @($rows | Where-Object { $_ } | ForEach-Object {
        $c = "$_" -split "`t"
        [PSCustomObject]@{ Code = $c[0]; Name = $c[1]; Lat = [double]::Parse($c[2], $inv); Lng = [double]::Parse($c[3], $inv) }
    })
    if ($offices.Count -eq 0) {
        Write-Host "No post office with coordinates matches '$Term'." -ForegroundColor Yellow
        return $null
    }

    $picked = if ($offices.Count -eq 1) { $offices[0] } else {
        $labels = @($offices | ForEach-Object { "{0,-10} {1,-32} ({2}, {3})" -f $_.Code, $_.Name, $_.Lat.ToString($inv), $_.Lng.ToString($inv) })
        if ($offices.Count -eq 30) { Write-Host "Showing the first 30 matches — type more to narrow it down." -ForegroundColor DarkGray }
        $index = Show-Menu -Labels $labels -Prompt "Pick a post office"
        if ($index -eq -1) { return $null }
        $offices[$index]
    }
    return @{ Lat = $picked.Lat; Lng = $picked.Lng; Label = "$($picked.Code) - $($picked.Name)" }
}

$stateFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".android-last-location"
$last = if (Test-Path $stateFile) { (Get-Content $stateFile -Raw -Encoding UTF8).Trim() }
$lastCoords = if ($last) { ($last -split '\|')[0].Trim() }

$target = $null
while (-not $target) {
    Write-Host "lat,lng (e.g. 10.7769, 106.7009) or post office code/name to search" -ForegroundColor Cyan -NoNewline
    if ($last) { Write-Host " (Default: $($last.Replace('|', '—')))" -ForegroundColor DarkGray -NoNewline }
    Write-Host ": " -NoNewline
    $answer = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($answer)) {
        if (-not $lastCoords) { continue }
        $answer = $lastCoords
    }

    # Two numbers -> coordinates; anything else -> post office search
    $parts = @($answer -split '[,;\s]+' | Where-Object { $_ })
    $lat = 0.0; $lng = 0.0
    if ($parts.Count -eq 2 -and
        [double]::TryParse($parts[0], [Globalization.NumberStyles]::Float, $inv, [ref]$lat) -and
        [double]::TryParse($parts[1], [Globalization.NumberStyles]::Float, $inv, [ref]$lng)) {
        if ($lat -ge -90 -and $lat -le 90 -and $lng -ge -180 -and $lng -le 180) {
            $target = @{ Lat = $lat; Lng = $lng; Label = if ($answer -eq $lastCoords -and $last -match '\|') { ($last -split '\|', 2)[1].Trim() } else { $null } }
        } else {
            Write-Host "Out of range — latitude must be -90..90, longitude -180..180." -ForegroundColor Yellow
        }
        continue
    }
    $target = Find-PostOffice -Term $answer
}

$latText = $target.Lat.ToString($inv)
$lngText = $target.Lng.ToString($inv)

Write-Host "-> " -ForegroundColor Green -NoNewline
Write-Host "Moving $($device.AvdName) ($($device.Serial)) to " -ForegroundColor White -NoNewline
Write-Host "$latText, $lngText$(if ($target.Label) { "  [$($target.Label)]" })" -ForegroundColor Cyan

# geo fix takes longitude first
$output = & $adbExe -s $device.Serial emu geo fix $lngText $latText 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $output -match "KO|error") {
    Write-Host "geo fix failed: $($output.Trim())" -ForegroundColor Red
    exit 1
}

Set-Content -Path $stateFile -Value "$latText, $lngText$(if ($target.Label) { " | $($target.Label)" })" -Encoding UTF8
Write-Host "`n🎉 DONE — apps pick it up on their next location update (reopen the map screen if it doesn't move)." -ForegroundColor Magenta
