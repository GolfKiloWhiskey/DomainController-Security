<#
.NOTES
    Author:  Cliff Waite
    Date:    11/22/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.1

.SYNOPSIS
    Tests for the DC Report (dc-report). No domain, no DC and no AD module needed.

.DESCRIPTION
    - A fake domain, clientx.local, with DC01 (this server, all FSMO roles, GC) and DC02 (another site).
    - Stands in for the AD cmdlets, the health wrappers (services, shares, zones, time, network,
      hardware, SYSVOL state, dcdiag) and Edge, and records which DC each was asked about.
    - Covers the DNS order rule, the questions, a report for this DC and for another, every DC,
      a name that is not a DC, a single-DC domain, and that nothing is changed.
    - Exits with code 1 if any test fails.

.EXAMPLE
    pwsh -File .\Tests\Invoke-ReportTests.ps1

.VERSIONING
    0.7.1 - Initial tests.
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Fake AD: clientx.local, DC01 (this server) and DC02.
# ---------------------------------------------------------------------------
$global:FakeDcs = @(
    [pscustomobject]@{ Name = 'DC01'; HostName = 'DC01.clientx.local'; Site = 'HQ'; IPv4Address = '192.0.2.50'; IsGlobalCatalog = $true; IsReadOnly = $false
        OperationMasterRoles = @('SchemaMaster', 'DomainNamingMaster', 'PDCEmulator', 'RIDMaster', 'InfrastructureMaster'); OperatingSystem = 'Windows Server 2025 Standard'; Enabled = $true }
    [pscustomobject]@{ Name = 'DC02'; HostName = 'DC02.clientx.local'; Site = 'Branch'; IPv4Address = '192.0.2.51'; IsGlobalCatalog = $true; IsReadOnly = $false
        OperationMasterRoles = @(); OperatingSystem = 'Windows Server 2025 Standard'; Enabled = $true }
)
$global:AdWrites = New-Object System.Collections.Generic.List[string]
function global:Get-ADDomainController { param($Filter, $Server, $Identity, [switch]$Discover, $ErrorAction) if ($Discover) { return [pscustomobject]@{ HostName = @('DC01.clientx.local') } }; $global:FakeDcs }
function global:Get-ADDomain {
    param($Server, $ErrorAction)
    [pscustomobject]@{ DNSRoot = 'clientx.local'; NetBIOSName = 'CLIENTX'; DistinguishedName = 'DC=clientx,DC=local'; DomainSID = 'S-1-5-21-1'; DomainMode = 'Windows2025Domain'
        PDCEmulator = 'DC01.clientx.local'; RIDMaster = 'DC01.clientx.local'; InfrastructureMaster = 'DC01.clientx.local' }
}
function global:Get-ADForest { param($Server, $ErrorAction) [pscustomobject]@{ RootDomain = 'clientx.local'; ForestMode = 'Windows2025Forest'; SchemaMaster = 'DC01.clientx.local'; DomainNamingMaster = 'DC01.clientx.local' } }
function global:Get-ADReplicationPartnerMetadata {
    param($Target, $Scope, $Partition, $ErrorAction)
    $global:AskedRepl = $Target
    $partner = if ($Target -like 'DC01*') { 'DC02' } else { 'DC01' }
    @(
        [pscustomobject]@{ Partner = "CN=NTDS Settings,CN=$partner,CN=Servers,CN=HQ,CN=Sites,CN=Configuration,DC=clientx,DC=local"; Partition = 'DC=clientx,DC=local'
            LastReplicationSuccess = [datetime]'2026-11-22 09:00'; LastReplicationResult = 0; ConsecutiveReplicationFailures = 0 }
        [pscustomobject]@{ Partner = "CN=NTDS Settings,CN=$partner,CN=Servers,CN=HQ,CN=Sites,CN=Configuration,DC=clientx,DC=local"; Partition = 'CN=Configuration,DC=clientx,DC=local'
            LastReplicationSuccess = [datetime]'2026-11-21 22:00'; LastReplicationResult = 8453; ConsecutiveReplicationFailures = 3 }
    )
}
# Anything that writes to AD fails the "read only" test.
foreach ($verb in 'Set', 'New', 'Remove', 'Move') { New-Item -Path "function:global:$verb-ADObject" -Value ([scriptblock]::Create("`$global:AdWrites.Add('$verb-ADObject')")) -Force | Out-Null }

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path (Join-Path $repoRoot 'Nutmeg.AD') 'Nutmeg.AD.psd1') -Force
$mod = Get-Module Nutmeg.AD
& $mod { $script:NmSettingsTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ("NmSettings_" + [guid]::NewGuid().ToString('N') + '.json'); $script:NmSettingsData = $null; Update-NmConfigFromSetting }

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("NmReportTests_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
& $mod {
    param($root)
    $script:NmConfig.ExportRoot = Join-Path $root 'Exports'
    $script:NmConfig.DataRoot   = Join-Path $root 'Data'
    $script:NmLogPath = $null
    $script:TestAnswers = New-Object System.Collections.Generic.Queue[string]
    $script:Asked = New-Object System.Collections.Generic.List[string]
    function script:Read-NmHost { param([string]$Prompt) if ($script:TestAnswers.Count -gt 0) { $script:TestAnswers.Dequeue() } else { throw 'Test ran out of scripted answers.' } }

    # This server is DC01; the modules are there.
    function script:Test-NmIsThisComputer { param([string]$Name) (("$Name" -split '\.')[0]) -eq 'DC01' }
    function script:Test-NmElevated { $true }
    function script:Find-NmModule { param($Name) [pscustomobject]@{ Name = $Name; Version = [version]'1.0.0.0' } }
    function script:Test-NmModuleLoaded { param($Name) $false }
    function script:Import-NmModule { param($Name, [switch]$WindowsPowerShell) }
    function script:Get-NmDefaultServer { 'DC01.clientx.local' }

    # The health wrappers: each records which computer it was asked about ('' = this server).
    function script:Get-NmServiceStatus { param($Name, $ComputerName) $script:Asked.Add("svc $Name @$ComputerName"); 'Running' }
    function script:Test-NmSmbShare { param($Name, $ComputerName) $true }
    function script:Test-NmDnsZone { param($Name, $ComputerName) $true }
    function script:Get-NmTimeSource { param($ComputerName) if ($ComputerName) { 'DC01.clientx.local' } else { 'time.example.org' } }
    function script:Get-NmDcNetwork {
        param($ComputerName)
        $script:Asked.Add("net @$ComputerName")
        if ($ComputerName) { [pscustomobject]@{ Adapter = 'Ethernet'; IPv4 = '192.0.2.51'; Mask = '255.255.255.0'; Gateway = '192.0.2.1'; Dns = $script:Dc02Dns; Mac = '00-15-5D-00-00-02'; Dhcp = $false } }
        else { [pscustomobject]@{ Adapter = 'Ethernet'; IPv4 = '192.0.2.50'; Mask = '255.255.255.0'; Gateway = '192.0.2.1'; Dns = @('192.0.2.51', '127.0.0.1'); Mac = '00-15-5D-00-00-01'; Dhcp = $false } }
    }
    function script:Get-NmDnsClientServer { param($IPAddress, $ComputerName) @((Get-NmDcNetwork -ComputerName $ComputerName)[0].Dns) }
    function script:Get-NmHardwareInfo { param($ComputerName) [pscustomobject]@{ Os = 'Windows Server 2025 Standard'; Build = '26100'; LastBoot = '2026-11-22 08:00'; Hypervisor = 'Hyper-V'; Cpu = 'Virtual CPU'; Processors = 4; MemoryGB = 8; FreeGB = 90 } }
    function script:Get-NmSysvolState { param($ComputerName) 'Normal' }
    function script:Invoke-NmDcDiagRaw { param($Server) $script:Asked.Add("dcdiag $Server"); @("         ......................... $(($Server -split '\.')[0]) passed test Connectivity") }
    function script:Find-NmEdge { 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' }
    function script:Invoke-NmEdgePdf { param($Edge, $HtmlPath, $PdfPath) Set-Content -LiteralPath $PdfPath -Value '%PDF'; 0 }
    function script:Open-NmReport { param($Path) $script:Asked.Add("open $(Split-Path -Leaf $Path)") }
} $testRoot

function global:Reset-Report {
    & $global:NmTestModuleR { Reset-NmSession; $script:Asked.Clear(); $script:TestAnswers.Clear(); $script:Dc02Dns = @('192.0.2.51', '192.0.2.50') }
    $global:FakeDcs = @($global:FakeDcsAll)
    $global:AdWrites.Clear()
}
$global:NmTestModuleR = $mod
$global:FakeDcsAll = @($global:FakeDcs)
function global:Answer { param([string[]]$Values) & $global:NmTestModuleR { param($v) foreach ($x in $v) { $script:TestAnswers.Enqueue($x) } } $Values }

$script:Passed = 0
$script:Failed = New-Object System.Collections.Generic.List[string]
function Test-That {
    param([string]$Name, [scriptblock]$Body)
    try {
        Reset-Report
        $result = & $mod $Body
        if ($result -eq $false) { throw 'returned false' }
        $script:Passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } catch {
        $script:Failed.Add("$Name - $($_.Exception.Message)")
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '   Nutmeg.AD DC Report tests' -ForegroundColor Yellow
Write-Host '=============================================' -ForegroundColor Cyan

Test-That 'The tool is registered in Reports, reads only, and needs the AD module' {
    $t = Get-NmTool -Id 'dc-report'
    ($t.AdminCenter -eq 'report') -and ($t.Kind -eq 'Report') -and (@($t.Services) -contains 'AD') -and ($t.Prompt -eq 'Read-NmDcReportOption')
}

Test-That 'DNS order: more DCs = a partner first and itself after; one DC = itself first' {
    $ok = Test-NmDcDnsOrder -Dns @('192.0.2.51', '127.0.0.1') -OwnIp '192.0.2.50' -OtherDcIps @('192.0.2.51')
    $selfFirst = Test-NmDcDnsOrder -Dns @('127.0.0.1', '192.0.2.51') -OwnIp '192.0.2.50' -OtherDcIps @('192.0.2.51')
    $noSelf = Test-NmDcDnsOrder -Dns @('192.0.2.51') -OwnIp '192.0.2.50' -OtherDcIps @('192.0.2.51')
    $router = Test-NmDcDnsOrder -Dns @('192.0.2.1', '192.0.2.50') -OwnIp '192.0.2.50' -OtherDcIps @('192.0.2.51')
    $single = Test-NmDcDnsOrder -Dns @('192.0.2.50', '127.0.0.1') -OwnIp '192.0.2.50'
    $singleBad = Test-NmDcDnsOrder -Dns @('192.0.2.1') -OwnIp '192.0.2.50'
    $none = Test-NmDcDnsOrder -Dns @() -OwnIp '192.0.2.50'
    ($ok.Result -eq 'OK') -and ($selfFirst.Result -eq 'Warning') -and ($selfFirst.Detail -like '*itself first*') -and ($noSelf.Result -eq 'Warning') -and
    ($router.Detail -like '*192.0.2.1 is not a DC*') -and ($single.Result -eq 'OK') -and ($singleBad.Result -eq 'Warning') -and ($none.Result -eq 'Failed')
}

Test-That 'Questions: this DC by default; another DC from the list; every DC' {
    Answer @('', '2', '2', '3')
    $a = Read-NmDcReportOption 6>$null
    $b = Read-NmDcReportOption 6>$null
    $c = Read-NmDcReportOption 6>$null
    ((@($a.Server) -join ',') -eq 'DC01.clientx.local') -and ((@($b.Server) -join ',') -eq 'DC02.clientx.local') -and $c.All -and $script:TestAnswers.Count -eq 0
}

Test-That 'This DC: checked locally; report written (HTML, PDF), opened; roles, network, replication, health and dcdiag in it' {
    $null = Assert-NmConnection -Services AD
    $rows = @(Get-NmDcReport -Server 'DC01.clientx.local' 6>$null)
    $r = $rows[0]
    $html = ($r.Report -split ' \(')[0]
    $t = Get-Content -LiteralPath $html -Raw
    ($rows.Count -eq 1) -and ($r.Result -eq 'Written') -and ($r.Report -like '*(PDF beside it)') -and (Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($html, '.pdf'))) -and
    ($r.Roles -like 'Global catalog, SchemaMaster*') -and ($r.Replication -eq '2 link(s), 1 failing') -and ($script:Asked -contains 'svc NTDS @') -and ($script:Asked -contains 'net @') -and
    ($script:Asked -contains "open $(Split-Path -Leaf $html)") -and ($script:Asked -contains 'dcdiag DC01.clientx.local') -and
    ($t -match 'DC Report: DC01.clientx.local') -and ($t -match '<h2>Replication</h2>') -and ($t -match '<td>DC02</td>') -and ($t -match 'badge b-bad">Failed') -and
    ($t -match 'a partner DC first, itself after') -and ($t -match '<h2>dcdiag</h2>') -and ($t -match 'SYSVOL replication \(DFSR\)')
}

Test-That 'Another DC: every check asked of that DC, its DNS order judged against the others, its replication read' {
    $null = Assert-NmConnection -Services AD
    $script:Dc02Dns = @('127.0.0.1', '192.0.2.50')
    $rows = @(Get-NmDcReport -Server 'DC02' -NoPdf 6>$null)
    $t = Get-Content -LiteralPath $rows[0].Report -Raw
    ($rows[0].Result -eq 'Written') -and ($script:Asked -contains 'svc NTDS @DC02.clientx.local') -and ($script:Asked -contains 'net @DC02.clientx.local') -and
    ($global:AskedRepl -eq 'DC02.clientx.local') -and ($t -match 'itself first: a partner DC should come first') -and ($t -match 'not on this DC: PDC emulator') -and
    ($rows[0].Report -notlike '*PDF*')
}

Test-That 'Every DC: one report each, none opened; a name that is not a DC says so' {
    $null = Assert-NmConnection -Services AD
    $all = @(Get-NmDcReport -All -NoPdf -NoDcDiag 6>$null)
    $bad = @(Get-NmDcReport -Server 'DC09' -NoPdf 6>$null)
    ($all.Count -eq 2) -and (@($all | Where-Object Result -eq 'Written').Count -eq 2) -and (@($script:Asked | Where-Object { $_ -like 'open *' }).Count -eq 0) -and
    ($bad.Count -eq 1) -and ($bad[0].Result -eq 'Failed: not a DC of this domain') -and (@($script:Asked | Where-Object { $_ -like 'dcdiag*' }).Count -eq 0)
}

Test-That 'A single-DC domain: no replication partners, the DNS rule for a lone DC' {
    $null = Assert-NmConnection -Services AD
    $global:FakeDcs = @($global:FakeDcsAll[0])
    $rows = @(Get-NmDcReport -Server 'DC01.clientx.local' -NoPdf -NoDcDiag 6>$null)
    $t = Get-Content -LiteralPath $rows[0].Report -Raw
    ($rows[0].Replication -eq 'The only DC: no replication partners.') -and ($t -match 'The only DC: no replication partners') -and ($t -match 'the only DC should use its own DNS first')
}

Test-That 'Read only: nothing is written to AD' {
    $null = Assert-NmConnection -Services AD
    $null = @(Get-NmDcReport -All -NoPdf -NoDcDiag 6>$null)
    $code = Get-Content -Raw -Path (Join-Path $script:NmModuleRoot 'Tools\Reports\Get-NmDcReport.ps1')
    ($global:AdWrites.Count -eq 0) -and ($code -notmatch '\b(Set|New|Remove|Move|Rename)-AD') -and ($code -notmatch 'Confirm-NmChange')
}

Test-That 'Replication partners are named by server, not by their NTDS Settings path' {
    $r = @(Get-NmDcReplication -Server 'DC01.clientx.local')
    ($r[0].Partner -eq 'DC02') -and ($r[0].Result -eq 'OK') -and ($r[1].Result -eq 'Failed') -and ($r[1].Failures -eq 3) -and ($r[0].LastSuccess -eq '2026-11-22 09:00')
}

Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '=============================================' -ForegroundColor Cyan
if ($script:Failed.Count -eq 0) {
    Write-Host "   All $script:Passed tests passed." -ForegroundColor Green
    Write-Host '=============================================' -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "   $($script:Failed.Count) failed, $script:Passed passed:" -ForegroundColor Red
    $script:Failed | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    Write-Host '=============================================' -ForegroundColor Cyan
    exit 1
}
