<#
.NOTES
    Author:  Cliff Waite
    Date:    11/22/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.2

.SYNOPSIS
    A report per domain controller (HTML and PDF): what is specific to that DC, and whether it is healthy.

.DESCRIPTION
    - For this DC, another DC, or every DC in the domain: one report each, in C:\Temp\NutmegAD\Reports,
      with a PDF beside it (headless Edge). A single report opens when it is written.
    - The DC: name, site, IP, OS and build, last start, global catalog, read-only, FSMO roles it holds.
    - The server: hypervisor, processor, memory, free space.
    - Network: each adapter's IP, gateway, MAC and DNS order, checked against the standard: with more
      than one DC, a partner DC first and the DC itself second; a single DC, itself first; and the
      last-DNS server (1.1.1.1 by default, Settings > New forest build) at the end.
    - Replication: every partner and naming context, with the last success, the last result and
      consecutive failures (Get-ADReplicationPartnerMetadata). SYSVOL replication state (DFSR).
    - Health: the AD services, SYSVOL and NETLOGON, the DNS zones, the time source, and dcdiag
      (Core\DcHealth.ps1, the same checks as the end of the New Forest Build).
    - Read only: nothing on any DC is changed. Another DC is reached over CIM/WMI and its own tools
      (w32tm, dcdiag /s:), so remote management must be allowed to it.

.EXAMPLE
    Invoke-NmTool -Id dc-report

.EXAMPLE
    Get-NmDcReport -Server DC02.clientx.local -NoPdf

.EXAMPLE
    Get-NmDcReport -All

.VERSIONING
    0.7.2 - The DNS order expects the last-DNS server (1.1.1.1 by default) at the end.
    0.7.1 - First version.
#>

$NmTool = @{
    Name     = 'DC Report'
    Id       = 'dc-report'
    Category = 'Reports'
    Area     = 'report/Reports'
    Synopsis = 'A report per domain controller (HTML and PDF): roles, network and DNS order, replication, health, dcdiag'
    Version  = '0.7.2'
    Kind     = 'Report'
    Services = @('AD')
    Roles    = @('Domain Admins')
    Prompt   = 'Read-NmDcReportOption'
    Entry    = 'Get-NmDcReport'
    Columns  = @('DC', 'Site', 'Roles', 'Health', 'Replication', 'Result', 'Report')
}

function Get-NmDcList {
    # The domain's DCs: Name, HostName, Site, IPv4, IsGlobalCatalog, IsReadOnly, Roles (FSMO), OS, Enabled.
    [CmdletBinding()]
    param()
    $adp = Get-NmADParams
    foreach ($dc in @(Get-ADDomainController -Filter * @adp -ErrorAction Stop | Sort-Object HostName)) {
        [pscustomobject]@{
            Name            = "$($dc.Name)"
            HostName        = "$($dc.HostName)"
            Site            = "$($dc.Site)"
            IPv4            = "$($dc.IPv4Address)"
            IsGlobalCatalog = [bool]$dc.IsGlobalCatalog
            IsReadOnly      = [bool]$dc.IsReadOnly
            Roles           = @($dc.OperationMasterRoles | ForEach-Object { "$_" })
            OS              = "$($dc.OperatingSystem)"
            Enabled         = $(if ($null -eq $dc.Enabled) { $true } else { [bool]$dc.Enabled })
        }
    }
}

function Read-NmDcReportOption {
    <#
    .SYNOPSIS
        Which DC: this one, another, or every DC. Returns the entry's parameters, or $null.
    #>
    [CmdletBinding()]
    param()
    $dcs = @(Get-NmDcList)
    if (-not $dcs.Count) { Write-NmLog 'No domain controllers found.' -Level WARN; Wait-NmKey; return $null }
    $here = @($dcs | Where-Object { Test-NmIsThisComputer -Name $_.HostName })[0]
    $opts = @()
    if ($here) { $opts += [pscustomobject]@{ Key = '1'; Label = "This DC ($($here.HostName))" } }
    $opts += [pscustomobject]@{ Key = '2'; Label = 'Another DC'; Detail = "$($dcs.Count) in the domain" }
    $opts += [pscustomobject]@{ Key = '3'; Label = 'Every DC'; Detail = 'one report each' }
    $pick = Show-NmMenu -Title 'DC Report: which DC?' -Back -Options $opts -Default $(if ($here) { '1' } else { '2' })
    switch ($pick) {
        '1' { return @{ Server = @($here.HostName) } }
        '3' { return @{ All = $true } }
        '2' {
            $i = 0
            $list = @(foreach ($d in $dcs) { $i++; [pscustomobject]@{ Key = "$i"; Label = $d.HostName; Detail = "site $($d.Site)$(if ($d.IsReadOnly) { ', read-only' })" } })
            $p = Show-NmMenu -Title 'Which DC?' -Back -Options $list
            if ($p -eq 'B') { return $null }
            return @{ Server = @($dcs[[int]$p - 1].HostName) }
        }
        default { return $null }
    }
}

