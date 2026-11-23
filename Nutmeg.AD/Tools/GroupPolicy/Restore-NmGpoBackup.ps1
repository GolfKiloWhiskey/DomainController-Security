<#
.NOTES
    Author:  Cliff Waite
    Date:    11/23/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.1

.SYNOPSIS
    Restores a GPO from a backup the toolkit made (before aligning it, for example).

.DESCRIPTION
    - Lists the backups in C:\Temp\NutmegAD\GpoBackups, newest first: the GPO, when, and why
      ("Before align with security-enforce-uac 0.7.1").
    - Restores the picked backup over the GPO (Restore-GPO), after backing up the GPO as it is now,
      so a restore can be undone too.
    - The domain's short name must be typed: a restore replaces every setting in the GPO.
      -WhatIf shows what would happen.
    - Restores the GPO's settings only; its links stay as they are (Restore-GPO does not touch them).

.EXAMPLE
    Invoke-NmTool -Id gpo-restore

.EXAMPLE
    Restore-NmGpoBackup -Backup 'Security - Enforce UAC_20261123-101500' -WhatIf

.VERSIONING
    0.7.1 - First version (issue #43).
#>

$NmTool = @{
    Name     = 'Restore GPO from Backup'
    Id       = 'gpo-restore'
    Order    = 4                            # Build, Compare, Align, Restore
    Category = 'GroupPolicy'
    Area     = 'gpo/Baselines'
    Synopsis = 'Put a GPO back as it was, from a backup the toolkit made (the current state is backed up first)'
    Version  = '0.7.1'
    Kind     = 'ReportAndChange'
    Services = @('AD', 'GPO')
    Roles    = @('Domain Admins')
    Prompt   = 'Read-NmGpoRestoreOption'
    Entry    = 'Restore-NmGpoBackup'
    Columns  = @('Gpo', 'BackupTime', 'Reason', 'Result', 'NewBackup')
    Pickers  = @{ Backup = @{ Items = 'Get-NmGpoRestorePickItem'; Note = 'Tick the backups to restore, newest first. Each GPO is backed up as it is now before it is restored.' } }
}

function Get-NmGpoRestorePickItem {
    # The window's list of backups: GPO, when and why.
    [CmdletBinding()]
    param()
    foreach ($b in @(Get-NmGpoBackup)) { [pscustomobject]@{ Key = $b.Name; Label = "$($b.Gpo)   ($($b.Time))"; Detail = "$($b.Reason)$(if ($b.Domain) { "   |   $($b.Domain)" })" } }
}

function Read-NmGpoRestoreOption {
    # Which backups. Returns the entry's parameters, or $null.
    [CmdletBinding()]
    param()
    $all = @(Get-NmGpoBackup)
    if (-not $all.Count) { Write-NmLog "No GPO backups yet in $(Get-NmGpoBackupRoot) (Align GPOs with Baselines makes one before every change)." -Level WARN; Wait-NmKey; return $null }
    $items = @(foreach ($b in $all) { [pscustomobject]@{ Label = "$($b.Gpo)   ($($b.Time))"; Detail = $b.Reason } })
    $picked = @(Read-NmMultiChoice -Title 'Which backups?' -Items $items -Note 'Each GPO is backed up as it is now before it is restored.')
    if (-not $picked.Count) { return $null }
    return @{ Backup = [string[]]@($picked | ForEach-Object { $all[$_].Name }) }
}

function Restore-NmGpoBackup {
    <#
    .SYNOPSIS
        Restores GPOs from the toolkit's backups (folder names under GpoBackups). Returns a row per backup.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Backup, [switch]$WhatIf)
    $all = @(Get-NmGpoBackup)
    $gpos = @(Get-NmAllGpo)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($name in $Backup) {
        $b = @($all | Where-Object { $_.Name -eq $name })[0]
        $row = [pscustomobject]@{ Gpo = ''; BackupTime = ''; Reason = ''; Result = ''; NewBackup = ''; Folder = ''; GpoId = ''; GpoPath = '' }
        $out.Add($row)
        if (-not $b) { $row.Gpo = $name; $row.Result = 'Failed: no such backup'; continue }
        $row.Gpo = $b.Gpo; $row.BackupTime = $b.Time; $row.Reason = $b.Reason; $row.Folder = $b.Folder
        $g = @($gpos | Where-Object { "$($_.Id)".Trim('{', '}') -eq "$($b.GpoId)".Trim('{', '}') })[0]
        if (-not $g) { $row.Result = 'Failed: the GPO no longer exists in this domain (restore it in GPMC from the backup folder)'; continue }
        $row.GpoId = "$($g.Id)"; $row.GpoPath = "$($g.Path)"
        $facts = @("Backup: $($b.Time) ($($b.Reason))", "Folder: $($b.Folder)", 'Every setting in the GPO is replaced by the backup''s. Links stay as they are.', 'The GPO is backed up as it is now first.')
        if (-not (Confirm-NmChange -Action "Restore GPO '$($b.Gpo)' from its backup" -Targets @("$($b.Gpo) <- $($b.Time)") -Facts $facts -RequireTyped -WhatIf:$WhatIf)) {
            $row.Result = $(if ($WhatIf) { 'WhatIf: not changed' } else { 'Cancelled' })
            Write-NmRunHistory -ToolId 'gpo-restore' -ToolVersion '0.7.1' -Kind ReportAndChange -Mode $(if ($WhatIf) { 'WhatIf' } else { 'Cancelled' }) -Result Cancelled -Notes "$($b.Gpo) <- $($b.Name)"
            continue
        }
        try { $row.NewBackup = Save-NmGpoBackup -Gpo $g -Reason "Before restoring the backup of $($b.Time)" }
        catch { $row.Result = "Failed: not restored, the backup of its current state failed: $($_.Exception.Message)"; continue }
        try {
            Invoke-NmGpoRestoreCmd -BackupId $b.BackupId -Path $b.Folder
            $row.Result = 'Restored'
            Write-NmLog "Restored GPO '$($b.Gpo)' from $($b.Folder)." -Level SUCCESS
            Write-NmRunHistory -ToolId 'gpo-restore' -ToolVersion '0.7.1' -Kind ReportAndChange -ItemCount 1 -Notes "$($b.Gpo) <- $($b.Name); current state saved to $(Split-Path -Leaf $row.NewBackup)"
        } catch {
            $row.Result = "Failed: $($_.Exception.Message)"
            Write-NmRunHistory -ToolId 'gpo-restore' -ToolVersion '0.7.1' -Kind ReportAndChange -Result Failed -Notes "$($b.Gpo) <- $($b.Name): $($_.Exception.Message)"
        }
    }
    return $out.ToArray()
}
