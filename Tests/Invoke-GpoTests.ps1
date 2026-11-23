<#
.NOTES
    Author:  Cliff Waite
    Date:    11/22/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.1

.SYNOPSIS
    Tests for the baselines, gpo-build and gpo-compare. No domain, no DC and no GroupPolicy module needed.

.DESCRIPTION
    - Checks every baseline file in Nutmeg.AD\Baselines, and that the checks catch bad ones.
    - Fake GroupPolicy cmdlets (New-GPO, Get-GPO, Set-GPRegistryValue, Set-GPPrefRegistryValue)
      write real Registry.pol and Registry.xml files into a temp SYSVOL, and refuse what the real
      ones refuse (a GPO name used twice, an unknown GPO, a key outside HKLM\ and HKCU\).
    - Fake AD holds each GPO's version and extension list (Get-ADObject, Set-ADObject) and one
      domain group for account lookups.
    - Covers the file formats (Registry.pol, GptTmpl.inf, audit.csv, GPT.INI), building each kind,
      the questions, existing GPOs, -WhatIf, cancel, failures, and comparing (matches, different,
      missing, extra, not filled, older baseline, unstamped GPOs).
    - Exits with code 1 if any test fails.

.EXAMPLE
    pwsh -File .\Tests\Invoke-GpoTests.ps1

.VERSIONING
    0.7.1 - Initial tests.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("NmGpoTests_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
$global:FakeSysvol = Join-Path $testRoot 'SYSVOL'

# ---------------------------------------------------------------------------
# Fake GroupPolicy and AD
# ---------------------------------------------------------------------------
$global:FakeGpos = New-Object System.Collections.Generic.List[object]
$global:FakeGpoAd = @{}
$global:GpCalls = New-Object System.Collections.Generic.List[string]
$global:FailRegistryValue = ''

function global:Get-FakeGpoFolder { param([string]$Id) Join-Path $global:FakeSysvol "{$("$Id".Trim('{', '}').ToUpper())}" }
function global:Find-FakeGpo {
    param([string]$Guid)
    $g = @($global:FakeGpos.ToArray() | Where-Object { "$($_.Id)" -eq "$Guid".Trim('{', '}') })[0]
    if (-not $g) { throw "A GPO with ID {$Guid} was not found in the clientx.local domain." }
    $g
}
function global:Add-FakeGpoVersion {
    param($Gpo, [int]$By, [string]$Ext)
    $dn = $Gpo.Path
    $global:FakeGpoAd[$dn].versionNumber += $By
    if ($Ext -and $global:FakeGpoAd[$dn].gPCMachineExtensionNames -notlike "*$Ext*") { $global:FakeGpoAd[$dn].gPCMachineExtensionNames += "[$Ext]" }
    $ini = Join-Path (Get-FakeGpoFolder $Gpo.Id) 'GPT.INI'
    Set-Content -LiteralPath $ini -Value "[General]`r`nVersion=$($global:FakeGpoAd[$dn].versionNumber)`r`n" -NoNewline
}

function global:New-GPO {
    param([string]$Name, [string]$Comment, $Domain, $Server, $ErrorAction)
    $global:GpCalls.Add("New-GPO $Name @$Server")
    if (@($global:FakeGpos.ToArray() | Where-Object { $_.DisplayName -eq $Name }).Count) { throw "The GPO '$Name' already exists in the clientx.local domain." }
    $id = [guid]::NewGuid()
    $g = [pscustomobject]@{ Id = $id; DisplayName = $Name; Description = $Comment; Path = "cn={$("$id".ToUpper())},cn=policies,cn=system,DC=clientx,DC=local" }
    $global:FakeGpos.Add($g)
    $global:FakeGpoAd[$g.Path] = @{ versionNumber = 0; gPCMachineExtensionNames = '' }
    $folder = Get-FakeGpoFolder $id
    New-Item -Path (Join-Path $folder 'Machine'), (Join-Path $folder 'User') -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $folder 'GPT.INI') -Value "[General]`r`nVersion=0`r`n" -NoNewline
    $g
}
function global:Get-GPO {
    param([string]$Name, $Guid, [switch]$All, $Domain, $Server, $ErrorAction)
    if ($All) { return $global:FakeGpos.ToArray() }
    if ($Name) {
        $g = @($global:FakeGpos.ToArray() | Where-Object { $_.DisplayName -eq $Name })[0]
        if (-not $g -and $ErrorAction -ne 'SilentlyContinue') { throw "GPO '$Name' was not found." }
        return $g
    }
    Find-FakeGpo -Guid "$Guid"
}
function global:Set-GPRegistryValue {
    param($Guid, [string]$Key, [string]$ValueName, [string]$Type, $Value, $Domain, $Server, $ErrorAction)
    $global:GpCalls.Add("Set-GPRegistryValue $Key\$ValueName=$Value ($Type) @$Server")
    $g = Find-FakeGpo -Guid "$Guid"
    if ($Key -notmatch '^(HKLM|HKCU)\\') { throw 'The key must start with HKLM\ or HKCU\.' }
    if (@('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord') -notcontains $Type) { throw "Type $Type is not valid." }
    if ($global:FailRegistryValue -and $ValueName -eq $global:FailRegistryValue) { throw 'Access is denied.' }
    $user = $Key -like 'HKCU\*'
    $path = Join-Path (Join-Path (Get-FakeGpoFolder $g.Id) $(if ($user) { 'User' } else { 'Machine' })) 'Registry.pol'
    $m = $global:NmTestModuleG
    $entries = @(& $m { param($p) if (Test-Path $p) { ConvertFrom-NmRegistryPol -Bytes ([IO.File]::ReadAllBytes($p)) } } $path)
    $keyNoHive = $Key.Substring(5)
    $entries = @($entries | Where-Object { -not ($_.Key -eq $keyNoHive -and $_.ValueName -eq $ValueName) })
    $data = if ($Type -eq 'DWord') { [uint32][int64]([int]$Value -band 0xFFFFFFFFL) } else { $Value }
    $entries += [pscustomobject]@{ Key = $keyNoHive; ValueName = $ValueName; Type = $Type; Value = $data }
    $bytes = & $m { param($e) ConvertTo-NmRegistryPol -Entries $e } $entries
    [IO.File]::WriteAllBytes($path, $bytes)
    Add-FakeGpoVersion -Gpo $g -By $(if ($user) { 65536 } else { 1 }) -Ext $(if ($user) { '' } else { '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}' })
}
function global:Set-GPPrefRegistryValue {
    param($Guid, [string]$Context, [string]$Action, [string]$Key, [string]$ValueName, [string]$Type, $Value, $Domain, $Server, $ErrorAction)
    $global:GpCalls.Add("Set-GPPrefRegistryValue $Context $Action $Key\$ValueName=$Value ($Type)")
    $g = Find-FakeGpo -Guid "$Guid"
    if ($Key -notmatch '^(HKLM|HKCU)\\') { throw 'The key must start with HKLM\ or HKCU\.' }
    $folder = Join-Path (Join-Path (Join-Path (Get-FakeGpoFolder $g.Id) $(if ($Context -eq 'User') { 'User' } else { 'Machine' })) 'Preferences') 'Registry'
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    $hive = if ($Key -like 'HKLM\*') { 'HKEY_LOCAL_MACHINE' } else { 'HKEY_CURRENT_USER' }
    $t = @{ String = 'REG_SZ'; DWord = 'REG_DWORD'; ExpandString = 'REG_EXPAND_SZ'; MultiString = 'REG_MULTI_SZ'; QWord = 'REG_QWORD' }[$Type]
    $v = if ($Type -eq 'DWord') { ([uint32][int64]([int]$Value -band 0xFFFFFFFFL)).ToString('X8') } else { "$Value" }
    $act = $Action.Substring(0, 1)
    $xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><RegistrySettings clsid=`"{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}`"><Registry clsid=`"{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}`" name=`"$ValueName`"><Properties action=`"$act`" hive=`"$hive`" key=`"$($Key.Substring(5))`" name=`"$ValueName`" type=`"$t`" value=`"$v`"/></Registry></RegistrySettings>"
    Set-Content -LiteralPath (Join-Path $folder 'Registry.xml') -Value $xml
    Add-FakeGpoVersion -Gpo $g -By 1 -Ext '{B087BE9D-ED37-454F-AF9C-04291E351182}{BEE07A6A-EC9F-4659-B8C9-0B1937907C83}'
}
$global:FakeLinks = @{}         # GPO name -> @(@{ Path; Enabled; Enforced }); none = not linked
$global:FakeComputerOff = @{}   # GPO name -> $true when its computer settings are disabled
$global:Opened = New-Object System.Collections.Generic.List[string]
function global:Get-GPOReport {
    param($Guid, [string]$ReportType, [string]$Path, $Domain, $Server, $ErrorAction)
    $g = Find-FakeGpo -Guid "$Guid"
    if ($ReportType -eq 'Html') { Set-Content -LiteralPath $Path -Value "<html>$($g.DisplayName)</html>"; return }
    $links = foreach ($l in @($global:FakeLinks[$g.DisplayName])) { if ($l) {
        $som = if ($l.Path -eq 'Domain root') { 'clientx.local' } else { "clientx.local/$($l.Path)" }
        "<LinksTo><SOMName>x</SOMName><SOMPath>$som</SOMPath><Enabled>$("$([bool]$l.Enabled)".ToLower())</Enabled><NoOverride>$("$([bool]$l.Enforced)".ToLower())</NoOverride></LinksTo>" } }
    $comp = if ($global:FakeComputerOff[$g.DisplayName]) { 'false' } else { 'true' }
    "<?xml version=`"1.0`" encoding=`"utf-16`"?><GPO xmlns=`"http://www.microsoft.com/GroupPolicy/Settings`"><Name>$($g.DisplayName)</Name><Computer><Enabled>$comp</Enabled></Computer><User><Enabled>true</Enabled></User>$($links -join '')</GPO>"
}
function global:Get-ADObject {
    param($Identity, $Properties, $Server, $ErrorAction)
    if (-not $global:FakeGpoAd.ContainsKey("$Identity")) { throw "Cannot find an object with identity: '$Identity'." }
    [pscustomobject]$global:FakeGpoAd["$Identity"]
}
function global:Set-ADObject {
    param($Identity, [hashtable]$Replace, $Server, $ErrorAction)
    $global:GpCalls.Add("Set-ADObject $Identity @$Server")
    if (-not $global:FakeGpoAd.ContainsKey("$Identity")) { throw "Cannot find an object with identity: '$Identity'." }
    foreach ($k in $Replace.Keys) { $global:FakeGpoAd["$Identity"][$k] = $Replace[$k] }
}
function global:Get-ADGroup {
    param($Filter, $Server, $ErrorAction)
    if ("$Filter" -match "'RDP Admins'") { return [pscustomobject]@{ Name = 'RDP Admins'; SID = 'S-1-5-21-1000-2000-3000-1105' } }
}
function global:Get-ADUser { param($Filter, $Server, $ErrorAction) }

