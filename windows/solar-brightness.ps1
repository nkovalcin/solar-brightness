<#
.SYNOPSIS
  solar-brightness for Windows: set the laptop panel brightness from the real height of the sun.

.DESCRIPTION
  Every run computes the sun's elevation for your location and moves the brightness
  along a curve: bright at midday, dim after dusk, flat at night. A scheduled task runs
  it every 5 minutes. Same algorithm and config keys as the macOS script.

  Works on displays that expose brightness through WMI (laptop panels). External
  monitors usually do not, use the monitor's own controls or a DDC tool for those.

  A manual change wins: when the brightness differs from what this script set last
  time, it keeps your value and stays quiet for hold_minutes.

.EXAMPLE
  solar-brightness.ps1                       apply brightness for the sun right now
  solar-brightness.ps1 -DryRun               show what would happen
  solar-brightness.ps1 -Resume               cancel the pause after a manual change
  solar-brightness.ps1 -Sun [-Date 2026-12-21] [-Lat 48.15 -Lon 17.11]
  solar-brightness.ps1 -Where
  solar-brightness.ps1 -SetLocation 38.7223,-9.1393 -Name Lisbon
  solar-brightness.ps1 -SetLocation auto
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Resume,
    [switch]$Sun,
    [switch]$Where,
    [string]$Date,
    [string]$SetLocation,
    [string]$Name,
    [Nullable[double]]$Lat,
    [Nullable[double]]$Lon,
    # test hook: print the elevation for an ISO 8601 UTC time and exit
    [string]$ElevationAt
)

$ErrorActionPreference = 'Stop'
$Version = '1.0.0'
$Inv = [Globalization.CultureInfo]::InvariantCulture
# PowerShell on macOS and Linux (used by the tests) has no APPDATA
$AppData = if ($env:APPDATA) { $env:APPDATA } else { Join-Path $HOME '.config' }
$LocalAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.local/state' }
$ConfigDir = Join-Path $AppData 'solar-brightness'
$Config = Join-Path $ConfigDir 'config.json'
$DataDir = Join-Path $LocalAppData 'solar-brightness'
$StateFile = Join-Path $DataDir 'state.json'
$LogFile = Join-Path $DataDir 'solar-brightness.log'

$Defaults = @{
    curves             = @{ internal = @(@(25, 55), @(8, 40), @(0, 25), @(-6, 12), @(-12, 5)) }
    min                = @{ internal = 5 }
    hold_minutes       = 15
    override_tolerance = 2
    ip_lookup          = $true
    ip_cache_hours     = 6
    location           = $null
}

function F1([double]$x) { $x.ToString('0.0', $Inv) }
function F4([double]$x) { $x.ToString('0.0000', $Inv) }

# ---- config and state -------------------------------------------------------
function Read-Json($path) {
    if (-not (Test-Path $path)) { return $null }
    try { return Get-Content $path -Raw | ConvertFrom-Json } catch { Write-Warning "$path is not valid JSON, ignoring it"; return $null }
}

function Get-Config {
    $cfg = @{}
    foreach ($k in $Defaults.Keys) { $cfg[$k] = $Defaults[$k] }
    $user = Read-Json $Config
    if ($user) {
        foreach ($p in $user.PSObject.Properties) {
            if ($p.Name -eq 'curves' -and $p.Value.internal) { $cfg.curves = @{ internal = @($p.Value.internal) } }
            elseif ($p.Name -eq 'min' -and $null -ne $p.Value.internal) { $cfg.min = @{ internal = [int]$p.Value.internal } }
            else { $cfg[$p.Name] = $p.Value }
        }
    }
    return $cfg
}

function Save-ConfigKey([string]$key, $value) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $data = Read-Json $Config
    if (-not $data) { $data = [pscustomobject]@{} }
    $data.PSObject.Properties.Remove($key)
    if ($null -ne $value) { $data | Add-Member -NotePropertyName $key -NotePropertyValue $value }
    $data | ConvertTo-Json -Depth 5 | Set-Content $Config -Encoding UTF8
}

