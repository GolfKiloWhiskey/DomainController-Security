# ---------------------------------------------------------------------------
# Launcher.ps1 - Start-NmToolkit: the main menu, built from the tool registry
# ---------------------------------------------------------------------------

# Set when a finished New Forest Build hands over to the toolkit (Request-NmToolkitHandOff);
# Start-NutmegAD.ps1 reads it once the build's window or menu has closed.
$script:NmToolkitHandOff = $false

function Request-NmToolkitHandOff {
    <#
    .SYNOPSIS
        The build is finished: close the build (its window, if open) and let the launcher open the toolkit.
    #>
    [CmdletBinding()]
    param()
    $script:NmToolkitHandOff = $true
    Write-NmLog 'The build is finished: handing over to the toolkit.' -Level INFO -NoConsole
    if ($script:NmGui -and $script:NmGui.Active -and $script:NmGui.Window) {
        # After the current dialog's handler returns, not from inside it.
        $win = $script:NmGui.Window
        [void]$win.Dispatcher.BeginInvoke([action]{ $win.Close() }.GetNewClosure())
    }
}

function Get-NmToolkitHandOff {
    # True once a finished build asked for the toolkit (read by Start-NutmegAD.ps1).
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return [bool]$script:NmToolkitHandOff
}

function Get-NmStartMode {
    <#
    .SYNOPSIS
        What Start-NutmegAD.ps1 opens when it is not told: the New Forest Build or the toolkit,
        with the reason. No questions, nothing changed.
    .DESCRIPTION
        - A build saved on this server and not finished: the build, to carry on.
        - Not joined to a domain (a fresh workgroup server): the build.
        - Otherwise (a DC or a domain member, or a finished build): the toolkit.
    .OUTPUTS
        Mode ('NewForest' or 'Toolkit') and Reason.
    #>
    [CmdletBinding()]
    param($Computer, $BuildState, [switch]$NoState)
    try { if (-not $Computer) { $Computer = Get-NmLocalComputer } } catch { $Computer = $null }
    if (-not $NoState -and $null -eq $BuildState) { try { $BuildState = Get-NmBuildState } catch { $BuildState = $null } }
    if ($BuildState -and $BuildState.Answers -and -not $BuildState.Finished) {
        return [pscustomobject]@{ Mode = 'NewForest'; Reason = "A New Forest Build of $($BuildState.Answers.Domain) is in progress on this server: carrying on with it." }
    }
    if ($Computer -and -not $Computer.PartOfDomain) {
        return [pscustomobject]@{ Mode = 'NewForest'; Reason = "$($Computer.Name) is in a workgroup: opening the New Forest Build (the toolkit's other tools need a domain)." }
    }
    return [pscustomobject]@{ Mode = 'Toolkit'; Reason = '' }
}

function Show-NmToolList {
    # A menu of tools (one category, or search hits). Runs the one picked; loops until Back.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Tools,
        # Optional, one per tool: "Also in ..." / "Home: ..." shown after the synopsis.
        [string[]]$Notes = @()
    )

    if ($Tools.Count -eq 0) {
        Write-NmLog 'No tools match.' -Level WARN
        Wait-NmKey
        return
    }

    while ($true) {
        $i = 0
        $options = @(foreach ($t in $Tools) {
            $i++
            $tag = if ($t.Kind -ne 'Report') { '[CHANGE]' } else { $null }
            $detail = $t.Synopsis
            if ($Notes.Count -ge $i -and $Notes[$i - 1]) { $detail = "$detail  ($($Notes[$i - 1]))" }
            [pscustomobject]@{ Key = "$i"; Label = $t.Name; Tag = $tag; Detail = $detail }
        })
        $choice = Show-NmMenu -Title $Title -Options $options -Back
        if ($choice -eq 'B') { return }
        Invoke-NmTool -Id $Tools[[int]$choice - 1].Id
        if ($script:NmGoMain) { return }
    }
}

function Get-NmCenterState {
    # 'loaded', 'partly loaded' or 'not loaded yet', from the modules the area's tools use.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Center)
    $svc = @($Center.Services)
    if ($svc.Count -eq 0) { return 'nothing to load' }
    $up = @($svc | Where-Object { $script:NmSession.Services[$_] }).Count
    if ($up -eq $svc.Count) { 'loaded' } elseif ($up -gt 0) { 'partly loaded' } else { 'not loaded yet' }
}