# ---------------------------------------------------------------------------
Import-Module (Join-Path (Join-Path $repoRoot 'Nutmeg.AD') 'Nutmeg.AD.psd1') -Force
$mod = Get-Module Nutmeg.AD
$global:NmTestModuleG = $mod
& $mod { $script:NmSettingsTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ("NmGpoSettings_" + [guid]::NewGuid().ToString('N') + '.json'); $script:NmSettingsData = $null; Update-NmConfigFromSetting }
& $mod {
    param($root)
    $script:NmConfig.ExportRoot = Join-Path $root 'Exports'
    $script:NmConfig.DataRoot   = Join-Path $root 'Data'
    $script:NmLogPath = $null
    $script:TestAnswers = New-Object System.Collections.Generic.Queue[string]
    function script:Read-NmHost { param([string]$Prompt) if ($script:TestAnswers.Count -gt 0) { $script:TestAnswers.Dequeue() } else { throw 'Test ran out of scripted answers.' } }
    function script:Get-NmGpoFolder { param([string]$Id) Get-FakeGpoFolder $Id }
    function script:Assert-NmConnection { param($Services) $true }
    function script:Clear-NmScreen { }
    function script:Start-NmGpoEditor { param([string]$Path) $global:Opened.Add("edit $Path"); "LDAP://DC01.clientx.local/$Path" }
    function script:Open-NmReport { param($Path) $global:Opened.Add("open $(Split-Path -Leaf $Path)") }
    function script:Show-NmGpoViewer { param($Model) $global:Opened.Add("view $($Model.Heading)"); $global:LastView = $Model }
} $testRoot

function global:Reset-Gpo {
    & $global:NmTestModuleG {
        $script:TestAnswers.Clear()
        $script:NmBaselineTestFolder = $null
        $script:NmBaselineCache = $null
        $script:NmPlanApproved = $null
        Reset-NmSession
        $script:NmSession.Domain = 'clientx.local'; $script:NmSession.NetBIOS = 'CLIENTX'; $script:NmSession.DomainSid = 'S-1-5-21-1000-2000-3000'
        $script:NmSession.DomainDN = 'DC=clientx,DC=local'; $script:NmSession.PdcEmulator = 'DC01.clientx.local'; $script:NmSession.Server = 'DC01.clientx.local'
        $script:NmSession.Services = @{ AD = $true; GPO = $true }
    }
    $global:FakeGpos.Clear(); $global:FakeGpoAd.Clear(); $global:GpCalls.Clear(); $global:FailRegistryValue = ''
    $global:FakeLinks = @{}; $global:FakeComputerOff = @{}; $global:Opened.Clear()
    if (Test-Path $global:FakeSysvol) { Remove-Item $global:FakeSysvol -Recurse -Force }
    New-Item -Path $global:FakeSysvol -ItemType Directory -Force | Out-Null
}
function global:Answer { param([string[]]$Values) & $global:NmTestModuleG { param($v) foreach ($x in $v) { $script:TestAnswers.Enqueue($x) } } $Values }
function global:Write-TestBaseline {
    # A baseline file of the test's own in a temp folder (the shipped ones are left alone).
    param([string]$Text, [string]$File = 'Test.psd1')
    $dir = Join-Path $global:FakeSysvol '..\TestBaselines'
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir $File) -Value $Text
    & $global:NmTestModuleG { param($d) $script:NmBaselineTestFolder = $d; $script:NmBaselineCache = $null } (Resolve-Path $dir).Path
}

$script:Passed = 0
$script:Failed = New-Object System.Collections.Generic.List[string]
function Test-That {
    param([string]$Name, [scriptblock]$Body)
    try {
        Reset-Gpo
        $result = & $mod $Body
        if ($result -eq $false) { throw 'returned false' }
        $script:Passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } catch {
        $script:Failed.Add("$Name : $($_.Exception.Message)")
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         - $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))" -ForegroundColor Red
    }
}
function global:Assert-Equal { param($Expected, $Actual, [string]$What = 'value') if ("$Expected" -ne "$Actual") { throw "$What`: expected '$Expected', got '$Actual'" } }

# A minimal valid baseline, changed by each check test.
$global:GoodBaseline = @{
    Id = 'test-baseline'; Name = 'Test Baseline'; Version = '0.7.1'; Description = 'For tests.'
    Parameters = @( @{ Name = 'Seconds'; Prompt = 'Seconds'; Type = 'Int'; Default = 900; Min = 60; Max = 7200 } )
    Settings = @( @{ Id = 'one'; Kind = 'Policy'; Side = 'User'; Title = 'One'; Tags = @()
        Values = @( @{ Key = 'HKCU\Software\Policies\Test'; ValueName = 'V'; Type = 'String'; Value = '{Seconds}' } ) } )
}
function global:Copy-Good { $c = @{}; foreach ($k in $global:GoodBaseline.Keys) { $c[$k] = $global:GoodBaseline[$k] }; $c }

Write-Host 'Baseline files' -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Test-That 'Every shipped baseline loads and passes the checks; Ids unique; names in GpoDefaultLinks.csv; sources exist' {
    $all = @(Get-NmBaseline -IncludeInvalid)
    if ($all.Count -lt 9) { throw "only $($all.Count) baselines" }
    $bad = @($all | Where-Object { -not $_.Valid })
    if ($bad.Count) { throw "invalid: $(($bad | ForEach-Object { "$($_.Id): $($_.Problems -join '; ')" }) -join ' / ')" }
    $links = @(Import-Csv (Join-Path $script:NmModuleRoot 'Data\GpoDefaultLinks.csv') | ForEach-Object Baseline)
    foreach ($b in $all) {
        if ($links -notcontains $b.Name) { throw "$($b.Name) is not in GpoDefaultLinks.csv" }
        if ($b.Source -and -not (Test-Path (Join-Path (Split-Path $script:NmModuleRoot) $b.Source))) { throw "$($b.Id): source $($b.Source) not found" }
        if ($b.Version -ne '0.7.1') { throw "$($b.Id) version $($b.Version)" }
    }
    $true
}

