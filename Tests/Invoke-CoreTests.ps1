<#
.NOTES
    Author:  Cliff Waite
    Date:    11/20/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.1.0

.SYNOPSIS
    Tests for the Nutmeg.AD core. No domain, no DC and no AD or GroupPolicy module needed.

.DESCRIPTION
    - Imports the module fresh and points its data and export folders at a throwaway temp folder.
    - Replaces the prompt function (Read-NmHost) with scripted answers, so menus and confirmations run unattended.
    - Stands in for this computer, the account, the Windows modules and the AD cmdlets (a fake DC01 in clientx.local).
    - Covers logging, exports, the [#] index, tool registration rules, the domain session, module loading,
      change confirmations, settings, the PowerShell 7 install, session-info and the main menu.
    - Exits with code 1 if any test fails, so it can gate a release.

.EXAMPLE
    pwsh -File .\Tests\Invoke-CoreTests.ps1

.VERSIONING
    0.1.0 - Initial core tests.
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Fake AD cmdlets: one domain, clientx.local, with DC01 (the PDC) and DC02.
# They record every call so tests can check which DC was asked.
# ---------------------------------------------------------------------------
$global:AdCalls = New-Object System.Collections.Generic.List[string]
function global:Get-ADDomain {
    param($Server, $ErrorAction)
    $global:AdCalls.Add("Get-ADDomain $Server")
    if ($Server -eq 'down.clientx.local') { throw 'Unable to contact the server.' }
    [pscustomobject]@{ DNSRoot = 'clientx.local'; NetBIOSName = 'CLIENTX'; DistinguishedName = 'DC=clientx,DC=local'
        DomainSID = 'S-1-5-21-1000-2000-3000'; DomainMode = 'Windows2016Domain'; PDCEmulator = 'DC01.clientx.local' }
}
function global:Get-ADForest {
    param($Server, $ErrorAction)
    $global:AdCalls.Add("Get-ADForest $Server")
    [pscustomobject]@{ RootDomain = 'clientx.local'; ForestMode = 'Windows2016Forest' }
}
function global:Get-ADDomainController {
    param([switch]$Discover, $Filter, $Server, $ErrorAction)
    $global:AdCalls.Add("Get-ADDomainController $(if ($Discover) { 'Discover' } else { "Filter $Server" })")
    if ($Discover) { return [pscustomobject]@{ HostName = @('DC02.clientx.local') } }
    @([pscustomobject]@{ HostName = 'DC01.clientx.local'; Site = 'HQ'; IsReadOnly = $false }
      [pscustomobject]@{ HostName = 'DC02.clientx.local'; Site = 'HQ'; IsReadOnly = $false })
}

# Release metadata and downloads for the PowerShell 7 install (no network in tests).
$global:WebCalls = New-Object System.Collections.Generic.List[string]
function global:Invoke-RestMethod {
    param($Uri, $TimeoutSec, $ErrorAction)
    $global:WebCalls.Add("REST $Uri")
    [pscustomobject]@{ StableReleaseTag = 'v7.7.0'; LTSReleaseTag = @('v7.6.10') }
}
function global:Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $ErrorAction)
    $global:WebCalls.Add("GET $Uri")
    $global:ProgressAtDownload = $ProgressPreference
    Set-Content -Path $OutFile -Value 'not really an msi'
}
$global:Started = New-Object System.Collections.Generic.List[string]
function global:Start-Process {
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, $ErrorAction, $Verb)
    $global:Started.Add("$FilePath $($ArgumentList -join ' ')")
    [pscustomobject]@{ ExitCode = $global:MsiExitCode }
}
$global:MsiExitCode = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path (Join-Path $repoRoot 'Nutmeg.AD') 'Nutmeg.AD.psd1'

