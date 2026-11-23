<#
.NOTES
    Author:  Cliff Waite
    Date:    11/23/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.1

.SYNOPSIS
    Aligns GPOs with their baselines: writes what is missing or different, or resets a GPO to its baseline exactly.

.DESCRIPTION
    - For GPOs built from a baseline (their comment says "Nutmeg baseline: <Id> <Version>"), or any GPO
      with -Baseline.
    - Align (the default): the baseline's settings only. Missing settings are written, different ones put
      back; the values the GPO already has for the baseline's parameters are kept; extra settings stay
      (they may be there for a reason).
    - Reset: the GPO made the baseline exactly: parameters at their defaults, extra settings removed.
    - Backs up the GPO first (Backup-GPO, into C:\Temp\NutmegAD\GpoBackups); Restore GPO from Backup
      (gpo-restore) puts it back.
    - Asks before each GPO, listing every change from X to Y (-WhatIf shows that and changes nothing).
      A GPO linked at the domain root or Domain Controllers needs the domain's short name typed.
    - Compares the GPO again afterwards; the row says what still differs (nothing, normally).
    - Never touches links, filtering, delegation or WMI filters.
    - Compare GPOs with Baselines runs it from the card of a GPO that does not match.

.EXAMPLE
    Invoke-NmTool -Id gpo-align

.EXAMPLE
    Set-NmGpoToBaseline -Gpo 'Security - Enforce UAC' -WhatIf

.EXAMPLE
    Set-NmGpoToBaseline -Gpo 'Security - Screen Timeout' -Mode Reset