Test-That 'The checks catch: unknown field and kind, wrong side, bad tag, undeclared and unused parameters, placeholder in a key, duplicate Id, bad audit name, wrong hive' {
    Assert-Equal 0 @(Test-NmBaseline -Data (Copy-Good)).Count 'problems in the good one'
    $cases = @(
        @{ Why = 'unknown field';      Change = { param($b) $b.Colour = 'red' };                                                       Expect = "unknown field 'Colour'" }
        @{ Why = 'unknown kind';       Change = { param($b) $b.Settings = @(@{ Id = 'x'; Kind = 'Wireless'; Side = 'Computer'; Title = 'x'; Tags = @() }); $b.Parameters = @() }; Expect = "Kind 'Wireless'" }
        @{ Why = 'side';               Change = { param($b) $b.Settings = @(@{ Id = 'x'; Kind = 'Service'; Side = 'User'; Title = 'x'; Tags = @(); Service = 'Spooler'; StartMode = 'Disabled' }); $b.Parameters = @() }; Expect = 'must be Computer' }
        @{ Why = 'tag';                Change = { param($b) $b.Settings[0].Tags = @('PCI:1.2') };                                       Expect = "tag 'PCI:1.2'" }
        @{ Why = 'undeclared';         Change = { param($b) $b.Parameters = @() };                                                      Expect = '{Seconds} is used but not declared' }
        @{ Why = 'unused';             Change = { param($b) $b.Parameters = @($b.Parameters) + @{ Name = 'Spare'; Prompt = 'x'; Type = 'String'; Default = '' } }; Expect = 'Spare is declared but not used' }
        @{ Why = 'placeholder in key'; Change = { param($b) $b.Settings = @(@{ Id = 'x'; Kind = 'SecurityOption'; Side = 'Computer'; Title = 'x'; Tags = @(); Key = 'MACHINE\Software\{Seconds}\V'; Type = 'DWord'; Value = 1 }) }; Expect = 'can only be used in a value' }
        @{ Why = 'duplicate id';       Change = { param($b) $b.Settings = @($b.Settings[0], $b.Settings[0]) };                          Expect = 'Id is used twice' }
        @{ Why = 'audit name';         Change = { param($b) $b.Settings = @(@{ Id = 'x'; Kind = 'Audit'; Side = 'Computer'; Title = 'x'; Tags = @(); Subcategory = 'Logins'; Setting = 'Success' }); $b.Parameters = @() }; Expect = "'Logins' is not an audit subcategory" }
        @{ Why = 'hive';               Change = { param($b) $b.Settings = @(@{ Id = 'x'; Kind = 'Policy'; Side = 'Computer'; Title = 'x'; Tags = @(); Values = @(@{ Key = 'HKCU\Software\X'; ValueName = 'V'; Type = 'DWord'; Value = 1 }) }); $b.Parameters = @() }; Expect = 'must start with HKLM\' }
        @{ Why = 'missing tags';       Change = { param($b) $b.Settings = @(@{ Id = 'x'; Kind = 'Service'; Side = 'Computer'; Title = 'x'; Service = 'Spooler'; StartMode = 'Disabled' }); $b.Parameters = @() }; Expect = 'Tags is missing' }
    )
    foreach ($c in $cases) {
        $b = Copy-Good
        $b.Settings = @(foreach ($s in $global:GoodBaseline.Settings) { $h = @{}; foreach ($k in $s.Keys) { $h[$k] = $s[$k] }; $h })
        & $c.Change $b
        $p = @(Test-NmBaseline -Data $b)
        if (-not @($p | Where-Object { $_ -like "*$($c.Expect)*" }).Count) { throw "$($c.Why): expected '$($c.Expect)', got: $($p -join ' | ')" }
    }
    $true
}

Test-That 'Control tags: Framework:Control with a known framework' {
    foreach ($ok in 'HIPAA:164.312(a)(2)(iii)', 'NIST800-53:AC-11', 'NIST800-171:3.1.10', 'CIS:2.3.17.1', 'STIG:V-254253') { if (-not (Test-NmBaselineTag -Tag $ok)) { throw "$ok refused" } }
    foreach ($no in 'AC-11', 'hipaa:1', 'NIST800-53:', 'Made:Up') { if (Test-NmBaselineTag -Tag $no) { throw "$no accepted" } }
    $true
}

Test-That 'A file that will not read, and two files with one Id, are reported and not offered' {
    Write-TestBaseline -File 'Broken.psd1' -Text "@{ Id = 'x'"
    Write-TestBaseline -File 'A.psd1' -Text "@{ Id = 'same'; Name = 'A'; Version = '0.7.1'; Description = 'a'; Settings = @( @{ Id = 's'; Kind = 'Service'; Side = 'Computer'; Title = 't'; Tags = @(); Service = 'Spooler'; StartMode = 'Disabled' } ) }"
    Write-TestBaseline -File 'B.psd1' -Text "@{ Id = 'same'; Name = 'B'; Version = '0.7.1'; Description = 'b'; Settings = @( @{ Id = 's'; Kind = 'Service'; Side = 'Computer'; Title = 't'; Tags = @(); Service = 'Spooler'; StartMode = 'Disabled' } ) }"
    $all = @(Get-NmBaseline -IncludeInvalid)
    Assert-Equal 3 $all.Count 'files'
    if (@(Get-NmBaseline).Count) { throw 'an invalid baseline was offered' }
    if (-not @($all | Where-Object { "$($_.Problems)" -like '*could not be read*' }).Count) { throw 'broken file not reported' }
    if (@($all | Where-Object { "$($_.Problems)" -like '*also used by another file*' }).Count -ne 2) { throw 'duplicate Id not reported' }
    $true
}

Write-Host 'Parameters and placeholders' -ForegroundColor Cyan
Test-That 'Placeholders: found, filled in, {{ }} kept as braces, unknown names left alone' {
    Assert-Equal 'A,B' ((Get-NmBaselinePlaceholder -Value @{ x = '{A} and {B}'; y = @('{A}', '{{Not}}') }) -join ',') 'found'
    Assert-Equal '900 {Other} {literal}' (Expand-NmBaselineText -Text '{Seconds} {Other} {{literal}}' -Values @{ Seconds = 900 }) 'expanded'
    $e = Expand-NmBaselineValue -Value @{ Members = @('{G}', 'Administrators'); N = 5 } -Values @{ G = 'RDP Admins' }
    Assert-Equal 'RDP Admins,Administrators' ($e.Members -join ',') 'array'
    Assert-Equal 5 $e.N 'number kept'
    $true
}

Test-That 'Defaults from the session and settings; values checked (range, choice, FQDN, IP range)' {
    Assert-Equal 'DC01.clientx.local,0x1' (Get-NmBaselineDefault -Parameter @{ Default = '{Session:Pdc},0x1' }) 'session'
    Assert-Equal 'Eastern Standard Time' (Get-NmBaselineDefault -Parameter @{ Default = '{Setting:BuildTimeZone}' }) 'setting'
    $int = @{ Name = 'S'; Type = 'Int'; Min = 60; Max = 7200 }
    if (Test-NmBaselineParamValue -Parameter $int -Value 900) { throw '900 refused' }
    if (-not (Test-NmBaselineParamValue -Parameter $int -Value 30)) { throw '30 accepted' }
    if (-not (Test-NmBaselineParamValue -Parameter $int -Value 'ten')) { throw 'text accepted' }
    if (-not (Test-NmBaselineParamValue -Parameter @{ Type = 'Choice'; Choices = @('Compatible', 'Modern') } -Value 'Legacy')) { throw 'bad choice accepted' }
    if (Test-NmBaselineParamValue -Parameter @{ Type = 'Fqdn' } -Value 'print01.clientx.local') { throw 'FQDN refused' }
    if (-not (Test-NmBaselineParamValue -Parameter @{ Type = 'Fqdn' } -Value 'print01')) { throw 'short name accepted as FQDN' }
    if (Test-NmBaselineParamValue -Parameter @{ Type = 'IpRange' } -Value '192.0.2.0/24') { throw 'range refused' }
    if (-not (Test-NmBaselineParamValue -Parameter @{ Type = 'String' } -Value '')) { throw 'empty accepted' }
    if (Test-NmBaselineParamValue -Parameter @{ Type = 'String'; Optional = $true } -Value '') { throw 'optional empty refused' }
    $r = Resolve-NmBaselineValues -Baseline ([pscustomobject]@{ Parameters = @(@{ Name = 'Seconds'; Type = 'Int'; Default = 900; Min = 60; Max = 7200 }) }) -Given @{ Seconds = 5 }
    if (-not "$($r.Problems)".Contains('Seconds: at least 60')) { throw "problems: $($r.Problems)" }
    $true
}

Test-That 'Audit subcategories: by name, with "Audit " in front, and "Audit Policy Change" (a name that starts with Audit)' {
    Assert-Equal '{0cce923f-69ae-11d9-bed3-505054503030}' (Get-NmAuditSubcategoryGuid -Name 'Credential Validation') 'name'
    Assert-Equal '{0cce9215-69ae-11d9-bed3-505054503030}' (Get-NmAuditSubcategoryGuid -Name 'Audit Logon') 'prefixed'
    Assert-Equal '{0cce922f-69ae-11d9-bed3-505054503030}' (Get-NmAuditSubcategoryGuid -Name 'Audit Policy Change') 'Audit Policy Change'
    Assert-Equal 'Audit Policy Change' (Get-NmAuditSubcategoryName -Guid '{0CCE922F-69AE-11D9-BED3-505054503030}') 'back to a name'
    Assert-Equal 59 $script:NmAuditSubcategories.Count 'subcategories'
    $true
}

Write-Host 'File formats' -ForegroundColor Cyan
Test-That 'Registry.pol: reads bytes built by hand (PReg header, a DWord and a string), and round-trips' {
    $u = [Text.Encoding]::Unicode
    $b = New-Object System.Collections.Generic.List[byte]
    $b.AddRange([byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0))
    $b.AddRange($u.GetBytes("[Software\Policies\T`0;Dw`0;")); $b.AddRange([BitConverter]::GetBytes(4)); $b.AddRange($u.GetBytes(';'))
    $b.AddRange([BitConverter]::GetBytes(4)); $b.AddRange($u.GetBytes(';')); $b.AddRange([BitConverter]::GetBytes([uint32]2147483632)); $b.AddRange($u.GetBytes(']'))
    $b.AddRange($u.GetBytes("[Software\Policies\T`0;Sz`0;")); $b.AddRange([BitConverter]::GetBytes(1)); $b.AddRange($u.GetBytes(';'))
    $b.AddRange([BitConverter]::GetBytes(8)); $b.AddRange($u.GetBytes(';')); $b.AddRange($u.GetBytes("900`0")); $b.AddRange($u.GetBytes(']'))
    $e = @(ConvertFrom-NmRegistryPol -Bytes $b.ToArray())
    Assert-Equal 2 $e.Count 'entries'
    Assert-Equal 'Software\Policies\T|Dw|DWord|2147483632' "$($e[0].Key)|$($e[0].ValueName)|$($e[0].Type)|$($e[0].Value)" 'dword'
    Assert-Equal 'Sz|String|900' "$($e[1].ValueName)|$($e[1].Type)|$($e[1].Value)" 'string'
    $again = @(ConvertFrom-NmRegistryPol -Bytes (ConvertTo-NmRegistryPol -Entries $e))
    Assert-Equal ($e | ConvertTo-Json -Compress) ($again | ConvertTo-Json -Compress) 'round trip'
    try { ConvertFrom-NmRegistryPol -Bytes ([byte[]](1, 2, 3, 4, 5, 6, 7, 8)); throw 'no error' } catch { if ("$_" -notlike '*PReg*') { throw } }
    $true
}

Test-That 'GptTmpl.inf lines for each kind, as GPMC writes them' {
    $l = { param($s) @(ConvertTo-NmGptTmplLine -Setting $s) }
    Assert-Equal 'Registry Values|MACHINE\System\CurrentControlSet\Control\Lsa\LmCompatibilityLevel=4,5' "$((& $l @{ Kind = 'SecurityOption'; Key = 'MACHINE\System\CurrentControlSet\Control\Lsa\LmCompatibilityLevel'; Type = 'DWord'; Value = 5 }) | ForEach-Object { "$($_.Section)|$($_.Line)" })" 'dword'
    Assert-Equal 'MACHINE\Software\X\Caption=1,"Say ""hi"""' (& $l @{ Kind = 'SecurityOption'; Key = 'MACHINE\Software\X\Caption'; Type = 'String'; Value = 'Say "hi"' })[0].Line 'string'
    Assert-Equal 'NewAdministratorName = "LocalBoss"' (& $l @{ Kind = 'SystemAccess'; Name = 'NewAdministratorName'; Value = 'LocalBoss' })[0].Line 'system access text'
    Assert-Equal 'EnableGuestAccount = 0' (& $l @{ Kind = 'SystemAccess'; Name = 'EnableGuestAccount'; Value = 0 })[0].Line 'system access number'
    Assert-Equal 'SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-555' (& $l @{ Kind = 'UserRight'; Right = 'SeRemoteInteractiveLogonRight'; Members = @('S-1-5-32-544', '*S-1-5-32-555') })[0].Line 'user right'
    $g = & $l @{ Kind = 'RestrictedGroup'; Group = 'S-1-5-32-555'; Members = @('S-1-5-21-1-1105'); MemberOf = @() }
    Assert-Equal '*S-1-5-32-555__Memberof = |*S-1-5-32-555__Members = *S-1-5-21-1-1105' (($g | ForEach-Object Line) -join '|') 'restricted group'
    $svc = (& $l @{ Kind = 'Service'; Service = 'Spooler'; StartMode = 'Disabled' })[0]
    if ($svc.Line -notlike '"Spooler",4,"D:AR(*;;;BA)*') { throw "service: $($svc.Line)" }
    $true
}

Test-That 'GptTmpl.inf: merged into an existing file, written as UTF-16 with a BOM, sections in order, read back' {
    $id = [guid]::NewGuid().ToString()
    $path = Get-NmGpoFilePath -Id $id -File GptTmpl
    Write-NmGpoText -Path $path -Text "[Unicode]`r`nUnicode=yes`r`n[Registry Values]`r`nMACHINE\Software\Old=4,1`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n" -Encoding Unicode
    Write-NmGptTmpl -Id $id -Lines @([pscustomobject]@{ Section = 'Registry Values'; Line = 'MACHINE\Software\New=4,0' }, [pscustomobject]@{ Section = 'System Access'; Line = 'EnableGuestAccount = 0' }, [pscustomobject]@{ Section = 'Registry Values'; Line = 'MACHINE\Software\Old=4,2' })
    $bytes = [IO.File]::ReadAllBytes($path)
    if (-not ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)) { throw 'no UTF-16 BOM' }
    $text = [IO.File]::ReadAllText($path)
    $order = @('[Unicode]', '[System Access]', '[Registry Values]', '[Version]' | ForEach-Object { $text.IndexOf($_) })
    if (($order | Sort-Object) -join ',' -ne ($order -join ',') -or $order -contains -1) { throw "sections out of order: $text" }
    $doc = Read-NmGpoGptTmpl -Id $id
    Assert-Equal 'MACHINE\Software\Old=4,2' $doc['Registry Values']['machine\software\old'] 'replaced, not duplicated'
    Assert-Equal 2 $doc['Registry Values'].Count 'registry values'
    $true
}

Test-That 'audit.csv: header, one row per subcategory with GUID and value, merged by GUID' {
    $id = [guid]::NewGuid().ToString()
    Write-NmGpoAudit -Id $id -Settings @(@{ Subcategory = 'Logon'; Setting = 'Success' }, @{ Subcategory = 'Audit Policy Change'; Setting = 'SuccessAndFailure' })
    Write-NmGpoAudit -Id $id -Settings @(@{ Subcategory = 'Logon'; Setting = 'SuccessAndFailure' })
    $lines = @((Read-NmGpoText -Path (Get-NmGpoFilePath -Id $id -File Audit)) -split "`r`n" | Where-Object { $_ })
    Assert-Equal 3 $lines.Count 'lines'
    Assert-Equal $script:NmAuditCsvHeader $lines[0] 'header'
    Assert-Equal ',System,Audit Logon,{0cce9215-69ae-11d9-bed3-505054503030},Success and Failure,,3' $lines[1] 'logon, merged'
    Assert-Equal ',System,Audit Audit Policy Change,{0cce922f-69ae-11d9-bed3-505054503030},Success and Failure,,3' $lines[2] 'audit policy change'
    $true
}

