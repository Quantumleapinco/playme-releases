# Removes Nagenli from Windows. Your library, settings and watch history stay where they are. Run it with:
#   irm https://quantumleapinco.github.io/nagenli-releases/uninstall.ps1 | iex
#
# What it does: stops Nagenli if it is running, takes it out of the Start menu and out of what starts with
# Windows, and deletes its program folder (%LOCALAPPDATA%\Programs\Nagenli). It needs no administrator rights,
# downloads nothing and sends nothing.
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:LOCALAPPDATA 'Programs\Nagenli'

# Only the copy in its own folder is stopped, not any other program of that name.
Get-Process -Name nagenli -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force
Start-Sleep -Milliseconds 500

Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name Nagenli -ErrorAction SilentlyContinue
# The same program under its earlier name (PlayMe), if one is left.
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name PlayMe -ErrorAction SilentlyContinue
$programs = [Environment]::GetFolderPath('Programs')
Remove-Item (Join-Path $programs 'Nagenli.lnk'), (Join-Path $programs 'PlayMe.lnk') -ErrorAction SilentlyContinue
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }

Write-Host 'Nagenli is removed.'
Write-Host "Your data is still in: $env:APPDATA\Nagenli (delete that folder too to remove everything)."
