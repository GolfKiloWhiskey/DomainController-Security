<#
.NOTES
    Author:  Cliff Waite
    Date:    11/22/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.6

.SYNOPSIS
    Compares GPOs with their baselines: missing, different and extra settings, and parameters not filled in.

.DESCRIPTION
    - One GPO, or every GPO built from a baseline (its comment says "Nutmeg baseline: <Id> <Version>").
      A GPO without that comment can still be compared: pick the baseline for it.
    - Default Domain Policy (DDP) and Default Domain Controllers Policy (DDCP) are excluded from
      normal baseline comparisons. Pick them directly or pass -IncludeDefaultGpos for a read-only
      check against clean Windows OS defaults (DDP password/lockout edits are surfaced as Notes).
    - Reads the GPO's own files in SYSVOL (Registry.pol, registry preferences, GptTmpl.inf, audit.csv),
      so it sees what clients see.
    - A row per baseline setting (Matches, Different, Missing, Not filled), then a row per setting the
      GPO has that the baseline does not (Extra). A parameter's value is shown in Detail.
    - Notes a GPO built from an older version of its baseline.
    - Read only: nothing is changed.

.EXAMPLE
    Invoke-NmTool -Id gpo-compare

.EXAMPLE
    Compare-NmGpoBaseline -All -DifferencesOnly

.EXAMPLE
    Compare-NmGpoBaseline -IncludeDefaultGpos

.EXAMPLE
    Compare-NmGpoBaseline -Gpo 'Security - Enforce UAC (old)' -Baseline security-enforce-uac