.VERSIONING
    0.7.1 - First version (issue #43): Align and Reset, backup first, compare after.
#>

$NmTool = @{
    Name     = 'Align GPOs with Baselines'
    Id       = 'gpo-align'
    Order    = 3                            # Build, Compare, Align, Restore
    Category = 'GroupPolicy'
    Area     = 'gpo/Baselines'
    Synopsis = 'Put a GPO back to its baseline: write what is missing or different, or reset it exactly (backed up first)'
    Version  = '0.7.1'
    Kind     = 'ReportAndChange'
    Services = @('AD', 'GPO')
    Roles    = @('Domain Admins')
    Prompt   = 'Read-NmGpoAlignOption'
    Entry    = 'Set-NmGpoToBaseline'
    DeepDive = 'Show-NmGpoAlignDetail'
    Columns  = @('Gpo', 'Mode', 'Changed', 'Removed', 'Result', 'Backup')
    Pickers  = @{ Gpo = @{ Items = 'Get-NmGpoAlignPickItem'; NeedsDomain = $true; Note = 'Tick the GPOs to align. Each is backed up first, and you approve its changes one GPO at a time.' } }
    CardActions = @(
        @{ Label = 'Edit GPO'; Action = 'Invoke-NmGpoCardEdit'; ToolTip = 'Open this GPO in the Group Policy Management Editor (on the DC in use)' }
        @{ Label = 'View GPO'; Action = 'Invoke-NmGpoCardView'; ToolTip = 'This GPO''s settings, here: a tab per part' }
    )
}

function Get-NmGpoAlignPickItem {
    # The window's list: GPOs built from a baseline (others need -Baseline, in the console).
    [CmdletBinding()]
    param()
    foreach ($g in @(Get-NmAllGpo)) {
        $st = Read-NmBaselineStamp -Comment "$($g.Description)"
        if ($st) { [pscustomobject]@{ Key = "$($g.DisplayName)"; Label = "$($g.DisplayName)"; Detail = "Built from $($st.Id) v$($st.Version)" } }
    }
}

function Read-NmGpoAlignOption {
    <#
    .SYNOPSIS
        Which GPOs (built from a baseline) and which mode. Returns the entry's parameters, or $null.
    #>
    [CmdletBinding()]
    param()
    $gpos = @(Get-NmAllGpo | Where-Object { Read-NmBaselineStamp -Comment "$($_.Description)" })
    if (-not $gpos.Count) { Write-NmLog 'No GPO carries a baseline stamp yet (gpo-build adds it).' -Level WARN; Wait-NmKey; return $null }
    $items = @(foreach ($g in $gpos) { $st = Read-NmBaselineStamp -Comment "$($g.Description)"; [pscustomobject]@{ Label = "$($g.DisplayName)"; Detail = "built from $($st.Id) v$($st.Version)" } })
    $picked = @(Read-NmMultiChoice -Title 'Which GPOs?' -Items $items -Note 'Each is backed up first; you approve its changes one GPO at a time.')
    if (-not $picked.Count) { return $null }
    $mode = Read-NmGpoAlignMode
    if (-not $mode) { return $null }
    return @{ Gpo = [string[]]@($picked | ForEach-Object { "$($gpos[$_].DisplayName)" }); Mode = $mode }
}

function Set-NmGpoToBaseline {
    <#
    .SYNOPSIS
        Aligns GPOs with their baselines. Returns a row per GPO.
    .PARAMETER Gpo
        GPO names. Each is aligned with the baseline in its comment, or with -Baseline.
    .PARAMETER Mode
        Align (the baseline's settings only; values and extra settings kept) or Reset (the baseline
        exactly: default values, extra settings removed).
    .PARAMETER Values
        Parameter values to use instead (per GPO name, or one flat hashtable for all).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Gpo,
        [ValidateSet('Align', 'Reset')][string]$Mode = 'Align',
        [string]$Baseline,
        [hashtable]$Values = @{},
        [switch]$WhatIf
    )
    $all = @(Get-NmAllGpo)
    $out = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($name in $Gpo) {
        $n++
        Write-Progress -Activity 'Aligning GPOs' -Status "[$n/$($Gpo.Count)] $name" -PercentComplete ([int](100 * ($n - 1) / $Gpo.Count))
        $row = [pscustomobject]@{ Gpo = $name; Baseline = ''; Mode = $Mode; Changed = 0; Removed = 0; Kept = 0; Result = ''; Backup = ''; Remaining = ''; Details = @(); GpoId = ''; GpoPath = '' }
        $out.Add($row)
        $g = @($all | Where-Object { $_.DisplayName -eq $name })[0]
        if (-not $g) { $row.Result = 'Failed: no GPO by this name'; continue }
        $row.GpoId = "$($g.Id)"; $row.GpoPath = "$($g.Path)"
        $id = $Baseline
        if (-not $id) {
            $st = Read-NmBaselineStamp -Comment "$($g.Description)"
            if (-not $st) { $row.Result = 'Failed: not built from a baseline (no stamp in its comment): give -Baseline'; continue }
            $id = $st.Id
        }
        $b = @(Get-NmBaseline -Id $id)[0]
        if (-not $b) { $row.Result = "Failed: the baseline '$id' is not in this toolkit"; continue }
        $row.Baseline = $b.Name
        $given = if ($Values.ContainsKey($name) -and $Values[$name] -is [hashtable]) { $Values[$name] } else { $Values }

        try { $plan = Get-NmGpoAlignPlan -Gpo $g -Baseline $b -Mode $Mode -Values $given }
        catch { $row.Result = "Failed: could not be read: $($_.Exception.Message)"; continue }
        if ($plan.Problems.Count) { $row.Result = "Failed: $($plan.Problems -join '; ')"; continue }
        $row.Kept = $plan.Kept
        $row.Details = @(@($plan.Changes | ForEach-Object { [pscustomobject]@{ SettingId = $_.SettingId; Setting = $_.Setting; Action = 'Write'; From = $_.From; To = $_.To; Result = '' } }) +
                         @($plan.Removals | ForEach-Object { [pscustomobject]@{ SettingId = ''; Setting = $_.Setting; Action = 'Remove'; From = $_.From; To = '(removed)'; Result = '' } }))
        if (-not $plan.Changes.Count -and -not $plan.Removals.Count) {
            $row.Result = "Already matches$(if ($plan.Kept) { " ($($plan.Kept) extra setting(s) kept)" })"
            continue
        }

        # The plan, then one approval. The baseline's own notes first (Run ready first, and so on).
        foreach ($note in @($b.Notes)) { Write-NmLog "$($b.Name): $note" -Level WARN }
        $where = Get-NmGpoWhereRow -Gpo $g -Baseline $b
        $wide = "$($where.Actual)" -match '(^|; )(Domain root|Domain Controllers)( \(|;|$)'
        $targets = @(foreach ($d in $row.Details) { if ($d.Action -eq 'Remove') { "Remove: $($d.Setting) = $($d.From)" } else { "$($d.Setting): $($d.From) -> $($d.To)" } })
        $facts = @("Baseline: $($b.Name) v$($b.Version)", "Mode: $(if ($Mode -eq 'Reset') { 'reset to the baseline exactly (extra settings removed, default values)' } else { 'align the baseline''s settings (values and extra settings kept)' })")
        foreach ($k in @($plan.Values.Keys | Sort-Object)) { $facts += "${k}: $($plan.Values[$k])" }
        $facts += "Links: $($where.Actual)"
        $facts += 'The GPO is backed up first (Restore GPO from Backup puts it back).'
        if (-not (Confirm-NmChange -Action "$(if ($Mode -eq 'Reset') { 'Reset' } else { 'Align' }) GPO '$name' with its baseline" -Targets $targets -Facts $facts -DomainWide:$wide -WhatIf:$WhatIf)) {
            $row.Result = $(if ($WhatIf) { 'WhatIf: not changed' } else { 'Cancelled' })
            $row.Changed = $plan.Changes.Count; $row.Removed = $plan.Removals.Count
            Write-NmRunHistory -ToolId 'gpo-align' -ToolVersion '0.7.1' -Kind ReportAndChange -Mode $(if ($WhatIf) { 'WhatIf' } else { 'Cancelled' }) -Result Cancelled -Notes "$name ($Mode)"
            continue
        }

        try { $row.Backup = Save-NmGpoBackup -Gpo $g -Reason "Before $($Mode.ToLower()) with $($b.Id) $($b.Version)" }
        catch { $row.Result = "Failed: not changed, the backup failed: $($_.Exception.Message)"; continue }

        $failed = New-Object System.Collections.Generic.List[string]
        if ($plan.Changes.Count) {
            $written = @(Invoke-NmBaselineWrite -Gpo $g -Baseline $b -Values $plan.Values -SettingId @($plan.Changes | ForEach-Object { $_.SettingId }))
            foreach ($w in $written) {
                foreach ($d in @($row.Details | Where-Object { $_.Action -eq 'Write' -and $_.SettingId -eq $w.SettingId })) { $d.Result = $w.Result }
                if ($w.Result -ne 'Written') { $failed.Add("$($w.Setting): $($w.Result -replace '^Failed: ', '')") }
            }
        }
        if ($plan.Removals.Count) {
            foreach ($r in @(Remove-NmGpoExtra -Gpo $g -Items $plan.Removals)) {
                foreach ($d in @($row.Details | Where-Object { $_.Action -eq 'Remove' -and $_.Setting -eq $r.Setting })) { $d.Result = $r.Result }
                if ($r.Result -ne 'Removed') { $failed.Add("$($r.Setting): $($r.Result -replace '^Failed: ', '')") }
            }
        }
        $row.Changed = $plan.Changes.Count; $row.Removed = $plan.Removals.Count

        # The proof: compare again.
        $after = Get-NmGpoAlignPlan -Gpo $g -Baseline $b -Mode $Mode -Values $plan.Values
        $left = @($after.Changes).Count + @($after.Removals).Count
        $row.Remaining = $(if ($left) { "$left still differ" } else { 'none' })
        if ($failed.Count) {
            $row.Result = "Failed: $($failed.Count) setting(s) not changed ($($failed[0]))"
            Write-NmRunHistory -ToolId 'gpo-align' -ToolVersion '0.7.1' -Kind ReportAndChange -ItemCount ($row.Changed + $row.Removed) -Result Failed -Notes "$name ($Mode): $($failed -join '; ')"
        } else {
            $row.Result = $(if ($Mode -eq 'Reset') { 'Reset' } else { 'Aligned' })
            Write-NmRunHistory -ToolId 'gpo-align' -ToolVersion '0.7.1' -Kind ReportAndChange -ItemCount ($row.Changed + $row.Removed) -Notes "$name ($Mode, $($b.Id) $($b.Version)): $($row.Changed) written, $($row.Removed) removed; backup $(Split-Path -Leaf $row.Backup)"
        }
        foreach ($d in $row.Details) { Write-NmLog "$name - $($d.Action) $($d.Setting): $($d.From) -> $($d.To) [$($d.Result)]" -Level INFO -NoConsole }
    }
    Write-Progress -Activity 'Aligning GPOs' -Completed
    return $out.ToArray()
}

function Show-NmGpoAlignDetail {
    # One GPO's changes: each setting, from what to what, and what came of it.
    param($Row)
    Write-Host "$($Row.Gpo) ($($Row.Baseline), $($Row.Mode))" -ForegroundColor Cyan
    if ($Row.Backup) { Write-Host "   Backup: $($Row.Backup)" -ForegroundColor DarkGray }
    if (@($Row.Details).Count) { $Row.Details | Format-Table Action, Setting, From, To, Result -AutoSize -Wrap | Out-Host }
    else { Write-Host "   $($Row.Result)" -ForegroundColor DarkGray }
}