Test-That 'Extension names: merged, sorted by GUID, nothing twice; the version goes up by one in AD and GPT.INI' {
    $m = Merge-NmGpoExtensionName -Current '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]' -Add @($script:NmCseSecurity, $script:NmCseAudit, $script:NmCseSecurity)
    Assert-Equal '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}][{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}][{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}]' $m 'merged'
    $g = New-GPO -Name 'Version test'
    $global:FakeGpoAd[$g.Path].versionNumber = 65538
    $v = Update-NmGpoVersion -Id "$($g.Id)" -Path $g.Path -Extensions @(, $script:NmCseSecurity)
    Assert-Equal 65539 $v 'new version'
    Assert-Equal 65539 $global:FakeGpoAd[$g.Path].versionNumber 'AD'
    if ((Get-Content (Join-Path (Get-FakeGpoFolder $g.Id) 'GPT.INI') -Raw) -notmatch 'Version=65539') { throw 'GPT.INI not updated' }
    if ($global:FakeGpoAd[$g.Path].gPCMachineExtensionNames -notlike '*{827D319E-6EAC-11D2-A4EA-00C04F79F83A}*') { throw 'security CSE not added' }
    if (-not @($global:GpCalls | Where-Object { $_ -like 'Set-ADObject*@DC01.clientx.local' }).Count) { throw 'AD write did not go to the session DC' }
    $true
}

Test-That 'Accounts as SIDs: SIDs, well-known names, domain groups by RID, AD lookups; an unknown name fails' {
    Assert-Equal 'S-1-5-32-544' (Resolve-NmAccountSid -Name 'Administrators') 'builtin'
    Assert-Equal 'S-1-5-32-555' (Resolve-NmAccountSid -Name 'BUILTIN\Remote Desktop Users') 'with prefix'
    Assert-Equal 'S-1-5-21-1000-2000-3000-512' (Resolve-NmAccountSid -Name 'CLIENTX\Domain Admins') 'domain admins'
    Assert-Equal 'S-1-5-21-1000-2000-3000-1105' (Resolve-NmAccountSid -Name 'RDP Admins') 'AD lookup'
    Assert-Equal 'S-1-5-11' (Resolve-NmAccountSid -Name '*S-1-5-11') 'sid'
    try { Resolve-NmAccountSid -Name 'Nobody Here'; throw 'no error' } catch { if ("$_" -notlike '*No account named*') { throw } }
    $true
}

Write-Host 'gpo-build' -ForegroundColor Cyan
Test-That 'Build: -WhatIf creates nothing; the plan lists the settings' {
    $r = @(New-NmGpoFromBaseline -Baseline security-enforce-uac -WhatIf)
    Assert-Equal 'WhatIf: not changed' $r[0].Result 'result'
    Assert-Equal 0 $global:FakeGpos.Count 'GPOs'
    $true
}

Test-That 'Build: UAC (security options) - stamped, GptTmpl.inf written, security extension and version raised, on the session DC' {
    Answer 'y'
    $r = @(New-NmGpoFromBaseline -Baseline security-enforce-uac)
    Assert-Equal 'Created' $r[0].Result 'result'
    Assert-Equal '7 of 7' $r[0].Settings 'settings'
    Assert-Equal 'Domain root' $r[0].SuggestedLinks 'suggested links'
    $g = $global:FakeGpos[0]
    Assert-Equal 'Security - Enforce UAC' $g.DisplayName 'name'
    Assert-Equal 'Nutmeg baseline: security-enforce-uac 0.7.1' $g.Description 'stamp'
    if ($global:GpCalls[0] -ne 'New-GPO Security - Enforce UAC @DC01.clientx.local') { throw "New-GPO: $($global:GpCalls[0])" }
    $doc = Read-NmGpoGptTmpl -Id "$($g.Id)"
    Assert-Equal 7 $doc['Registry Values'].Count 'registry values'
    Assert-Equal 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA=4,1' $doc['Registry Values']['machine\software\microsoft\windows\currentversion\policies\system\enablelua'] 'EnableLUA'
    Assert-Equal 1 $global:FakeGpoAd[$g.Path].versionNumber 'version'
    if ($global:FakeGpoAd[$g.Path].gPCMachineExtensionNames -notlike '*{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}*') { throw 'security CSE missing' }
    if (-not @(Get-NmRunHistory | Where-Object { $_.ToolId -eq 'gpo-build' -and $_.Notes -like 'Security - Enforce UAC*' }).Count) { throw 'no run history' }
    $true
}

Test-That 'Build: Screen Timeout (user policy) with a value given; Registry.pol on the user side holds it' {
    Answer 'y'
    $r = @(New-NmGpoFromBaseline -Baseline security-screen-timeout -Values @{ 'security-screen-timeout' = @{ TimeoutSeconds = 600 } } -GpoName @{ 'security-screen-timeout' = 'Screen Lock 10 min' })
    Assert-Equal 'Created' $r[0].Result 'result'
    $g = $global:FakeGpos[0]
    Assert-Equal 'Screen Lock 10 min' $g.DisplayName 'name'
    $pol = @(Read-NmGpoRegistryPol -Id "$($g.Id)" -Side User)
    Assert-Equal 4 $pol.Count 'values'
    Assert-Equal '600' (@($pol | Where-Object ValueName -eq 'ScreenSaveTimeOut')[0].Value) 'timeout'
    if (@(Read-NmGpoRegistryPol -Id "$($g.Id)" -Side Computer).Count) { throw 'computer side written' }
    $true
}

Test-That 'Build: Time Synchronization (policy + preference) - NTP server defaults to the PDC; DWord preference written' {
    Answer 'y'
    $r = @(New-NmGpoFromBaseline -Baseline network-time-synchronization)
    Assert-Equal 'Created' $r[0].Result 'result'
    Assert-Equal 'Devices' $r[0].SuggestedLinks 'links'
    $g = $global:FakeGpos[0]
    $pol = @(Read-NmGpoRegistryPol -Id "$($g.Id)" -Side Computer)
    Assert-Equal 'DC01.clientx.local,0x1' (@($pol | Where-Object ValueName -eq 'NtpServer')[0].Value) 'ntp server'
    Assert-Equal 'DWord' (@($pol | Where-Object ValueName -eq 'SpecialPollInterval')[0].Type) 'poll type'
    $pref = @(Read-NmGpoPrefRegistry -Id "$($g.Id)" -Side Computer)
    Assert-Equal 'HKLM|SYSTEM\CurrentControlSet\Services\tzautoupdate|Start|DWord|3|Update' "$($pref[0].Hive)|$($pref[0].Key)|$($pref[0].ValueName)|$($pref[0].Type)|$($pref[0].Value)|$($pref[0].Action)" 'preference'
    $true
}

Test-That 'Build: Domain Auditing (audit) and Print Spooler (service) - audit.csv and the audit extension; service line' {
    Answer 'y', 'y'
    $r = @(New-NmGpoFromBaseline -Baseline security-domain-auditing-dcs, security-disable-print-spooler)
    Assert-Equal 'Created|Created' (($r | ForEach-Object Result) -join '|') 'results'
    $audit = $global:FakeGpos[0]
    Assert-Equal 23 @(Read-NmGpoAudit -Id "$($audit.Id)").Count 'audit rows'
    if ($global:FakeGpoAd[$audit.Path].gPCMachineExtensionNames -notlike '*{F3CCC681-B74C-4060-9F26-CD84525DCA2A}{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}*') { throw 'audit CSE missing' }
    if ($global:FakeGpoAd[$audit.Path].gPCMachineExtensionNames -like '*827D319E*') { throw 'security CSE added with no security template' }
    $svc = Read-NmGpoGptTmpl -Id "$($global:FakeGpos[1].Id)"
    if ($svc['Service General Setting']['spooler'] -notlike '"Spooler",4,*') { throw 'service line' }
    $true
}

Test-That 'Build: an existing GPO is never changed; a bad value, a missing baseline and Cancel each stop before anything is created' {
    New-GPO -Name 'Security - NTLM Hardening' | Out-Null
    $global:GpCalls.Clear()
    $r = @(New-NmGpoFromBaseline -Baseline security-ntlm-hardening)
    if ($r[0].Result -notlike 'Already there*') { throw "existing: $($r[0].Result)" }
    if ($global:GpCalls.Count) { throw "calls made: $($global:GpCalls -join '; ')" }
    $r = @(New-NmGpoFromBaseline -Baseline security-screen-timeout -Values @{ TimeoutSeconds = 5 })
    if ($r[0].Result -notlike 'Failed: TimeoutSeconds: at least 60*') { throw "bad value: $($r[0].Result)" }
    $r = @(New-NmGpoFromBaseline -Baseline no-such-baseline)
    if ($r[0].Result -notlike "Failed: no valid baseline*") { throw "missing: $($r[0].Result)" }
    Answer 'n'
    $r = @(New-NmGpoFromBaseline -Baseline security-enforce-uac)
    Assert-Equal 'Cancelled' $r[0].Result 'cancel'
    Assert-Equal 1 $global:FakeGpos.Count 'GPOs'
    $true
}

Test-That 'Build: a setting that fails is reported; the rest are still written' {
    $global:FailRegistryValue = 'SpecialPollInterval'
    Answer 'y'
    $r = @(New-NmGpoFromBaseline -Baseline network-time-synchronization)
    if ($r[0].Result -notlike 'Failed: 1 of 3 settings not written*Access is denied*') { throw "result: $($r[0].Result)" }
    Assert-Equal '2 of 3' $r[0].Settings 'settings'
    if (@(Read-NmGpoPrefRegistry -Id "$($global:FakeGpos[0].Id)").Count -ne 1) { throw 'the preference after it was not written' }
    $true
}

