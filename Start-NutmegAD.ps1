<#
.NOTES
    Author:  Cliff Waite
    Date:    11/20/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.4.0

.SYNOPSIS
    Launches the Nutmeg AD Toolkit.

.DESCRIPTION
    - Runs in Windows PowerShell 5.1 or PowerShell 7 (7 recommended). Keep this file 5.1-safe.
    - Not elevated: offers to start again as administrator.
    - In Windows PowerShell 5.1: offers to start again in PowerShell 7, or to install the current
      PowerShell 7 LTS release first (Microsoft's signed MSI, Microsoft Update on).
    - Imports the Nutmeg.AD module from this folder (always the copy next to this file) and opens
      the main menu.
    - -LogPath carries on in that log instead of starting a new one (Get-NutmegAD.ps1 passes the log
      it started, so a build has one log from download to the finished DC).
    - -Gui opens the same tools in a window instead of the console menu (Windows only). The window
      needs an STA thread: Windows PowerShell 5.1 has one; PowerShell 7 is started with -STA.
    - -NewForest opens the New Forest Build on a fresh workgroup server instead. It always runs in
      Windows PowerShell 5.1 (the server roles' modules live there), and the build's sign-in task
      starts it this way after each restart. It stays in the console: with -Gui too, -Gui is ignored.

.EXAMPLE
    .\Start-NutmegAD.ps1

.EXAMPLE
    .\Start-NutmegAD.ps1 -Stay
    Stays in the PowerShell it was started in, with no offer to move to PowerShell 7 or elevate.

.EXAMPLE
    .\Start-NutmegAD.ps1 -Gui
    Opens the toolkit in a window: the same tools, confirmations, logs and run history.

.EXAMPLE
    .\Start-NutmegAD.ps1 -NewForest
    Builds the first DC of a new forest on this workgroup server, or carries on with the saved build.

.VERSIONING
    0.4.0 - -Gui: the window (STA; carried through the elevation and PowerShell 7 offers). The build stays in the console.
    0.3.2 - Ignores a -LogPath that starts with '-' (a parameter name passed as the value).
    0.3.1 - Starts in its own folder, so the window is left in the toolkit folder (the sign-in task opened in System32).
    0.3.0 - -LogPath: carry on in an existing log (and pass it on when it starts itself again).
    0.2.0 - -NewForest: the New Forest Build, always in Windows PowerShell 5.1.
    0.1.0 - Initial launcher.
#>
param([switch]$Stay, [switch]$NewForest, [switch]$Gui, [string]$LogPath)

$ScriptVersion = '0.4.0'

if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-Host 'The Nutmeg AD Toolkit needs Windows PowerShell 5.1 or PowerShell 7.' -ForegroundColor Red
    return
}

# Work from the toolkit's folder, however it was started (the build's sign-in task opens in System32),
# so the window is left there, ready to run it again.
Set-Location -LiteralPath $PSScriptRoot

$onWindows = ($env:OS -eq 'Windows_NT')
# A log path that is really a parameter name (or missing) is ignored, not passed on.
if ($LogPath -and $LogPath.StartsWith('-')) { $LogPath = '' }
if ($LogPath) { $env:NUTMEG_AD_LOG = $LogPath }
# Passing the log on: a direct call quotes arguments itself; Start-Process needs the quotes added.
$logArgs = @(); $logArgsQuoted = @()
if ($LogPath) { $logArgs = @('-LogPath', $LogPath); $logArgsQuoted = @('-LogPath', "`"$LogPath`"") }

# The build is console only (Windows PowerShell 5.1, through restarts): never in the window.
if ($NewForest -and $Gui) {
    Write-Host 'The New Forest Build runs in the console only; starting it there.' -ForegroundColor Yellow
    $Gui = $false
}
$guiArgs = @(); if ($Gui) { $guiArgs = @('-Gui') }

# The build runs in Windows PowerShell 5.1: started from PowerShell 7, hand over to it.
if ($NewForest -and $onWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    & powershell.exe -NoLogo -NoProfile -File $PSCommandPath -NewForest @logArgs
    return
}

$modulePath = Join-Path (Join-Path $PSScriptRoot 'Nutmeg.AD') 'Nutmeg.AD.psd1'
try {
    Import-Module $modulePath -Force -ErrorAction Stop
} catch {
    Write-Host "Could not load the toolkit: $($_.Exception.Message)" -ForegroundColor Red
    return
}

if ($onWindows -and -not $Stay) {
    $self = (Get-Process -Id $PID).Path

    if (-not (Test-NmElevated)) {
        Write-Host 'The toolkit is not running as administrator. Some checks and every change need it.' -ForegroundColor Yellow
        if (Read-NmYesNo -Prompt 'Start it again as administrator?' -Default 'Y') {
            $relaunch = @('-NoExit', '-File', "`"$PSCommandPath`"")
            if ($NewForest) { $relaunch += '-NewForest' }
            $relaunch += $guiArgs
            $relaunch += $logArgsQuoted
            Start-Process -FilePath $self -Verb RunAs -ArgumentList $relaunch
            return
        }
    }

    if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $NewForest) {
        $pwsh = Find-NmPwsh
        if (-not $pwsh) {
            Write-Host 'PowerShell 7 is not installed. The toolkit works in Windows PowerShell 5.1, but 7 is recommended.' -ForegroundColor Yellow
            if (Read-NmYesNo -Prompt 'Install the current PowerShell 7 LTS release now (from Microsoft, with Microsoft Update on)?' -Default 'N') {
                $r = Install-NmPowerShell7
                $r | Format-Table Item, Version, Result -AutoSize | Out-Host
                $pwsh = Find-NmPwsh
            }
        }
        if ($pwsh -and (Read-NmYesNo -Prompt 'Start the toolkit in PowerShell 7?' -Default 'Y')) {
            # -STA: the window (WPF) needs it; the console menu does not mind.
            & $pwsh -NoLogo -STA -File $PSCommandPath -Stay @guiArgs @logArgs
            return
        }
    }
}

if ($NewForest) {
    Invoke-NmTool -Id new-forest
    return
}
if ($Gui) {
    if (-not $onWindows) { Write-Host 'The window needs Windows. Opening the console menu.' -ForegroundColor Yellow; Start-NmToolkit; return }
    # WPF needs an STA thread: Windows PowerShell 5.1 has one; PowerShell 7 started without -STA may not.
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $exe = (Get-Process -Id $PID).Path
        Start-Process -FilePath $exe -ArgumentList (@('-STA', '-NoExit', '-File', "`"$PSCommandPath`"", '-Stay', '-Gui') + $logArgsQuoted)
        return
    }
    Start-NmToolkitGui
    return
}
Start-NmToolkit