Import-Module $modulePath -Force
$mod = Get-Module Nutmeg.AD
# Tests never read or write your own settings: an empty settings file of their own.
& $mod { $script:NmSettingsTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ("NmAdSettings_" + [guid]::NewGuid().ToString('N') + '.json'); $script:NmSettingsData = $null; Update-NmConfigFromSetting }

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("NmAdTests_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

& $mod {
    param($root)
    $script:NmConfig.ExportRoot = Join-Path $root 'Exports'
    $script:NmConfig.DataRoot   = Join-Path $root 'Data'
    $script:NmLogPath = $null
    # Scripted answers for every prompt: tests push into this queue before calling a prompt.
    $script:TestAnswers = New-Object System.Collections.Generic.Queue[string]
    function script:Read-NmHost { param([string]$Prompt) if ($script:TestAnswers.Count -gt 0) { $script:TestAnswers.Dequeue() } else { throw 'Test ran out of scripted answers (a menu asked more than expected).' } }

    # This computer, the account and the Windows modules, as the tests set them.
    $script:FakePc = [pscustomobject]@{ Name = 'DC01'; Domain = 'clientx.local'; PartOfDomain = $true; IsDC = $true; IsPdc = $true; DnsHostName = 'DC01.clientx.local' }
    $script:FakeElevated = $true
    $script:FakeSids = @('S-1-5-32-544', 'S-1-5-21-1000-2000-3000-512', 'S-1-5-21-1000-2000-3000-519')
    $script:FakeModules = @{ ActiveDirectory = '1.0.1.0'; GroupPolicy = '1.0.0.0' }
    $script:Imported = New-Object System.Collections.Generic.List[string]
    function script:Get-NmLocalComputer { $script:FakePc }
    function script:Test-NmElevated { $script:FakeElevated }
    function script:Get-NmCurrentIdentity { [pscustomobject]@{ Name = 'CLIENTX\admin.msp'; Sids = $script:FakeSids } }
    function script:Find-NmModule { param($Name) if ($script:FakeModules.ContainsKey($Name)) { [pscustomobject]@{ Name = $Name; Version = [version]$script:FakeModules[$Name] } } }
    function script:Test-NmModuleLoaded { param($Name) $script:Imported.Contains($Name) }
    function script:Import-NmModule { param($Name, [switch]$WindowsPowerShell) $script:Imported.Add("$Name$(if ($WindowsPowerShell) { ' (WinPS)' })") }
} $testRoot

$script:Passed = 0
$script:Failed = New-Object System.Collections.Generic.List[string]

function Test-That {
    param([string]$Name, [scriptblock]$Body)
    try {
        $result = & $mod $Body
        if ($result -eq $false) { throw 'returned false' }
        $script:Passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } catch {
        $script:Failed.Add("$Name - $($_.Exception.Message)")
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Global, so test bodies (which run inside the module) can call them too.
$global:NmTestModule = $mod
function global:Answer { param([string[]]$Values) & $global:NmTestModule { param($v) foreach ($x in $v) { $script:TestAnswers.Enqueue($x) } } $Values }
function global:Reset-Fake {
    & $global:NmTestModule {
        Reset-NmSession
        $script:Imported.Clear()
        $script:TestAnswers.Clear()
        $script:FakePc = [pscustomobject]@{ Name = 'DC01'; Domain = 'clientx.local'; PartOfDomain = $true; IsDC = $true; IsPdc = $true; DnsHostName = 'DC01.clientx.local' }
        $script:FakeElevated = $true
        $script:FakeModules = @{ ActiveDirectory = '1.0.1.0'; GroupPolicy = '1.0.0.0' }
    }
    $global:AdCalls.Clear()
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '   Nutmeg.AD core tests' -ForegroundColor Yellow
Write-Host '=============================================' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Logging, exports, index
# ---------------------------------------------------------------------------
Test-That 'Write-NmLog writes a timestamped line to the session log' {
    Write-NmLog 'hello log' -Level INFO -NoConsole
    $line = @(Get-Content (Get-NmLogPath))[-1]
    ($line -match '^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] \[INFO\] hello log$') -and ((Split-Path -Leaf (Get-NmLogPath)) -like 'NutmegAD_*.txt')
}

Test-That 'A log handed over (NUTMEG_AD_LOG) is carried on, with a marker, and nothing in it lost' {
    $handed = Join-Path $script:NmConfig.DataRoot 'Logs\Handed.txt'
    New-Item -Path (Split-Path -Parent $handed) -ItemType Directory -Force | Out-Null
    Set-Content -Path $handed -Value '[2026-11-21 08:00:00] [INFO] from Get-NutmegAD.ps1'
    $was = $script:NmLogPath
    $env:NUTMEG_AD_LOG = $handed; $script:NmLogPath = $null
    try {
        $p = Get-NmLogPath
        Write-NmLog 'from the toolkit' -Level INFO -NoConsole
        $lines = @(Get-Content $handed)
    } finally { Remove-Item Env:\NUTMEG_AD_LOG; $script:NmLogPath = $was }
    $p -eq $handed -and $lines.Count -eq 3 -and $lines[0] -match 'from Get-NutmegAD' -and $lines[1] -match '---- Session continued: .* toolkit ' -and $lines[2] -match 'from the toolkit'
}

Test-That 'Two sessions started in the same second get a log each' {
    $was = $script:NmLogPath
    try {
        $script:NmLogPath = $null; $a = Get-NmLogPath; Set-Content -Path $a -Value 'first'
        $script:NmLogPath = $null; $b = Get-NmLogPath
    } finally { $script:NmLogPath = $was }
    $a -ne $b -and ((Split-Path -Leaf $b) -like 'NutmegAD_*_2.txt' -or (Split-Path -Leaf $b) -notlike (Split-Path -Leaf $a))
}

Test-That 'With nothing to carry on, a session starts its own NutmegAD_<time>.txt' {
    $was = $script:NmLogPath; $script:NmLogPath = $null
    try { $p = Get-NmLogPath } finally { $script:NmLogPath = $was }
    (Split-Path -Leaf $p) -like 'NutmegAD_*.txt'
}

Test-That 'The launcher passes the log on: plain to direct calls, quoted to Start-Process' {
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'Start-NutmegAD.ps1') -Raw
    $text -match 'powershell\.exe -NoLogo -NoProfile -File \$PSCommandPath -NewForest @modeArgs @logArgs' -and $text -match '& \$pwsh -NoLogo -STA -File \$PSCommandPath -Stay @modeArgs @logArgs' -and
        $text -match '\$relaunch \+= \$logArgsQuoted' -and $text -match '\$env:NUTMEG_AD_LOG = \$LogPath'
}

Test-That 'HTML report: one self-contained, print-ready file; text encoded (no markup or non-ASCII gets through raw); badges by status' {
    $p = Join-Path (Get-NmReportFolder) 'report-test.html'
    $null = New-NmHtmlReport -Title 'Test <report>' -Subtitle 'Caf' -Meta @('Run by CLIENTX\admin') -Path $p -Sections @(
        @{ Title = 'Facts'; Kind = 'Facts'; Rows = @([pscustomobject]@{ Name = 'Domain'; Value = 'clientx.local' }, [pscustomobject]@{ Name = 'Name'; Value = ('Jos' + [char]0x00E9) }) }
        @{ Title = 'Checks'; Kind = 'Table'; Columns = @('Check', 'Result'); StatusColumn = 'Result'; Rows = @([pscustomobject]@{ Check = '<script>x</script>'; Result = 'OK' }, [pscustomobject]@{ Check = 'b'; Result = 'Warning' }, [pscustomobject]@{ Check = 'c'; Result = 'Failed' }) }
        @{ Title = 'Next'; Kind = 'List'; Items = @('one', 'two') })
    $t = Get-Content -LiteralPath $p -Raw
    $bytes = [System.IO.File]::ReadAllBytes($p)
    ($t -match '<title>Test &lt;report&gt;</title>') -and ($t -notmatch '<script>') -and ($t -match '&lt;script&gt;') -and ($t -match 'Jos&#233;') -and
    ($t -match 'badge b-ok">OK') -and ($t -match 'badge b-warn">Warning') -and ($t -match 'badge b-bad">Failed') -and ($t -match '<li>two</li>') -and
    ($t -match '@media print') -and ($t -notmatch 'https?://') -and (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) -and ($bytes[0] -ne 0xEF)
}

Test-That 'PDF copy: none without Edge (the HTML stays); Edge is asked to print headless' {
    $p = Join-Path (Get-NmReportFolder) 'report-test.html'
    $real = ${function:script:Find-NmEdge}
    try {
        ${function:script:Find-NmEdge} = { '' }
        $none = ConvertTo-NmPdf -HtmlPath $p 6>$null
    } finally { Set-Item -Path function:script:Find-NmEdge -Value $real }
    $code = (Get-Command Invoke-NmEdgePdf).ScriptBlock.ToString()
    ($none -eq '') -and (Test-Path -LiteralPath $p) -and ($code -match '--headless') -and ($code -match '--print-to-pdf') -and ($code -match '--no-pdf-header-footer')
}

Test-That 'Add-NmIndex numbers rows from 1 in a [#] column first' {
    $r = @(Add-NmIndex -InputObject @([pscustomobject]@{ A = 'x' }, [pscustomobject]@{ A = 'y' }))
    $r[0].'#' -eq 1 -and $r[1].'#' -eq 2 -and @($r[0].PSObject.Properties.Name)[0] -eq '#'
}

Test-That 'Export file names carry the domain short name, and exports leave out the [#] column' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    $name = Get-NmExportFileName -ToolId 'session-info' -Domain 'clientx.local'
    $path = Export-NmResult -Data @(Add-NmIndex -InputObject @([pscustomobject]@{ A = 1 })) -ToolId 'session-info' -NoPrompt
    $cols = @((Import-Csv $path | Select-Object -First 1).PSObject.Properties.Name)
    ($name -like 'session-info_clientx_*.csv') -and ((Split-Path -Leaf $path) -like 'session-info_clientx_*') -and ($cols -notcontains '#')
}

Test-That 'Run history records the domain and the DC' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    Write-NmRunHistory -ToolId 'test-tool' -ToolVersion '1.0' -ItemCount 3
    $last = @(Get-NmRunHistory -Last 1)[0]
    $last.Domain -eq 'clientx.local' -and $last.Server -eq 'DC01.clientx.local' -and $last.ItemCount -eq '3'
}

# ---------------------------------------------------------------------------
# Tool registration
# ---------------------------------------------------------------------------
function global:Invoke-NmTestTool { param() [pscustomobject]@{ Name = 'one' } }
Test-That 'A valid tool registers in its area and section' {
    Register-NmTool -Path 'test.ps1' -Definition @{ Name = 'Test Tool'; Id = 'test-tool'; Category = 'Directory'; Area = 'ad/structure'; Synopsis = 's'; Version = '1.0'; Kind = 'Report'; Services = @('AD'); Entry = 'Invoke-NmTestTool' }
    $t = Get-NmTool -Id 'test-tool'
    $t -and $t.AdminCenter -eq 'ad' -and $t.Section -eq 'Structure'
}

Test-That 'Registration refuses a missing field, a bad Id, an unknown service, an unknown area and a duplicate Id' {
    $before = $script:NmToolLoadErrors.Count
    $base = @{ Name = 'X'; Id = 'x-tool'; Category = 'Directory'; Synopsis = 's'; Version = '1.0'; Kind = 'Report'; Services = @(); Entry = 'Invoke-NmTestTool' }
    $noName = $base.Clone(); $noName.Remove('Name')
    Register-NmTool -Path 'a.ps1' -Definition $noName
    $badId = $base.Clone(); $badId.Id = 'Bad_Id'
    Register-NmTool -Path 'b.ps1' -Definition $badId
    $badSvc = $base.Clone(); $badSvc.Services = @('EXO')
    Register-NmTool -Path 'c.ps1' -Definition $badSvc
    $badArea = $base.Clone(); $badArea.Area = 'exo/Mailboxes'
    Register-NmTool -Path 'd.ps1' -Definition $badArea
    $dup = $base.Clone(); $dup.Id = 'test-tool'
    Register-NmTool -Path 'e.ps1' -Definition $dup
    $reasons = @($script:NmToolLoadErrors | Select-Object -Skip $before | ForEach-Object { $_.Reason })
    $reasons.Count -eq 5 -and $reasons[0] -match 'Missing' -and $reasons[1] -match 'lower-case' -and $reasons[2] -match 'Unknown service' -and $reasons[3] -match 'unknown admin center' -and $reasons[4] -match 'Duplicate'
}

Test-That 'session-info loads from the Tools folder into Toolkit > Diagnostics' {
    $t = Get-NmTool -Id 'session-info'
    $t -and $t.AdminCenter -eq 'kit' -and $t.Section -eq 'Diagnostics' -and @($script:NmToolLoadErrors | Where-Object { $_.File -like '*Get-NmSessionInfo*' }).Count -eq 0
}

Test-That 'The areas are Group Policy, Active Directory, Hardening readiness, Reports, New forest build and Toolkit, in that order' {
    (@($script:NmAdminCenters.Name) -join '|') -eq 'Group Policy|Active Directory|Hardening readiness|Reports|New forest build|Toolkit|Other'
}

# ---------------------------------------------------------------------------
# The domain session
# ---------------------------------------------------------------------------
Test-That 'A tool with no services loads nothing and reads no domain' {
    Reset-Fake
    (Assert-NmConnection -Services @()) -and $script:Imported.Count -eq 0 -and $global:AdCalls.Count -eq 0
}

Test-That 'On a DC, AD loads and the domain is read from this DC' {
    Reset-Fake
    $ok = Assert-NmConnection -Services AD
    $s = Get-NmSession
    $ok -and $s.Domain -eq 'clientx.local' -and $s.NetBIOS -eq 'CLIENTX' -and $s.Server -eq 'DC01.clientx.local' -and
        $s.DomainSid -eq 'S-1-5-21-1000-2000-3000' -and $s.Forest -eq 'clientx.local' -and $s.PdcEmulator -eq 'DC01.clientx.local' -and
        ($global:AdCalls -contains 'Get-ADDomain DC01.clientx.local') -and $s.Services.AD
}

Test-That 'Off a DC, the DC comes from AD discovery' {
    Reset-Fake
    $script:FakePc = [pscustomobject]@{ Name = 'MGMT01'; Domain = 'clientx.local'; PartOfDomain = $true; IsDC = $false; IsPdc = $false; DnsHostName = 'MGMT01.clientx.local' }
    $ok = Assert-NmConnection -Services AD
    $ok -and (Get-NmSession).Server -eq 'DC02.clientx.local' -and ($global:AdCalls -contains 'Get-ADDomainController Discover')
}

Test-That 'A second tool does not load the module or read the domain again' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    $calls = $global:AdCalls.Count
    $null = Assert-NmConnection -Services AD
    $script:Imported.Count -eq 1 -and $global:AdCalls.Count -eq $calls
}

