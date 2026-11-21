# ---------------------------------------------------------------------------
# ToolRegistry.ps1 - validates tool metadata, lists tools and runs them
# ---------------------------------------------------------------------------
# Every file in Tools\<Category>\ defines a $NmTool hashtable and an entry function.
# See Tools\_ToolTemplate.ps1 for the full format.

$script:NmToolKinds    = @('Report', 'Change', 'ReportAndChange')
$script:NmToolRequired = @('Name', 'Id', 'Category', 'Synopsis', 'Version', 'Kind', 'Services', 'Entry')

# Areas ("admin centers" in the code, as in M365-Tools): the top level of the menu, in display order.
# A tool says where it lives with Area = '<area id>/<Section>' (or just '<area id>' for the area's
# first section) and can list other places with AlsoIn = @('<area id>/<Section>').
# Sections not named here are allowed; they are listed after the named ones.
$script:NmAdminCenters = @(
    [pscustomobject]@{ Id = 'gpo';    Name = 'Group Policy';        Sections = @('Baselines', 'Links and filtering', 'WMI filters', 'Central store', 'Inventory') }
    [pscustomobject]@{ Id = 'ad';     Name = 'Active Directory';    Sections = @('Structure', 'Groups', 'Computers', 'Users', 'Service accounts', 'Domain and forest') }
    [pscustomobject]@{ Id = 'ready';  Name = 'Hardening readiness'; Sections = @('Readiness') }
    [pscustomobject]@{ Id = 'report'; Name = 'Reports';             Sections = @('Reports') }
    [pscustomobject]@{ Id = 'build';  Name = 'New forest build';    Sections = @('First DC') }
    [pscustomobject]@{ Id = 'kit';    Name = 'Toolkit';             Sections = @('Diagnostics') }
    [pscustomobject]@{ Id = 'other';  Name = 'Other';               Sections = @('Other tools') }
)

# Where a tool without an Area goes, by its Category.
$script:NmCategoryArea = @{
    'GroupPolicy' = 'gpo'
    'Directory'   = 'ad'
    'Readiness'   = 'ready'
    'Reports'     = 'report'
    'Build'       = 'build'
    'Diagnostics' = 'kit'
}

function Resolve-NmToolArea {
    <#
    .SYNOPSIS
        Turns '<center id>' or '<center id>/<Section>' into a full '<center id>/<Section>', or $null if the center is unknown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Area)

    if (-not $Area) { return $null }
    $parts = $Area -split '/', 2
    $center = $script:NmAdminCenters | Where-Object { $_.Id -eq $parts[0].Trim().ToLower() } | Select-Object -First 1
    if (-not $center) { return $null }
    $section = if ($parts.Count -gt 1 -and $parts[1].Trim()) { $parts[1].Trim() } else { $center.Sections[0] }
    # Match a named section case-insensitively so 'gpo/inventory' lands in 'Inventory'.
    $named = $center.Sections | Where-Object { $_ -eq $section } | Select-Object -First 1
    if ($named) { $section = $named }
    return "$($center.Id)/$section"
}

