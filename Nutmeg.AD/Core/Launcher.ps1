# ---------------------------------------------------------------------------
# Launcher.ps1 - Start-NmToolkit: the main menu, built from the tool registry
# ---------------------------------------------------------------------------

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
        - Nothing is loaded at start: the first tool that needs the AD or GroupPolicy module loads it
          and reads the domain.
    #>
    [CmdletBinding()]
    param()

    Clear-NmScreen
    Write-NmLog "Nutmeg AD Toolkit $script:ModuleVersion started. Log: $(Get-NmLogPath)" -Level INFO -NoConsole
    $null = Remove-NmOldLog

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