Test-That 'GPO tools load ActiveDirectory first, then GroupPolicy through Windows PowerShell' {
    Reset-Fake
    $ok = Assert-NmConnection -Services GPO
    $ok -and $script:Imported.Count -eq 2 -and $script:Imported[0] -eq 'ActiveDirectory' -and $script:Imported[1] -eq 'GroupPolicy (WinPS)' -and (Get-NmSession).Services.GPO
}

Test-That 'A missing module fails with the Windows feature to add, and nothing is marked loaded' {
    Reset-Fake
    $script:FakeModules.Remove('GroupPolicy')
    $ok = Assert-NmConnection -Services GPO
    $log = Get-Content (Get-NmLogPath) -Raw
    (-not $ok) -and -not (Get-NmSession).Services.GPO -and $log -match 'Install-WindowsFeature GPMC'
}

Test-That 'An unknown service is refused' {
    Reset-Fake
    -not (Assert-NmConnection -Services 'EXO')
}

Test-That 'Get-NmADParams and Get-NmGPParams send every call to the session DC' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    $a = Get-NmADParams; $g = Get-NmGPParams
    $a.Server -eq 'DC01.clientx.local' -and $g.Server -eq 'DC01.clientx.local' -and $g.Domain -eq 'clientx.local'
}

Test-That 'Set-NmServer moves to another DC, and keeps the old one if the new one does not answer' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    $moved = Set-NmServer -Server 'DC02.clientx.local'
    $now = (Get-NmSession).Server
    $bad = Set-NmServer -Server 'down.clientx.local'
    $moved -and $now -eq 'DC02.clientx.local' -and (-not $bad) -and (Get-NmSession).Server -eq 'DC02.clientx.local'
}