function Test-NmDcDnsOrder {
    <#
    .SYNOPSIS
        Is a DC's DNS order the standard? More than one DC: a partner DC first, the DC itself (its own
        IP or 127.0.0.1) after it. A single DC: itself first. Either way the last-DNS server (-Last,
        1.1.1.1 by default, Settings > New forest build) ends the list. Returns Result (OK, Warning,
        Failed) and Detail.
    #>
    [CmdletBinding()]
    param([string[]]$Dns = @(), [string]$OwnIp, [string[]]$OtherDcIps = @(), [string]$Last = (Get-NmLastDns))
    $Dns = @($Dns | Where-Object { $_ })
    $self = { param($x) $x -eq '127.0.0.1' -or ($OwnIp -and $x -eq $OwnIp) }
    if (-not $Dns.Count) { return [pscustomobject]@{ Result = 'Failed'; Detail = 'no DNS servers set' } }
    $shown = $Dns -join ', '
    # The last-DNS server at the end is the standard; the order is judged on the rest.
    $hasLast = (-not $Last) -or ($Dns[-1] -eq $Last)
    $core = @(if ($Last -and $Dns[-1] -eq $Last) { $Dns | Select-Object -First ($Dns.Count - 1) } else { $Dns })
    $lastNote = if ($hasLast) { '' } else { "; $Last should be the last entry" }
    $res = {
        param($r, $d)
        if ($r -eq 'OK' -and -not $hasLast) { $r = 'Warning' }
        [pscustomobject]@{ Result = $r; Detail = "$shown ($d$lastNote)" }
    }
    if (-not $core.Count) { return (& $res 'Warning' 'only the last-DNS server: the DC should use its own DNS') }
    if (-not @($OtherDcIps | Where-Object { $_ }).Count) {
        if (& $self $core[0]) { return (& $res 'OK' 'the only DC: itself first') }
        return (& $res 'Warning' 'the only DC should use its own DNS first')
    }
    $first = $core[0]
    $hasSelf = @($core | Where-Object { & $self $_ }).Count -gt 0
    if ($OtherDcIps -contains $first -and $hasSelf) { return (& $res 'OK' 'a partner DC first, itself after') }
    if (& $self $first) { return (& $res 'Warning' 'itself first: a partner DC should come first, then itself') }
    if ($OtherDcIps -contains $first) { return (& $res 'Warning' 'itself is missing: add it after the partner') }
    return (& $res 'Warning' "$first is not a DC of this domain")
}

function Get-NmDcReplication {
    # The DC's inbound replication: Partner, Partition, LastSuccess, LastResult, Failures, Result.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server)
    foreach ($m in @(Get-ADReplicationPartnerMetadata -Target $Server -Scope Server -Partition * -ErrorAction Stop)) {
        $partner = if ("$($m.Partner)" -match '^CN=NTDS Settings,CN=([^,]+),') { $Matches[1] } else { "$($m.Partner)" }
        $fails = [int]$m.ConsecutiveReplicationFailures
        [pscustomobject]@{
            Partner     = $partner
            Partition   = "$($m.Partition)"
            LastSuccess = $(if ($m.LastReplicationSuccess) { ([datetime]$m.LastReplicationSuccess).ToString('yyyy-MM-dd HH:mm') } else { 'never' })
            LastResult  = "$($m.LastReplicationResult)"
            Failures    = $fails
            Result      = $(if ([int]$m.LastReplicationResult -eq 0 -and $fails -eq 0) { 'OK' } else { 'Failed' })
        }
    }
}

