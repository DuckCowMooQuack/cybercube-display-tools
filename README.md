# CyberCube Display Tools

Small Python utilities for publishing animated 240x240 GIFs to a Quboox CyberCube over its local HTTP API.

The project currently includes two display modes:

- `cybercube_dashboard.py`: renders CPU, memory, disk, and time as a compact system dashboard.
- `cybercube_spotify.py`: renders Spotify now-playing artwork and text while Spotify is actively playing, then switches back to a CyberCube-hosted idle GIF when Spotify is paused or inactive.

The scripts are intentionally simple: they render a GIF locally, upload it to `/api/upload?dir=image`, and activate it with `/api/activate`.

## Requirements

- Python 3.8+
- A CyberCube reachable on your local network
- Pillow
- Optional: WSL on Windows if you want to use the included Task Scheduler setup
- Optional: a Spotify refresh token if you want now-playing mode

Install Python dependencies:

```bash
python3 -m pip install -r requirements.txt
```

## Find Your Cube IP

Use the IP address assigned to your CyberCube on your LAN. The examples below use `192.168.4.26`; replace it with your device IP.

You can quickly check the cube API:

```bash
curl http://192.168.4.26/api/status
```

## System Dashboard

Render and publish once:

```bash
python3 cybercube_dashboard.py --cube 192.168.4.26
```

Preview without uploading:

```bash
python3 cybercube_dashboard.py --dry-run
```

Run periodically:

```bash
python3 cybercube_dashboard.py --cube 192.168.4.26 --interval 60
```

By default, `--source auto` tries Windows metrics through `powershell.exe` when available and falls back to Linux `/proc` metrics. You can force either source:

```bash
python3 cybercube_dashboard.py --source windows
python3 cybercube_dashboard.py --source linux
```

## Spotify Now Playing

Create a Spotify token cache file:

```bash
mkdir -p ~/.config/cybercube
cp examples/spotify-token.example.json ~/.config/cybercube/spotify-token.json
```

Edit `~/.config/cybercube/spotify-token.json`:

```json
{
  "client_id": "your_spotify_client_id",
  "refresh_token": "your_spotify_refresh_token"
}
```

Run once:

```bash
python3 cybercube_spotify.py --cube 192.168.4.26
```

Run continuously:

```bash
python3 cybercube_spotify.py --cube 192.168.4.26 --interval 1
```

When Spotify is actively playing, the script uploads and activates the generated now-playing GIF. When Spotify is paused or inactive, it activates the idle GIF path once and then leaves it alone so the GIF can loop without restarting.

The default idle path is:

```text
/image/Starfield_1.gif
```

Change it with:

```bash
python3 cybercube_spotify.py --idle-path /image/YourIdleGif.gif
```

## Environment Variables

The scripts can also be configured with environment variables:

```bash
export CYBERCUBE_IP=192.168.4.26
export CYBERCUBE_SPOTIFY_INTERVAL=1
export CYBERCUBE_SPOTIFY_OUTPUT="/tmp/cybercube_spotify.gif"
export CYBERCUBE_SPOTIFY_TOKEN_PATH="$HOME/.config/cybercube/spotify-token.json"
export CYBERCUBE_IDLE_PATH="/image/Starfield_1.gif"
```

Then start the Spotify loop:

```bash
./start_cybercube_spotify.sh
```

## Windows Startup Task

The `windows/` folder includes scripts that register a hidden Task Scheduler task. The task runs at user logon and starts the Spotify/idle display loop through WSL.

From Windows PowerShell:

```powershell
cd C:\path\to\CyberCube\windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Register-CyberCubeSpotifyTask.ps1 `
  -CubeIp "192.168.4.26" `
  -WslDistro "Ubuntu-24.04" `
  -WslUser "your-wsl-user" `
  -SpotifyTokenPath "/home/your-wsl-user/.config/cybercube/spotify-token.json" `
  -IdlePath "/image/Starfield_1.gif"