Test-That 'Build: user rights and restricted groups resolve accounts to SIDs; an unknown account fails only its setting' {
    Write-TestBaseline -Text @'
@{
    Id = 'test-rights'; Name = 'Test Rights'; Version = '0.7.1'; Description = 'Rights.'
    Parameters = @( @{ Name = 'RdpGroup'; Prompt = 'Group allowed to RDP'; Type = 'Group'; Default = 'RDP Admins' } )
    Settings = @(
        @{ Id = 'rdp-right'; Kind = 'UserRight'; Side = 'Computer'; Title = 'Allow log on through Remote Desktop Services'; Tags = @(); Right = 'SeRemoteInteractiveLogonRight'; Members = @('Administrators', '{RdpGroup}') }
        @{ Id = 'rdp-group'; Kind = 'RestrictedGroup'; Side = 'Computer'; Title = 'Remote Desktop Users'; Tags = @(); Group = 'Remote Desktop Users'; Members = @('{RdpGroup}') }
        @{ Id = 'guest'; Kind = 'SystemAccess'; Side = 'Computer'; Title = 'Guest account disabled'; Tags = @(); Name = 'EnableGuestAccount'; Value = 0 }
        @{ Id = 'bad'; Kind = 'UserRight'; Side = 'Computer'; Title = 'Nobody'; Tags = @(); Right = 'SeBatchLogonRight'; Members = @('Nobody Here') }
    )
}
'@
    Answer 'y'
    $r = @(New-NmGpoFromBaseline -Baseline test-rights)
    if ($r[0].Result -notlike "Failed: 1 of 4 settings not written (Nobody: No account named 'Nobody Here'*") { throw "result: $($r[0].Result)" }
    $doc = Read-NmGpoGptTmpl -Id "$($global:FakeGpos[0].Id)"
    Assert-Equal 'SeRemoteInteractiveLogonRight = *S-1-5-32-544,*S-1-5-21-1000-2000-3000-1105' $doc['Privilege Rights']['seremoteinteractivelogonright'] 'right'
    Assert-Equal '*S-1-5-32-555__Members = *S-1-5-21-1000-2000-3000-1105' $doc['Group Membership']['*s-1-5-32-555__members'] 'restricted group'
    Assert-Equal 'EnableGuestAccount = 0' $doc['System Access']['enableguestaccount'] 'system access'
    if ($doc['Privilege Rights'].Contains('sebatchlogonright')) { throw 'the failed right was written' }
    $true
}

Test-That 'Build questions: pick a baseline, keep the name, answer its parameter (a bad answer is asked again)' {
    $all = @(Get-NmBaseline)
    $ix = [array]::IndexOf(@($all | ForEach-Object Id), 'security-screen-timeout') + 1
    Answer "$ix", '', '30', '600'
    $a = Read-NmGpoBuildOption
    Assert-Equal 'security-screen-timeout' ($a.Baseline -join ',') 'baseline'
    Assert-Equal '600' $a.Values['security-screen-timeout'].TimeoutSeconds 'value'
    Assert-Equal 'Security - Screen Timeout' $a.GpoName['security-screen-timeout'] 'name'
    if ($script:TestAnswers.Count) { throw "answers left over: $($script:TestAnswers.Count)" }
    $true
}

Test-That 'Build questions: a GPO that exists is not built; Compare is offered and shown' {
    Answer 'y'
    New-NmGpoFromBaseline -Baseline security-enforce-uac | Out-Null
    $all = @(Get-NmBaseline)
    $ix = [array]::IndexOf(@($all | ForEach-Object Id), 'security-enforce-uac') + 1
    Answer "$ix", '', 'y', ''
    $a = Read-NmGpoBuildOption
    if ($null -ne $a) { throw 'something would be built' }
    $true
}

Test-That 'Build through Invoke-NmTool with parameters (unattended, as the New Forest Build will call it)' {
    $r = @(Invoke-NmTool -Id gpo-build -Parameters @{ Baseline = @('security-ldaps-hardening-dcs'); WhatIf = $true } -NoMenu)
    Assert-Equal 'WhatIf: not changed' $r[0].Result 'result'
    Assert-Equal 'Domain Controllers' $r[0].SuggestedLinks 'links'
    $true
}

Write-Host 'gpo-compare' -ForegroundColor Cyan
Test-That 'Compare: a GPO just built matches its baseline everywhere; the parameter value is shown' {
    Answer 'y', 'y', 'y', 'y'
    New-NmGpoFromBaseline -Baseline security-enforce-uac, security-screen-timeout, network-time-synchronization, security-domain-auditing-dcs -Values @{ TimeoutSeconds = 600 } | Out-Null
    $rows = @(Compare-NmGpoBaseline -All | Where-Object Kind -ne 'Links')
    $notOk = @($rows | Where-Object { $_.Result -ne 'Matches' })
    if ($notOk.Count) { throw "not matching: $(($notOk | ForEach-Object { "$($_.Gpo): $($_.Setting) [$($_.Result)] exp '$($_.Expected)' got '$($_.Actual)'" }) -join ' / ')" }
    Assert-Equal (7 + 4 + 3 + 23) $rows.Count 'rows'
    Assert-Equal 'TimeoutSeconds = 600' (@($rows | Where-Object SettingId -eq 'screensaver-timeout')[0].Detail) 'parameter'
    Assert-Equal 'NtpServer = DC01.clientx.local,0x1' (@($rows | Where-Object SettingId -eq 'ntp-client')[0].Detail) 'ntp parameter'
    $true
}

Test-That 'Compare: different, missing, extra and not-filled settings are found' {
    Answer 'y', 'y'
    New-NmGpoFromBaseline -Baseline security-enforce-uac, security-screen-timeout | Out-Null
    $uac = $global:FakeGpos[0]
    $path = Get-NmGpoFilePath -Id "$($uac.Id)" -File GptTmpl
    $text = [IO.File]::ReadAllText($path)
    $text = $text.Replace('EnableLUA=4,1', 'EnableLUA=4,0').Replace("MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\PromptOnSecureDesktop=4,1`r`n", '')
    $text = $text.Replace('[Version]', "[System Access]`r`nEnableGuestAccount = 1`r`n[Version]")
    Write-NmGpoText -Path $path -Text $text -Encoding Unicode
    Set-GPRegistryValue -Guid $global:FakeGpos[1].Id -Key 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop' -ValueName 'ScreenSaveTimeOut' -Type String -Value '{TimeoutSeconds}'
    $rows = @(Compare-NmGpoBaseline -All -DifferencesOnly)
    $get = { param($id) @($rows | Where-Object SettingId -eq $id)[0] }
    Assert-Equal 'Different' (& $get 'admin-approval-all').Result 'EnableLUA'
    Assert-Equal '4,1' (& $get 'admin-approval-all').Expected 'expected'
    Assert-Equal '4,0' (& $get 'admin-approval-all').Actual 'actual'
    Assert-Equal 'Missing' (& $get 'secure-desktop').Result 'missing'
    Assert-Equal 'Not filled' (& $get 'screensaver-timeout').Result 'not filled'
    $extra = @($rows | Where-Object Result -eq 'Extra')
    Assert-Equal 'EnableGuestAccount' $extra[0].Setting 'extra'
    if (@($rows | Where-Object Result -eq 'Matches').Count) { throw 'matches shown with -DifferencesOnly' }
    $true
}

Test-That 'Compare: older baseline noted; unstamped GPO needs a baseline; -Baseline compares any GPO; unknown GPO fails' {
    Answer 'y'
    New-NmGpoFromBaseline -Baseline security-ntlm-hardening | Out-Null
    $global:FakeGpos[0].Description = 'Nutmeg baseline: security-ntlm-hardening 0.7.0'
    $rows = @(Compare-NmGpoBaseline -Gpo 'Security - NTLM Hardening' | Where-Object Kind -ne 'Links')
    Assert-Equal 'Note' $rows[0].Result 'note'
    Assert-Equal 'Matches' $rows[1].Result 'setting'
    $global:FakeGpos[0].Description = 'Made by hand'
    $rows = @(Compare-NmGpoBaseline -Gpo 'Security - NTLM Hardening')
    if ($rows[0].Result -notlike 'Failed: not built from a baseline*') { throw "unstamped: $($rows[0].Result)" }
    $rows = @(Compare-NmGpoBaseline -Gpo 'Security - NTLM Hardening' -Baseline security-ntlm-hardening | Where-Object Kind -ne 'Links')
    Assert-Equal 'Matches' $rows[0].Result 'with -Baseline'
    $rows = @(Compare-NmGpoBaseline -Gpo 'Security - LDAPS Hardening (Devices)' -Baseline security-ldaps-hardening-devices)
    if ($rows[0].Result -notlike 'Failed: no GPO*') { throw "unknown GPO: $($rows[0].Result)" }
    if (@(Compare-NmGpoBaseline -All).Count) { throw 'an unstamped GPO was included in -All' }
    $true
}

Test-That 'Compare: user rights and restricted groups - a {Param} member matches any one account; an added account is Different' {
    Write-TestBaseline -Text @'
@{
    Id = 'test-rights'; Name = 'Test Rights'; Version = '0.7.1'; Description = 'Rights.'
    Parameters = @( @{ Name = 'RdpGroup'; Prompt = 'Group allowed to RDP'; Type = 'Group'; Default = 'RDP Admins' } )
    Settings = @(
        @{ Id = 'rdp-right'; Kind = 'UserRight'; Side = 'Computer'; Title = 'RDP right'; Tags = @(); Right = 'SeRemoteInteractiveLogonRight'; Members = @('Administrators', '{RdpGroup}') }
        @{ Id = 'rdp-group'; Kind = 'RestrictedGroup'; Side = 'Computer'; Title = 'Remote Desktop Users'; Tags = @(); Group = 'Remote Desktop Users'; Members = @('{RdpGroup}') }
    )
}
'@
    Answer 'y'
    New-NmGpoFromBaseline -Baseline test-rights | Out-Null
    $rows = @(Compare-NmGpoBaseline -All | Where-Object Kind -ne 'Links')
    Assert-Equal 'Matches|Matches' (($rows | ForEach-Object Result) -join '|') 'results'
    Assert-Equal '{RdpGroup} = S-1-5-21-1000-2000-3000-1105' $rows[0].Detail 'parameter member'
    $path = Get-NmGpoFilePath -Id "$($global:FakeGpos[0].Id)" -File GptTmpl
    Write-NmGpoText -Path $path -Text (([IO.File]::ReadAllText($path)).Replace('*S-1-5-32-544,', '*S-1-5-32-544,*S-1-5-21-1000-2000-3000-512,')) -Encoding Unicode
    $rows = @(Compare-NmGpoBaseline -All | Where-Object Kind -ne 'Links')
    Assert-Equal 'Different' $rows[0].Result 'extra member'
    if ($rows[0].Actual -notlike '*Domain Admins*') { throw "SIDs not shown by name: $($rows[0].Actual)" }
    $true
}

Test-That 'Compare questions: every stamped GPO, then only what needs attention' {
    Answer 'y'
    New-NmGpoFromBaseline -Baseline security-ntlm-hardening | Out-Null
    Answer '1', 'y'
    $a = Read-NmGpoCompareOption
    if (-not $a.All -or -not $a.DifferencesOnly) { throw "answers: $($a | ConvertTo-Json -Compress)" }
    Answer '3', '1', '1', 'n'
    $a = Read-NmGpoCompareOption
    Assert-Equal 'Security - NTLM Hardening' ($a.Gpo -join ',') 'gpo'
    Assert-Equal (@(Get-NmBaseline)[0].Id) $a.Baseline 'baseline'
    $true
}