function Get-State {
    $s = Read-Json $StateFile
    if (-not $s) { $s = [pscustomobject]@{} }
    return $s
}
function Save-State($s) {
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    $s | ConvertTo-Json -Depth 4 | Set-Content $StateFile -Encoding UTF8
}
function Set-Prop($obj, [string]$name, $value) {
    $obj.PSObject.Properties.Remove($name)
    if ($null -ne $value) { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

function Write-Log([string]$msg) {
    Write-Output $msg
    New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
    Add-Content -Path $LogFile -Value $msg -Encoding UTF8
    if ((Get-Item $LogFile).Length -gt 512KB) {
        $tail = Get-Content $LogFile -Tail 1000
        Set-Content $LogFile -Value $tail -Encoding UTF8
    }
}

# ---- sun (NOAA, about 0.5 degree accuracy) ----------------------------------
function Get-SolarElevation([datetime]$utc, [double]$lat, [double]$lon) {
    $utc = $utc.ToUniversalTime()
    $doy = $utc.DayOfYear
    $hour = $utc.Hour + $utc.Minute / 60.0 + $utc.Second / 3600.0
    $g = 2.0 * [math]::PI / 365.0 * ($doy - 1 + ($hour - 12.0) / 24.0)
    $eq = 229.18 * (0.000075 + 0.001868 * [math]::Cos($g) - 0.032077 * [math]::Sin($g) -
        0.014615 * [math]::Cos(2 * $g) - 0.040849 * [math]::Sin(2 * $g))
    $decl = 0.006918 - 0.399912 * [math]::Cos($g) + 0.070257 * [math]::Sin($g) -
        0.006758 * [math]::Cos(2 * $g) + 0.000907 * [math]::Sin(2 * $g) -
        0.002697 * [math]::Cos(3 * $g) + 0.00148 * [math]::Sin(3 * $g)
    $tst = $hour * 60.0 + $eq + 4.0 * $lon
    $ha = ($tst / 4.0 - 180.0) * [math]::PI / 180.0
    $phi = $lat * [math]::PI / 180.0
    [double]$cz = [math]::Sin($phi) * [math]::Sin($decl) + [math]::Cos($phi) * [math]::Cos($decl) * [math]::Cos($ha)
    # keep the literals double: [math]::Min(1, $x) would pick the int overload and round
    $cz = [math]::Max([double]-1.0, [math]::Min([double]1.0, $cz))
    return 90.0 - [math]::Acos($cz) * 180.0 / [math]::PI
}

function Get-Level([double]$e, $curve) {
    $pts = @($curve | ForEach-Object { , @([double]$_[0], [double]$_[1]) } | Sort-Object { $_[0] } -Descending)
    if ($e -ge $pts[0][0]) { return [int][math]::Round($pts[0][1]) }
    if ($e -le $pts[-1][0]) { return [int][math]::Round($pts[-1][1]) }
    for ($i = 0; $i -lt $pts.Count - 1; $i++) {
        $hi = $pts[$i]; $lo = $pts[$i + 1]
        if ($e -le $hi[0] -and $e -ge $lo[0]) {
            $t = ($e - $lo[0]) / ($hi[0] - $lo[0])
            return [int][math]::Round($lo[1] + $t * ($hi[1] - $lo[1]), [MidpointRounding]::ToEven)
        }
    }
    return [int][math]::Round($pts[-1][1])
}

# ---- location ---------------------------------------------------------------
function Resolve-Location($cfg, $state, [bool]$fresh) {
    $pin = $cfg.location
    if ($pin -and -not $fresh) { return @{ lat = [double]$pin.lat; lon = [double]$pin.lon; name = "pinned: $($pin.name)" } }
    $cache = $state.location_cache
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($cfg.ip_lookup) {
        if ($cache -and -not $fresh -and ($now - [double]$cache.ts) -lt [double]$cfg.ip_cache_hours * 3600) {
            return @{ lat = [double]$cache.lat; lon = [double]$cache.lon; name = "$($cache.name) (cached)" }
        }
        try {
            $d = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 3 -UserAgent "solar-brightness/$Version"
            $parts = $d.loc -split ','
            $loc = @{ lat = [double]::Parse($parts[0], $Inv); lon = [double]::Parse($parts[1], $Inv); name = "IP: $($d.city), $($d.country)" }
            Set-Prop $state 'location_cache' ([pscustomobject]@{ lat = $loc.lat; lon = $loc.lon; name = $loc.name; ts = $now })
            return $loc
        } catch { }
    }
    if ($cache) { return @{ lat = [double]$cache.lat; lon = [double]$cache.lon; name = "$($cache.name) (last known, offline)" } }
    return $null
}

# ---- display ----------------------------------------------------------------
function Get-Brightness {
    try { return [int](Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop | Select-Object -First 1).CurrentBrightness }
    catch { return $null }
}
function Set-Brightness([int]$level) {
    Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop |
        Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]0; Brightness = [byte]$level } | Out-Null
}