function New-NmDcReport {
    <#
    .SYNOPSIS
        One DC's report (HTML in the reports folder). Returns Path and the summary for the results row.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dc, [object[]]$AllDcs = @(), [switch]$NoDcDiag)
    $s = Get-NmSession
    $cn = if (Test-NmIsThisComputer -Name $Dc.HostName) { '' } else { $Dc.HostName }
    $fact = { param($n, $v) [pscustomobject]@{ Name = $n; Value = "$v" } }
    $notes = New-Object System.Collections.Generic.List[string]

    $hw = $null
    try { $hw = Get-NmHardwareInfo -ComputerName $cn } catch { $notes.Add("Server details not read: $($_.Exception.Message)") }
    $nics = @()
    try { $nics = @(Get-NmDcNetwork -ComputerName $cn) } catch { $notes.Add("Network not read: $($_.Exception.Message)") }
    $others = @($AllDcs | Where-Object { $_.HostName -ne $Dc.HostName } | ForEach-Object { $_.IPv4 } | Where-Object { $_ })
    $netRows = foreach ($n in $nics) {
        $order = Test-NmDcDnsOrder -Dns $n.Dns -OwnIp $n.IPv4 -OtherDcIps $others
        [pscustomobject]@{ Adapter = $n.Adapter; IP = "$($n.IPv4) / $($n.Mask)"; Gateway = $n.Gateway; MAC = $n.Mac; DNS = $order.Detail; Result = $order.Result }
    }
    $repl = @()
    $replNote = ''
    if (@($AllDcs).Count -le 1) { $replNote = 'The only DC: no replication partners.' }
    else {
        try { $repl = @(Get-NmDcReplication -Server $Dc.HostName) } catch { $replNote = "Replication not read: $($_.Exception.Message)" }
    }
    $sysvol = ''
    try { $sysvol = Get-NmSysvolState -ComputerName $cn } catch { $sysvol = '' }
    $health = Get-NmDcHealth -Server $Dc.HostName -Domain "$($s.Domain)" -IPAddress $Dc.IPv4 -NoDcDiag:$NoDcDiag
    $checks = @($health.Checks)
    $checks += [pscustomobject]@{ Check = 'SYSVOL replication (DFSR)'; Result = $(if ($sysvol -eq 'Normal') { 'OK' } else { 'Warning' }); Detail = $(if ($sysvol) { $sysvol } else { 'not read' }) }

    $roles = @($Dc.Roles)
    $roleText = (@($(if ($Dc.IsGlobalCatalog) { 'Global catalog' }), $(if ($Dc.IsReadOnly) { 'Read-only (RODC)' })) + $roles | Where-Object { $_ }) -join ', '
    $sections = @(
        @{ Title = 'The domain controller'; Kind = 'Facts'; Rows = @(
            (& $fact 'Name' $Dc.HostName), (& $fact 'Domain' "$($s.Domain) ($($s.NetBIOS))"), (& $fact 'Site' $Dc.Site), (& $fact 'IP address' $Dc.IPv4),
            (& $fact 'Operating system' $(if ($hw) { "$($hw.Os) (build $($hw.Build))" } else { $Dc.OS })),
            (& $fact 'Last started' $(if ($hw) { $hw.LastBoot } else { 'not read' })),
            (& $fact 'Global catalog' $(if ($Dc.IsGlobalCatalog) { 'Yes' } else { 'No' })), (& $fact 'Read-only (RODC)' $(if ($Dc.IsReadOnly) { 'Yes' } else { 'No' })),
            (& $fact 'FSMO roles held' $(if ($roles.Count) { $roles -join ', ' } else { 'none' })),
            (& $fact 'DCs in the domain' "$(@($AllDcs).Count)")) }
        @{ Title = 'Server'; Kind = 'Facts'; Rows = @(
            (& $fact 'Hypervisor' $(if ($hw) { $hw.Hypervisor } else { 'not read' })),
            (& $fact 'Processor' $(if ($hw) { "$($hw.Cpu), $($hw.Processors) logical processors" } else { 'not read' })),
            (& $fact 'Memory' $(if ($hw) { "$($hw.MemoryGB) GB" } else { 'not read' })),
            (& $fact 'Free on the system drive' $(if ($hw -and $null -ne $hw.FreeGB) { "$($hw.FreeGB) GB" } else { 'not read' }))) }
        @{ Title = 'Network'; Kind = 'Table'; Note = 'DNS order: with more than one DC, a partner DC first and the DC itself after it.'; Columns = @('Adapter', 'IP', 'Gateway', 'MAC', 'DNS', 'Result'); StatusColumn = 'Result'; Rows = @($netRows) }
        @{ Title = 'Replication'; Kind = 'Table'; Note = $replNote; Columns = @('Partner', 'Partition', 'LastSuccess', 'LastResult', 'Failures', 'Result'); StatusColumn = 'Result'; Rows = @($repl) }
        @{ Title = 'Health'; Kind = 'Table'; Columns = @('Check', 'Result', 'Detail'); StatusColumn = 'Result'; Rows = @($checks) }
    )
    if (-not $NoDcDiag) { $sections += @{ Title = 'dcdiag'; Kind = 'Table'; Note = 'Warnings: tests that are often noisy for a while after a promotion.'; Columns = @('Test', 'Target', 'Result', 'Detail'); StatusColumn = 'Result'; Rows = @($health.DcDiag) } }
    if ($notes.Count) { $sections += @{ Title = 'Not read'; Kind = 'List'; Items = $notes.ToArray() } }

    $path = Join-Path (Get-NmReportFolder) (Get-NmExportFileName -ToolId "dc-report-$($Dc.Name)" -Domain "$($s.Domain)" -Extension html)
    $null = New-NmHtmlReport -Title "DC Report: $($Dc.HostName)" -Subtitle "$($s.Domain), site $($Dc.Site)" -Path $path -Sections $sections -Meta @(
        "Run by $([Environment]::UserDomainName)\$([Environment]::UserName)", "From $([Environment]::MachineName)", (Get-Date).ToString('yyyy-MM-dd HH:mm'))

    $ok = @($checks | Where-Object Result -eq 'OK').Count
    $diagFail = @($health.DcDiag | Where-Object Result -eq 'Failed').Count
    $replFail = @($repl | Where-Object Result -ne 'OK').Count
    [pscustomobject]@{
        Path        = $path
        Roles       = $roleText
        Health      = "$ok of $($checks.Count) checks OK$(if (-not $NoDcDiag) { "; dcdiag $diagFail failed" })"
        Replication = $(if ($replNote -and -not $repl.Count) { $replNote } else { "$(@($repl).Count) link(s), $replFail failing" })
    }
}