Write-Host 'The window' -ForegroundColor Cyan
Test-That 'Window form: baselines and GPOs are pick lists, the compare baseline a drop-down; nothing typed' {
    $b = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id gpo-build))
    $f = @($b | Where-Object Name -eq 'Baseline')[0]
    Assert-Equal 'PickMany|True' "$($f.Kind)|$($f.Required)" 'gpo-build Baseline'
    if (@($b | Where-Object { $_.Name -in 'Values', 'GpoName' }).Count) { throw 'hashtables shown in the form' }
    $c = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id gpo-compare))
    Assert-Equal 'PickMany|PickOne|Switch' ((@('Gpo', 'Baseline', 'All') | ForEach-Object { $n = $_; @($c | Where-Object Name -eq $n)[0].Kind }) -join '|') 'gpo-compare'
    if (-not @($c | Where-Object Name -eq 'Gpo')[0].Picker.NeedsDomain) { throw 'the GPO list should wait for the domain' }
    $true
}

Test-That 'Window pick list for gpo-build: every baseline, with what it does, what it asks and where it links' {
    $f = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id gpo-build) | Where-Object Name -eq 'Baseline')[0]
    $items = @(Get-NmGuiPickItem -Field $f)
    Assert-Equal @(Get-NmBaseline).Count $items.Count 'items'
    $st = @($items | Where-Object Key -eq 'security-screen-timeout')[0]
    Assert-Equal 'Security - Screen Timeout' $st.Label 'label'
    if ($st.Detail -notlike '*4 setting(s)*asks: Seconds before the screen locks*links at: Users*') { throw "detail: $($st.Detail)" }
    if (-not (Test-NmGuiPickMatch -Item $st -Text 'screen')) { throw 'search' }
    if (Test-NmGuiPickMatch -Item $st -Text 'kerberos') { throw 'search matched the wrong item' }
    $true
}

Test-That 'Window form values: ticks become the list, none ticked asks for one, an empty drop-down is left out' {
    $spec = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id gpo-build))
    $a = ConvertFrom-NmGuiForm -Spec $spec -Values @{ Baseline = @('security-enforce-uac', 'security-ntlm-hardening') }
    Assert-Equal 'security-enforce-uac,security-ntlm-hardening' ($a.Baseline -join ',') 'ticked'
    if ($a.Baseline -isnot [string[]]) { throw 'not a string array' }
    try { ConvertFrom-NmGuiForm -Spec $spec -Values @{ Baseline = @() }; throw 'no error' } catch { if ("$_" -notlike 'Tick at least one*') { throw } }
    $cspec = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id gpo-compare))
    $a = ConvertFrom-NmGuiForm -Spec $cspec -Values @{ Gpo = @('Security - Enforce UAC'); Baseline = ''; All = $false }
    if ($a.ContainsKey('Baseline') -or $a.ContainsKey('All')) { throw "left in: $($a.Keys -join ',')" }
    $true
}

Test-That 'Window Run for gpo-build asks each ticked baseline''s name and values (WhatIf kept); an existing GPO is left out' {
    Answer '', '600'
    $a = Complete-NmGpoBuildArgs -EntryArgs @{ Baseline = [string[]]@('security-screen-timeout'); WhatIf = $true }
    Assert-Equal '600' $a.Values['security-screen-timeout'].TimeoutSeconds 'value'
    Assert-Equal 'Security - Screen Timeout' $a.GpoName['security-screen-timeout'] 'name'
    if (-not $a.WhatIf) { throw 'WhatIf lost' }
    New-GPO -Name 'Security - Enforce UAC' | Out-Null
    Answer '', 'n'
    if ($null -ne (Complete-NmGpoBuildArgs -EntryArgs @{ Baseline = [string[]]@('security-enforce-uac') })) { throw 'an existing GPO would be built' }
    $true
}

Test-That 'Window cards for gpo-compare: one card per GPO, its status the worst, settings under Different / Matches, one line each' {
    Answer 'y', 'y'
    New-NmGpoFromBaseline -Baseline security-enforce-uac, security-ntlm-hardening | Out-Null
    $path = Get-NmGpoFilePath -Id "$($global:FakeGpos[0].Id)" -File GptTmpl
    Write-NmGpoText -Path $path -Text (([IO.File]::ReadAllText($path)).Replace('EnableLUA=4,1', 'EnableLUA=4,0')) -Encoding Unicode
    $global:FakeLinks['Security - Enforce UAC'] = @(@{ Path = 'Domain root'; Enabled = $true })
    $global:FakeLinks['Security - NTLM Hardening'] = @(@{ Path = 'Domain root'; Enabled = $true })
    $rows = @(Compare-NmGpoBaseline -All)
    Assert-Equal 'Linked|Different' "$($rows[0].Result)|$($rows[1].Result)" 'where it applies, then problems'
    Assert-Equal 'User Account Control: Run all administrators in Admin Approval Mode = Enabled: expected 4,1, found 4,0' $rows[1].Line 'line'
    $t = Get-NmTool -Id gpo-compare
    $m = Get-NmGuiCardModel -Rows $rows -Columns $t.Columns -GroupBy $t.CardGroup -CardFacet $t.CardFacet
    Assert-Equal 2 $m.Cards 'cards'
    $uac = @($m.Items | Where-Object Title -eq 'Security - Enforce UAC')[0]
    Assert-Equal "Doesn't match|High" "$($uac.Status)|$($uac.Level)" 'UAC card status'
    Assert-Equal 'Linked|Different|Matches (6)' (($uac.Fields | ForEach-Object Name) -join '|') 'UAC fields'
    if ($uac.Fields[1].Value -notlike '*expected 4,1, found 4,0') { throw "line: $($uac.Fields[1].Value)" }
    $ntlm = @($m.Items | Where-Object Title -eq 'Security - NTLM Hardening')[0]
    Assert-Equal 'Matches|OK' "$($ntlm.Status)|$($ntlm.Level)" 'NTLM card status'
    $true
}

Test-That 'Window sizes: the options area grows to half the window; a long tick list opens 7 rows tall; Output names each run' {
    Assert-Equal 230 (Get-NmGuiOptionsMaxHeight -WindowHeight 300) 'small window'
    Assert-Equal 450 (Get-NmGuiOptionsMaxHeight -WindowHeight 900) 'half of 900'
    if (-not [double]::IsPositiveInfinity((Get-NmGuiPickListHeight -Count 12))) { throw '12 items should all show' }
    Assert-Equal 300 (Get-NmGuiPickListHeight -Count 20) 'long list'
    $t = Get-NmTool -Id gpo-compare
    Assert-Equal "---- Compare GPOs with Baselines v$($t.Version), 17:56 ----" (Get-NmGuiRunLine -Tool $t -Start ([datetime]'2026-11-22 17:56')) 'start line'
    Assert-Equal '---- 43 result(s) in 0.8 s ----' (Get-NmGuiRunLine -Tool $t -Count 43 -Seconds 0.81) 'end line'
    if ((Get-NmGuiRunLine -Tool $t -Start (Get-Date) -WhatIf) -notlike '*(WhatIf)*') { throw 'WhatIf not shown' }
    if ($script:NmGuiMainControls -notcontains 'OptionsScroll') { throw 'OptionsScroll not looked up' }
    $true
}

Test-That 'Window: tick lists take the options area''s width (failed before: @() on the list threw, and the catch hid it)' {
    $oldCtl = $script:NmGui.Controls; $oldWin = $script:NmGui.Window; $oldWide = $script:NmGui.WideBoxes
    try {
        $script:NmGui.Controls = @{ OptionsScroll = [pscustomobject]@{ MaxHeight = 230 }; OptionsBorder = [pscustomobject]@{ ActualWidth = 1250 } }
        $script:NmGui.Window = [pscustomobject]@{ ActualHeight = 1000 }
        $script:NmGui.WideBoxes = New-Object System.Collections.Generic.List[object]
        $a = [pscustomobject]@{ Width = 320 }; $b = [pscustomobject]@{ Width = 320 }
        $script:NmGui.WideBoxes.Add($a); $script:NmGui.WideBoxes.Add($b)
        Update-NmGuiOptionsSize
        Assert-Equal 1200 $a.Width 'first list'
        Assert-Equal 1200 $b.Width 'second list'
        Assert-Equal 500 $script:NmGui.Controls.OptionsScroll.MaxHeight 'options height'
    } finally { $script:NmGui.Controls = $oldCtl; $script:NmGui.Window = $oldWin; $script:NmGui.WideBoxes = $oldWide }
    $true
}

Test-That 'Window look: Windows 11 only in PowerShell 7 on .NET 9+, light or dark as Windows is set; Classic always light' {
    Assert-Equal 'Windows 11|Light' (($l = Get-NmGuiLook -Setting 'Windows 11' -PsMajor 7 -NetMajor 10 -AppsUseLightTheme 1) | ForEach-Object { "$($_.Look)|$($_.Mode)" }) 'light'
    Assert-Equal 'Windows 11|Dark' ((Get-NmGuiLook -Setting 'Windows 11' -PsMajor 7 -NetMajor 10 -AppsUseLightTheme 0) | ForEach-Object { "$($_.Look)|$($_.Mode)" }) 'dark'
    Assert-Equal 'Classic|Light' ((Get-NmGuiLook -Setting 'Windows 11' -PsMajor 5 -NetMajor 4 -AppsUseLightTheme 0) | ForEach-Object { "$($_.Look)|$($_.Mode)" }) '5.1'
    Assert-Equal 'Classic|Light' ((Get-NmGuiLook -Setting 'Windows 11' -PsMajor 7 -NetMajor 8 -AppsUseLightTheme 0) | ForEach-Object { "$($_.Look)|$($_.Mode)" }) '.NET 8'
    Assert-Equal 'Classic|Light' ((Get-NmGuiLook -Setting 'Classic' -PsMajor 7 -NetMajor 10 -AppsUseLightTheme 0) | ForEach-Object { "$($_.Look)|$($_.Mode)" }) 'Classic chosen'
    Assert-Equal 'Windows 11' (Get-NmSetting -Key WindowLook) 'default setting'
    $true
}

Test-That 'Window colours: teal becomes Nutmeg red in both modes; dark mode darkens surfaces and lightens text; text on red or the sidebar stays light' {
    Assert-Equal '#CF2027' (Resolve-NmGuiColor -Hex '#0E6B66' -Mode Light) 'accent light'
    Assert-Equal '#D93A40' (Resolve-NmGuiColor -Hex '#0e6b66' -Mode Dark) 'accent dark'
    Assert-Equal '#FFFFFF' (Resolve-NmGuiColor -Hex '#FFFFFF' -Mode Light) 'white stays in light'
    Assert-Equal '#202020' (Resolve-NmGuiColor -Hex '#FFFFFF' -Mode Dark) 'surface in dark'
    Assert-Equal '#F3F3F3' (Resolve-NmGuiColor -Hex '#16191F' -Mode Dark) 'text in dark'
    Assert-Equal '#FFFFFE' (Resolve-NmGuiColor -Hex '#FFFFFE' -Mode Dark) 'text on red stays white'
    Assert-Equal '#00FFFFFF' (Resolve-NmGuiColor -Hex '#00FFFFFF' -Mode Dark) 'transparent left alone'
    $x = Convert-NmGuiXamlColor -Xaml '<Border Background="#FFFFFF" BorderBrush="#0E6B66"><TextBlock Foreground="#16191F"/><Rectangle Fill="#00FFFFFF"/></Border>' -Mode Dark
    Assert-Equal '<Border Background="#202020" BorderBrush="#D93A40"><TextBlock Foreground="#F3F3F3"/><Rectangle Fill="#00FFFFFF"/></Border>' $x 'XAML'
    # No teal is left where the brand map cannot reach it: every #0E6B66-family colour in the window code is in the map.
    $src = Get-Content (Join-Path $script:NmModuleRoot 'Core\Gui.ps1') -Raw
    if ($src -match 'ConvertFromString\(' -and @([regex]::Matches($src, 'ConvertFromString\(')).Count -ne 1) { throw 'a brush is made without Get-NmGuiBrush' }
    $true
}

