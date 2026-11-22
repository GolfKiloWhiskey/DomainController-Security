# ---------------------------------------------------------------------------
# DcHealth.ps1 - is this domain controller healthy? (the build's report, later the DC report)
# ---------------------------------------------------------------------------
# One small wrapper per Windows call (so the tests stand in for each), and Get-NmDcHealth, which
# turns them into check rows: Check, Result (OK, Warning, Failed), Detail. dcdiag's own tests come
# back as rows too (ConvertFrom-NmDcDiag).

function Get-NmServiceStatus {
    # A service's status ('Running', 'Stopped', ...), or 'Missing'.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $s) { return 'Missing' }
    return "$($s.Status)"
}

function Test-NmSmbShare {
    # True when the share exists on this server (SYSVOL, NETLOGON).
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-SmbShare -Name $Name -ErrorAction SilentlyContinue)
}

function Test-NmDnsZone {
    # True when this DNS server holds the zone.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-DnsServerZone -Name $Name -ErrorAction SilentlyContinue)
}

function Get-NmTimeSource {
    # Where this server takes its time from (w32tm /query /source).
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return ("$(& w32tm.exe /query /source 2>&1)").Trim()
}

function Get-NmDnsClientServer {
    # The DNS servers the adapter with -IPAddress uses, in order.
    [CmdletBinding()]
    param([string]$IPAddress)
    $ifs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { -not $IPAddress -or $_.IPAddress -eq $IPAddress } | Select-Object -First 1)
    if (-not $ifs.Count) { return @() }
    @((Get-DnsClientServerAddress -InterfaceIndex $ifs[0].InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
}

function Get-NmHardwareInfo {
    # CPU, logical processors and memory (GB).
    [CmdletBinding()]
    param()
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue)[0]
    [pscustomobject]@{
        Cpu        = $(if ($cpu) { ("$($cpu.Name)" -replace '\s+', ' ').Trim() } else { '' })
        Processors = [int]$cs.NumberOfLogicalProcessors
        MemoryGB   = [math]::Round(([double]$cs.TotalPhysicalMemory / 1GB), 1)
    }
}

function Invoke-NmDcDiagRaw {
    # dcdiag's output lines for -Server (in the background in the window: it takes a minute).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server)
    @(Invoke-NmGuiBackground -Status 'Running dcdiag' -Parameters @{ S = $Server } -ScriptBlock {
        param($S)
        & dcdiag.exe "/s:$S" 2>&1 | ForEach-Object { "$_" }
    })
}

# dcdiag tests that often fail for a while right after a promotion (event logs, replication of a new
# DC): a failure is shown as a Warning, with a note, not as a broken DC.
$script:NmDcDiagSoftTests = @('SystemLog', 'DFSREvent', 'KccEvent', 'Replications')

function ConvertFrom-NmDcDiag {
    <#
    .SYNOPSIS
        dcdiag's text as rows: Test, Target, Result (Passed, Failed, or Warning for a test that is
        often noisy right after a promotion), Detail.
    #>
    [CmdletBinding()]
    param([string[]]$Lines = @())
    foreach ($l in $Lines) {
        if ("$l" -match '\.{3,}\s*(\S+)\s+(passed|failed)\s+test\s+(\S+)') {
            $target = $Matches[1]; $ok = ($Matches[2] -eq 'passed'); $test = $Matches[3]
            $soft = (-not $ok) -and ($script:NmDcDiagSoftTests -contains $test)
            [pscustomobject]@{
                Test   = $test
                Target = $target
                Result = $(if ($ok) { 'Passed' } elseif ($soft) { 'Warning' } else { 'Failed' })
                Detail = $(if ($soft) { 'often reported for a while after a promotion; run dcdiag again later' } else { '' })
            }
        }
    }
}

