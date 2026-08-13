param(
    [string]$TaskName = "CyberCube Spotify",
    [string]$ShutdownTaskName = "CyberCube Spotify Shutdown Idle",
    [string]$TaskPath = "\Startup\"
)

$ErrorActionPreference = "Stop"

$tasks = @($TaskName, $ShutdownTaskName)
foreach ($name in $tasks) {
    $task = Get-ScheduledTask -TaskName $name -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $name -TaskPath $TaskPath -Confirm:$false
        Write-Host "Unregistered scheduled task: $TaskPath$name"
    }
    else {
        Write-Host "Scheduled task not found: $TaskPath$name"
    }
}