function Show-NmAdminCenterMenu {
    # One admin center: its sections (or straight to the tools when it has only one). Loops until Back.
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Center)

    if ($Center.Sections.Count -eq 1) {
        $sec = $Center.Sections[0]
        Show-NmToolList -Title $Center.Name -Tools @($sec.Items.Tool) -Notes @($sec.Items.Note)
        return
    }
    while ($true) {
        $i = 0
        $options = @(foreach ($sec in $Center.Sections) {
            $i++
            [pscustomobject]@{ Key = "$i"; Label = $sec.Name; Detail = "$($sec.Items.Count) tool(s)" }
        })
        $options += [pscustomobject]@{ Key = 'A'; Label = "All $($Center.Name) tools"; Detail = "$($Center.Count) tool(s)" }
        $choice = Show-NmMenu -Title $Center.Name -Options $options -Back
        if ($choice -eq 'B') { return }
        if ($choice -eq 'A') {
            $items = @($Center.Sections | ForEach-Object { $_.Items } | Where-Object { $_.IsHome } | Sort-Object { $_.Tool.Name })
            Push-NmNav 'All tools'
            try { Show-NmToolList -Title "All $($Center.Name) tools" -Tools @($items.Tool) -Notes @($items.Note) } finally { Pop-NmNav }
        } else {
            $sec = $Center.Sections[[int]$choice - 1]
            Push-NmNav $sec.Name
            try { Show-NmToolList -Title "$($Center.Name) > $($sec.Name)" -Tools @($sec.Items.Tool) -Notes @($sec.Items.Note) } finally { Pop-NmNav }
        }
        if ($script:NmGoMain) { return }
    }
}

function Start-NmToolkit {
    <#
    .SYNOPSIS
        Opens the Nutmeg AD Toolkit main menu.
    .DESCRIPTION
        - Clears the screen on start and deletes old session logs (Settings).
        - Main menu: the areas (Group Policy, Active Directory, Readiness, Reports, Toolkit) with tool
          counts and whether their modules are loaded; each opens its sections, then the tools. Plus
          Search, Domain and DC, Run history, Settings and tools that did not load.
        - Reads the domain and DC on start (loading ActiveDirectory) so the header shows them right
          away; GroupPolicy loads when a GPO tool needs it.
    #>
    [CmdletBinding()]
    param()

    Clear-NmScreen
    Write-NmLog "Nutmeg AD Toolkit $script:ModuleVersion started. Log: $(Get-NmLogPath)" -Level INFO -NoConsole
    $null = Remove-NmOldLog
    $null = Initialize-NmStartupDomain

    while ($true) {
        $script:NmGoMain = $false
        $centers = @(Get-NmAdminCenter)

        $i = 0
        $options = @(foreach ($c in $centers) {
            $i++
            [pscustomobject]@{ Key = "$i"; Label = $c.Name; Detail = "$($c.Count) tool(s), $(Get-NmCenterState -Center $c)" }
        })
        $options += [pscustomobject]@{ Key = 'S'; Label = 'Search tools' }
        $options += [pscustomobject]@{ Key = 'D'; Label = 'Domain and DC'; Detail = 'status, work against another DC' }
        $options += [pscustomobject]@{ Key = 'H'; Label = 'Run history' }
        $options += [pscustomobject]@{ Key = 'T'; Label = 'Settings'; Detail = 'folders, log retention, safety' }
        $loadErrors = @(Get-NmToolLoadError)
        if ($loadErrors.Count -gt 0) {
            $options += [pscustomobject]@{ Key = 'L'; Label = 'Tools not loaded'; Tag = "($($loadErrors.Count))" }
        }

        $choice = Show-NmMenu -Title 'Nutmeg AD Toolkit' -Options $options

        switch -Regex ($choice) {
            '^\d+$' {
                $center = $centers[[int]$choice - 1]
                Push-NmNav $center.Name
                try { Show-NmAdminCenterMenu -Center $center } finally { Pop-NmNav }
            }
            '^S$' {
                $term = Read-NmInput -Prompt 'Search for'
                if ($term) {
                    Push-NmNav "Search: $term"
                    try { Show-NmToolList -Title "Search: $term" -Tools (Get-NmTool -Search $term) } finally { Pop-NmNav }
                }
            }
            '^D$' { Push-NmNav 'Domain and DC'; try { Show-NmDomainMenu } finally { Pop-NmNav } }
            '^T$' { Push-NmNav 'Settings'; try { Show-NmSettingsMenu } finally { Pop-NmNav } }
            '^H$' {
                $rows = @(Get-NmRunHistory -Last 20)
                if ($rows.Count -eq 0) {
                    Write-NmLog 'No runs recorded yet.' -Level INFO
                } else {
                    $rows | Format-Table Timestamp, Domain, Server, ToolId, Kind, Mode, ItemCount, Result -AutoSize | Out-Host
                }
                Wait-NmKey
            }
            '^L$' {
                $loadErrors | Format-List File, Reason | Out-Host
                Wait-NmKey
            }
            '^Q$' {
                Write-NmLog 'Nutmeg AD Toolkit closed.' -Level INFO
                return
            }
        }
    }
}
