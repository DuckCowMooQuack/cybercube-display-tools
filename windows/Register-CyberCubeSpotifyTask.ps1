param(
    [string]$TaskName = "CyberCube Spotify",
    [string]$TaskPath = "\Startup\",
    [string]$LauncherPath = "C:\ProgramData\CyberCubeSpotify\Start-CyberCubeSpotify.ps1",
    [string]$HiddenLauncherPath = "C:\ProgramData\CyberCubeSpotify\Start-CyberCubeSpotifyHidden.vbs",
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
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
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
Write-Host "Launcher copied to: $LauncherPath"
Write-Host "Hidden launcher copied to: $HiddenLauncherPath"
Write-Host "Linux project path: $LinuxProjectPath"
Write-Host "Cube IP: $CubeIp"
Write-Host "Update interval: $Interval second(s)"
Write-Host "Idle path: $IdlePath"
if ($WslDistro) { Write-Host "WSL distro: $WslDistro" }
if ($WslUser) { Write-Host "WSL user: $WslUser" }
if ($SpotifyTokenPath) { Write-Host "Spotify token path: $SpotifyTokenPath" }
Write-Host "Log file: C:\ProgramData\CyberCubeSpotify\CyberCubeSpotifyWSL.log"
Write-Host "Linux log file: /tmp/CyberCubeSpotifyWSL.log"
