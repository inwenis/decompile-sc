# Downloads the latest StarCraft Modded release into %LOCALAPPDATA%\StarCraft-Modded and
# starts it. Windows PowerShell 5.1, which every Windows 10/11 has, is enough. The one line:
#
#   powershell -c "irm https://raw.githubusercontent.com/inwenis/decompile-sc/main/play.ps1 | iex"
#
# SCMOD_ZIP_URL installs a specific release instead of the latest; SCMOD_GAME names the
# StarCraft folder to use when the launcher should not find it on its own.
$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = if ($env:SCMOD_ZIP_URL) { $env:SCMOD_ZIP_URL } else { 'https://github.com/inwenis/decompile-sc/releases/latest/download/starcraft-modded.zip' }
    $dir = Join-Path $env:LOCALAPPDATA 'StarCraft-Modded'
    $zip = Join-Path $env:TEMP 'starcraft-modded.zip'
    Write-Host "Downloading $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Write-Host "Installed to $dir -- starting the game. Next time: run this line again (it updates), or Launch-StarCraft-Modded.cmd in that folder."
    $start = @{ FilePath = (Join-Path $dir 'Launch-StarCraft-Modded.cmd'); WorkingDirectory = $dir }
    if ($env:SCMOD_GAME) { $start.ArgumentList = "`"$env:SCMOD_GAME`"" }
    Start-Process @start
}
catch {
    Write-Host $_ -ForegroundColor Red
    Read-Host 'Press Enter to close'
}
