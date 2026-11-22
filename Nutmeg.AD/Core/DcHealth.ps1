# ---------------------------------------------------------------------------
# DcHealth.ps1 - is this domain controller healthy? (the build's report, later the DC report)
# ---------------------------------------------------------------------------
# One small wrapper per Windows call (so the tests stand in for each), and Get-NmDcHealth, which
# turns them into check rows: Check, Result (OK, Warning, Failed), Detail. dcdiag's own tests come
# back as rows too (ConvertFrom-NmDcDiag).

function Get-NmCimArgs {
    # -ComputerName for CIM calls, or nothing for this server.
    param([string]$ComputerName)
    if ($ComputerName) { return @{ ComputerName = $ComputerName; ErrorAction = 'Stop' } }
    return @{ ErrorAction = 'Stop' }
}

function Test-NmIsThisComputer {
    # True when -Name is this server (short name or FQDN), so checks run locally (no remoting needed).
    param([string]$Name)
    if (-not $Name) { return $true }
    return (("$Name" -split '\.')[0] -eq [Environment]::MachineName)
}

function Get-NmServiceStatus {
    # A service's state ('Running', 'Stopped', ...), or 'Missing'. -ComputerName: another DC (CIM).
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name, [string]$ComputerName)
    $ca = Get-NmCimArgs -ComputerName $ComputerName
    $s = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" @ca)[0]
    if (-not $s) { return 'Missing' }
    return "$($s.State)"
}

function Test-NmSmbShare {
    # True when the share exists on the server (SYSVOL, NETLOGON).
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name, [string]$ComputerName)
    $ca = Get-NmCimArgs -ComputerName $ComputerName
    return [bool](@(Get-CimInstance -ClassName Win32_Share -Filter "Name='$Name'" @ca).Count)
}

function Test-NmDnsZone {
    # True when the DNS server holds the zone.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name, [string]$ComputerName)
    $a = @{ Name = $Name; ErrorAction = 'SilentlyContinue' }
    if ($ComputerName) { $a.ComputerName = $ComputerName }
    return [bool](Get-DnsServerZone @a)
}

function Get-NmTimeSource {
    # Where the server takes its time from (w32tm /query /source).
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$ComputerName)
    $w = @('/query', '/source')
    if ($ComputerName) { $w = @('/query', "/computer:$ComputerName", '/source') }
    return ("$(& w32tm.exe @w 2>&1)").Trim()
}

function Get-NmDcNetwork {
    <#
    .SYNOPSIS
        The server's adapters with an IP: Adapter, IPv4, Mask, Gateway, Dns (in order), Mac, Dhcp.
    #>
    [CmdletBinding()]
    param([string]$ComputerName)
    $ca = Get-NmCimArgs -ComputerName $ComputerName
    foreach ($n in @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' @ca)) {
        $ips = @($n.IPAddress | Where-Object { "$_" -match '^\d+\.\d+\.\d+\.\d+$' })
        if (-not $ips.Count) { continue }
        [pscustomobject]@{
            Adapter = "$($n.Description)"
            IPv4    = "$($ips[0])"
            Mask    = "$(@($n.IPSubnet)[0])"
            Gateway = (@($n.DefaultIPGateway | Where-Object { $_ }) -join ', ')
            Dns     = @($n.DNSServerSearchOrder | Where-Object { $_ })
            Mac     = "$($n.MACAddress)"
            Dhcp    = [bool]$n.DHCPEnabled
        }
    }
}

function Get-NmDnsClientServer {
    # The DNS servers the adapter with -IPAddress uses (else the first adapter's), in order.
    [CmdletBinding()]
    param([string]$IPAddress, [string]$ComputerName)
    $nics = @(Get-NmDcNetwork -ComputerName $ComputerName)
    $nic = @($nics | Where-Object { -not $IPAddress -or $_.IPv4 -eq $IPAddress })[0]
    if (-not $nic) { $nic = $nics[0] }
    if (-not $nic) { return @() }
    @($nic.Dns)
}

function Get-NmHypervisorName {
    # 'Hyper-V', 'VMware', another vendor's name, or 'None' (physical), from the maker and model.
    param([string]$Text)
    if ($Text -match 'Microsoft Corporation.*Virtual Machine') { return 'Hyper-V' }
    if ($Text -match 'VMware') { return 'VMware' }
    if ($Text -match 'QEMU|KVM|Xen|VirtualBox|innotek|Nutanix|Parallels') { return ($Text -replace '\s+', ' ').Trim() }
    return 'None'
}

