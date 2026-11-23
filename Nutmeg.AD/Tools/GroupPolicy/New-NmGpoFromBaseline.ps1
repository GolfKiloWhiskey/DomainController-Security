<#
.NOTES
    Author:  Cliff Waite
    Date:    11/22/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.4

.SYNOPSIS
    Builds new GPOs from the baselines in Nutmeg.AD\Baselines, setting by setting.

.DESCRIPTION
    - Pick one or several baselines. For each: answer its parameters (defaults offered) and name
      the GPO (the baseline's name by default).
    - A GPO by that name already there is never overwritten: it is left alone and Compare is
      offered instead (gpo-compare).
    - Asks before each GPO is created (-WhatIf shows what would happen). The GPO's comment is
      stamped "Nutmeg baseline: <Id> <Version>" so gpo-compare can find its baseline later.
    - Writes Administrative Templates and registry preferences with the GroupPolicy cmdlets, and
      security options, user rights, restricted groups, services and audit policy into the GPO's
      files in SYSVOL, then raises the GPO's version so clients apply them.
    - The GPO is not linked. Links, filtering and delegation are chosen per GPO (gpo-scope, next
      step); the default links from Data\GpoDefaultLinks.csv are shown as a reminder.
    - Runs without prompts when given its parameters (-Baseline, -Values, -GpoName), so the New
      Forest Build can call it.

.EXAMPLE
    Invoke-NmTool -Id gpo-build

.EXAMPLE
    New-NmGpoFromBaseline -Baseline security-screen-timeout -Values @{ TimeoutSeconds = 600 } -WhatIf

.EXAMPLE
    New-NmGpoFromBaseline -Baseline security-enforce-uac, security-ntlm-hardening

.VERSIONING
    0.7.4 - View GPO in the app; GPMC report for GPMC's own.
    0.7.3 - Edit GPO and View GPO on each built GPO's card.
    0.7.2 - The window: baselines picked from a list (name, what it does, what it asks, suggested links); each
            baseline's values and GPO name asked when Run is pressed (BeforeRun). A failed row names the baseline.
    0.7.1 - First version: the easy kinds (Administrative Templates, registry preferences, security
            options, account settings, user rights, restricted groups, services, audit).
#>

$NmTool = @{
    Name     = 'Build GPOs from Baselines'
    Id       = 'gpo-build'
    Category = 'GroupPolicy'
    Area     = 'gpo/Baselines'
    Synopsis = 'Pick baselines, answer their parameters, and build each as a new GPO (not linked)'
    Version  = '0.7.4'
    Kind     = 'ReportAndChange'
    Services = @('AD', 'GPO')
    Roles    = @('Domain Admins')
    Prompt   = 'Read-NmGpoBuildOption'
    Entry    = 'New-NmGpoFromBaseline'
    # The window: baselines are ticked in a list; their values and GPO names are asked on Run.
    Pickers  = @{ Baseline = @{ Items = 'Get-NmGpoBuildPickItem'; Note = 'Tick the baselines to build. Each becomes a new, unlinked GPO; its values and name are asked when you press Run.' } }
    BeforeRun = 'Complete-NmGpoBuildArgs'
    CardActions = @(
        @{ Label = 'Edit GPO'; Action = 'Invoke-NmGpoCardEdit'; ToolTip = 'Open this GPO in the Group Policy Management Editor (on the DC in use)' }
        @{ Label = 'View GPO'; Action = 'Invoke-NmGpoCardView'; ToolTip = 'This GPO''s settings, here: a tab per part' }
        @{ Label = 'GPMC report'; Action = 'Invoke-NmGpoCardReport'; ToolTip = 'GPMC''s own full report of this GPO, saved and opened in the browser' }
    )
    DeepDive = 'Show-NmGpoBuildDetail'
    Columns  = @('Gpo', 'Baseline', 'Settings', 'Result', 'SuggestedLinks')
}

function Get-NmGpoByName {
    # The GPO with this display name, or $null (a wrapper so the tests can stand in for it).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $gp = Get-NmGPParams
    return (Get-GPO -Name $Name @gp -ErrorAction SilentlyContinue)
}

function Get-NmGpoBuildPickItem {
    # The window's list of baselines: what each does, how many settings, what it asks, where it links.
    [CmdletBinding()]
    param()
    foreach ($b in @(Get-NmBaseline)) {
        $asks = @($b.Parameters | ForEach-Object { "$($_.Prompt)" })
        $links = Get-NmBaselineDefaultLink -Name $b.Name
        $bits = @("$(@($b.Settings).Count) setting(s)")
        if ($asks.Count) { $bits += "asks: $($asks -join '; ')" }
        if ($links -and $links.Links.Count) { $bits += "links at: $($links.Links -join ', ')" }
        [pscustomobject]@{
            Key    = $b.Id
            Label  = $b.Name
            Detail = "$($b.Description) ($($bits -join ' | '))"
            Badge  = $(if (@($b.Requires).Count) { "Needs ADMX: $(@($b.Requires) -join ', ')" } else { '' })
        }
    }
}

function Read-NmGpoBuildAnswer {
    <#
    .SYNOPSIS
        For baselines already picked: the GPO name and the parameters of each. A GPO that exists is
        left out (Compare offered). Returns @{ Baseline; Values; GpoName }, or $null when nothing is left.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Baseline)
    $ids = New-Object System.Collections.Generic.List[string]
    $values = @{}
    $names = @{}
    foreach ($id in $Baseline) {
        $b = @(Get-NmBaseline -Id $id)[0]
        if (-not $b) { Write-NmLog "No valid baseline '$id'." -Level WARN; continue }
        Write-Host ''
        Write-Host $b.Name -ForegroundColor Cyan
        Write-Host "   $($b.Description)" -ForegroundColor DarkGray
        foreach ($n in @($b.Notes)) { Write-Host "   $n" -ForegroundColor DarkGray }
        if (@($b.Requires).Count) { Write-Host "   Needs in the ADMX central store: $(@($b.Requires) -join ', ')" -ForegroundColor Yellow }
        $name = Read-NmInput -Prompt 'GPO name' -Default $b.Name
        if (Get-NmGpoByName -Name $name) {
            Write-NmLog "A GPO named '$name' already exists. It will not be changed." -Level WARN
            if (Read-NmYesNo -Prompt 'Compare it with the baseline instead?' -Default 'Y') {
                $rows = @(Compare-NmGpoBaseline -Gpo $name -Baseline $b.Id)
                Show-NmResult -Results @(Add-NmIndex -InputObject $rows) -Property @('Setting', 'Expected', 'Actual', 'Result') -Title "Compare: $name"
                Wait-NmKey
            }
            continue
        }
        $ids.Add($b.Id)
        $names[$b.Id] = $name
        $values[$b.Id] = $(if (@($b.Parameters).Count) { Read-NmBaselineParameter -Baseline $b } else { @{} })
    }
    if (-not $ids.Count) { return $null }
    return @{ Baseline = $ids.ToArray(); Values = $values; GpoName = $names }
}