function Register-NmTool {
    <#
    .SYNOPSIS
        Validates one tool's $NmTool block and adds it to the registry. Problems go to Get-NmToolLoadError.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Definition,
        [Parameter(Mandatory)][string]$Path
    )

    $fail = {
        param($reason)
        $script:NmToolLoadErrors.Add([pscustomobject]@{ File = $Path; Reason = $reason })
    }

    if ($null -eq $Definition -or $Definition -isnot [hashtable]) {
        & $fail 'No $NmTool hashtable found in the file.'
        return
    }

    $missing = @($script:NmToolRequired | Where-Object { -not $Definition.ContainsKey($_) -or $null -eq $Definition[$_] })
    # Services may be an empty array (a tool that needs no connection), so only its absence counts.
    $missing = @($missing | Where-Object { $_ -ne 'Services' -or -not $Definition.ContainsKey('Services') })
    if ($missing.Count -gt 0) {
        & $fail "Missing field(s): $($missing -join ', ')."
        return
    }

    if ($Definition.Id -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        & $fail "Id '$($Definition.Id)' must be lower-case words joined by hyphens."
        return
    }
    if ($script:NmToolKinds -notcontains $Definition.Kind) {
        & $fail "Kind '$($Definition.Kind)' must be one of: $($script:NmToolKinds -join ', ')."
        return
    }
    $badSvc = @(@($Definition.Services) | Where-Object { $script:NmKnownServices -notcontains $_ })
    if ($badSvc.Count -gt 0) {
        & $fail "Unknown service(s): $($badSvc -join ', '). Known: $($script:NmKnownServices -join ', ')."
        return
    }
    if (-not (Get-Command -Name $Definition.Entry -CommandType Function -ErrorAction SilentlyContinue)) {
        & $fail "Entry function '$($Definition.Entry)' is not defined in the file."
        return
    }
    if ($Definition.View -and @('Table', 'Findings') -notcontains "$($Definition.View)") {
        & $fail "View '$($Definition.View)' must be Table or Findings."
        return
    }
    $cardGroup = @($Definition.CardGroup | Where-Object { "$_".Trim() } | ForEach-Object { "$_" })
    if ($cardGroup.Count -gt 2) {
        & $fail "CardGroup takes one or two column names (group by, then split by), not $($cardGroup.Count)."
        return
    }
    if ($Definition.DeepDive -and -not (Get-Command -Name $Definition.DeepDive -CommandType Function -ErrorAction SilentlyContinue)) {
        & $fail "DeepDive function '$($Definition.DeepDive)' is not defined in the file."
        return
    }
    if ($Definition.BulkAction) {
        if (-not (Get-Command -Name $Definition.BulkAction -CommandType Function -ErrorAction SilentlyContinue)) {
            & $fail "BulkAction function '$($Definition.BulkAction)' is not defined in the file."
            return
        }
        $labels = @($Definition.BulkActions | Where-Object { "$_".Trim() })
        if ($labels.Count -lt 1 -or $labels.Count -gt 6) {
            & $fail 'BulkActions needs 1 to 6 button labels for BulkAction.'
            return
        }
    }
    foreach ($hook in 'Prompt', 'Summary') {
        if ($Definition[$hook] -and -not (Get-Command -Name $Definition[$hook] -CommandType Function -ErrorAction SilentlyContinue)) {
            & $fail "$hook function '$($Definition[$hook])' is not defined in the file."
            return
        }
    }
    $areaText = if ($Definition.Area) { "$($Definition.Area)" } elseif ($script:NmCategoryArea.ContainsKey("$($Definition.Category)")) { $script:NmCategoryArea["$($Definition.Category)"] } else { 'other' }
    $area = Resolve-NmToolArea -Area $areaText
    if (-not $area) {
        & $fail "Area '$areaText' names an unknown admin center. Known: $(($script:NmAdminCenters.Id) -join ', ')."
        return
    }
    $alsoIn = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($Definition.AlsoIn | Where-Object { $_ })) {
        $r = Resolve-NmToolArea -Area "$a"
        if (-not $r) {
            & $fail "AlsoIn '$a' names an unknown admin center. Known: $(($script:NmAdminCenters.Id) -join ', ')."
            return
        }
        if ($r -ne $area -and -not $alsoIn.Contains($r)) { $alsoIn.Add($r) }
    }
    if (@($script:NmTools | Where-Object { $_.Id -eq $Definition.Id }).Count -gt 0) {
        & $fail "Duplicate tool Id '$($Definition.Id)'."
        return
    }

    $script:NmTools.Add([pscustomobject]@{
        Name           = $Definition.Name
        Id             = $Definition.Id
        Category       = $Definition.Category
        AdminCenter    = ($area -split '/', 2)[0]
        Section        = ($area -split '/', 2)[1]
        AlsoIn         = $alsoIn.ToArray()
        Synopsis       = $Definition.Synopsis
        Version        = "$($Definition.Version)"
        Kind           = $Definition.Kind
        Services       = @($Definition.Services | Where-Object { $_ })
        Roles          = @($Definition.Roles | Where-Object { $_ })
        Entry          = $Definition.Entry
        DeepDive       = $Definition.DeepDive
        Prompt         = $Definition.Prompt
        Summary        = $Definition.Summary
        Columns        = @($Definition.Columns | Where-Object { $_ })
        View           = $(if ($Definition.View) { "$($Definition.View)" } else { 'Table' })
        CardGroup      = $cardGroup
        BulkAction     = $Definition.BulkAction
        BulkActions    = @($Definition.BulkActions | Where-Object { "$_".Trim() } | ForEach-Object { "$_" })
        Path           = $Path
    })
}

function Get-NmTool {
    <#
    .SYNOPSIS
        Lists registered tools, optionally filtered by Id, category or a search term.
    #>
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$Category,
        [string]$AdminCenter,
        [string]$Section,
        [string]$Search
    )
    $tools = $script:NmTools
    if ($Id)       { $tools = $tools | Where-Object { $_.Id -eq $Id } }
    if ($Category) { $tools = $tools | Where-Object { $_.Category -eq $Category } }
    if ($AdminCenter) {
        # Includes tools listed here with AlsoIn. -Section narrows to one section of the center.
        $tools = $tools | Where-Object {
            ($_.AdminCenter -eq $AdminCenter -and (-not $Section -or $_.Section -eq $Section)) -or
            @($_.AlsoIn | Where-Object { ($Section -and $_ -eq "$AdminCenter/$Section") -or (-not $Section -and $_ -like "$AdminCenter/*") }).Count -gt 0
        }
    }
    if ($Search)   {
        $tools = $tools | Where-Object { $_.Name -like "*$Search*" -or $_.Synopsis -like "*$Search*" -or $_.Id -like "*$Search*" }
    }
    return @($tools | Sort-Object Category, Name)
}

