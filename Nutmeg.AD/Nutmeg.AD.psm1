<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.2.3

.SYNOPSIS
    Nutmeg.AD - one menu-driven toolkit for Active Directory domain controller onboarding.

.DESCRIPTION
    - Loads the shared core (domain session, logging, menus, exports, safety checks, settings).
    - Discovers every tool under .\Tools\<Category>\*.ps1 and registers it from its $NmTool metadata block.
    - Files whose names start with an underscore (templates, work in progress) are skipped.
    - Exports the core's public functions and every tool's entry function, so tools also run without the menu.

.EXAMPLE
    Import-Module .\Nutmeg.AD\Nutmeg.AD.psd1
    Start-NmToolkit

.EXAMPLE
    Import-Module .\Nutmeg.AD\Nutmeg.AD.psd1
    Get-NmTool | Format-Table AdminCenter, Section, Name, Kind, Version

.VERSIONING
    0.2.3 - GroupPolicy found in PowerShell 7 (Find-NmModule -SkipEditionCheck); result tables wrap instead of cutting text.
    0.2.2 - Downloads run with the progress bar off (Save-NmDownload): Windows PowerShell 5.1 crawled with it on.
    0.2.1 - Get-NutmegAD.ps1 (standalone, next to the launcher): download or update the toolkit on a server.
    0.2.0 - New Forest Build, phases 0 and 1 (new-forest): pre-flight, questions, static IP, name, AD DS, promotion,
            resume after restarts (Core\Server.ps1, Core\Build.ps1); one-confirmation plans in Confirm-NmChange; Read-NmSecret.
    0.1.0 - Core adapted from the Nutmeg M365 Toolkit (logging, settings, menus, exports, safety, tool registry,
            launcher), the domain session (Core\Domain.ps1), the AD and GroupPolicy modules (Core\Modules.ps1),
            the PowerShell 7 install (Core\PowerShell7.ps1) and the first tool, session-info.
#>

# ---------------------------------------------------------------------------
# Module state and default paths
# ---------------------------------------------------------------------------
$script:ModuleVersion = '0.2.3'
$script:NmModuleRoot  = $PSScriptRoot

$script:NmOnWindows = ($env:OS -eq 'Windows_NT')
if ($script:NmOnWindows) {
    $script:NmDefaultRoot = 'C:\Temp'
} else {
    # Non-Windows is for development and tests only; production runs on a DC.
    $script:NmDefaultRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'Temp'
}

$script:NmConfig = [pscustomobject]@{
    ExportRoot       = $script:NmDefaultRoot
    DataRoot         = Join-Path $script:NmDefaultRoot 'NutmegAD'
    BulkConfirmCount = 25        # changes touching more objects than this need the domain name typed
}

# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------
$coreFiles = @('Logging', 'Settings', 'Modules', 'Export', 'Menu', 'Safety', 'Domain', 'PowerShell7', 'Server', 'Build', 'ToolRegistry', 'Launcher')
foreach ($name in $coreFiles) {
    . (Join-Path (Join-Path $PSScriptRoot 'Core') "$name.ps1")
}

# Saved settings over the defaults above; environment variables still win.
try { Update-NmConfigFromSetting } catch { Write-Warning "Settings not applied: $($_.Exception.Message)" }

# ---------------------------------------------------------------------------
# Tools: dot-sourced here, at module scope, so their functions belong to the module
# ---------------------------------------------------------------------------
$script:NmTools          = New-Object System.Collections.Generic.List[object]
$script:NmToolLoadErrors = New-Object System.Collections.Generic.List[object]

$toolRoot = Join-Path $PSScriptRoot 'Tools'
if (Test-Path $toolRoot) {
    $toolFiles = Get-ChildItem -Path $toolRoot -Filter '*.ps1' -Recurse -File |
        Where-Object { $_.Name -notlike '_*' -and $_.FullName -notmatch '[\\/]_' } |
        Sort-Object FullName

    foreach ($file in $toolFiles) {
        $NmTool = $null
        # A syntax error in a dot-sourced file is not always thrown, so check first and report it.
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            $first = $parseErrors[0]
            $script:NmToolLoadErrors.Add([pscustomobject]@{
                File   = $file.FullName
                Reason = "Syntax error at line $($first.Extent.StartLineNumber): $($first.Message)"
            })
            continue
        }
        try {
            . $file.FullName
            Register-NmTool -Definition $NmTool -Path $file.FullName
        } catch {
            $script:NmToolLoadErrors.Add([pscustomobject]@{
                File   = $file.FullName
                Reason = "Failed to load: $($_.Exception.Message)"
            })
        }
        Remove-Variable -Name NmTool -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
$publicCore = @(
    'Start-NmToolkit'
    'Get-NmTool', 'Get-NmAdminCenter', 'Invoke-NmTool', 'Get-NmToolLoadError'
    'Get-NmSession', 'Assert-NmConnection', 'Get-NmServiceState', 'Set-NmServer', 'Get-NmADParams', 'Get-NmGPParams'
    'Get-NmLocalComputer', 'Test-NmElevated', 'Get-NmAdminMembership'
    'Write-NmLog', 'Get-NmLogPath', 'Write-NmRunHistory', 'Get-NmRunHistory'
    'Show-NmHeader', 'Show-NmMenu', 'Show-NmResultMenu', 'Show-NmResult', 'Add-NmIndex',
    'Read-NmInput', 'Read-NmYesNo', 'Read-NmMultiChoice', 'Wait-NmKey'
    'Export-NmResult', 'Confirm-NmChange', 'Assert-NmModule'
    'Get-NmSetting', 'Set-NmSetting', 'Clear-NmSetting'
    'Find-NmPwsh', 'Install-NmPowerShell7', 'Read-NmSecret'
)
$toolEntries = @($script:NmTools | ForEach-Object { $_.Entry })
Export-ModuleMember -Function ($publicCore + $toolEntries)
