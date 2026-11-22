<#
.NOTES
    Author:  Cliff Waite
    Date:    11/22/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.1

.SYNOPSIS
    Compares GPOs with their baselines: missing, different and extra settings, and parameters not filled in.

.DESCRIPTION
    - One GPO, or every GPO built from a baseline (its comment says "Nutmeg baseline: <Id> <Version>").
      A GPO without that comment can still be compared: pick the baseline for it.
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
    Compare-NmGpoBaseline -Gpo 'Security - Enforce UAC (old)' -Baseline security-enforce-uac

.VERSIONING
    0.7.1 - First version.
#>

$NmTool = @{
    Name     = 'Compare GPOs with Baselines'
    Id       = 'gpo-compare'
    Category = 'GroupPolicy'
    Area     = 'gpo/Baselines'
    Synopsis = 'One GPO or all of them against their baseline: missing, different and extra settings'
    Version  = '0.7.1'
    Kind     = 'Report'
    Services = @('AD', 'GPO')
    Roles    = @('Domain Admins')
    Prompt   = 'Read-NmGpoCompareOption'
    Entry    = 'Compare-NmGpoBaseline'
    Summary  = 'Show-NmGpoCompareSummary'
    Columns  = @('Gpo', 'Setting', 'Expected', 'Actual', 'Result')
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
        Every GPO built from a baseline, one of them, or another GPO with a baseline picked.
    #>
    [CmdletBinding()]
    param()
    $gpos = @(Get-NmAllGpo)
    $stamped = @($gpos | Where-Object { Read-NmBaselineStamp -Comment "$($_.Description)" })
    $opts = @(
        [pscustomobject]@{ Key = '1'; Label = 'Every GPO built from a baseline'; Detail = "$($stamped.Count) found" }
        [pscustomobject]@{ Key = '2'; Label = 'One GPO built from a baseline' }
        [pscustomobject]@{ Key = '3'; Label = 'Another GPO, against a baseline I pick' }
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
            $list = @(foreach ($g in $gpos) { $i++; [pscustomobject]@{ Key = "$i"; Label = "$($g.DisplayName)" } })
            if (-not $list.Count) { Write-NmLog 'No GPOs found.' -Level WARN; Wait-NmKey; return $null }
            $p = Show-NmMenu -Title 'Which GPO?' -Back -Options $list
            if ($p -eq 'B') { return $null }
            $bl = @(Get-NmBaseline)
            $i = 0
            $bopts = @(foreach ($b in $bl) { $i++; [pscustomobject]@{ Key = "$i"; Label = $b.Name; Detail = "v$($b.Version)" } })
            $q = Show-NmMenu -Title 'Against which baseline?' -Back -Options $bopts
            if ($q -eq 'B') { return $null }
            return @{ Gpo = @("$($gpos[[int]$p - 1].DisplayName)"); Baseline = $bl[[int]$q - 1].Id; DifferencesOnly = [bool](& $diff) }
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
    .PARAMETER All
        Every GPO whose comment names a baseline.
    .PARAMETER DifferencesOnly
        Leave out the rows that match.
    #>
    [CmdletBinding()]
    param([string[]]$Gpo = @(), [switch]$All, [string]$Baseline, [switch]$DifferencesOnly)
    $gpos = @(Get-NmAllGpo)
    $targets = if ($All) { @($gpos | Where-Object { Read-NmBaselineStamp -Comment "$($_.Description)" }) }
               else { @(foreach ($n in $Gpo) { $g = @($gpos | Where-Object { $_.DisplayName -eq $n })[0]; if ($g) { $g } else { [pscustomobject]@{ DisplayName = $n; Id = ''; Description = ''; Missing = $true } } }) }
    $rows = New-Object System.Collections.Generic.List[object]
    $fail = { param($g, $why) $rows.Add([pscustomobject]@{ Gpo = "$($g.DisplayName)"; Baseline = ''; Setting = '(the GPO)'; SettingId = ''; Kind = ''; Expected = ''; Actual = ''; Result = "Failed: $why"; Detail = '' }) }
    $n = 0
    foreach ($g in $targets) {
        $n++
        Write-Progress -Activity 'Comparing GPOs' -Status "[$n/$($targets.Count)] $($g.DisplayName)" -PercentComplete ([int](100 * ($n - 1) / [Math]::Max(1, $targets.Count)))
        if ($g.PSObject.Properties['Missing']) { & $fail $g 'no GPO by this name'; continue }
        $id = $Baseline
        if (-not $id) {
            $st = Read-NmBaselineStamp -Comment "$($g.Description)"
            if (-not $st) { & $fail $g 'not built from a baseline (no stamp in its comment): pick the baseline to compare with'; continue }
            $id = $st.Id
        }
        $b = @(Get-NmBaseline -Id $id)[0]
        if (-not $b) { & $fail $g "the baseline '$id' is not in this toolkit"; continue }
        try {
            foreach ($r in @(Compare-NmGpoWithBaseline -Gpo $g -Baseline $b)) {
                if ($DifferencesOnly -and $r.Result -eq 'Matches') { continue }
                $rows.Add($r)
            }
        } catch { & $fail $g "could not be read: $($_.Exception.Message)" }
    }
    Write-Progress -Activity 'Comparing GPOs' -Completed
    return $rows.ToArray()
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