function Complete-NmGpoBuildArgs {
    # The window's Run: the baselines ticked in the form, then their names and values as dialogs.
    [CmdletBinding()]
    param([hashtable]$EntryArgs)
    $a = Read-NmGpoBuildAnswer -Baseline @($EntryArgs.Baseline)
    if ($null -eq $a) { return $null }
    if ($EntryArgs.WhatIf) { $a.WhatIf = $true }
    return $a
}

function Read-NmGpoBuildOption {
    <#
    .SYNOPSIS
        Which baselines, their parameters and the GPO names. Returns the entry's parameters, or $null.
    #>
    [CmdletBinding()]
    param()
    $all = @(Get-NmBaseline)
    $bad = @(Get-NmBaseline -IncludeInvalid | Where-Object { -not $_.Valid })
    foreach ($b in $bad) { Write-NmLog "Baseline file $(Split-Path -Leaf $b.Path) is not loaded: $(@($b.Problems)[0])" -Level WARN }
    if (-not $all.Count) { Write-NmLog 'No baselines found in Nutmeg.AD\Baselines.' -Level WARN; Wait-NmKey; return $null }
    $items = @(foreach ($b in $all) {
        $exists = [bool](Get-NmGpoByName -Name $b.Name)
        [pscustomobject]@{ Label = "$($b.Name)$(if ($exists) { '   (a GPO by this name exists)' })"; Detail = "$($b.Description) [$(@($b.Settings).Count) settings, v$($b.Version)]" }
    })
    $picked = @(Read-NmMultiChoice -Title 'Which baselines?' -Items $items -Note 'Each becomes a new GPO. Nothing is linked.')
    if (-not $picked.Count) { return $null }
    return (Read-NmGpoBuildAnswer -Baseline @($picked | ForEach-Object { $all[$_].Id }))
}

