param(
    [string]$TaskName = "CyberCube Spotify",
    [string]$TaskPath = "\Startup\",
    [string]$TaskDataDir = "",
    [string]$LauncherPath = "",
    [string]$HiddenLauncherPath = "",
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
$projectRoot = Split-Path -Parent $PSScriptRoot

if (-not $TaskDataDir) {
    $TaskDataDir = Join-Path $projectRoot ".task"
}
if (-not $LauncherPath) {
    $LauncherPath = Join-Path $TaskDataDir "Start-CyberCubeSpotify.ps1"
}
if (-not $HiddenLauncherPath) {
    $HiddenLauncherPath = Join-Path $TaskDataDir "Start-CyberCubeSpotifyHidden.vbs"
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

$targetDir = Split-Path -Parent $LauncherPath
$hiddenTargetDir = Split-Path -Parent $HiddenLauncherPath
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
New-Item -ItemType Directory -Force -Path $hiddenTargetDir | Out-Null
Copy-Item -Path $sourceLauncher -Destination $LauncherPath -Force
Copy-Item -Path $sourceHiddenLauncher -Destination $HiddenLauncherPath -Force

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

Write-Host "Registered scheduled task: $TaskPath$TaskName"
Write-Host "Task data directory: $TaskDataDir"
Write-Host "Launcher copied to: $LauncherPath"
Write-Host "Hidden launcher copied to: $HiddenLauncherPath"
Write-Host "Linux project path: $LinuxProjectPath"
Write-Host "Cube IP: $CubeIp"
Write-Host "Update interval: $Interval second(s)"
Write-Host "Idle path: $IdlePath"
if ($WslDistro) { Write-Host "WSL distro: $WslDistro" }
if ($WslUser) { Write-Host "WSL user: $WslUser" }
if ($SpotifyTokenPath) { Write-Host "Spotify token path: $SpotifyTokenPath" }
Write-Host "Log file: $(Join-Path $TaskDataDir 'CyberCubeSpotifyWSL.log')"
Write-Host "WSL output is captured in the Windows log file."
