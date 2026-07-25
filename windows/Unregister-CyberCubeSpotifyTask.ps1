param(
    [string]$TaskName = "CyberCube Spotify",
    [string]$TaskPath = "\Startup\"
)

$ErrorActionPreference = "Stop"

Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false
Write-Host "Unregistered scheduled task: $TaskPath$TaskName"