Test-That 'Admin group membership comes from the token SIDs' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    $m = @(Get-NmAdminMembership)
    ($m | Where-Object Group -eq 'Domain Admins').Member -and -not ($m | Where-Object Group -eq 'Schema Admins').Member -and ($m | Where-Object Group -eq 'Enterprise Admins').Member
}

Test-That 'The banner shows the domain, the DC and what is loaded' {
    Reset-Fake
    $before = Get-NmBannerText
    $null = Assert-NmConnection -Services AD
    $after = Get-NmBannerText
    $before -match 'not read yet' -and $after -match 'clientx\.local \(CLIENTX\)' -and $after -match 'DC: DC01\.clientx\.local' -and $after -match 'AD loaded, GPO -'
}

Test-That 'In PowerShell 7, modules are looked for with -SkipEditionCheck (GroupPolicy is hidden without it)' {
    # The real Find-NmModule, with Get-Module standing in: GroupPolicy is only found with the switch.
    $global:ListArgs = $null
    function script:Get-Module { param([switch]$ListAvailable, $Name, $ErrorAction, [switch]$SkipEditionCheck) $global:ListArgs = $PSBoundParameters; if ($SkipEditionCheck) { [pscustomobject]@{ Name = $Name; Version = [version]'1.0.0.0' } } }
    $file = Join-Path (Join-Path $script:NmModuleRoot 'Core') 'Modules.ps1'
    $def = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null).FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Find-NmModule' }, $true)[0]
    try {
        # The real function from the file (the tests' stand-in replaces it in the module), in a child scope.
        $found = & { . ([scriptblock]::Create($def.Extent.Text)); Find-NmModule -Name GroupPolicy }
    } finally { Remove-Item Function:\Get-Module -ErrorAction SilentlyContinue }
    $found.Name -eq 'GroupPolicy' -and $global:ListArgs.ContainsKey('SkipEditionCheck')
}