.VERSIONING
    0.7.6 - Default Domain Policy (DDP) and Default Domain Controllers Policy (DDCP) excluded from normal
            baseline comparisons; optional read-only OS-default integrity check (-IncludeDefaultGpos or
            picked directly), with DDP password/lockout customizations surfaced as Notes.
    0.7.5 - Align with baseline on the card of a GPO that does not match (gpo-align); Compare runs again after it.
    0.7.4 - Two labels per GPO: its settings (Matches, Doesn't match, Failed: the tags filter on these) and where it applies
            (Linked, Not linked, Not applied); View GPO in the app, GPMC report for GPMC's own.
    0.7.3 - Where each GPO applies (links, enabled, enforced; not linked or not applied flagged); the window counts GPOs and
            filters them by state (Matches, Doesn't match, Not linked, ...); Edit GPO and View GPO on each card.
    0.7.2 - The window: one card per GPO (what needs attention first, a line per setting); GPOs and the
            baseline picked from lists. Rows come per GPO with the problems first. Nothing picked: says so.
    0.7.1 - First version.
#>

$NmTool = @{
    Name     = 'Compare GPOs with Baselines'
    Id       = 'gpo-compare'
    Order    = 2                            # Build, Compare, Align, Restore
    Category = 'GroupPolicy'
    Area     = 'gpo/Baselines'
    Synopsis = 'One GPO or all of them against their baseline: missing, different and extra settings'
    Version  = '0.7.6'
    Kind     = 'Report'
    Services = @('AD', 'GPO')
    Roles    = @('Domain Admins')
    Prompt   = 'Read-NmGpoCompareOption'
    Entry    = 'Compare-NmGpoBaseline'
    Summary  = 'Show-NmGpoCompareSummary'
    Columns  = @('Gpo', 'Setting', 'Expected', 'Actual', 'Result')
    # The window: a card per GPO, its settings under Different, Missing, ... Matches, one line each.
    CardGroup = @('Gpo', 'Result', 'Line')
    # The headline and the tags count GPOs by their settings (Matches, Doesn't match); each card also
    # says where the GPO applies, and can open its GPO.
    CardNoun  = 'GPO'
    CardFacet = 'GpoState'
    CardBadge = 'LinkState'
    CardActions = @(
        @{ Label = 'Align with baseline'; Action = 'Invoke-NmGpoCardAlign'; ToolTip = 'Put this GPO back to its baseline (Align GPOs with Baselines): backed up first, you approve every change'
           Hide = @(@{ Column = 'GpoState'; Values = @('Matches') }, @{ Column = 'IsDefaultGpo'; Values = @('True') }) }
        @{ Label = 'Edit GPO'; Action = 'Invoke-NmGpoCardEdit'; ToolTip = 'Open this GPO in the Group Policy Management Editor (on the DC in use)' }
        @{ Label = 'View GPO'; Action = 'Invoke-NmGpoCardView'; ToolTip = 'This GPO''s settings, here: a tab per part' }
        @{ Label = 'GPMC report'; Action = 'Invoke-NmGpoCardReport'; ToolTip = 'GPMC''s own full report of this GPO, saved and opened in the browser' }
    )
    Pickers  = @{
        Gpo      = @{ Items = 'Get-NmGpoComparePickItem'; NeedsDomain = $true; Note = 'Tick GPOs, or tick All below for every GPO built from a baseline. Tick IncludeDefaultGpos to check DDP/DDCP against clean Windows OS defaults.' }
        Baseline = @{ Items = 'Get-NmBaselinePickItem'; Empty = '(the one in each GPO''s comment)' }
    }
}

function Get-NmGpoComparePickItem {
    # The window's list of GPOs: baseline-stamped first, then OS default GPOs (DDP/DDCP), then other unstamped GPOs.
    [CmdletBinding()]
    param()
    $gpos = @(Get-NmAllGpo)
    $defaults = @($gpos | Where-Object { Test-NmDefaultGpo -Gpo $_ })
    $stamped = @($gpos | Where-Object { -not (Test-NmDefaultGpo -Gpo $_) -and (Read-NmBaselineStamp -Comment "$($_.Description)") })
    $other = @($gpos | Where-Object { -not (Test-NmDefaultGpo -Gpo $_) -and -not (Read-NmBaselineStamp -Comment "$($_.Description)") })
    foreach ($g in $stamped) { $st = Read-NmBaselineStamp -Comment "$($g.Description)"; [pscustomobject]@{ Key = "$($g.DisplayName)"; Label = "$($g.DisplayName)"; Detail = "Built from $($st.Id) v$($st.Version)" } }
    foreach ($g in $defaults) { [pscustomobject]@{ Key = "$($g.DisplayName)"; Label = "$($g.DisplayName)"; Detail = 'OS default GPO: checks against clean Windows defaults (read-only)'; Badge = 'OS default' } }
    foreach ($g in $other) { [pscustomobject]@{ Key = "$($g.DisplayName)"; Label = "$($g.DisplayName)"; Detail = 'Not built from a baseline: pick the baseline to compare with'; Badge = 'No stamp' } }
}

function Get-NmBaselinePickItem {
    # The baselines, for the drop-down.
    [CmdletBinding()]
    param()
    foreach ($b in @(Get-NmBaseline)) { [pscustomobject]@{ Key = $b.Id; Label = $b.Name; Detail = "v$($b.Version)" } }
}

function Get-NmAllGpo {
    # Every GPO in the domain (a wrapper so the tests can stand in for it).
    [CmdletBinding()]
    param()
    $gp = Get-NmGPParams
    return @(Get-GPO -All @gp -ErrorAction Stop | Sort-Object DisplayName)
}

function Read-NmGpoCompareOption {
    <#
    .SYNOPSIS
        Every GPO built from a baseline, one of them, another GPO with a baseline picked, or OS default GPOs.
    #>
    [CmdletBinding()]
    param()
    $gpos = @(Get-NmAllGpo)
    $defaults = @($gpos | Where-Object { Test-NmDefaultGpo -Gpo $_ })
    $nonDefault = @($gpos | Where-Object { -not (Test-NmDefaultGpo -Gpo $_) })
    $stamped = @($nonDefault | Where-Object { Read-NmBaselineStamp -Comment "$($_.Description)" })
    $opts = @(
        [pscustomobject]@{ Key = '1'; Label = 'Every GPO built from a baseline'; Detail = "$($stamped.Count) found" }
        [pscustomobject]@{ Key = '2'; Label = 'One GPO built from a baseline' }
        [pscustomobject]@{ Key = '3'; Label = 'Another GPO, against a baseline I pick' }
        [pscustomobject]@{ Key = '4'; Label = 'Default Domain & DC Policies (OS default check)'; Detail = "$($defaults.Count) found (read-only)" }
    )
    $pick = Show-NmMenu -Title 'Compare GPOs with Baselines' -Back -Options $opts -Default '1'
    $diff = { Read-NmYesNo -Prompt 'Show only the settings that need attention?' -Default 'N' }
    switch ($pick) {
        '1' {
            if (-not $stamped.Count) { Write-NmLog 'No GPO carries a baseline stamp yet (gpo-build adds it).' -Level WARN; Wait-NmKey; return $null }
            return @{ All = $true; DifferencesOnly = [bool](& $diff) }
        }
        '2' {
            if (-not $stamped.Count) { Write-NmLog 'No GPO carries a baseline stamp yet (gpo-build adds it).' -Level WARN; Wait-NmKey; return $null }
            $i = 0
            $list = @(foreach ($g in $stamped) { $i++; $st = Read-NmBaselineStamp -Comment "$($g.Description)"; [pscustomobject]@{ Key = "$i"; Label = "$($g.DisplayName)"; Detail = "$($st.Id) $($st.Version)" } })
            $p = Show-NmMenu -Title 'Which GPO?' -Back -Options $list
            if ($p -eq 'B') { return $null }
            return @{ Gpo = @("$($stamped[[int]$p - 1].DisplayName)"); DifferencesOnly = [bool](& $diff) }
        }
        '3' {
            $i = 0
            $list = @(foreach ($g in $nonDefault) { $i++; [pscustomobject]@{ Key = "$i"; Label = "$($g.DisplayName)" } })
            if (-not $list.Count) { Write-NmLog 'No non-default GPOs found.' -Level WARN; Wait-NmKey; return $null }
            $p = Show-NmMenu -Title 'Which GPO?' -Back -Options $list
            if ($p -eq 'B') { return $null }
            $bl = @(Get-NmBaseline)
            $i = 0
            $bopts = @(foreach ($b in $bl) { $i++; [pscustomobject]@{ Key = "$i"; Label = $b.Name; Detail = "v$($b.Version)" } })
            $q = Show-NmMenu -Title 'Against which baseline?' -Back -Options $bopts
            if ($q -eq 'B') { return $null }
            return @{ Gpo = @("$($nonDefault[[int]$p - 1].DisplayName)"); Baseline = $bl[[int]$q - 1].Id; DifferencesOnly = [bool](& $diff) }
        }
        '4' {
            if (-not $defaults.Count) { Write-NmLog 'Default Domain Policy / Default Domain Controllers Policy were not found.' -Level WARN; Wait-NmKey; return $null }
            return @{ IncludeDefaultGpos = $true; DifferencesOnly = [bool](& $diff) }
        }
        default { return $null }
    }
}

function Compare-NmGpoBaseline {
    <#
    .SYNOPSIS
        GPOs against their baselines. Returns a row per setting (see Compare-NmGpoWithBaseline).
    .PARAMETER Gpo
        GPO names. Each is compared with the baseline in its comment, or with -Baseline.
        Default Domain Policy and Default Domain Controllers Policy are checked read-only against clean Windows OS defaults.
    .PARAMETER All
        Every GPO whose comment names a baseline (excludes Default Domain Policy and Default Domain Controllers Policy).
    .PARAMETER IncludeDefaultGpos
        Also check Default Domain Policy (DDP) and Default Domain Controllers Policy (DDCP) against clean Windows OS defaults (read-only).
    .PARAMETER DifferencesOnly
        Leave out the rows that match.
    #>
    [CmdletBinding()]
    param([string[]]$Gpo = @(), [switch]$All, [string]$Baseline, [switch]$IncludeDefaultGpos, [switch]$DifferencesOnly)
    $named = @($Gpo | Where-Object { "$_".Trim() })
    if (-not $All -and -not $IncludeDefaultGpos -and -not $named.Count) { throw 'Pick the GPOs to compare, or choose All.' }
    $gpos = @(Get-NmAllGpo)
    $targetList = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $addTarget = {
        param($obj)
        $k = if ($obj.PSObject.Properties['Id'] -and "$($obj.Id)") { "$($obj.Id)".ToLower() } else { "name:$($obj.DisplayName)".ToLower() }
        if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $targetList.Add($obj) }
    }
    if ($All) {
        foreach ($g in @($gpos | Where-Object { -not (Test-NmDefaultGpo -Gpo $_) -and (Read-NmBaselineStamp -Comment "$($_.Description)") })) { & $addTarget $g }
    }
    foreach ($n in $named) {
        $g = @($gpos | Where-Object { $_.DisplayName -eq $n })[0]
        if ($g) { & $addTarget $g } else { & $addTarget ([pscustomobject]@{ DisplayName = $n; Id = ''; Description = ''; Missing = $true }) }
    }
    if ($IncludeDefaultGpos) {
        foreach ($g in @($gpos | Where-Object { Test-NmDefaultGpo -Gpo $_ })) { & $addTarget $g }
    }
    $targets = $targetList.ToArray()
    $rows = New-Object System.Collections.Generic.List[object]
    $states = New-Object System.Collections.Generic.List[string]
    $linkStates = New-Object System.Collections.Generic.List[string]
    $fail = { param($g, $why, [bool]$isDef = $false) $rows.Add([pscustomobject]@{ Gpo = "$($g.DisplayName)"; Baseline = ''; Setting = '(the GPO)'; SettingId = ''; Kind = ''; Expected = ''; Actual = ''; Result = "Failed: $why"; Detail = ''; Line = "Failed: $why"
        Links = ''; GpoState = 'Failed'; LinkState = ''; GpoId = "$($g.Id)"; GpoPath = "$(if ($g.PSObject.Properties['Path']) { $g.Path })"; IsDefaultGpo = $isDef }) }
    $n = 0
    foreach ($g in $targets) {
        $n++
        Write-Progress -Activity 'Comparing GPOs' -Status "[$n/$($targets.Count)] $($g.DisplayName)" -PercentComplete ([int](100 * ($n - 1) / [Math]::Max(1, $targets.Count)))
        if ($g.PSObject.Properties['Missing']) { & $fail $g 'no GPO by this name' $false; $states.Add('Failed'); continue }
        $defKind = Get-NmDefaultGpoKind -Id "$($g.Id)"
        $isDef = [bool]$defKind
        if ($isDef) {
            if ($Baseline) {
                & $fail $g 'OS default GPO (DDP/DDCP) should not be compared against a Nutmeg baseline; run without -Baseline to check clean Windows OS defaults' $true
                $states.Add('Failed'); continue
            }
            $b = Get-NmDefaultGpoBaseline -Kind $defKind
        } else {
            $id = $Baseline
            if (-not $id) {
                $st = Read-NmBaselineStamp -Comment "$($g.Description)"
                if (-not $st) { & $fail $g 'not built from a baseline (no stamp in its comment): pick the baseline to compare with' $false; $states.Add('Failed'); continue }
                $id = $st.Id
            }
            $b = @(Get-NmBaseline -Id $id)[0]
            if (-not $b) { & $fail $g "the baseline '$id' is not in this toolkit" $false; $states.Add('Failed'); continue }
        }
        try {
            $found = if ($isDef) { @(Compare-NmDefaultGpo -Gpo $g) } else { @(Compare-NmGpoWithBaseline -Gpo $g -Baseline $b) }
            $where = Get-NmGpoWhereRow -Gpo $g -Baseline $b
            $state = Get-NmGpoOverallState -Rows $found -StrictExtra:$isDef
            # Where it applies first, then what needs attention, then what matches (each in the baseline's order).
            $ordered = @($where) + @(foreach ($res in 'Note', 'Not filled', 'Different', 'Missing', 'Extra', 'Matches') { @($found | Where-Object { $_.Result -eq $res }) })
            foreach ($r in $ordered) {
                if ($DifferencesOnly -and ($r.Result -eq 'Matches' -or $r.Result -eq 'Linked')) { continue }
                $r | Add-Member -NotePropertyName Line -NotePropertyValue (Get-NmGpoCompareLine -Row $r) -Force
                $r | Add-Member -NotePropertyName Links -NotePropertyValue $where.Actual -Force
                $r | Add-Member -NotePropertyName GpoState -NotePropertyValue $state -Force
                $r | Add-Member -NotePropertyName LinkState -NotePropertyValue $where.Result -Force
                $r | Add-Member -NotePropertyName GpoId -NotePropertyValue "$($g.Id)" -Force
                $r | Add-Member -NotePropertyName GpoPath -NotePropertyValue "$($g.Path)" -Force
                $r | Add-Member -NotePropertyName IsDefaultGpo -NotePropertyValue $isDef -Force
                $rows.Add($r)
            }
            $states.Add($state); $linkStates.Add("$($where.Result)")
        } catch { & $fail $g "could not be read: $($_.Exception.Message)" $isDef; $states.Add('Failed') }
    }
    Write-Progress -Activity 'Comparing GPOs' -Completed
    if ($states.Count) { Write-NmLog (Get-NmGpoStateSummary -States $states.ToArray() -LinkStates $linkStates.ToArray()) -Level INFO }
    return $rows.ToArray()
}

function Get-NmGpoWhereRow {
    # The row that says where a GPO applies: its links against the suggested ones, and whether the
    # side its baseline uses is enabled. A report that cannot be read is noted, not a failure.
    param([Parameter(Mandatory)]$Gpo, [Parameter(Mandatory)]$Baseline)
    $suggested = if ($Baseline.PSObject.Properties['SuggestedLinks'] -and @($Baseline.SuggestedLinks).Count) {
        @($Baseline.SuggestedLinks)
    } else {
        $sugg = Get-NmBaselineDefaultLink -Name $Baseline.Name
        @(if ($sugg) { $sugg.Links })
    }
    $row = [pscustomobject]@{ Gpo = "$($Gpo.DisplayName)"; Baseline = $Baseline.Name; Setting = '(where it applies)'; SettingId = ''; Kind = 'Links'
        Expected = $(if ($suggested.Count) { "suggested: $($suggested -join '; ')" } else { '' }); Actual = ''; Result = ''; Detail = '' }
    try {
        $rep = ConvertFrom-NmGpoReportXml -Xml (Get-NmGpoReportXml -Id "$($Gpo.Id)")
        $sides = @($Baseline.Settings | ForEach-Object { "$($_.Side)" } | Sort-Object -Unique)
        $st = Get-NmGpoApplyState -Report $rep -Sides $sides -Suggested $suggested
        $row.Actual = Format-NmGpoLinks -Links $rep.Links
        $row.Result = $st.Result; $row.Detail = $st.Detail
    } catch {
        $row.Actual = '(links not read)'; $row.Result = 'Unknown'; $row.Detail = "The GPO's report could not be read: $($_.Exception.Message)"
    }
    return $row
}

function Get-NmGpoOverallState {
    # A GPO's settings in one word, for its card's first label and the tags: Failed, Doesn't match or
    # Matches. Where it applies is its second label (LinkState), apart from this.
    # -StrictExtra (used for OS default GPOs): any Extra setting also marks the GPO as Doesn't match.
    param([object[]]$Rows = @(), [switch]$StrictExtra)
    $r = @($Rows | ForEach-Object { "$($_.Result)" })
    if (@($r | Where-Object { $_ -like 'Failed*' }).Count) { return 'Failed' }
    if (@($r | Where-Object { $_ -in 'Different', 'Missing', 'Not filled' }).Count) { return "Doesn't match" }
    if ($StrictExtra -and @($r | Where-Object { $_ -eq 'Extra' }).Count) { return "Doesn't match" }
    return 'Matches'
}

function Get-NmGpoStateSummary {
    # "Compared 9 GPOs: 7 match, 2 don't match; 3 not linked, 1 not applied."
    param([string[]]$States = @(), [string[]]$LinkStates = @())
    $n = $States.Count
    $parts = foreach ($s in 'Matches', "Doesn't match", 'Failed') {
        $c = @($States | Where-Object { $_ -eq $s }).Count
        if ($c) { "$c $(switch ($s) { 'Matches' { 'match' } "Doesn't match" { $(if ($c -eq 1) { "doesn't match" } else { "don't match" }) } default { 'failed' } })" }
    }
    $links = foreach ($s in 'Not linked', 'Not applied') {
        $c = @($LinkStates | Where-Object { $_ -eq $s }).Count
        if ($c) { "$c $($s.ToLower())" }
    }
    $t = "Compared $n GPO$(if ($n -ne 1) { 's' }): $(@($parts) -join ', ')"
    if (@($links).Count) { $t += "; $(@($links) -join ', ')" }
    return "$t."
}

function Get-NmGpoCompareLine {
    # One line for a setting in its GPO's card: just the setting when it matches, what was expected
    # and found when it does not.
    param($Row)
    switch ("$($Row.Result)") {
        'Matches'    { return "$($Row.Setting)$(if ($Row.Detail) { " ($($Row.Detail))" })" }
        'Missing'    { return "$($Row.Setting): not set (expected $($Row.Expected))" }
        'Extra'      { return "$($Row.Setting) = $($Row.Actual) ($($Row.Kind), not in the baseline)" }
        'Note'       { return "$($Row.Detail)" }
        { $_ -in 'Linked', 'Not linked', 'Not applied', 'Unknown' } { return "Links: $($Row.Actual)$(if ($Row.Detail) { ". $($Row.Detail)" })" }
        default      { return "$($Row.Setting): expected $($Row.Expected), found $($Row.Actual)" }
    }
}

function Show-NmGpoCompareSummary {
    # Per GPO: how many settings match, differ, are missing, not filled or extra.
    param($Results)
    $Results | Group-Object Gpo | ForEach-Object {
        $r = @($_.Group)
        [pscustomobject]@{
            Gpo        = $_.Name
            Baseline   = "$(@($r | Where-Object { $_.Baseline })[0].Baseline)"
            Matches    = @($r | Where-Object { $_.Result -eq 'Matches' }).Count
            Different  = @($r | Where-Object { $_.Result -eq 'Different' }).Count
            Missing    = @($r | Where-Object { $_.Result -eq 'Missing' }).Count
            NotFilled  = @($r | Where-Object { $_.Result -eq 'Not filled' }).Count
            Extra      = @($r | Where-Object { $_.Result -eq 'Extra' }).Count
            Failed     = @($r | Where-Object { $_.Result -like 'Failed*' }).Count
        }
    } | Format-Table -AutoSize -Wrap | Out-Host
}