```

Notes:

- `-WslDistro` and `-WslUser` are optional. If omitted, Windows uses your default WSL distro and user.
- Use the exact distro name shown by `wsl.exe -l -v`; an in-place Ubuntu upgrade may leave the WSL name older than the Ubuntu release inside it.
- The task is created at `Task Scheduler Library\Startup\CyberCube Spotify`.
- The registration script derives the Linux project path from the parent of the `windows` folder.
- By default, copied task launchers and the Windows log are kept in the project-local `.task\` folder.
- The WSL process writes the generated Spotify GIF to `.task/cybercube_spotify.gif` under the Linux project path.
- Re-running the registration command updates the existing task.

Start it immediately:

```powershell
Start-ScheduledTask -TaskPath "\Startup\" -TaskName "CyberCube Spotify"
```

Stop it and clean up any old WSL process:

```powershell
Stop-ScheduledTask -TaskPath "\Startup\" -TaskName "CyberCube Spotify"
wsl.exe bash -lc "pkill -f '[c]ybercube_spotify.py' || true"
```

Check status and logs:

```powershell
Get-ScheduledTask -TaskPath "\Startup\" -TaskName "CyberCube Spotify" | Get-ScheduledTaskInfo
Get-Content ..\.task\CyberCubeSpotifyWSL.log -Tail 50
```

Unregister the task:

```powershell
cd C:\path\to\CyberCube\windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Unregister-CyberCubeSpotifyTask.ps1
```

## Configuration Reference

### `cybercube_dashboard.py`

```text
--cube        CyberCube IP address
--output      Local GIF output path
--source      auto, windows, or linux
--interval    Seconds between updates; 0 runs once
--dry-run     Render locally without uploading
```

### `cybercube_spotify.py`

```text
--cube         CyberCube IP address
--output       Local GIF output path
--token-path   Spotify token cache JSON path
--idle-path    CyberCube image path to activate while Spotify is inactive
--interval     Seconds between updates; 0 runs once
--dry-run      Render locally without uploading
```

### Windows Task Registration

```text
-TaskName            Scheduled task name
-TaskPath            Scheduled task folder, default \Startup\
-TaskDataDir         Project-local copied launchers and Windows log directory, default ..\.task
-LauncherPath        Installed PowerShell launcher path, default under -TaskDataDir
-HiddenLauncherPath  Installed VBScript hidden launcher path, default under -TaskDataDir
-LinuxProjectPath    Linux path to this project; auto-detected when possible
-WslDistro           Optional WSL distro name
-WslUser             Optional WSL user name
-CubeIp              CyberCube IP address
-Interval            Spotify polling interval in seconds
-SpotifyTokenPath    Spotify token cache path inside WSL
-IdlePath            CyberCube image path for idle mode
```

## Troubleshooting

- If the CyberCube GIF restarts every second while Spotify is inactive, make sure you are running the latest script and that no old `cybercube_spotify.py` process is still running.
- If PowerShell blocks `.ps1` files, use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`.
- If the task opens a console window, re-run the registration script so it installs the hidden `wscript.exe` launcher.
- If Spotify never enters now-playing mode, confirm the token cache exists and contains `client_id` and `refresh_token`.
- If the cube does not update, confirm `http://<cube-ip>/api/status` works from the same machine.

## Security Notes

- Do not commit your real Spotify token cache. `.gitignore` excludes common token file names.
- The CyberCube HTTP API is unauthenticated on the LAN. Keep the device on a trusted network.

## Publish To GitHub

Create an empty public repository on GitHub, then connect and push this local repo:

```bash
git remote add origin https://github.com/YOUR_USERNAME/cybercube-display-tools.git
git branch -M main
git push -u origin main
```

Or use GitHub CLI:

```bash
gh repo create cybercube-display-tools --public --source=. --remote=origin --push
```

## License

MIT
