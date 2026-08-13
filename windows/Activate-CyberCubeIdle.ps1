param(
    [string]$CubeIp = "192.168.4.26",
    [string]$IdlePath = "/image/Starfield_1.gif",
    [string]$LogDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $LogDir) {
    $LogDir = Split-Path -Parent $PSCommandPath
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$logPath = Join-Path $LogDir "CyberCubeSpotifyShutdown.log"
$timestamp = Get-Date -Format s
$encodedPath = [System.Uri]::EscapeDataString($IdlePath)
$uri = "http://$CubeIp/api/activate?dir=image&path=$encodedPath"

try {
    Add-Content -Path $logPath -Value ("[{0}] Activating idle path {1} on {2}" -f $timestamp, $IdlePath, $CubeIp)
    $response = Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec 5
    $ok = if ($null -ne $response.ok) { $response.ok } else { "unknown" }
    Add-Content -Path $logPath -Value ("[{0}] Activate response ok: {1}" -f (Get-Date -Format s), $ok)
}
catch {
    Add-Content -Path $logPath -Value ("[{0}] Idle activation failed: {1}" -f (Get-Date -Format s), $_.Exception.Message)
    exit 1
}
