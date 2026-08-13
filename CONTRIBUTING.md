# Contributing

Issues and pull requests are welcome.

Before opening a pull request:

1. Keep configuration out of source files. Prefer command-line options or environment variables.
2. Do not commit Spotify tokens, generated GIFs, logs, or `__pycache__` files.
3. Run the syntax checks:

```bash
python3 -m py_compile cybercube_dashboard.py cybercube_spotify.py
bash -n start_cybercube_spotify.sh
```

If you change the Windows startup scripts, also run:

```powershell
powershell.exe -NoProfile -Command "$files = @('windows/Register-CyberCubeSpotifyTask.ps1', 'windows/Start-CyberCubeSpotify.ps1', 'windows/Activate-CyberCubeIdle.ps1', 'windows/Unregister-CyberCubeSpotifyTask.ps1'); foreach ($file in $files) { $errors = $null; [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $file), [ref]$errors) | Out-Null; if ($errors) { $errors; exit 1 } }"
```