Test-That 'Result tables wrap long values instead of cutting them off' {
    # Show-NmResult draws with Out-Host, which a test cannot capture: check it asks for -Wrap.
    $body = (Get-Command Show-NmResult -CommandType Function).ScriptBlock.ToString()
    $body -match 'Format-Table -AutoSize -Wrap \| Out-Host'
}

# ---------------------------------------------------------------------------
# Change confirmations
# ---------------------------------------------------------------------------
Test-That 'WhatIf shows the change and returns false without asking' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    $r = Confirm-NmChange -Action 'Create OU' -Targets @('OU=Devices') -WhatIf
    (-not $r) -and $script:TestAnswers.Count -eq 0
}

Test-That 'A small change asks Y/N' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    Answer @('y')
    $yes = Confirm-NmChange -Action 'Create OU' -Targets @('OU=Devices')
    Answer @('')
    $no = Confirm-NmChange -Action 'Create OU' -Targets @('OU=Devices')
    $yes -and -not $no
}

Test-That 'A domain-wide change needs the domain short name typed' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    Answer @('y')
    $wrong = Confirm-NmChange -Action 'Link GPO at the domain root' -DomainWide
    Answer @('clientx')
    $right = Confirm-NmChange -Action 'Link GPO at the domain root' -DomainWide
    (-not $wrong) -and $right
}