function Get-NmDcHealth {
    <#
    .SYNOPSIS
        Checks this DC: FSMO roles, the AD services, SYSVOL and NETLOGON, its DNS zones, its DNS
        client settings, its time source, and dcdiag. Returns Checks (rows) and DcDiag (rows).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Server, [Parameter(Mandatory)][string]$Domain, [string]$IPAddress, [switch]$NoDcDiag)
    $rows = New-Object System.Collections.Generic.List[object]
    $row = { param($c, $r, $d) $rows.Add([pscustomobject]@{ Check = $c; Result = $r; Detail = "$d" }) }
    $short = ($Server -split '\.')[0]

    try {
        $adp = Get-NmADParams
        $d = Get-ADDomain @adp -ErrorAction Stop
        $f = Get-ADForest @adp -ErrorAction Stop
        $roles = [ordered]@{ 'PDC emulator' = $d.PDCEmulator; 'RID master' = $d.RIDMaster; 'Infrastructure master' = $d.InfrastructureMaster; 'Schema master' = $f.SchemaMaster; 'Domain naming master' = $f.DomainNamingMaster }
        $elsewhere = @($roles.Keys | Where-Object { (("$($roles[$_])" -split '\.')[0]) -ne $short })
        & $row 'FSMO roles' $(if ($elsewhere.Count) { 'Warning' } else { 'OK' }) $(if ($elsewhere.Count) { "not on this DC: $($elsewhere -join ', ')" } else { "all five on $short" })
    } catch { & $row 'FSMO roles' 'Warning' "not read: $($_.Exception.Message)" }

    foreach ($svc in @(@('NTDS', 'Active Directory Domain Services'), @('DNS', 'DNS Server'), @('Netlogon', 'Netlogon'), @('Kdc', 'Kerberos Key Distribution Center'), @('DFSR', 'DFS Replication (SYSVOL)'))) {
        $st = Get-NmServiceStatus -Name $svc[0]
        & $row "Service: $($svc[1])" $(if ($st -eq 'Running') { 'OK' } else { 'Failed' }) $st
    }
    foreach ($share in 'SYSVOL', 'NETLOGON') {
        $ok = Test-NmSmbShare -Name $share
        & $row "Share: $share" $(if ($ok) { 'OK' } else { 'Failed' }) $(if ($ok) { 'shared' } else { 'not shared yet (SYSVOL may still be initialising: check again in a few minutes)' })
    }
    foreach ($zone in @($Domain, "_msdcs.$Domain")) {
        $ok = Test-NmDnsZone -Name $zone
        & $row "DNS zone: $zone" $(if ($ok) { 'OK' } else { 'Failed' }) $(if ($ok) { 'present' } else { 'missing' })
    }
    $dns = @(Get-NmDnsClientServer -IPAddress $IPAddress)
    $self = @($dns | Where-Object { $_ -eq '127.0.0.1' -or $_ -eq $IPAddress }).Count -gt 0
    & $row 'DNS client settings' $(if ($self) { 'OK' } else { 'Warning' }) $(if ($dns.Count) { ($dns -join ', ') + $(if (-not $self) { ' (the DC should use its own DNS)' }) } else { 'none' })
    $ts = Get-NmTimeSource
    & $row 'Time source' $(if ($ts -match '(?i)local cmos clock|free-running') { 'Warning' } else { 'OK' }) $(if ($ts) { $ts } else { 'unknown' })

    $diag = @()
    if (-not $NoDcDiag) {
        try { $diag = @(ConvertFrom-NmDcDiag -Lines @(Invoke-NmDcDiagRaw -Server $Server)) }
        catch { & $row 'dcdiag' 'Warning' "not run: $($_.Exception.Message)" }
        if (-not $diag.Count -and -not @($rows | Where-Object Check -eq 'dcdiag').Count) { & $row 'dcdiag' 'Warning' 'no results read from dcdiag' }
    }
    [pscustomobject]@{ Checks = $rows.ToArray(); DcDiag = @($diag) }
}
