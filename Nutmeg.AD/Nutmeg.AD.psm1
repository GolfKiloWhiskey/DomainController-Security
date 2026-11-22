<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.9

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
    0.7.9 - 1.1.1.1 last on a DC's DNS (setting BuildLastDns; Get-NmLastDns, Add-NmLastDns, Set-NmDnsServer): the build sets it, the
            DC report and health check expect it. CLAUDE.md: check GitHub (open PRs, newest main) before new work.
    0.7.8 - DC Report (dc-report, Reports): a report per DC. DcHealth checks reach another DC (CIM, w32tm /computer:, dcdiag /s:);
            Get-NmDcNetwork, Get-NmSysvolState; Open-NmReport moved to Core\Report.ps1.
    0.7.7 - Reports: Core\Report.ps1 (self-contained HTML, PDF through headless Edge), Core\DcHealth.ps1 (DC health checks,
            dcdiag). The New Forest Build ends with its report; build steps record when they began.
    0.7.6 - The window opens sized to the usable screen with a margin (Get-NmGuiWindowPlacement); maximised on a small screen.
    0.7.5 - Step progress from the VM run: a status that is only a percent shows the activity with the percent once; the status
            bar keeps the last progress between records.
    0.7.4 - Core\Steps.ps1: a live step list for long runs (window panel, console lines, progress in the log); background calls
            pass their progress on; the Output panel follows along. The New Forest Build uses it.
    0.7.3 - Fixed the restart loop after promotion (restart steps saved before their notice; Get-NmLastBootTime); notices
            with only words open as the modern dialog. New Forest Build results: a Build card (the answers) first and a Still to do card last; cards whose rows share one
            status no longer repeat it on every line.
    0.7.2 - New Forest Build: server check its own pop-up first; a pending restart ends phase 0 even without a rename; before AD DS a
            pending restart stops the build: restart now or within 30 minutes (reminders every 5). Stop-NmScheduledRestart, Get-NmNow.
    0.7.1 - From Cliff's VM review: build answers saved as given (Core\Build.ps1 drafts) and checked again on carry-on; domain and
            IP checked at their question; time zone list; window dialogs fit the window, keep their section, show check
            badges; status bar per question; approval facts; a card per phase; restart notice; cleaner Output panel.
    0.7.0 - Launcher 0.7.0 checks the server at start (Get-NmStartMode): the build on a workgroup server or with a build
            in progress, the toolkit otherwise; -Toolkit to skip the check.
    0.6.0 - Launcher 0.6.0: the window by default (-Console for the console), PowerShell 7 without asking when installed;
            the sign-in task passes -Console for a console build; Get-NutmegAD.ps1 1.9.
    0.5.0 - Modern dialogs: no console text (sections, notes, tables, suggested answers), one approval dialog for changes
            (Read-NmGuiConfirm), long steps in the background (Invoke-NmGuiBackground); build mode shows this server.
    0.4.0 - The New Forest Build in the window (Start-NmToolkitGui -NewForest, password dialog, sign-in task reopens the window);
            Get-NutmegAD.ps1 1.8 installs PowerShell 7 without asking and opens the build in the window (Install-NmPowerShell7 -ApprovedBy).
    0.3.1 - Get-NutmegAD.ps1 1.7 opens the window after the download on a domain member or DC (-Console for the menu).
    0.3.0 - The window (Core\Gui.ps1, Start-NmToolkitGui; Start-NutmegAD.ps1 -Gui), ported from the Nutmeg M365 Toolkit
            without its tenant, cloud and sign-in pieces. The New Forest Build stays console only.
    0.2.11 - Get-NutmegAD.ps1 1.6 updates itself from the download and steps out of the toolkit folder before replacing it.
    0.2.10 - Get-NutmegAD.ps1 1.5 hands -NewForest/-LogPath over as named parameters; launcher 0.3.2 ignores a bad -LogPath.
    0.2.9 - The window is left in the toolkit folder: the launcher moves there, the sign-in task starts there.
    0.2.8 - New Forest Build: Eastern Standard Time is the default time zone (Settings > New forest build).
    0.2.7 - One log across restarts: Get-NutmegAD.ps1 starts it, Start-NutmegAD.ps1 -LogPath and the build's state carry it on.
    0.2.6 - Log fixes from the VM run: each build step logs its result; time zone note; Closed vs Cancelled; no ((no domain)).
    0.2.5 - Clean screens at start: Get-NutmegAD.ps1 1.3 and the New Forest Build (issue #6).
    0.2.4 - Get-NutmegAD.ps1 1.2 starts the toolkit after the download (the build on a workgroup server).
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
$script:ModuleVersion = '0.7.9'
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
$coreFiles = @('Logging', 'Settings', 'Modules', 'Export', 'Menu', 'Safety', 'Domain', 'PowerShell7', 'Server', 'Steps', 'Report', 'DcHealth', 'Build', 'ToolRegistry', 'Launcher', 'Gui')
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
    'Start-NmToolkit', 'Start-NmToolkitGui', 'Get-NmStartMode'
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