Test-That 'More targets than the bulk limit need the name typed too' {
    Reset-Fake
    $null = Assert-NmConnection -Services AD
    $many = 1..30 | ForEach-Object { "user$_" }
    Answer @('clientx')
    Confirm-NmChange -Action 'Reset passwords' -Targets $many
}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
Test-That 'Settings save, apply to the config, and refuse values out of range' {
    Set-NmSetting -Key BulkConfirmCount -Value 10
    $applied = $script:NmConfig.BulkConfirmCount -eq 10 -and (Get-NmSetting -Key BulkConfirmCount) -eq 10
    $refused = $false
    try { Set-NmSetting -Key BulkConfirmCount -Value 0 } catch { $refused = $true }
    Clear-NmSetting -Key BulkConfirmCount
    $applied -and $refused -and $script:NmConfig.BulkConfirmCount -eq 25
}

Test-That 'Only the AD toolkit settings exist' {
    (@($script:NmSettingDefs.Key) -join ',') -eq 'ExportRoot,LogRetentionDays,BulkConfirmCount,BuildTimeZone,ResultsView'
}

# ---------------------------------------------------------------------------
# PowerShell 7
# ---------------------------------------------------------------------------
Test-That 'The LTS version comes from the release metadata, and the MSI matches the processor' {
    (Get-NmPwshLtsVersion) -eq '7.6.10' -and
        (Get-NmPwshMsiUri -Version '7.6.10' -Arch x64) -eq 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.10/PowerShell-7.6.10-win-x64.msi' -and
        (Get-NmPwshMsiUri -Version '7.6.10' -Arch arm64) -like '*-win-arm64.msi'
}

Test-That 'The install refuses when not elevated' {
    Reset-Fake
    $was = $script:NmOnWindows; $script:NmOnWindows = $true; $script:FakeElevated = $false
    try { $r = Install-NmPowerShell7 } finally { $script:NmOnWindows = $was }
    $r.Result -match 'administrator'
}

Test-That 'The install runs the MSI with Microsoft Update on, after the signature check' {
    Reset-Fake
    $global:Started.Clear(); $global:MsiExitCode = 0
    $was = $script:NmOnWindows; $script:NmOnWindows = $true
    function script:Test-NmMicrosoftSignature { param($Path) $true }
    try { Answer @('y'); $r = Install-NmPowerShell7 } finally { $script:NmOnWindows = $was }
    $cmd = @($global:Started)[0]
    $r.Result -eq 'Installed' -and $r.Version -eq '7.6.10' -and $cmd -like 'msiexec.exe*' -and $cmd -match 'USE_MU=1' -and $cmd -match 'ENABLE_MU=1' -and $cmd -match 'ADD_PATH=1' -and $cmd -match '/qn'
}

Test-That 'Install with -ApprovedBy asks nothing, logs the approval, and puts the plan back afterwards' {
    Reset-Fake
    $global:Started.Clear(); $global:MsiExitCode = 0
    $was = $script:NmOnWindows; $script:NmOnWindows = $true
    function script:Test-NmMicrosoftSignature { param($Path) $true }
    $script:NmPlanApproved = $null
    try { $r = Install-NmPowerShell7 -ApprovedBy 'Get-NutmegAD.ps1: PowerShell 7 is part of every toolkit server' 6>$null } finally { $script:NmOnWindows = $was }
    $log = Get-Content -LiteralPath (Get-NmLogPath) -Raw
    $r.Result -eq 'Installed' -and $script:TestAnswers.Count -eq 0 -and (-not $script:NmPlanApproved) -and
        $log -match "Approved with the plan 'Get-NutmegAD.ps1: PowerShell 7 is part of every toolkit server': Install PowerShell 7.6.10"
}

