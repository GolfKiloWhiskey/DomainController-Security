<#
.NOTES
    Author:  Cliff Waite
    Date:    11/20/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 1.0

.SYNOPSIS
    Checks that this computer, this account and this PowerShell are ready for the toolkit.

.DESCRIPTION
    - PowerShell: the version running, and whether PowerShell 7 is installed when running 5.1.
    - Elevation: whether PowerShell runs as administrator.
    - Computer: name, and whether it is a DC (and the PDC emulator).
    - Modules: ActiveDirectory and GroupPolicy, installed and loaded.
    - Domain: DNS and NetBIOS name, forest, domain and forest levels, PDC emulator, the DC in use.
    - Account: who is running it, and whether they are in Domain, Schema and Enterprise Admins.
    - Toolkit: version, tools loaded and not loaded, log, data and export folders.
    - It loads the AD module itself (the one tool that does), so a missing module shows as a row
      instead of stopping the check.

.EXAMPLE
    Invoke-NmTool -Id session-info

.EXAMPLE
    Get-NmSessionInfo | Where-Object Status -ne 'OK'

.VERSIONING
    1.0 - Initial version.
#>

$NmTool = @{
    Name     = 'Session and Prerequisite Check'
    Id       = 'session-info'
    Category = 'Diagnostics'
    Area     = 'kit/Diagnostics'
    Synopsis = 'PowerShell, elevation, DC, modules, domain, admin groups and toolkit folders'
    Version  = '1.0'
    Kind     = 'Report'
    Services = @()
    Entry    = 'Get-NmSessionInfo'
    Columns  = @('Area', 'Item', 'Value', 'Status')
}

function Get-NmSessionInfo {
    [CmdletBinding()]
    param()

    $row = { param($a, $i, $v, $st) [pscustomobject]@{ Area = $a; Item = $i; Value = "$v"; Status = $st } }

    # PowerShell
    $ver = $PSVersionTable.PSVersion
    if ($ver.Major -ge 7) {
        & $row 'PowerShell' 'Version' "$ver ($($PSVersionTable.PSEdition))" 'OK'
    } else {
        & $row 'PowerShell' 'Version' "$ver ($($PSVersionTable.PSEdition))" 'Warning: works, but PowerShell 7 is recommended'
        $pwsh = Find-NmPwsh
        & $row 'PowerShell' 'PowerShell 7' $(if ($pwsh) { $pwsh } else { 'not installed' }) $(if ($pwsh) { 'OK: start the toolkit with Start-NutmegAD.ps1 to use it' } else { 'Warning: Start-NutmegAD.ps1 offers to install it' })
    }
    $elevated = Test-NmElevated
    & $row 'PowerShell' 'Elevated' $(if ($elevated) { 'yes' } else { 'no' }) $(if ($elevated) { 'OK' } else { 'Warning: run as administrator for changes and some checks' })

    # Computer
    try {
        $pc = Get-NmLocalComputer
        $role = if ($pc.IsPdc) { 'domain controller (PDC emulator)' } elseif ($pc.IsDC) { 'domain controller' } elseif ($pc.PartOfDomain) { "member of $($pc.Domain)" } else { 'not joined to a domain' }
        & $row 'Computer' 'This computer' "$($pc.Name): $role" $(if ($pc.IsDC) { 'OK' } else { 'Warning: the toolkit is meant to run on a DC' })
    } catch {
        & $row 'Computer' 'This computer' '' "Failed: $($_.Exception.Message)"
    }

    # Modules
    foreach ($svc in $script:NmServiceModules.Keys) {
        $m = $script:NmServiceModules[$svc]
        $found = Find-NmModule -Name $m.Name
        $loaded = Test-NmModuleLoaded -Name $m.Name
        $value = if ($found) { "$($found.Version)$(if ($loaded) { ', loaded' } else { ', not loaded yet' })" } else { 'not installed' }
        $status = if ($found) { 'OK' } else { "Not ready: Install-WindowsFeature $($m.Feature)" }
        & $row 'Modules' $m.Name $value $status
    }

    # Domain (needs the AD module)
    if (Assert-NmConnection -Services AD) {
        $s = Get-NmSession
        & $row 'Domain' 'Domain' "$($s.Domain) ($($s.NetBIOS))" 'OK'
        & $row 'Domain' 'Forest' "$($s.Forest)" 'OK'
        & $row 'Domain' 'Domain level' "$($s.DomainMode)" 'OK'
        & $row 'Domain' 'Forest level' "$($s.ForestMode)" 'OK'
        & $row 'Domain' 'PDC emulator' "$($s.PdcEmulator)" 'OK'
        & $row 'Domain' 'Working against' "$($s.Server)" 'OK'

        # Account
        $who = Get-NmCurrentIdentity
        & $row 'Account' 'Running as' "$($who.Name)" 'OK'
        $sameForest = ("$($s.Forest)" -eq "$($s.Domain)")
        foreach ($m in @(Get-NmAdminMembership -DomainSid $s.DomainSid)) {
            if ($m.Group -ne 'Domain Admins' -and -not $sameForest) {
                & $row 'Account' $m.Group 'kept in the forest root domain' 'Info: not checked from a child domain'
                continue
            }
            $status = if ($m.Member) { 'OK' } elseif ($m.Group -eq 'Domain Admins') { 'Not ready: most tools need Domain Admins' } else { 'Info: needed only for forest-wide changes' }
            & $row 'Account' $m.Group $(if ($m.Member) { 'member' } else { 'not a member' }) $status
        }
    } else {
        & $row 'Domain' 'Domain' 'could not be read' 'Not ready: see the errors above'
    }

    # Toolkit
    & $row 'Toolkit' 'Version' $script:ModuleVersion 'OK'
    $loadErrors = @(Get-NmToolLoadError)
    & $row 'Toolkit' 'Tools' "$(@(Get-NmTool).Count) loaded, $($loadErrors.Count) not loaded" $(if ($loadErrors.Count) { 'Warning: see Main menu > Tools not loaded' } else { 'OK' })
    & $row 'Toolkit' 'Log' (Get-NmLogPath) 'OK'
    & $row 'Toolkit' 'Data folder' $script:NmConfig.DataRoot $(if (Test-Path $script:NmConfig.DataRoot) { 'OK' } else { 'OK: created on first write' })
    & $row 'Toolkit' 'Exports' $script:NmConfig.ExportRoot $(if (Test-Path $script:NmConfig.ExportRoot) { 'OK' } else { 'OK: created on first export' })
}