function Get-NmDcReport {
    <#
    .SYNOPSIS
        Writes a report (HTML and PDF) for each DC asked for. Returns a row per DC.
    #>
    [CmdletBinding()]
    param([string[]]$Server = @(), [switch]$All, [switch]$NoDcDiag, [switch]$NoPdf)
    $dcs = @(Get-NmDcList)
    $targets = if ($All -or -not $Server.Count) {
        if ($All) { $dcs } else { @($dcs | Where-Object { Test-NmIsThisComputer -Name $_.HostName }) }
    } else {
        @($dcs | Where-Object { $Server -contains $_.HostName -or $Server -contains $_.Name })
    }
    $targets = @($targets)
    $rows = New-Object System.Collections.Generic.List[object]
    # A name that is not one of the domain's DCs: a row that says so.
    foreach ($m in @($Server | Where-Object { $n = $_; $n -and -not @($dcs | Where-Object { $_.HostName -eq $n -or $_.Name -eq $n }).Count })) {
        $rows.Add([pscustomobject]@{ DC = $m; Site = ''; Roles = ''; Health = ''; Replication = ''; Result = 'Failed: not a DC of this domain'; Report = '' })
    }
    $i = 0
    foreach ($dc in $targets) {
        $i++
        Write-Progress -Activity 'DC Report' -Status "[$i/$($targets.Count)] $($dc.HostName)" -PercentComplete ([int](100 * ($i - 1) / [Math]::Max(1, $targets.Count)))
        try {
            $r = New-NmDcReport -Dc $dc -AllDcs $dcs -NoDcDiag:$NoDcDiag
            $pdf = if ($NoPdf) { '' } else { ConvertTo-NmPdf -HtmlPath $r.Path }
            Write-NmLog "DC report for $($dc.HostName): $($r.Path)$(if ($pdf) { " (PDF: $pdf)" })" -Level SUCCESS -NoConsole
            $rows.Add([pscustomobject]@{ DC = $dc.HostName; Site = $dc.Site; Roles = $r.Roles; Health = $r.Health; Replication = $r.Replication; Result = 'Written'; Report = "$($r.Path)$(if ($pdf) { " (PDF beside it)" })" })
            if ($targets.Count -eq 1) { Open-NmReport -Path $r.Path }
        } catch {
            Write-NmLog "DC report for $($dc.HostName) failed: $($_.Exception.Message)" -Level ERROR
            $rows.Add([pscustomobject]@{ DC = $dc.HostName; Site = $dc.Site; Roles = ''; Health = ''; Replication = ''; Result = "Failed: $($_.Exception.Message)"; Report = '' })
        }
    }
    Write-Progress -Activity 'DC Report' -Completed
    return $rows.ToArray()
}
