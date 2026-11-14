<#
  Remove solar-brightness from Windows. Config stays unless you pass -Purge.
    powershell -ExecutionPolicy Bypass -File windows\uninstall.ps1 [-Purge]
#>
param([switch]$Purge)
Unregister-ScheduledTask -TaskName 'solar-brightness' -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'solar-brightness') -ErrorAction SilentlyContinue
if ($Purge) { Remove-Item -Recurse -Force (Join-Path $env:APPDATA 'solar-brightness') -ErrorAction SilentlyContinue }
'solar-brightness removed'