Test-That 'Window layout: saved per person, limits kept, a damaged file falls back to the default' {
    $script:NmGuiLayoutTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ("NmLayout_" + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $d = Read-NmGuiLayout
        Assert-Equal '260|340|False|False|220' "$($d.SidebarWidth)|$($d.ToolsWidth)|$($d.PanelsHidden)|$($d.OutputOpen)|$($d.OutputHeight)" 'default'
        Save-NmGuiLayout -Layout @{ SidebarWidth = 200; ToolsWidth = 9999; PanelsHidden = $true; OutputOpen = $true; OutputHeight = 10 }
        $l = Read-NmGuiLayout
        Assert-Equal '200|640|True|True|80' "$($l.SidebarWidth)|$($l.ToolsWidth)|$($l.PanelsHidden)|$($l.OutputOpen)|$($l.OutputHeight)" 'saved, limits kept'
        Set-Content -LiteralPath $script:NmGuiLayoutTestFile -Value '{ not json'
        Assert-Equal 260 (Read-NmGuiLayout).SidebarWidth 'damaged file'
        $p = ConvertTo-NmGuiLayout -Data ([pscustomobject]@{ SidebarWidth = 'wide'; OutputOpen = 'True' })
        Assert-Equal '260|True' "$($p.SidebarWidth)|$($p.OutputOpen)" 'bad values'
    } finally { Remove-Item -LiteralPath $script:NmGuiLayoutTestFile -Force -ErrorAction SilentlyContinue; $script:NmGuiLayoutTestFile = $null }
    $true
}

Test-That 'Window layout: the menu button hides both side panels and brings them back; a panel dragged shut comes back at its default width' {
    $l = Get-NmGuiLayoutDefault
    $l.SidebarWidth = 300; $l.ToolsWidth = 0
    $h = Switch-NmGuiPanelState -Layout $l
    if (-not $h.PanelsHidden) { throw 'not hidden' }
    Assert-Equal 300 $h.SidebarWidth 'width kept while hidden'
    $b = Switch-NmGuiPanelState -Layout $h
    Assert-Equal 'False|300|340' "$($b.PanelsHidden)|$($b.SidebarWidth)|$($b.ToolsWidth)" 'back'
    if ($l.PanelsHidden) { throw 'the layout passed in was changed' }
    $true
}

Test-That 'Window: options fold into one line after Run, in the form''s words' {
    $spec = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id gpo-compare))
    Assert-Equal 'Gpo: Security - Enforce UAC and 2 more   |   Baseline: security-enforce-uac   |   Differences only' (Get-NmGuiOptionsSummary -Spec $spec -Values @{ Gpo = @('Security - Enforce UAC', 'B', 'C'); Baseline = 'security-enforce-uac'; All = $false; DifferencesOnly = $true }) 'summary'
    Assert-Equal 'All' (Get-NmGuiOptionsSummary -Spec $spec -Values @{ Gpo = @(); Baseline = ''; All = $true; DifferencesOnly = $false }) 'All only'
    Assert-Equal 'Default options' (Get-NmGuiOptionsSummary -Spec $spec -Values @{}) 'nothing set'
    $true
}

Test-That 'Window: the drop-down''s inner toggle stretches (under the Windows 11 theme it shrank to its arrow on the left)' {
    if ($script:NmGuiTheme -notmatch '<ToggleButton Focusable="False" ClickMode="Press" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"') { throw 'the ComboBox toggle is not pinned to stretch' }
    $true
}

Test-That 'Where a GPO applies: links shown (disabled, enforced); not linked or all links off is amber; linked with its side disabled is red' {
    Answer 'y', 'y', 'y', 'y'
    New-NmGpoFromBaseline -Baseline security-enforce-uac, security-ntlm-hardening, security-ldaps-hardening-dcs, security-screen-timeout | Out-Null
    $global:FakeLinks['Security - Enforce UAC'] = @(@{ Path = 'Domain root'; Enabled = $true; Enforced = $true }, @{ Path = 'Devices/Workstations'; Enabled = $false })
    $global:FakeLinks['Security - NTLM Hardening'] = @(@{ Path = 'Domain root'; Enabled = $false })
    $global:FakeLinks['Security - LDAPS Hardening (DC''s)'] = @(@{ Path = 'Domain Controllers'; Enabled = $true })
    $global:FakeComputerOff['Security - LDAPS Hardening (DC''s)'] = $true
    $rows = @(Compare-NmGpoBaseline -All)
    $where = @{}; foreach ($r in @($rows | Where-Object Kind -eq 'Links')) { $where[$r.Gpo] = $r }
    Assert-Equal 'Linked|Domain root (enforced); Devices/Workstations (disabled)' "$($where['Security - Enforce UAC'].Result)|$($where['Security - Enforce UAC'].Actual)" 'UAC'
    Assert-Equal 'Not linked|Every link is disabled: it applies to nothing.' "$($where['Security - NTLM Hardening'].Result)|$($where['Security - NTLM Hardening'].Detail)" 'NTLM'
    Assert-Equal 'Not applied' $where['Security - LDAPS Hardening (DC''s)'].Result 'LDAPS: computer side off'
    Assert-Equal 'Not linked|(not linked)' "$($where['Security - Screen Timeout'].Result)|$($where['Security - Screen Timeout'].Actual)" 'Screen Timeout: nowhere'
    Assert-Equal 'Domain root (enforced); Devices/Workstations (disabled)' (@($rows | Where-Object { $_.Gpo -eq 'Security - Enforce UAC' -and $_.Kind -ne 'Links' })[0].Links) 'Links on every row'
    $state = @{}; $link = @{}; foreach ($r in $rows) { $state[$r.Gpo] = $r.GpoState; $link[$r.Gpo] = $r.LinkState }
    $names = @('Security - Enforce UAC', 'Security - NTLM Hardening', 'Security - LDAPS Hardening (DC''s)', 'Security - Screen Timeout')
    Assert-Equal 'Matches|Matches|Matches|Matches' (@($names | ForEach-Object { $state[$_] }) -join '|') 'settings state: all match'
    Assert-Equal 'Linked|Not linked|Not applied|Not linked' (@($names | ForEach-Object { $link[$_] }) -join '|') 'where it applies, apart'
    Assert-Equal 'Medium' (Get-NmGuiStatusLevel -Column Result -Value 'Not linked') 'amber'
    Assert-Equal 'High' (Get-NmGuiStatusLevel -Column Result -Value 'Not applied') 'red'
    Assert-Equal 'High' (Get-NmGuiStatusLevel -Column GpoState -Value "Doesn't match") 'red'
    $true
}

Test-That 'Linked away from the suggested links is only noted (links are chosen per client)' {
    $rep = [pscustomobject]@{ Links = @([pscustomobject]@{ Path = 'Devices'; Enabled = $true; Enforced = $false }); ComputerEnabled = $true; UserEnabled = $true }
    $st = Get-NmGpoApplyState -Report $rep -Sides @('Computer') -Suggested @('Domain root')
    Assert-Equal 'Linked' $st.Result 'still linked'
    if ($st.Detail -notlike 'Suggested links not used: Domain root*') { throw "detail: $($st.Detail)" }
    $true
}

Test-That 'Window headline counts GPOs; the tags count GPOs by state (All first) and filter whole cards' {
    Answer 'y', 'y', 'y'
    New-NmGpoFromBaseline -Baseline security-enforce-uac, security-ntlm-hardening, security-kerberos-encryption | Out-Null
    $global:FakeLinks['Security - Enforce UAC'] = @(@{ Path = 'Domain root'; Enabled = $true })
    $global:FakeLinks['Security - NTLM Hardening'] = @(@{ Path = 'Domain root'; Enabled = $true })
    $path = Get-NmGpoFilePath -Id "$($global:FakeGpos[1].Id)" -File GptTmpl
    Write-NmGpoText -Path $path -Text (([IO.File]::ReadAllText($path)).Replace('LmCompatibilityLevel=4,5', 'LmCompatibilityLevel=4,3')) -Encoding Unicode
    $rows = @(Compare-NmGpoBaseline -All)
    $t = Get-NmTool -Id gpo-compare
    Assert-Equal '3 GPOs  |  ran 23:30  |  0.4 s' (Get-NmGuiResultTitle -Tool $t -Rows $rows -At ([datetime]'2026-11-23 23:30') -Seconds 0.4) 'headline'
    Assert-Equal '43 result(s)  |  ran 23:30  |  0.4 s' (Get-NmGuiResultTitle -Tool (Get-NmTool -Id gpo-build) -Rows (1..43 | ForEach-Object { [pscustomobject]@{ Gpo = "g$_" } }) -At ([datetime]'2026-11-23 23:30') -Seconds 0.4) 'other tools count rows'
    $m = Get-NmGuiCardModel -Rows $rows -Columns $t.Columns -GroupBy $t.CardGroup -CardFacet $t.CardFacet
    Assert-Equal 'GpoState|3' "$($m.FacetColumn)|$($m.AllCards)" 'facet column, all'
    $counts = @{}; foreach ($f in $m.Facets) { $counts[$f.Value] = $f.Count }
    Assert-Equal "2|1" "$($counts['Matches'])|$($counts["Doesn't match"])" 'counts per GPO, by their settings'
    if ($counts.ContainsKey('Not linked')) { throw 'where it applies is a label, not a tag' }
    $f = Get-NmGuiCardModel -Rows $rows -Columns $t.Columns -GroupBy $t.CardGroup -CardFacet $t.CardFacet -Facet "Doesn't match"
    Assert-Equal 'Security - NTLM Hardening' (($f.Items | ForEach-Object Title) -join ',') 'filtered to the card'
    if (@($f.Items[0].Fields).Count -lt 2) { throw 'the whole card should show (Linked and Different), not only some rows' }
    $true
}

