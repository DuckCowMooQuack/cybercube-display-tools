param(
    [string]$LinuxProjectPath = "",
    [string]$WslDistro = "",
    [string]$WslUser = "",
    [string]$CubeIp = "192.168.4.26",
    [int]$Interval = 1,
    [string]$LogDir = "",
    [string]$SpotifyTokenPath = "",
    [string]$IdlePath = "/image/Starfield_1.gif"
)

$ErrorActionPreference = "Stop"

function ConvertTo-BashSingleQuoted {
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

if (-not $LogDir) {
    $LogDir = Split-Path -Parent $PSCommandPath
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$logPath = Join-Path $LogDir "CyberCubeSpotifyWSL.log"
$wslExe = "C:\WINDOWS\System32\wsl.exe"

if (-not $LinuxProjectPath) {
    throw "LinuxProjectPath is required. Register the task with Register-CyberCubeSpotifyTask.ps1."
}

$quotedLinuxProjectPath = ConvertTo-BashSingleQuoted $LinuxProjectPath
$linuxTaskDataDir = "$LinuxProjectPath/.task"
$linuxOutputPath = "$linuxTaskDataDir/cybercube_spotify.gif"
$envAssignments = @(
    "CYBERCUBE_IP=$(ConvertTo-BashSingleQuoted $CubeIp)"
    "CYBERCUBE_SPOTIFY_INTERVAL=$(ConvertTo-BashSingleQuoted $($Interval.ToString()))"
    "CYBERCUBE_IDLE_PATH=$(ConvertTo-BashSingleQuoted $IdlePath)"
    "CYBERCUBE_SPOTIFY_OUTPUT=$(ConvertTo-BashSingleQuoted $linuxOutputPath)"
)
if ($SpotifyTokenPath) {
    $envAssignments += "CYBERCUBE_SPOTIFY_TOKEN_PATH=$(ConvertTo-BashSingleQuoted $SpotifyTokenPath)"
}
$envCommand = $envAssignments -join " "
$quotedLinuxTaskDataDir = ConvertTo-BashSingleQuoted $linuxTaskDataDir
$linuxCommand = "mkdir -p $quotedLinuxTaskDataDir; pkill -f '[c]ybercube_spotify.py' 2>/dev/null || true; cd $quotedLinuxProjectPath && $envCommand exec ./start_cybercube_spotify.sh"

$argumentList = @()
if ($WslDistro) {
    $argumentList += @("--distribution", $WslDistro)
}
if ($WslUser) {
    $argumentList += @("--user", $WslUser)
}
$argumentList += @("bash", "-lc", $linuxCommand)

$timestamp = Get-Date -Format s
Add-Content -Path $logPath -Value ("[{0}] Launching CyberCube Spotify WSL task" -f $timestamp)
Add-Content -Path $logPath -Value ("[{0}] Command: {1} {2}" -f $timestamp, $wslExe, ($argumentList -join " "))
Add-Content -Path $logPath -Value ("[{0}] Linux project path: {1}" -f $timestamp, $LinuxProjectPath)
Add-Content -Path $logPath -Value ("[{0}] WSL distro: {1}" -f $timestamp, $(if ($WslDistro) { $WslDistro } else { "default" }))
Add-Content -Path $logPath -Value ("[{0}] WSL user: {1}" -f $timestamp, $(if ($WslUser) { $WslUser } else { "default" }))
Add-Content -Path $logPath -Value ("[{0}] WSL output log: {1}" -f $timestamp, $logPath)
Add-Content -Path $logPath -Value ("[{0}] Linux output GIF: {1}" -f $timestamp, $linuxOutputPath)

try {
    & $wslExe @argumentList *>> $logPath
    $exitCode = $LASTEXITCODE
}
catch {
    Add-Content -Path $logPath -Value ("[{0}] Launcher error: {1}" -f (Get-Date -Format s), $_.Exception.Message)
    throw
}

Add-Content -Path $logPath -Value ("[{0}] CyberCube Spotify WSL task exited with code {1}" -f (Get-Date -Format s), $exitCode)
exit $exitCode