Test-That 'The PowerShell 7 download runs with the progress bar off (5.1 crawls with it on)' {
    Reset-Fake
    $global:ProgressAtDownload = $null
    $was = $script:NmOnWindows; $script:NmOnWindows = $true
    function script:Test-NmMicrosoftSignature { param($Path) $true }
    # Inside the module, so it reads the preference the toolkit set, as the real cmdlet does.
    function script:Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec, $ErrorAction) $global:ProgressAtDownload = $ProgressPreference; Set-Content -Path $OutFile -Value 'x' }
    try { Answer @('y'); $null = Install-NmPowerShell7 } finally { $script:NmOnWindows = $was; Remove-Item -Path Function:\Invoke-WebRequest -ErrorAction SilentlyContinue }
    "$global:ProgressAtDownload" -eq 'SilentlyContinue' -and "$ProgressPreference" -ne 'SilentlyContinue'
}

Test-That 'An unsigned download is never run' {
    Reset-Fake
    $global:Started.Clear()
    $was = $script:NmOnWindows; $script:NmOnWindows = $true
    function script:Test-NmMicrosoftSignature { param($Path) $false }
    try { Answer @('y'); $r = Install-NmPowerShell7 } finally { $script:NmOnWindows = $was }
    $r.Result -match 'not signed by Microsoft' -and $global:Started.Count -eq 0
}

Test-That 'An installer error is reported with its code, and declining installs nothing' {
    Reset-Fake
    $global:Started.Clear(); $global:MsiExitCode = 1603
    $was = $script:NmOnWindows; $script:NmOnWindows = $true
    function script:Test-NmMicrosoftSignature { param($Path) $true }
    try {
        Answer @('y'); $failed = Install-NmPowerShell7
        $count = $global:Started.Count
        Answer @('n'); $declined = Install-NmPowerShell7
    } finally { $script:NmOnWindows = $was; $global:MsiExitCode = 0 }
    $failed.Result -match '1603' -and $declined.Result -eq 'Cancelled' -and $global:Started.Count -eq $count
}

# ---------------------------------------------------------------------------
# session-info
# ---------------------------------------------------------------------------
Test-That 'session-info on a DC as a domain admin: domain read, admin groups OK, modules OK' {
    Reset-Fake
    $rows = @(Invoke-NmTool -Id session-info -NoMenu)
    $get = { param($i) $rows | Where-Object Item -eq $i | Select-Object -First 1 }
    (& $get 'Domain').Value -eq 'clientx.local (CLIENTX)' -and (& $get 'Domain Admins').Status -eq 'OK' -and
        (& $get 'Schema Admins').Status -like 'Info:*' -and (& $get 'ActiveDirectory').Status -eq 'OK' -and
        (& $get 'This computer').Value -match 'PDC emulator' -and (& $get 'Working against').Value -eq 'DC01.clientx.local'
}

Test-That 'session-info without the AD module still runs and says what to install' {
    Reset-Fake
    $script:FakeModules.Remove('ActiveDirectory')
    $script:FakeElevated = $false
    $rows = @(Invoke-NmTool -Id session-info -NoMenu)
    $get = { param($i) $rows | Where-Object Item -eq $i | Select-Object -First 1 }
    (& $get 'ActiveDirectory').Status -match 'RSAT-AD-PowerShell' -and (& $get 'Domain').Status -like 'Not ready*' -and (& $get 'Elevated').Status -like 'Warning*' -and (& $get 'Version').Area -eq 'PowerShell'
}

Test-That 'A tool whose module is missing stops before it runs, and the run is recorded as failed' {
    Reset-Fake
    $script:FakeModules.Remove('ActiveDirectory')
    $global:TestToolRan = $false
    function global:Invoke-NmNeedsAd { $global:TestToolRan = $true }
    Register-NmTool -Path 'f.ps1' -Definition @{ Name = 'Needs AD'; Id = 'needs-ad'; Category = 'Directory'; Synopsis = 's'; Version = '1.0'; Kind = 'Report'; Services = @('AD'); Entry = 'Invoke-NmNeedsAd' }
    $null = Invoke-NmTool -Id needs-ad -NoMenu
    (-not $global:TestToolRan) -and (@(Get-NmRunHistory -Last 1)[0].Result -eq 'Failed')
}

