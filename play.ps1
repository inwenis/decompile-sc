# Downloads the latest StarCraft Modded release into %LOCALAPPDATA%\StarCraft-Modded, puts a
# "StarCraft Modded" shortcut on the desktop and starts the game. Windows PowerShell 5.1,
# which every Windows 10/11 has, is enough. The one line:
#
#   powershell -c "irm https://raw.githubusercontent.com/inwenis/decompile-sc/main/play.ps1 | iex"
#
# SCMOD_ZIP_URL installs a specific release instead of the latest; SCMOD_GAME names the
# StarCraft folder when the launcher should not find it on its own; SCMOD_DESKTOP puts the
# shortcut somewhere other than the desktop.
$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = if ($env:SCMOD_ZIP_URL) { $env:SCMOD_ZIP_URL } else { 'https://github.com/inwenis/decompile-sc/releases/latest/download/starcraft-modded.zip' }
    $dir = Join-Path $env:LOCALAPPDATA 'StarCraft-Modded'
    $zip = Join-Path $env:TEMP 'starcraft-modded.zip'
    Write-Host "Downloading $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    $launcher = Join-Path $dir 'Launch-StarCraft-Modded.cmd'
    $desktop = if ($env:SCMOD_DESKTOP) { $env:SCMOD_DESKTOP } else { [Environment]::GetFolderPath('Desktop') }
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'StarCraft Modded.lnk'))
    $lnk.TargetPath = $launcher
    $lnk.WorkingDirectory = $dir
    $lnk.Description = 'StarCraft: Brood War 1.16.1 with the mod'
    $installPath = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\Starcraft' -ErrorAction SilentlyContinue).InstallPath
    if ($installPath -and (Test-Path (Join-Path $installPath 'StarCraft.exe'))) { $lnk.IconLocation = (Join-Path $installPath 'StarCraft.exe') + ',0' }
    $lnk.Save()
    Write-Host "Installed to $dir -- starting the game. Next time: the StarCraft Modded shortcut on your desktop. Run this line again to update."
    Start-Process -FilePath $launcher -WorkingDirectory $dir
}
catch {
    Write-Host $_ -ForegroundColor Red
    Read-Host 'Press Enter to close'
}
