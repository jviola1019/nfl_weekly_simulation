# Registers the weekly testing program as a Windows scheduled task, so it keeps running when no Claude Code session is
# open. It starts prospective_dispatch.R every 15 minutes, hidden (conhost --headless), as you, only while you are signed
# in; it may wake the PC, and a start missed while the PC was off runs when it is back. Run it yourself, once, in
# PowerShell; no administrator rights are needed:
#   powershell -ExecutionPolicy Bypass -File register_prospective_task.ps1 -Store <dir> -Prod <checkout> -Res <checkout>
# Remove it with:  Unregister-ScheduledTask -TaskPath '\nfl\' -TaskName 'prospective-dispatch' -Confirm:$false
param(
  [Parameter(Mandatory = $true)][string]$Store,
  [Parameter(Mandatory = $true)][string]$Prod,
  [Parameter(Mandatory = $true)][string]$Res,
  [int]$FirstWeek = 9,
  [int]$LastWeek = 18,
  [string]$Rscript = "C:\Program Files\R\R-4.5.1\bin\Rscript.exe"
)
$dispatch = Join-Path $Res "reports\2026-10-29\hypotheses\prospective_dispatch.R"
if (-not (Test-Path $dispatch)) { throw "not found: $dispatch" }
if (-not (Test-Path $Rscript)) { throw "not found: $Rscript" }
$argLine = "--headless `"$Rscript`" `"$dispatch`" --store=$Store --prod=$Prod --res=$Res --first-week=$FirstWeek --last-week=$LastWeek"
$action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\conhost.exe" -Argument $argLine -WorkingDirectory $Store
$start = (Get-Date).Date.AddHours((Get-Date).Hour + 1)   # the next full hour, so the starts fall on the quarter hours
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Minutes 15)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 6)
Register-ScheduledTask -TaskPath '\nfl\' -TaskName 'prospective-dispatch' -Action $action -Trigger $trigger -Settings $settings `
  -Description "nfl_props_v1 weekly runs, snapshots and scoring (reports/2026-10-29/hypotheses/prospective_dispatch.R)" | Out-Null
Get-ScheduledTask -TaskPath '\nfl\' -TaskName 'prospective-dispatch' | Get-ScheduledTaskInfo | Select-Object TaskName, NextRunTime