function Get-NmHardwareInfo {
    # The server: OS and build, last start, hypervisor, CPU, logical processors, memory (GB), free space on the system drive (GB).
    [CmdletBinding()]
    param([string]$ComputerName)
    $ca = Get-NmCimArgs -ComputerName $ComputerName
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem @ca
    $os = Get-CimInstance -ClassName Win32_OperatingSystem @ca
    $cpu = @(Get-CimInstance -ClassName Win32_Processor @ca)[0]
    $sys = "$($os.SystemDrive)"; if (-not $sys) { $sys = 'C:' }
    $disk = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$sys'" @ca)[0]
    [pscustomobject]@{
        Os         = "$($os.Caption)"
        Build      = "$($os.BuildNumber)"
        LastBoot   = $(if ($os.LastBootUpTime) { ([datetime]$os.LastBootUpTime).ToString('yyyy-MM-dd HH:mm') } else { '' })
        Hypervisor = (Get-NmHypervisorName -Text "$($cs.Manufacturer) $($cs.Model)")
        Cpu        = $(if ($cpu) { ("$($cpu.Name)" -replace '\s+', ' ').Trim() } else { '' })
        Processors = [int]$cs.NumberOfLogicalProcessors
        MemoryGB   = [math]::Round(([double]$cs.TotalPhysicalMemory / 1GB), 1)
        FreeGB     = $(if ($disk) { [math]::Round(([double]$disk.FreeSpace / 1GB), 1) } else { $null })
    }
}

function Get-NmSysvolState {
    # SYSVOL's DFS Replication state on the server: Normal, Initial sync, In error, ... ('' when not read).
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$ComputerName)
    $ca = Get-NmCimArgs -ComputerName $ComputerName
    $f = @(Get-CimInstance -Namespace 'root/microsoftdfs' -ClassName DfsrReplicatedFolderInfo -Filter "ReplicatedFolderName='SYSVOL Share'" @ca)[0]
    if (-not $f) { return '' }
    $names = @{ 0 = 'Uninitialized'; 1 = 'Initialized'; 2 = 'Initial sync'; 3 = 'Auto recovery'; 4 = 'Normal'; 5 = 'In error' }
    $n = [int]$f.State
    if ($names.ContainsKey($n)) { return $names[$n] }
    return "State $n"
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
    # Another DC is checked over CIM / its own tools; this one locally.
    $cn = if (Test-NmIsThisComputer -Name $Server) { '' } else { $Server }
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
        $st = try { Get-NmServiceStatus -Name $svc[0] -ComputerName $cn } catch { "not read: $($_.Exception.Message)" }
        & $row "Service: $($svc[1])" $(if ($st -eq 'Running') { 'OK' } else { 'Failed' }) $st
    }
    foreach ($share in 'SYSVOL', 'NETLOGON') {
        $ok = try { Test-NmSmbShare -Name $share -ComputerName $cn } catch { $false }
        & $row "Share: $share" $(if ($ok) { 'OK' } else { 'Failed' }) $(if ($ok) { 'shared' } else { 'not shared yet (SYSVOL may still be initialising: check again in a few minutes)' })
    }
    foreach ($zone in @($Domain, "_msdcs.$Domain")) {
        $ok = try { Test-NmDnsZone -Name $zone -ComputerName $cn } catch { $false }
        & $row "DNS zone: $zone" $(if ($ok) { 'OK' } else { 'Failed' }) $(if ($ok) { 'present' } else { 'missing' })
    }
    $dns = @(try { Get-NmDnsClientServer -IPAddress $IPAddress -ComputerName $cn } catch { })
    $self = @($dns | Where-Object { $_ -eq '127.0.0.1' -or ($IPAddress -and $_ -eq $IPAddress) }).Count -gt 0
    & $row 'DNS client settings' $(if ($self) { 'OK' } else { 'Warning' }) $(if ($dns.Count) { ($dns -join ', ') + $(if (-not $self) { ' (the DC should use its own DNS)' }) } else { 'none' })
    $ts = try { Get-NmTimeSource -ComputerName $cn } catch { '' }
    & $row 'Time source' $(if ($ts -match '(?i)local cmos clock|free-running') { 'Warning' } else { 'OK' }) $(if ($ts) { $ts } else { 'unknown' })

    $diag = @()
    if (-not $NoDcDiag) {
        try { $diag = @(ConvertFrom-NmDcDiag -Lines @(Invoke-NmDcDiagRaw -Server $Server)) }
        catch { & $row 'dcdiag' 'Warning' "not run: $($_.Exception.Message)" }
        if (-not $diag.Count -and -not @($rows | Where-Object Check -eq 'dcdiag').Count) { & $row 'dcdiag' 'Warning' 'no results read from dcdiag' }
    }
    [pscustomobject]@{ Checks = $rows.ToArray(); DcDiag = @($diag) }
}