Test-That 'Leaving a tool after a run logs Closed; backing out before one logs Cancelled' {
    Reset-Fake
    $global:PromptAnswers = New-Object System.Collections.Generic.Queue[object]
    function global:Read-NmPromptTool { if ($global:PromptAnswers.Count) { $global:PromptAnswers.Dequeue() } else { $null } }
    function global:Invoke-NmPromptTool { param($X) [pscustomobject]@{ X = $X } }
    Register-NmTool -Path 'g.ps1' -Definition @{ Name = 'Prompt Tool'; Id = 'prompt-tool'; Category = 'Directory'; Synopsis = 's'; Version = '1.0'; Kind = 'Report'; Services = @(); Prompt = 'Read-NmPromptTool'; Entry = 'Invoke-NmPromptTool' }
    $null = Invoke-NmTool -Id prompt-tool *>$null
    $cancelled = (Get-Content (Get-NmLogPath))[-1]
    $global:PromptAnswers.Enqueue(@{ X = 1 })
    Answer @('B')
    $null = Invoke-NmTool -Id prompt-tool *>$null
    $closed = (Get-Content (Get-NmLogPath))[-1]
    $cancelled -match 'Cancelled Prompt Tool\.$' -and $closed -match 'Closed Prompt Tool\.$'
}

Test-That 'Change confirmations before any domain is read say (no domain), not ((no domain))' {
    Reset-Fake
    Answer @('y')
    $null = Confirm-NmChange -Action 'Set the time zone' 6>$null
    $line = (Get-Content (Get-NmLogPath))[-1]
    $line -match 'Confirmed: Set the time zone \(no domain\)$'
}

# ---------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------
Test-That 'Show-NmMenu asks again on a wrong key and returns the right one' {
    Answer @('9', '1')
    $pick = Show-NmMenu -Title 'Pick' -Back -Options @([pscustomobject]@{ Key = '1'; Label = 'One' }) 6>$null
    $pick -eq '1' -and $script:TestAnswers.Count -eq 0
}

Test-That 'Main menu: an area with one section opens its tools; Back and Quit leave' {
    Reset-Fake
    $centers = @(Get-NmAdminCenter)
    $kit = [array]::IndexOf(@($centers.Id), 'kit') + 1
    Answer @("$kit", 'B', 'Q')
    Start-NmToolkit *>$null
    $script:TestAnswers.Count -eq 0
}

Test-That 'Main menu: Domain and DC > Status reads the domain' {
    Reset-Fake
    Answer @('D', '1', '', 'B', 'Q')
    Start-NmToolkit *>$null
    (Get-NmSession).Domain -eq 'clientx.local' -and $script:TestAnswers.Count -eq 0
}

Test-That 'Main menu: Domain and DC > another DC moves the session there' {
    Reset-Fake
    Answer @('D', '2', '2', '', 'B', 'Q')
    Start-NmToolkit *>$null
    (Get-NmSession).Server -eq 'DC02.clientx.local'
}

# ---------------------------------------------------------------------------
# Code rules
# ---------------------------------------------------------------------------
Test-That 'Code files are ASCII only' {
    $files = Get-ChildItem -Path (Join-Path $repoRoot 'Nutmeg.AD'), (Join-Path $repoRoot 'Tests'), (Join-Path $repoRoot 'Start-NutmegAD.ps1'), (Join-Path $repoRoot 'Get-NutmegAD.ps1') -Include *.ps1, *.psm1, *.psd1 -Recurse -File
    $bad = @($files | Where-Object { [System.IO.File]::ReadAllBytes($_.FullName) | Where-Object { $_ -gt 127 } | Select-Object -First 1 })
    if ($bad.Count) { throw "non-ASCII in: $($bad.Name -join ', ')" }
    $true
}

Test-That 'No tool or core file calls Read-Host directly' {
    $files = Get-ChildItem -Path (Join-Path $repoRoot 'Nutmeg.AD') -Include *.ps1 -Recurse -File
    $hits = @($files | Select-String -Pattern 'Read-Host' | Where-Object { $_.Path -notlike '*Menu.ps1' })
    if ($hits.Count) { throw "Read-Host in: $(($hits | ForEach-Object { "$(Split-Path -Leaf $_.Path):$($_.LineNumber)" }) -join ', ')" }
    $true
}

# ---------------------------------------------------------------------------
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
& $mod { if ($script:NmSettingsTestFile -and (Test-Path $script:NmSettingsTestFile)) { Remove-Item $script:NmSettingsTestFile -Force } }

Write-Host '=============================================' -ForegroundColor Cyan
if ($script:Failed.Count -eq 0) {
    Write-Host "   All $script:Passed tests passed." -ForegroundColor Green
    Write-Host '=============================================' -ForegroundColor Cyan
    exit 0
}
Write-Host "   $($script:Failed.Count) failed, $script:Passed passed:" -ForegroundColor Red
$script:Failed | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
Write-Host '=============================================' -ForegroundColor Cyan
exit 1