function Get-NmAdminCenter {
    <#
    .SYNOPSIS
        The tools grouped by admin center, then by section, in menu order. Centers with no tools are left out.
    .DESCRIPTION
        Each center has Id, Name, Count (tools whose home is here), Services (every service its tools use)
        and Sections. Each section has Name and Items; each item has Tool, IsHome, and Note
        ("Also in ..." for a home tool listed elsewhere, "Home: ..." for a tool listed here from elsewhere).
    .EXAMPLE
        Get-NmAdminCenter | ForEach-Object { "$($_.Name): $($_.Count)" }
    #>
    [CmdletBinding()]
    param()

    $tools = @(Get-NmTool)
    $label = {
        param($full)
        $p = $full -split '/', 2
        $c = $script:NmAdminCenters | Where-Object { $_.Id -eq $p[0] } | Select-Object -First 1
        if ($c.Sections.Count -gt 1 -or $c.Sections[0] -ne $p[1]) { "$($c.Name) > $($p[1])" } else { $c.Name }
    }

    foreach ($center in $script:NmAdminCenters) {
        $here = @($tools | Where-Object { $_.AdminCenter -eq $center.Id -or @($_.AlsoIn | Where-Object { $_ -like "$($center.Id)/*" }).Count -gt 0 })
        if ($here.Count -eq 0) { continue }

        $names = New-Object System.Collections.Generic.List[string]
        foreach ($n in $center.Sections) { $names.Add($n) }
        $extra = foreach ($t in $here) {
            if ($t.AdminCenter -eq $center.Id) { $t.Section }
            foreach ($a in $t.AlsoIn) { if ($a -like "$($center.Id)/*") { ($a -split '/', 2)[1] } }
        }
        foreach ($n in @($extra | Sort-Object -Unique)) { if (-not $names.Contains($n)) { $names.Add($n) } }

        $sections = foreach ($n in $names) {
            $items = foreach ($t in $here) {
                $isHome = $t.AdminCenter -eq $center.Id -and $t.Section -eq $n
                $isAlso = @($t.AlsoIn) -contains "$($center.Id)/$n"
                if (-not ($isHome -or $isAlso)) { continue }
                $note = if ($isHome) {
                    if ($t.AlsoIn.Count) { 'Also in ' + ((@($t.AlsoIn | ForEach-Object { & $label $_ })) -join ', ') } else { '' }
                } else {
                    'Home: ' + (& $label "$($t.AdminCenter)/$($t.Section)")
                }
                [pscustomobject]@{ Tool = $t; IsHome = $isHome; Note = $note }
            }
            $items = @($items | Sort-Object { $_.Tool.Name })
            if ($items.Count) { [pscustomobject]@{ Name = $n; Items = $items } }
        }

        [pscustomobject]@{
            Id       = $center.Id
            Name     = $center.Name
            Count    = @($here | Where-Object { $_.AdminCenter -eq $center.Id }).Count
            Services = @($here | Where-Object { $_.AdminCenter -eq $center.Id } | ForEach-Object { $_.Services } | Where-Object { $_ } | Sort-Object -Unique)
            Sections = @($sections)
        }
    }
}

function Get-NmToolLoadError {
    <#
    .SYNOPSIS
        Tools that were found but not loaded, with the reason.
    #>
    [CmdletBinding()]
    param()
    return $script:NmToolLoadErrors.ToArray()
}