function New-NmGpoFromBaseline {
    <#
    .SYNOPSIS
        Builds a new GPO from each baseline given. Returns a row per GPO.
    .PARAMETER Baseline
        Baseline Ids (Get-NmBaseline).
    .PARAMETER Values
        Parameter values: per baseline (@{ '<id>' = @{ Name = value } }), or one flat hashtable used
        for every baseline. Parameters not given take their defaults.
    .PARAMETER GpoName
        GPO names per baseline Id; the baseline's name by default.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Baseline,
        [hashtable]$Values = @{},
        [hashtable]$GpoName = @{},
        [switch]$WhatIf
    )
    $gp = Get-NmGPParams
    $out = New-Object System.Collections.Generic.List[object]
    $n = 0
    foreach ($id in $Baseline) {
        $n++
        Write-Progress -Activity 'Building GPOs' -Status "[$n/$($Baseline.Count)] $id" -PercentComplete ([int](100 * ($n - 1) / $Baseline.Count))
        $b = @(Get-NmBaseline -Id $id)[0]
        $row = [pscustomobject]@{ Gpo = $id; Baseline = $id; Version = ''; Settings = ''; Result = ''; SuggestedLinks = ''; GpoId = ''; GpoPath = ''; Details = @() }
        $out.Add($row)
        if (-not $b) { $row.Result = "Failed: no valid baseline '$id'"; continue }
        $row.Baseline = $b.Name
        $row.Version = $b.Version
        $name = if ($GpoName.ContainsKey($id) -and "$($GpoName[$id])".Trim()) { "$($GpoName[$id])".Trim() } else { $b.Name }
        $row.Gpo = $name
        $links = Get-NmBaselineDefaultLink -Name $b.Name
        if ($links) { $row.SuggestedLinks = ($links.Links -join '; ') }

        $given = if ($Values.ContainsKey($id) -and $Values[$id] -is [hashtable]) { $Values[$id] } else { $Values }
        $resolved = Resolve-NmBaselineValues -Baseline $b -Given $given
        if ($resolved.Problems.Count) { $row.Result = "Failed: $($resolved.Problems -join '; ')"; continue }

        if (Get-NmGpoByName -Name $name) {
            $row.Result = 'Already there: not changed (compare it with gpo-compare)'
            Write-NmLog "GPO '$name' already exists; not changed." -Level WARN
            continue
        }

        $targets = @(foreach ($s in @($b.Settings)) { Expand-NmBaselineText -Text "$($s.Title)" -Values $resolved.Values })
        $facts = @("Baseline: $($b.Name) v$($b.Version)")
        foreach ($k in @($resolved.Values.Keys | Sort-Object)) { $facts += "${k}: $($resolved.Values[$k])" }
        $facts += 'The GPO is created unlinked.'
        if (-not (Confirm-NmChange -Action "Create GPO '$name'" -Targets $targets -Facts $facts -WhatIf:$WhatIf)) {
            $row.Result = $(if ($WhatIf) { 'WhatIf: not changed' } else { 'Cancelled' })
            Write-NmRunHistory -ToolId 'gpo-build' -ToolVersion '0.7.1' -Kind ReportAndChange -Mode $(if ($WhatIf) { 'WhatIf' } else { 'Cancelled' }) -Result Cancelled -Notes "$name ($($b.Id))"
            continue
        }

        try {
            $gpo = New-GPO -Name $name -Comment (Get-NmBaselineStamp -Baseline $b) @gp -ErrorAction Stop
        } catch {
            $row.Result = "Failed: GPO not created: $($_.Exception.Message)"
            Write-NmRunHistory -ToolId 'gpo-build' -ToolVersion '0.7.1' -Kind ReportAndChange -ItemCount 0 -Result Failed -Notes "$name ($($b.Id)): $($_.Exception.Message)"
            continue
        }
        $row.GpoId = "$($gpo.Id)"
        $row.GpoPath = "$($gpo.Path)"
        Write-NmLog "Created GPO '$name' ($($gpo.Id))." -Level SUCCESS
        $written = @(Invoke-NmBaselineWrite -Gpo $gpo -Baseline $b -Values $resolved.Values)
        $row.Details = $written
        $failed = @($written | Where-Object { $_.Result -ne 'Written' })
        $row.Settings = "$($written.Count - $failed.Count) of $($written.Count)"
        if ($failed.Count) {
            $row.Result = "Failed: $($failed.Count) of $($written.Count) settings not written ($($failed[0].Setting): $($failed[0].Result -replace '^Failed: ', ''))"
            Write-NmRunHistory -ToolId 'gpo-build' -ToolVersion '0.7.1' -Kind ReportAndChange -ItemCount $written.Count -Result Failed -Notes "$name ($($b.Id) $($b.Version)): $($failed.Count) settings failed"
        } else {
            $row.Result = 'Created'
            Write-NmRunHistory -ToolId 'gpo-build' -ToolVersion '0.7.1' -Kind ReportAndChange -ItemCount $written.Count -Notes "$name ($($b.Id) $($b.Version))"
        }
    }
    Write-Progress -Activity 'Building GPOs' -Completed
    if (@($out | Where-Object { $_.Result -eq 'Created' }).Count) {
        Write-NmLog 'The new GPOs are not linked. Links, filtering and delegation are chosen per GPO (gpo-scope); the suggested links are in the table.' -Level INFO
    }
    return $out.ToArray()
}

function Show-NmGpoBuildDetail {
    # One GPO's settings and what came of each.
    param($Row)
    Write-Host "$($Row.Gpo) ($($Row.Baseline) v$($Row.Version))" -ForegroundColor Cyan
    if (@($Row.Details).Count) { $Row.Details | Format-Table Setting, Kind, Result -AutoSize -Wrap | Out-Host }
    else { Write-Host "   $($Row.Result)" -ForegroundColor DarkGray }
}