# ---- main -------------------------------------------------------------------
if ($ElevationAt) {
    $t = [datetime]::Parse($ElevationAt, $Inv, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
    (Get-SolarElevation $t $Lat $Lon).ToString('R', $Inv)
    exit 0
}

$cfg = Get-Config
$state = Get-State

if ($SetLocation) {
    if ($SetLocation -eq 'auto') { Save-ConfigKey 'location' $null; 'location unpinned, detecting automatically'; exit 0 }
    if ($SetLocation -eq 'here') {
        $l = Resolve-Location $cfg $state $true
        if (-not $l) { 'no location found (IP lookup failed)'; exit 1 }
        $pin = [pscustomobject]@{ lat = $l.lat; lon = $l.lon; name = $l.name }
    } else {
        $parts = $SetLocation -split '[,; ]+'
        try { $pin = [pscustomobject]@{ lat = [double]::Parse($parts[0], $Inv); lon = [double]::Parse($parts[1], $Inv); name = '' } }
        catch { 'use -SetLocation LAT,LON  e.g. -SetLocation 38.7223,-9.1393 -Name Lisbon'; exit 2 }
        if ($Name) { $pin.name = $Name } else { $pin.name = "$(F4 $pin.lat), $(F4 $pin.lon)" }
    }
    Save-ConfigKey 'location' $pin
    Save-State $state
    "pinned: $($pin.name)  ($($pin.lat.ToString($Inv)), $($pin.lon.ToString($Inv)))"
    exit 0
}

if ($null -ne $Lat -and $null -ne $Lon) { $loc = @{ lat = [double]$Lat; lon = [double]$Lon; name = 'command line' } }
else { $loc = Resolve-Location $cfg $state $false }
$curve = $cfg.curves.internal

if ($Where) {
    if ($loc) { "location   $(F4 $loc.lat), $(F4 $loc.lon)  ($($loc.name))" } else { 'location   unknown' }
    if (Test-Path $Config) { "config     $Config" } else { 'config     defaults (no config.json)' }
    $b = Get-Brightness
    if ($null -ne $b) { "panel      yes, now $b" } else { 'panel      no WMI brightness on this display' }
    Save-State $state
    exit 0
}

if ($Sun) {
    if (-not $loc) { 'no location: pin one with -SetLocation LAT,LON'; exit 1 }
    if ($Date) { $day = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $Inv) } else { $day = (Get-Date).Date }
    "location $(F4 $loc.lat), $(F4 $loc.lon)  ($($loc.name))   date $($day.ToString('yyyy-MM-dd'))"
    ''
    '  time   sun      level'
    foreach ($h in 0..11) {
        $t = $day.AddHours($h * 2)
        $e = Get-SolarElevation $t.ToUniversalTime() $loc.lat $loc.lon
        '  {0}  {1,6} deg  {2,4}' -f $t.ToString('HH:mm'), (F1 $e), (Get-Level $e $curve)
    }
    Save-State $state
    exit 0
}

$now = Get-Date
if (-not $loc) { Write-Log ("{0}  no location yet, brightness untouched (pin one: -SetLocation LAT,LON)" -f $now.ToString('HH:mm')); exit 0 }

if ($Resume) { Set-Prop $state 'hold_until' $null; Set-Prop $state 'applied' $null }

$e = Get-SolarElevation $now.ToUniversalTime() $loc.lat $loc.lon
$target = [math]::Max([int]$cfg.min.internal, [math]::Min(100, (Get-Level $e $curve)))
$head = '{0}  sun {1} deg  ->  {2}   [{3}]' -f $now.ToString('HH:mm'), (F1 $e), $target, $loc.name
$actual = Get-Brightness
if ($null -eq $actual) { Write-Log "$head`n  this display has no WMI brightness (external monitor?)"; Save-State $state; exit 0 }

$last = $state.applied
if ($null -ne $last -and [math]::Abs($actual - [int]$last) -gt [int]$cfg.override_tolerance) {
    $until = $now.AddMinutes([int]$cfg.hold_minutes)
    Write-Log ("$head`n  manual change ($last -> $actual), keeping it until {0}" -f $until.ToString('HH:mm'))
    if (-not $DryRun) { Set-Prop $state 'applied' $actual; Set-Prop $state 'hold_until' $until.ToString('o', $Inv); Save-State $state }
    exit 0
}
if ($state.hold_until) {
    $until = [datetime]::Parse($state.hold_until, $Inv, [Globalization.DateTimeStyles]::RoundtripKind)
    if ($now -lt $until) {
        Write-Log ("$head`n  your setting holds for {0} more min" -f [math]::Ceiling(($until - $now).TotalMinutes))
        Save-State $state
        exit 0
    }
    Set-Prop $state 'hold_until' $null
}
if ($actual -eq $target) {
    Write-Log "$head   (already there)"
    if (-not $DryRun) { Set-Prop $state 'applied' $target; Save-State $state }
    exit 0
}
if ($DryRun) { Write-Output "$head   [dry run, now $actual]"; exit 0 }
Set-Brightness $target
Set-Prop $state 'applied' $target
Save-State $state
Write-Log "$head   ($actual -> $target)"