function Invoke-NmTool {
    <#
    .SYNOPSIS
        Runs one tool: shows required roles, loads what it needs, runs it, logs the run,
        then offers the Result Action Menu (unless -NoMenu).
    .EXAMPLE
        Invoke-NmTool -Id session-info
    .EXAMPLE
        $rows = Invoke-NmTool -Id session-info -NoMenu
    .NOTES
        -Parameters skips the tool's own setup questions (its Prompt function) and passes these to the entry function.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [hashtable]$Parameters,
        [switch]$WhatIf,
        [switch]$NoMenu
    )

    $tool = Get-NmTool -Id $Id | Select-Object -First 1
    if (-not $tool) {
        Write-NmLog "No tool with Id '$Id'." -Level ERROR
        return
    }

    # Screen context: path, the tool's version, and its notes on its first screen.
    $notes = @(@{ Text = $tool.Synopsis; Color = 'DarkGray' })
    if ($tool.Roles.Count -gt 0) { $notes += @{ Text = "Needs: $($tool.Roles -join ', ')"; Color = 'DarkGray' } }
    if ($tool.Kind -ne 'Report') { $notes += @{ Text = 'This tool can make changes. You will be asked before each one.'; Color = 'Yellow' } }

    Push-NmNav $tool.Name
    $script:NmScreenVersion = $tool.Version
    $script:NmScreenNotes = if ($NoMenu) { @() } else { $notes }
    try {
        $usePrompt = (-not $Parameters) -and $tool.Prompt
        if (-not $usePrompt -and -not $NoMenu) {
            Show-NmHeader -Title $tool.Name -Clear
        }

        if (-not (Assert-NmConnection -Services $tool.Services)) {
            Write-NmLog "Could not load what $($tool.Name) needs (see above)." -Level ERROR
            Write-NmRunHistory -ToolId $tool.Id -ToolVersion $tool.Version -Kind $tool.Kind -Result Failed -Notes 'Modules or domain not available'
            if (-not $NoMenu) { Wait-NmKey }
            return
        }

        $entryCmd = Get-Command -Name $tool.Entry -CommandType Function
        $mode = if ($WhatIf) { 'WhatIf' } else { 'Run' }

        # Hand the menu the functions' own script blocks: they keep the module scope, so the
        # tool's helper functions stay visible (a GetNewClosure() wrapper would lose them).
        $deepDive = if ($tool.DeepDive) { (Get-Command -Name $tool.DeepDive -CommandType Function).ScriptBlock } else { $null }
        $summary  = if ($tool.Summary)  { (Get-Command -Name $tool.Summary  -CommandType Function).ScriptBlock } else { $null }

        # Outer loop: the tool's own options. Back from the results returns here, not to the
        # category menu. Back on the options screen leaves the tool.
        while ($true) {
            $entryArgs = @{}
            if ($Parameters) {
                $entryArgs = $Parameters.Clone()
            } elseif ($tool.Prompt) {
                if (-not $NoMenu) { $script:NmScreenNotes = $notes }
                try {
                    $answers = & $tool.Prompt
                } catch {
                    Write-NmLog "$($tool.Name) setup failed: $($_.Exception.Message)" -Level ERROR
                    if (-not $NoMenu) { Wait-NmKey }
                    return
                }
                if ($null -eq $answers) {
                    Write-NmLog 'Cancelled.' -Level INFO -NoConsole
                    return
                }
                $entryArgs = $answers
            }
            if ($WhatIf -and $entryCmd.Parameters.ContainsKey('WhatIf')) { $entryArgs.WhatIf = $true }

            # Inner loop: run, show results; Re-run repeats the same query.
            $firstRun = $true
            $next = $null
            while ($true) {
                # Each run starts on a clean screen: header, progress, results, actions.
                if (-not $NoMenu -and ($usePrompt -or -not $firstRun)) {
                    Show-NmHeader -Title $tool.Name -Clear
                }
                $firstRun = $false

                try {
                    Write-NmLog "Running $($tool.Name) v$($tool.Version)." -Level INFO -NoConsole
                    $raw = @(& $tool.Entry @entryArgs)
                } catch {
                    Write-NmLog "$($tool.Name) failed: $($_.Exception.Message)" -Level ERROR
                    Write-NmRunHistory -ToolId $tool.Id -ToolVersion $tool.Version -Kind $tool.Kind -Mode $mode -Result Failed -Notes $_.Exception.Message
                    if (-not $NoMenu) { Wait-NmKey }
                    $next = 'Back'
                    break
                }

                $results = @(Add-NmIndex -InputObject $raw)
                Write-NmRunHistory -ToolId $tool.Id -ToolVersion $tool.Version -Kind $tool.Kind -Mode $mode -ItemCount $results.Count

                if ($NoMenu) { return $results }

                $columns = @($tool.Columns | Where-Object { $_ })
                if ($columns.Count -gt 0) {
                    Show-NmResult -Results $results -Property $columns -Title $tool.Name
                } else {
                    Show-NmResult -Results $results -Title $tool.Name
                }

                $bulk = if ($tool.BulkAction) { (Get-Command -Name $tool.BulkAction -CommandType Function).ScriptBlock } else { $null }
                $next = Show-NmResultMenu -Results $results -ToolId $tool.Id -DeepDive $deepDive -Summary $summary -Columns $columns -Title $tool.Name `
                    -BulkAction $bulk -BulkActions @($tool.BulkActions)
                if ($next -ne 'Rerun') { break }
            }

            # Tools with their own options go back to them; tools without leave. [M] leaves too.
            if (-not $usePrompt -or $next -eq 'Quit' -or $script:NmGoMain) { return }
        }
    } finally {
        Pop-NmNav
        $script:NmScreenVersion = $null
        $script:NmScreenNotes = @()
    }
}
