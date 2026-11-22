<#
.NOTES
    Author:  Cliff Waite
    Date:    MM/DD/YYYY
    Email:   cliff.ps@nutmegtech.com
    Version: 1.0

.SYNOPSIS
    One line: what the tool does.

.DESCRIPTION
    - What it reports or changes.
    - Which filters or options it offers.
    - What the deep-dive view shows, if it has one.

.EXAMPLE
    Invoke-NmTool -Id example-tool

.EXAMPLE
    Invoke-NmExampleTool | Export-Csv C:\Temp\example.csv

.VERSIONING
    1.0 - Initial version.
#>

# ---------------------------------------------------------------------------
# HOW TO USE THIS TEMPLATE
#   1. Copy it to Tools\<Category>\<Verb>-Nm<Thing>.ps1 (no leading underscore: files
#      starting with _ are skipped by the loader).
#   2. Fill in $NmTool and the entry function. Do not load modules, log to file or export
#      yourself: the core does that (Assert-NmConnection runs before your function).
#   3. Send every AD call to the session's DC: $p = Get-NmADParams; Get-ADUser ... @p
#      (GroupPolicy cmdlets: Get-NmGPParams, which adds -Domain).
#   4. Return objects. The launcher adds the [#] column, shows the table and offers
#      Re-run / Export / Grid view / Deep-dive.
#   5. Change tools: call Confirm-NmChange before every write and honour -WhatIf.
# ---------------------------------------------------------------------------

$NmTool = @{
    Name     = 'Example Tool'                 # shown in menus
    Id       = 'example-tool'                 # lower-case-hyphenated, unique
    Category = 'Directory'                    # file folder / fallback menu group
    Area     = 'ad/Structure'                 # area/section: gpo, ad, ready, report, kit
    AlsoIn   = @()                            # optional: other places to list it, e.g. @('report')
    Synopsis = 'One line shown beside the name in menus'
    Version  = '1.0'
    Kind     = 'Report'                       # Report | Change | ReportAndChange
    Services = @('AD')                        # AD, GPO (or @() for none)
    Roles    = @('Domain Admins')             # shown before the tool runs
    Entry    = 'Invoke-NmExampleTool'         # function below
    DeepDive = 'Show-NmExampleToolDetail'     # optional: function that takes one result row
    Columns  = @('Name', 'Path')              # optional: columns shown on screen
    # Optional, for the window (docs/ARCHITECTURE.md):
    # CardGroup = @('Gpo', 'Result', 'Line') # a card per Gpo, rows under each Result, shown as Line
    # Pickers   = @{ Name = @{ Items = 'Get-NmExamplePickItem'; Note = 'Tick the ones to use.' } }
    # BeforeRun = 'Complete-NmExampleArgs'   # asks what the form cannot hold when Run is pressed
}

function Invoke-NmExampleTool {
    # Change tools: add a [switch]$WhatIf parameter and call Confirm-NmChange -Action ... -Targets ... -WhatIf:$WhatIf
    # before every write; return a row per target with a Result column; record with Write-NmRunHistory.
    [CmdletBinding()]
    param()

    $p = Get-NmADParams
    Write-NmLog 'Reading OUs...' -Level INFO
    foreach ($ou in @(Get-ADOrganizationalUnit -Filter * @p)) {
        [pscustomobject]@{
            Name = $ou.Name
            Path = $ou.DistinguishedName
        }
    }
}

function Show-NmExampleToolDetail {
    param($Row)
    $p = Get-NmADParams
    Write-Host 'OU' -ForegroundColor Cyan
    Get-ADOrganizationalUnit -Identity $Row.Path -Properties * @p | Format-List | Out-Host
}
