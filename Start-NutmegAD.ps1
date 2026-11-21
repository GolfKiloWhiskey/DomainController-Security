<#
.NOTES
    Author:  Cliff Waite
    Date:    11/20/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.6.0

.SYNOPSIS
    Launches the Nutmeg AD Toolkit.

.DESCRIPTION
    - Opens the window by default (Windows only); -Console opens the console menu instead.
      -Gui is still accepted (it was the switch for the window before 0.6.0) and changes nothing.
    - Runs in PowerShell 7 whenever it is installed: started in Windows PowerShell 5.1, it moves to
      PowerShell 7 without asking (with -STA, which the window needs). Not installed: it offers to
      install the current LTS release (Microsoft's signed MSI, Microsoft Update on) and carries on in
      5.1 if declined. Keep this file 5.1-safe.
    - Not elevated: offers to start again as administrator.
    - Imports the Nutmeg.AD module from this folder (always the copy next to this file).
    - -LogPath carries on in that log instead of starting a new one (Get-NutmegAD.ps1 passes the log
      it started, so a build has one log from download to the finished DC).
    - -NewForest opens the New Forest Build on a fresh workgroup server, in the window unless
      -Console. It always runs in Windows PowerShell 5.1 (the server roles' modules live there), and
      the build's sign-in task starts it the same way (window or console) after each restart.

.EXAMPLE
    .\Start-NutmegAD.ps1
    The window, in PowerShell 7 when it is installed.

.EXAMPLE
    .\Start-NutmegAD.ps1 -Console
    The console menu.

.EXAMPLE
    .\Start-NutmegAD.ps1 -Stay
    Stays in the PowerShell it was started in, with no move to PowerShell 7 and no offer to elevate.

.EXAMPLE
    .\Start-NutmegAD.ps1 -NewForest
    The New Forest Build in the window (Windows PowerShell 5.1): questions, plan and DSRM password as dialogs.

.EXAMPLE
    .\Start-NutmegAD.ps1 -NewForest -Console
    The New Forest Build in the console.

.VERSIONING
    0.6.0 - The window by default (-Console for the console); PowerShell 7 used without asking when installed.
    0.5.0 - -NewForest -Gui: the build in the window (Windows PowerShell 5.1); no longer sent to the console.
    0.4.0 - -Gui: the window (STA; carried through the elevation and PowerShell 7 offers). The build stays in the console.
    0.3.2 - Ignores a -LogPath that starts with '-' (a parameter name passed as the value).
    0.3.1 - Starts in its own folder, so the window is left in the toolkit folder (the sign-in task opened in System32).
    0.3.0 - -LogPath: carry on in an existing log (and pass it on when it starts itself again).
    0.2.0 - -NewForest: the New Forest Build, always in Windows PowerShell 5.1.
    0.1.0 - Initial launcher.
#>
param([switch]$Stay, [switch]$NewForest, [switch]$Console, [switch]$Gui, [string]$LogPath)

$ScriptVersion = '0.6.0'

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

# The window unless -Console (or off Windows, where there is no window); every restart of this
# script below passes the choice on.
$useWindow = $onWindows -and -not $Console
$modeArgs = @(); if (-not $useWindow) { $modeArgs = @('-Console') }

# The build runs in Windows PowerShell 5.1: started from PowerShell 7, hand over to it.
if ($NewForest -and $onWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    & powershell.exe -NoLogo -NoProfile -File $PSCommandPath -NewForest @modeArgs @logArgs
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
            $relaunch += $modeArgs
            $relaunch += $logArgsQuoted
            Start-Process -FilePath $self -Verb RunAs -ArgumentList $relaunch
            return
        }
    }

    # PowerShell 7 whenever it is installed (Cliff): no question. The build stays in 5.1.
    if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $NewForest) {
        $pwsh = Find-NmPwsh
        if (-not $pwsh) {
            Write-Host 'PowerShell 7 is not installed. The toolkit works in Windows PowerShell 5.1, but 7 is recommended.' -ForegroundColor Yellow
            if (Read-NmYesNo -Prompt 'Install the current PowerShell 7 LTS release now (from Microsoft, with Microsoft Update on)?' -Default 'Y') {
                $r = Install-NmPowerShell7
                $r | Format-Table Item, Version, Result -AutoSize | Out-Host
                $pwsh = Find-NmPwsh
            }
        }
        if ($pwsh) {
            Write-Host "Starting the toolkit in PowerShell 7 ($pwsh)." -ForegroundColor DarkGray
            # -STA: the window (WPF) needs it; the console menu does not mind.
            & $pwsh -NoLogo -STA -File $PSCommandPath -Stay @modeArgs @logArgs
            return
        }
    }
}

if (-not $useWindow -and -not $onWindows -and -not $Console) { Write-Host 'The window needs Windows. Opening the console.' -ForegroundColor Yellow }

if ($NewForest) {
    if ($useWindow) {
        # Windows PowerShell 5.1 is STA already; started otherwise, start it again so.
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
            Start-Process -FilePath 'powershell.exe' -ArgumentList (@('-STA', '-NoExit', '-NoProfile', '-File', "`"$PSCommandPath`"", '-Stay', '-NewForest') + $logArgsQuoted)
            return
        }
        Start-NmToolkitGui -NewForest
        return
    }
    Invoke-NmTool -Id new-forest
    return
}
if ($useWindow) {
    # WPF needs an STA thread: Windows PowerShell 5.1 has one; PowerShell 7 started without -STA may not.
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $exe = (Get-Process -Id $PID).Path
        Start-Process -FilePath $exe -ArgumentList (@('-STA', '-NoExit', '-File', "`"$PSCommandPath`"", '-Stay') + $logArgsQuoted)
        return
    }
    Start-NmToolkitGui
    return
}
Start-NmToolkit