Test-That 'Card buttons: Edit GPO opens Microsoft''s editor on the DC in use; View GPO saves GPMC''s report and opens it; the console says the totals' {
    Answer 'y'
    New-NmGpoFromBaseline -Baseline security-ntlm-hardening | Out-Null
    $rows = @(Compare-NmGpoBaseline -All)
    $t = Get-NmTool -Id gpo-compare
    Assert-Equal 'Edit GPO|View GPO|GPMC report' (($t.CardActions | ForEach-Object Label) -join '|') 'compare buttons'
    Assert-Equal 'Edit GPO|View GPO|GPMC report' (((Get-NmTool -Id gpo-build).CardActions | ForEach-Object Label) -join '|') 'build buttons'
    Invoke-NmGpoCardEdit -Row $rows[0]
    Assert-Equal "edit $($global:FakeGpos[0].Path)" $global:Opened[0] 'editor'
    Invoke-NmGpoCardReport -Row $rows[0]
    if ($global:Opened[1] -notlike 'open GPO_Security - NTLM Hardening_*.html') { throw "report: $($global:Opened[1])" }
    Invoke-NmGpoCardView -Row $rows[0]
    if ($global:Opened[2] -ne 'view Security - NTLM Hardening') { throw "view: $($global:Opened[2])" }
    Assert-Equal 'Compared 4 GPOs: 2 match, 1 doesn''t match, 1 failed; 1 not linked.' (Get-NmGpoStateSummary -States @('Matches', 'Matches', "Doesn't match", 'Failed') -LinkStates @('Linked', 'Not linked', 'Linked')) 'console totals'
    Assert-Equal 'Compared 2 GPOs: 2 don''t match.' (Get-NmGpoStateSummary -States @("Doesn't match", "Doesn't match") -LinkStates @('Linked', 'Linked')) 'plural'
    $true
}

Test-That 'Window cards for gpo-compare carry two labels: the settings (green Matches, red Doesn''t match) and where it applies; the edge takes the worse' {
    Answer 'y', 'y'
    New-NmGpoFromBaseline -Baseline security-ntlm-hardening, security-kerberos-encryption | Out-Null
    $global:FakeLinks['Security - NTLM Hardening'] = @(@{ Path = 'Domain root'; Enabled = $true })
    $rows = @(Compare-NmGpoBaseline -All)
    $t = Get-NmTool -Id gpo-compare
    $m = Get-NmGuiCardModel -Rows $rows -Columns $t.Columns -GroupBy $t.CardGroup -CardFacet $t.CardFacet -CardBadge $t.CardBadge
    $ntlm = @($m.Items | Where-Object Title -eq 'Security - NTLM Hardening')[0]
    $kerb = @($m.Items | Where-Object Title -eq 'Security - Kerberos Encryption')[0]
    Assert-Equal 'Matches|OK|Linked|OK|OK' "$($ntlm.Status)|$($ntlm.StatusLevel)|$($ntlm.Badge)|$($ntlm.BadgeLevel)|$($ntlm.Level)" 'linked and matching'
    Assert-Equal 'Matches|OK|Not linked|Medium|Medium' "$($kerb.Status)|$($kerb.StatusLevel)|$($kerb.Badge)|$($kerb.BadgeLevel)|$($kerb.Level)" 'matching but not linked'
    $true
}

Test-That 'View GPO: the GPO''s report as a tab per part, in GPMC''s words (security options, templates with their fields, audit, services, rights, preferences)' {
    $xml = @'
<?xml version="1.0" encoding="utf-16"?>
<GPO xmlns="http://www.microsoft.com/GroupPolicy/Settings" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Name>Security - Test</Name>
  <Computer><Enabled>true</Enabled>
    <ExtensionData><Extension xmlns:q1="http://www.microsoft.com/GroupPolicy/Settings/Security" xsi:type="q1:SecuritySettings">
      <q1:SecurityOptions><q1:KeyName>MACHINE\Software\X\EnableLUA</q1:KeyName><q1:SettingNumber>1</q1:SettingNumber>
        <q1:Display><q1:Name>User Account Control: Run all administrators in Admin Approval Mode</q1:Name><q1:DisplayBoolean>true</q1:DisplayBoolean></q1:Display></q1:SecurityOptions>
      <q1:SystemServices><q1:Name>Spooler</q1:Name><q1:StartupMode>Disabled</q1:StartupMode><q1:SecurityDescriptor>x</q1:SecurityDescriptor></q1:SystemServices>
      <q1:UserRightsAssignment><q1:Name>SeRemoteInteractiveLogonRight</q1:Name><q1:Member><Name xmlns="http://www.microsoft.com/GroupPolicy/Types">BUILTIN\Administrators</Name></q1:Member><q1:Member><Name xmlns="http://www.microsoft.com/GroupPolicy/Types">CLIENTX\RDP Admins</Name></q1:Member></q1:UserRightsAssignment>
    </Extension><Name>Security</Name></ExtensionData>
    <ExtensionData><Extension xmlns:q2="http://www.microsoft.com/GroupPolicy/Settings/Auditing" xsi:type="q2:AuditSettings">
      <q2:AuditSetting><q2:PolicyTarget>System</q2:PolicyTarget><q2:SubcategoryName>Audit Logon</q2:SubcategoryName><q2:SubcategoryGuid>{0cce9215}</q2:SubcategoryGuid><q2:SettingValue>3</q2:SettingValue></q2:AuditSetting>
    </Extension><Name>Advanced Audit Configuration</Name></ExtensionData>
    <ExtensionData><Extension xmlns:q3="http://www.microsoft.com/GroupPolicy/Settings/Windows/Registry" xsi:type="q3:RegistrySettings">
      <q3:RegistrySettings clsid="{A3CCFC41}"><q3:Registry clsid="{9CD4B2F4}" name="Start"><q3:Properties action="U" hive="HKEY_LOCAL_MACHINE" key="SYSTEM\CurrentControlSet\Services\tzautoupdate" name="Start" type="REG_DWORD" value="00000003"/></q3:Registry></q3:RegistrySettings>
    </Extension><Name>Windows Registry</Name></ExtensionData>
  </Computer>
  <User><Enabled>false</Enabled>
    <ExtensionData><Extension xmlns:q4="http://www.microsoft.com/GroupPolicy/Settings/Registry" xsi:type="q4:RegistrySettings">
      <q4:Policy><q4:Name>Screen saver timeout</q4:Name><q4:State>Enabled</q4:State><q4:Explain>long text</q4:Explain><q4:Category>Control Panel/Personalization</q4:Category>
        <q4:Numeric><q4:Name>Seconds:</q4:Name><q4:State>Enabled</q4:State><q4:Value>900</q4:Value></q4:Numeric></q4:Policy>
    </Extension><Name>Registry</Name></ExtensionData>
  </User>
  <LinksTo><SOMName>Domain Controllers</SOMName><SOMPath>clientx.local/Domain Controllers</SOMPath><Enabled>true</Enabled><NoOverride>false</NoOverride></LinksTo>
</GPO>
'@
    $m = ConvertTo-NmGpoViewModel -Xml $xml -Domain 'clientx.local'
    Assert-Equal 'Security - Test' $m.Heading 'heading'
    if ($m.Summary -notlike 'Links: Domain Controllers*user settings DISABLED*') { throw "summary: $($m.Summary)" }
    Assert-Equal 'Computer: Security|Computer: Advanced Audit Configuration|Computer: Windows Registry|User: Registry' (($m.Sections | ForEach-Object Title) -join '|') 'sections'
    $sec = $m.Sections[0].Rows
    Assert-Equal 'User Account Control: Run all administrators in Admin Approval Mode = Enabled' "$($sec[0].Setting) = $($sec[0].Value)" 'security option in GPMC words'
    Assert-Equal 'Spooler = Disabled' "$($sec[1].Setting) = $($sec[1].Value)" 'service, no descriptor'
    Assert-Equal 'SeRemoteInteractiveLogonRight = BUILTIN\Administrators, CLIENTX\RDP Admins' "$($sec[2].Setting) = $($sec[2].Value)" 'user right'
    Assert-Equal 'Audit Logon = Success and Failure' "$($m.Sections[1].Rows[0].Setting) = $($m.Sections[1].Rows[0].Value)" 'audit'
    Assert-Equal 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\tzautoupdate\Start = REG_DWORD = 00000003 (Update)' "$($m.Sections[2].Rows[0].Setting) = $($m.Sections[2].Rows[0].Value)" 'preference'
    Assert-Equal 'Control Panel/Personalization: Screen saver timeout = Enabled; Seconds: = 900' "$($m.Sections[3].Rows[0].Setting) = $($m.Sections[3].Rows[0].Value)" 'template with its field'
    $true
}

Test-That 'Compare with nothing picked says what to do' {
    try { Compare-NmGpoBaseline; throw 'no error' } catch { if ("$_" -notlike 'Pick the GPOs to compare*') { throw } }
    $true
}

Test-That 'Registry: a picker whose list function is missing, and CardGroup with four columns, are refused' {
    $before = $script:NmToolLoadErrors.Count
    function script:Invoke-NmPickTest { param([string[]]$Thing) }
    Register-NmTool -Path 'test.ps1' -Definition @{ Name = 'P'; Id = 'pick-test'; Category = 'GroupPolicy'; Area = 'gpo/Baselines'; Synopsis = 's'; Version = '0.7.1'; Kind = 'Report'; Services = @(); Entry = 'Invoke-NmPickTest'
        Pickers = @{ Thing = @{ Items = 'Get-NoSuchList' } } }
    Register-NmTool -Path 'test.ps1' -Definition @{ Name = 'P'; Id = 'pick-test2'; Category = 'GroupPolicy'; Area = 'gpo/Baselines'; Synopsis = 's'; Version = '0.7.1'; Kind = 'Report'; Services = @(); Entry = 'Invoke-NmPickTest'
        CardGroup = @('a', 'b', 'c', 'd') }
    $new = @($script:NmToolLoadErrors | Select-Object -Skip $before)
    if ($new.Count -ne 2 -or $new[0].Reason -notlike "*Items function 'Get-NoSuchList'*" -or $new[1].Reason -notlike '*one to three*') { throw "errors: $($new.Reason -join ' / ')" }
    if (Get-NmTool -Id pick-test) { throw 'registered anyway' }
    $true
}

Test-That 'Both tools are registered under Group Policy > Baselines; compare is read only' {
    $b = Get-NmTool -Id gpo-build
    $c = Get-NmTool -Id gpo-compare
    Assert-Equal 'gpo|Baselines|ReportAndChange' "$($b.AdminCenter)|$($b.Section)|$($b.Kind)" 'gpo-build'
    Assert-Equal 'gpo|Baselines|Report' "$($c.AdminCenter)|$($c.Section)|$($c.Kind)" 'gpo-compare'
    $src = Get-Content (Join-Path $script:NmModuleRoot 'Tools\GroupPolicy\Compare-NmGpoBaseline.ps1') -Raw
    if ($src -match '\b(New|Set|Remove)-GP|Set-ADObject|Write-NmGpo|Update-NmGpoVersion') { throw 'compare writes something' }
    $true
}

# ---------------------------------------------------------------------------
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
& $mod { if ($script:NmSettingsTestFile -and (Test-Path $script:NmSettingsTestFile)) { Remove-Item $script:NmSettingsTestFile -Force } }
Write-Host '=============================================' -ForegroundColor Cyan
if ($script:Failed.Count -eq 0) {
    Write-Host "   All $script:Passed tests passed." -ForegroundColor Green
    exit 0
}
Write-Host "   $($script:Failed.Count) failed, $script:Passed passed." -ForegroundColor Red
exit 1
