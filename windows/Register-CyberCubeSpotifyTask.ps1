param(
    [string]$TaskName = "CyberCube Spotify",
    [string]$ShutdownTaskName = "CyberCube Spotify Shutdown Idle",
    [string]$TaskPath = "\Startup\",
    [string]$TaskDataDir = "",
    [string]$LauncherPath = "",
    [string]$HiddenLauncherPath = "",
    [string]$IdleActivatorPath = "",
    [string]$LinuxProjectPath = "",
    [string]$WslDistro = "",
    [string]$WslUser = "",
    [string]$CubeIp = "192.168.4.26",
    [int]$Interval = 1,
    [string]$SpotifyTokenPath = "",
    [string]$IdlePath = "/image/Starfield_1.gif"
)

$ErrorActionPreference = "Stop"

$wslExe = "C:\WINDOWS\System32\wsl.exe"
$sourceLauncher = Join-Path $PSScriptRoot "Start-CyberCubeSpotify.ps1"
$sourceHiddenLauncher = Join-Path $PSScriptRoot "Start-CyberCubeSpotifyHidden.vbs"
$sourceIdleActivator = Join-Path $PSScriptRoot "Activate-CyberCubeIdle.ps1"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Assert-NoLineBreak {
    param(
        [string]$Name,
        [string]$Value
    )

    if ($Value -match "[`r`n]") {
        throw "$Name contains a line break. Re-run registration with that argument on one physical line."
    }
}

if (-not $TaskDataDir) {
    $TaskDataDir = Join-Path $projectRoot ".task"
}
if (-not $LauncherPath) {
    $LauncherPath = $sourceLauncher
}
if (-not $HiddenLauncherPath) {
    $HiddenLauncherPath = $sourceHiddenLauncher
}
if (-not $IdleActivatorPath) {
    $IdleActivatorPath = $sourceIdleActivator
}

if (-not $LinuxProjectPath) {
    if ($projectRoot -match '^\\\\(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$') {
        $LinuxProjectPath = "/" + ($Matches[1] -replace '\\', '/')
    }
    elseif ($projectRoot -match '^([A-Za-z]):\\(.+)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $path = $Matches[2] -replace '\\', '/'
        $LinuxProjectPath = "/mnt/$drive/$path"
    }
    else {
        $LinuxProjectPath = (& $wslExe wslpath -a $projectRoot).Trim()
    }
}

Assert-NoLineBreak "TaskDataDir" $TaskDataDir
Assert-NoLineBreak "LauncherPath" $LauncherPath
Assert-NoLineBreak "HiddenLauncherPath" $HiddenLauncherPath
Assert-NoLineBreak "IdleActivatorPath" $IdleActivatorPath
Assert-NoLineBreak "LinuxProjectPath" $LinuxProjectPath
Assert-NoLineBreak "SpotifyTokenPath" $SpotifyTokenPath
Assert-NoLineBreak "IdlePath" $IdlePath

New-Item -ItemType Directory -Force -Path $TaskDataDir | Out-Null

$hiddenArgs = @(
    "//B"
    "//Nologo"
    "`"$HiddenLauncherPath`""
    "`"$LauncherPath`""
    "-LinuxProjectPath"
    "`"$LinuxProjectPath`""
    "-CubeIp"
    "`"$CubeIp`""
    "-Interval"
    $Interval.ToString()
    "-LogDir"
    "`"$TaskDataDir`""
    "-IdlePath"
    "`"$IdlePath`""
)
if ($WslDistro) {
    $hiddenArgs += @("-WslDistro", "`"$WslDistro`"")
}
if ($WslUser) {
    $hiddenArgs += @("-WslUser", "`"$WslUser`"")
}
if ($SpotifyTokenPath) {
    $hiddenArgs += @("-SpotifyTokenPath", "`"$SpotifyTokenPath`"")
}

$action = New-ScheduledTaskAction `
    -Execute "C:\WINDOWS\System32\wscript.exe" `
    -Argument ($hiddenArgs -join " ")

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Days 30) `
    -Hidden `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName $TaskName `
    -TaskPath $TaskPath `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Publishes Spotify now-playing artwork to the Quboox CyberCube from WSL." `
    -Force | Out-Null

$shutdownArgs = @(
    "-NoProfile"
    "-ExecutionPolicy"
    "Bypass"
    "-File"
    "`"$IdleActivatorPath`""
    "-CubeIp"
    "`"$CubeIp`""
    "-IdlePath"
    "`"$IdlePath`""
    "-LogDir"
    "`"$TaskDataDir`""
)
$shutdownAction = New-ScheduledTaskAction `
    -Execute "C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument ($shutdownArgs -join " ")

$eventTriggerClass = Get-CimClass -Namespace "Root/Microsoft/Windows/TaskScheduler" -ClassName "MSFT_TaskEventTrigger"
$shutdownTrigger = New-CimInstance -CimClass $eventTriggerClass -ClientOnly
$shutdownTrigger.Enabled = $true
$shutdownTrigger.Subscription = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='USER32'] and EventID=1074]]</Select>
  </Query>
</QueryList>
"@

$shutdownSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2) `
    -Hidden `
    -MultipleInstances Parallel

$shutdownPrincipal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $ShutdownTaskName `
    -TaskPath $TaskPath `
    -Action $shutdownAction `
    -Trigger $shutdownTrigger `
    -Settings $shutdownSettings `
    -Principal $shutdownPrincipal `
    -Description "Best-effort CyberCube idle activation when Windows begins shutdown or restart." `
    -Force | Out-Null

Write-Host "Registered scheduled task: $TaskPath$TaskName"
Write-Host "Registered shutdown idle task: $TaskPath$ShutdownTaskName"
Write-Host "Task data directory: $TaskDataDir"
Write-Host "Launcher path: $LauncherPath"
Write-Host "Hidden launcher path: $HiddenLauncherPath"
Write-Host "Idle activator path: $IdleActivatorPath"
Write-Host "Linux project path: $LinuxProjectPath"
Write-Host "Cube IP: $CubeIp"
Write-Host "Update interval: $Interval second(s)"
Write-Host "Idle path: $IdlePath"
if ($WslDistro) { Write-Host "WSL distro: $WslDistro" }
if ($WslUser) { Write-Host "WSL user: $WslUser" }
if ($SpotifyTokenPath) { Write-Host "Spotify token path: $SpotifyTokenPath" }
Write-Host "Log file: $(Join-Path $TaskDataDir 'CyberCubeSpotifyWSL.log')"
Write-Host "Shutdown idle log file: $(Join-Path $TaskDataDir 'CyberCubeSpotifyShutdown.log')"
Write-Host "WSL output is captured in the Windows log file."
