<#
  Install solar-brightness on Windows: copies the script to %LOCALAPPDATA%\solar-brightness
  and registers a scheduled task that runs it every 5 minutes and at logon.
  No administrator rights needed:
    powershell -ExecutionPolicy Bypass -File windows\install.ps1
#>
$ErrorActionPreference = 'Stop'
$TaskName = 'solar-brightness'
$Dir = Join-Path $env:LOCALAPPDATA 'solar-brightness'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'solar-brightness.ps1') $Dir -Force
$ps = Join-Path $Dir 'solar-brightness.ps1'

# the token name works over SSH too, where USERDOMAIN can be WORKGROUP
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name

# conhost --headless keeps a console window from flashing every 5 minutes
$action = New-ScheduledTaskAction -Execute 'conhost.exe' `
    -Argument "--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ps`""
$every5 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5)
$logon = New-ScheduledTaskTrigger -AtLogOn -User $me
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
$principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($every5, $logon) `
    -Settings $settings -Principal $principal -Description 'Display brightness from the height of the sun' -Force | Out-Null

'--- where:'
& $ps -Where
'--- today:'
& $ps -Sun
'--- now:'
& $ps -Resume
"installed. Task '$TaskName' runs every 5 minutes. Log: $Dir\solar-brightness.log"
