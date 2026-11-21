<#
.NOTES
    Author:  Cliff Waite
    Date:    11/20/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.1.0

.SYNOPSIS
    Launches the Nutmeg AD Toolkit.

.DESCRIPTION
    - Runs in Windows PowerShell 5.1 or PowerShell 7 (7 recommended). Keep this file 5.1-safe.
    - Not elevated: offers to start again as administrator.
    - In Windows PowerShell 5.1: offers to start again in PowerShell 7, or to install the current
      PowerShell 7 LTS release first (Microsoft's signed MSI, Microsoft Update on).
    - Imports the Nutmeg.AD module from this folder (always the copy next to this file) and opens
      the main menu.
    - -NewForest opens the New Forest Build on a fresh workgroup server instead. It always runs in
      Windows PowerShell 5.1 (the server roles' modules live there), and the build's sign-in task
      starts it this way after each restart.

.EXAMPLE
    .\Start-NutmegAD.ps1

.EXAMPLE
    .\Start-NutmegAD.ps1 -Stay
    Stays in the PowerShell it was started in, with no offer to move to PowerShell 7 or elevate.

.EXAMPLE
    .\Start-NutmegAD.ps1 -NewForest
    Builds the first DC of a new forest on this workgroup server, or carries on with the saved build.

.VERSIONING
    0.2.0 - -NewForest: the New Forest Build, always in Windows PowerShell 5.1.
    0.1.0 - Initial launcher.
#>
param([switch]$Stay, [switch]$NewForest)

$ScriptVersion = '0.2.0'

if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    Write-Host 'The Nutmeg AD Toolkit needs Windows PowerShell 5.1 or PowerShell 7.' -ForegroundColor Red
    return
}

$onWindows = ($env:OS -eq 'Windows_NT')

# The build runs in Windows PowerShell 5.1: started from PowerShell 7, hand over to it.
if ($NewForest -and $onWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    & powershell.exe -NoLogo -NoProfile -File $PSCommandPath -NewForest
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
            & $pwsh -NoLogo -File $PSCommandPath -Stay
            return
        }
    }
}

if ($NewForest) {
    Invoke-NmTool -Id new-forest
    return
}
Start-NmToolkit
