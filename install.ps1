# Installs Nagenli on Windows, or repairs/upgrades an existing install. Open PowerShell and run:
#   irm https://quantumleapinco.github.io/nagenli-releases/install.ps1 | iex
#
# What it does, in order:
#   1. Downloads manifest.json and Nagenli-Setup.exe from https://quantumleapinco.github.io/nagenli-releases
#      into a new folder in your Temp folder. Nothing else is downloaded.
#   2. Checks the installer's size and SHA-256 fingerprint against manifest.json, and stops if they differ.
#   3. Runs the installer. It puts Nagenli in %LOCALAPPDATA%\Programs\Nagenli, in the Start menu, and makes it
#      start with Windows. Nagenli updates itself from then on. No administrator rights are needed.
#   4. Deletes the downloaded files.
# A file fetched by PowerShell itself does not get Windows' "downloaded from the internet" mark, so
# Windows does not show its blue "protected your PC" window. Nothing is sent anywhere but the download requests.
#
# Exit codes (when the file is run directly; pasted into PowerShell it sets $LASTEXITCODE): 0 installed,
# 1 could not download, 2 the download does not match the release, 3 the installer did not finish.
# To try it without installing: set $env:NAGENLI_DRY = 1 first; it stops after the check.

function Install-Nagenli {
    $Base = 'https://quantumleapinco.github.io/nagenli-releases'
    $Name = 'Nagenli-Setup.exe'
    $dry = [bool]$env:NAGENLI_DRY
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue' # the progress bar makes downloads very slow in Windows PowerShell 5.1
    # Windows PowerShell 5.1 does not use a modern TLS version unless asked to.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $dir = Join-Path ([IO.Path]::GetTempPath()) ('nagenli-install-' + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        Write-Host 'Downloading Nagenli...'
        try {
            Invoke-WebRequest -UseBasicParsing "$Base/manifest.json" -OutFile (Join-Path $dir 'manifest.json')
            $want = (Get-Content (Join-Path $dir 'manifest.json') -Raw | ConvertFrom-Json).files.$Name
            if (-not $want) { throw "This release has no $Name." }
            Invoke-WebRequest -UseBasicParsing "$Base/$Name" -OutFile (Join-Path $dir $Name)
        } catch {
            Write-Host "Could not download Nagenli: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host 'Check your internet connection and run the command again.'
            return 1
        }

        $file = Join-Path $dir $Name
        $got = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLower()
        if ((Get-Item $file).Length -ne $want.size -or $got -ne $want.sha256) {
            Write-Host 'The download is damaged (its size or fingerprint does not match the release). Nothing was installed. Try again.' -ForegroundColor Red
            return 2
        }
        Write-Host "Downloaded and checked: $Name, $([math]::Round($want.size / 1MB, 1)) MB, SHA-256 $got"

        if ($dry) {
            $mark = Get-Item $file -Stream Zone.Identifier -ErrorAction SilentlyContinue
            Write-Host "NAGENLI_DRY is set: stopping before the installer runs. Internet mark on the file: $(if ($mark) { 'yes' } else { 'none' })."
            return 0
        }

        Write-Host 'Installing Nagenli (for your user only; no administrator rights)...'
        $p = Start-Process -FilePath $file -PassThru
        # The installer copies itself, starts the installed Nagenli and ends. If it stays, something went wrong.
        if (-not $p.WaitForExit(120000)) {
            Write-Host 'The installer did not finish. Nothing more was done.' -ForegroundColor Red
            return 3
        }
        $installed = Join-Path $env:LOCALAPPDATA 'Programs\Nagenli\nagenli.exe'
        if (-not (Test-Path $installed) -or (Get-FileHash -Algorithm SHA256 $installed).Hash.ToLower() -ne $got) {
            Write-Host "The installer ended but Nagenli is not in place at $installed." -ForegroundColor Red
            return 3
        }
        Write-Host 'Nagenli is installed and starts with Windows.'
        Write-Host 'It opens in your browser at http://127.0.0.1:8686 and its icon sits next to the clock.'
        Write-Host 'If Windows Firewall asks, click Allow access: without it your phone and TV cannot find this computer.'
        return 0
    } finally {
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$code = Install-Nagenli
$global:LASTEXITCODE = $code
# Run as a file, leave with the code; pasted into a window (or through iex), never close the person's window.
if ($MyInvocation.MyCommand.Path) { exit $code }
