<#
  setup_task.ps1 - registers the Task Scheduler job for refresh_stock.ps1
  Run ONCE from an elevated PowerShell on the SAP box:
      powershell -ExecutionPolicy Bypass -File C:\scripts\setup_task.ps1
  Creates task "BSC Stock MIS Refresh": every 15 min, hidden, runs whether or
  not a user is logged on, kills a hung run after 10 min. Re-running replaces it.
#>
$ErrorActionPreference = "Stop"
$TaskName = "BSC Stock MIS Refresh"
$Script   = "C:\scripts\refresh_stock.ps1"
if (-not (Test-Path $Script)) { throw "Not found: $Script - copy refresh_stock.ps1 there first." }

$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
           -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings= New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew `
           -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

# Runs as the current user (must be the account that has the git credentials cached).
$user = "$env:USERDOMAIN\$env:USERNAME"
Write-Host "Registering '$TaskName' to run as $user every 15 min ..."
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -User $user -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Start-Sleep 3
Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo | Select-Object LastRunTime, LastTaskResult, NextRunTime | Format-List
Write-Host "Done. Check C:\scripts\refresh_stock.log after the first run."
