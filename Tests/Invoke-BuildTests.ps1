<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.1.0

.SYNOPSIS
    Tests for the New Forest Build (new-forest): pre-flight, questions, phase 0, phase 1 and the check.

.DESCRIPTION
    - Stands in for a fresh Windows Server 2025 VM in a workgroup: one DHCP adapter on 192.0.2.37/24,
      no domain answering, and fakes for every Windows call the build makes, recorded in order.
    - "Restarts" are simulated by changing the fake computer between runs.
    - Covers what the build refuses, the defaults it offers, the one confirmation, the order of the
      steps (the IP last), resuming after a restart or a failure, the DSRM password never being saved,
      and finishing.

.EXAMPLE
    pwsh -File .\Tests\Invoke-BuildTests.ps1

.VERSIONING
    0.1.0 - Initial build tests.
#>

$ErrorActionPreference = 'Stop'

# Fake AD for the check after promotion.
function global:Get-ADDomain {
    param($Server, $ErrorAction)
    [pscustomobject]@{ DNSRoot = 'clientx.local'; NetBIOSName = 'CLIENTX'; DistinguishedName = 'DC=clientx,DC=local'
        DomainSID = 'S-1-5-21-1000-2000-3000'; DomainMode = 'Windows2025Domain'; PDCEmulator = 'DC01.clientx.local' }
}
function global:Get-ADForest { param($Server, $ErrorAction) [pscustomobject]@{ RootDomain = 'clientx.local'; ForestMode = 'Windows2025Forest' } }

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path (Join-Path $repoRoot 'Nutmeg.AD') 'Nutmeg.AD.psd1') -Force
$mod = Get-Module Nutmeg.AD
$global:NmTestModule = $mod
& $mod { $script:NmSettingsTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ("NmAdSettings_" + [guid]::NewGuid().ToString('N') + '.json'); $script:NmSettingsData = $null; Update-NmConfigFromSetting }

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("NmAdBuild_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

& $mod {
    param($root)
    $script:NmConfig.ExportRoot = Join-Path $root 'Exports'
    $script:NmConfig.DataRoot   = Join-Path $root 'Data'
    $script:NmLogPath = $null
    $script:TestAnswers = New-Object System.Collections.Generic.Queue[string]
    $script:SecretAnswers = New-Object System.Collections.Generic.Queue[string]
    $script:Calls = New-Object System.Collections.Generic.List[string]
    $script:ForestArgsSeen = $null
    function script:Read-NmHost { param([string]$Prompt) if ($script:TestAnswers.Count -gt 0) { $script:TestAnswers.Dequeue() } else { throw 'Test ran out of scripted answers (a menu asked more than expected).' } }
    function script:Read-NmSecret { param($Prompt) if (-not $script:SecretAnswers.Count) { throw 'Test ran out of passwords.' } ConvertTo-SecureString -String $script:SecretAnswers.Dequeue() -AsPlainText -Force }

    # The server, as the tests set it.
    function script:Test-NmWindowsPowerShell { $script:FakeWinPs }
    function script:Test-NmElevated { $script:FakeElevated }
    function script:Get-NmOsInfo { [pscustomobject]@{ Caption = 'Microsoft Windows Server 2025 Standard'; Version = '10.0.26100'; Build = 26100; ProductType = $script:FakeProductType } }
    function script:Get-NmLocalComputer { $script:FakePc }
    function script:Test-NmPendingReboot { $false }
    function script:Get-NmFreeSpaceGB { 80 }
    function script:Get-NmBlockedFile { $script:FakeBlocked }
    function script:Get-NmHypervisor { 'Hyper-V' }
    function script:Get-NmNetAdapterInfo { $script:FakeNics }
    function script:Get-NmTimeZoneId { $script:FakeTz }
    function script:Test-NmTimeZoneId { param($Id) @('UTC', 'Eastern Standard Time', 'Central Standard Time') -contains $Id }
    function script:Set-NmTimeZone { param($Id) $script:Calls.Add("TimeZone $Id"); $script:FakeTz = $Id }
    function script:Set-NmComputerName { param($NewName) $script:Calls.Add("Rename $NewName") }
    function script:Test-NmIpInUse { param($IPAddress) $script:FakeIpInUse }
    function script:Set-NmStaticIp { param($InterfaceIndex, $IPAddress, $PrefixLength, $Gateway, $DnsServers) $script:Calls.Add("StaticIp $InterfaceIndex $IPAddress/$PrefixLength gw $Gateway dns $($DnsServers -join ',')") }
    function script:Test-NmDomainAnswers { param($Domain) $script:FakeDomainAnswers }
    function script:Register-NmResumeTask { param($LauncherPath, [switch]$Gui) $script:Calls.Add("ResumeTask $LauncherPath$(if ($Gui) { ' -Gui' })") }
    function script:Unregister-NmResumeTask { $script:Calls.Add('ResumeTask removed') }
    function script:Restart-NmServer { param($Seconds) $script:Calls.Add("Restart $Seconds") }
    function script:Install-NmAddsFeature { $script:Calls.Add('Features'); [pscustomobject]@{ Success = $true; RestartNeeded = 'No' } }
    function script:Test-NmForestInstallation { param($ForestArgs) $script:Calls.Add('PreCheck'); $script:ForestArgsSeen = $ForestArgs; [pscustomobject]@{ Status = $script:FakePreCheck; Message = 'The local Administrator password does not meet requirements.' } }
    function script:Install-NmForest { param($ForestArgs) $script:Calls.Add('Promote'); [pscustomobject]@{ Status = 'Success'; Message = '' } }
    # AD module for the check after promotion.
    function script:Find-NmModule { param($Name) [pscustomobject]@{ Name = $Name; Version = [version]'1.0.0.0' } }
    function script:Test-NmModuleLoaded { param($Name) $false }
    function script:Import-NmModule { param($Name, [switch]$WindowsPowerShell) }
} $testRoot

function global:Answer { param([string[]]$Values) & $global:NmTestModule { param($v) foreach ($x in $v) { $script:TestAnswers.Enqueue($x) } } $Values }
function global:Secret { param([string[]]$Values) & $global:NmTestModule { param($v) foreach ($x in $v) { $script:SecretAnswers.Enqueue($x) } } $Values }
function global:Reset-Server {
    # A fresh VM from the checkpoint: workgroup, DHCP, no saved build.
    & $global:NmTestModule {
        Reset-NmSession
        $script:TestAnswers.Clear(); $script:SecretAnswers.Clear(); $script:Calls.Clear(); $script:ForestArgsSeen = $null
        $script:FakeWinPs = $true; $script:FakeElevated = $true; $script:FakeProductType = 3; $script:FakeBlocked = @()
        $script:FakePc = [pscustomobject]@{ Name = 'WIN-7Q2B4K9'; Domain = ''; PartOfDomain = $false; IsDC = $false; IsPdc = $false; DnsHostName = 'WIN-7Q2B4K9' }
        $script:FakeNics = @([pscustomobject]@{ Name = 'Ethernet'; Index = 4; Mac = '00-15-5D-00-00-01'; Description = 'Microsoft Hyper-V Network Adapter'; IPv4 = '192.0.2.37'; PrefixLength = 24; Gateway = '192.0.2.1'; Dns = @('192.0.2.1'); Dhcp = $true })
        $script:FakeTz = 'UTC'; $script:FakeIpInUse = $false; $script:FakeDomainAnswers = $false; $script:FakePreCheck = 'Success'
        $p = Get-NmBuildStatePath
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
}
function global:Restart-Fake {
    # What the server looks like after a restart: the new name, and after promotion a DC.
    param([switch]$Promoted)
    & $global:NmTestModule {
        param($promoted)
        $script:TestAnswers.Clear(); $script:Calls.Clear()
        if ($promoted) {
            $script:FakePc = [pscustomobject]@{ Name = 'DC01'; Domain = 'clientx.local'; PartOfDomain = $true; IsDC = $true; IsPdc = $true; DnsHostName = 'DC01.clientx.local' }
            $script:FakeProductType = 2
        } else {
            $script:FakePc = [pscustomobject]@{ Name = 'DC01'; Domain = ''; PartOfDomain = $false; IsDC = $false; IsPdc = $false; DnsHostName = 'DC01' }
        }
        $script:FakeNics = @([pscustomobject]@{ Name = 'Ethernet'; Index = 4; Mac = '00-15-5D-00-00-01'; Description = 'Microsoft Hyper-V Network Adapter'; IPv4 = '192.0.2.50'; PrefixLength = 24; Gateway = '192.0.2.1'; Dns = @('192.0.2.1'); Dhcp = $false })
    } $Promoted.IsPresent
}
# The standard answers: clientx.local, defaults everywhere, DC01, Eastern time, one DC, then the typed approval.
$global:StdAnswers = @('clientx.local', '', '1', 'n', 'dc01', 'Eastern Standard Time', '', '', '', '', '', 'clientx')

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

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '   Nutmeg.AD New Forest Build tests' -ForegroundColor Yellow
Write-Host '=============================================' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# The tool and its checks
# ---------------------------------------------------------------------------
Test-That 'new-forest is a Change tool in New forest build > First DC' {
    $t = Get-NmTool -Id new-forest
    $t -and $t.AdminCenter -eq 'build' -and $t.Section -eq 'First DC' -and $t.Kind -eq 'Change' -and @($t.Services).Count -eq 0
}

Test-That 'Pre-flight on a fresh workgroup server: nothing Not ready, Hyper-V seen' {
    Reset-Server
    $rows = @(Get-NmNewForestPreflight)
    @($rows | Where-Object Result -eq 'Not ready').Count -eq 0 -and ($rows | Where-Object Check -eq 'Hypervisor').Detail -eq 'Hyper-V' -and $rows.Count -ge 9
}

foreach ($case in @(
    @{ Name = 'a domain-joined server';  Set = { $script:FakePc = [pscustomobject]@{ Name = 'SRV1'; Domain = 'other.local'; PartOfDomain = $true; IsDC = $false; IsPdc = $false; DnsHostName = 'SRV1.other.local' } }; Check = 'Not joined to a domain' }
    @{ Name = 'PowerShell 7';            Set = { $script:FakeWinPs = $false }; Check = 'Windows PowerShell 5.1' }
    @{ Name = 'not elevated';            Set = { $script:FakeElevated = $false }; Check = 'Running as administrator' }
    @{ Name = 'an existing DC';          Set = { $script:FakeProductType = 2 }; Check = 'Windows Server 2016 or later' }
    @{ Name = 'blocked toolkit files';   Set = { $script:FakeBlocked = @([pscustomobject]@{ FullName = 'x.ps1' }) }; Check = 'Toolkit files unblocked' }
    @{ Name = 'no connected adapter';    Set = { $script:FakeNics = @() }; Check = 'Network adapter' }
)) {
    $global:CaseSet = $case.Set; $global:CaseCheck = $case.Check
    Test-That "Pre-flight stops on $($case.Name), before any question, and saves nothing" {
        Reset-Server
        & $global:NmTestModule $global:CaseSet
        Answer @('')   # Wait-NmKey after the refusal
        $r = Read-NmNewForestPlan 6>$null
        $row = @(Get-NmNewForestPreflight) | Where-Object Check -eq $global:CaseCheck
        ($null -eq $r) -and $row.Result -eq 'Not ready' -and $script:TestAnswers.Count -eq 0 -and -not (Get-NmBuildState)
    }
}

Test-That 'The build opens on a cleared screen with the toolkit header (issue #6)' {
    Reset-Server
    $global:Cleared = 0
    $original = (Get-Command Clear-NmScreen -CommandType Function).ScriptBlock
    function script:Clear-NmScreen { $global:Cleared++ }
    try { Answer @(''); $script:FakeElevated = $false; $null = Read-NmNewForestPlan 6>$null } finally { Set-Item -Path Function:\script:Clear-NmScreen -Value $original }
    $global:Cleared -eq 1
}

Test-That 'Two connected adapters are a warning, not a stop' {
    Reset-Server
    $script:FakeNics = @($script:FakeNics[0], [pscustomobject]@{ Name = 'Ethernet 2'; Index = 7; IPv4 = '198.51.100.9'; PrefixLength = 24; Gateway = ''; Dns = @(); Dhcp = $true; Mac = 'x'; Description = 'y' })
    (@(Get-NmNewForestPreflight) | Where-Object Check -eq 'Network adapter').Result -eq 'Warning'
}

Test-That 'The suggested DC address is .50 in the current subnet' {
    (Get-NmSuggestedDcIp -CurrentIp '192.0.2.37') -eq '192.0.2.50' -and (Get-NmSuggestedDcIp -CurrentIp '10.20.30.199') -eq '10.20.30.50' -and (Get-NmSuggestedDcIp -CurrentIp 'nope') -eq ''
}

Test-That 'Names: two-part DNS names, 15-character NetBIOS and computer names' {
    (Test-NmDomainNameText 'clientx.local') -and (Test-NmDomainNameText 'corp.clientx.com') -and -not (Test-NmDomainNameText 'clientx') -and
        -not (Test-NmDomainNameText '192.0.2.1') -and -not (Test-NmDomainNameText 'bad_name.local') -and
        (Test-NmNetbiosText 'CLIENTX') -and -not (Test-NmNetbiosText 'ABCDEFGHIJKLMNOP') -and -not (Test-NmNetbiosText 'CLIENT.X') -and
        (Test-NmComputerNameText 'DC01') -and -not (Test-NmComputerNameText '12345') -and -not (Test-NmComputerNameText 'DC01-TOO-LONG-NAME')
}

# ---------------------------------------------------------------------------
# Questions and approval
# ---------------------------------------------------------------------------
Test-That 'The questions offer the server''s own defaults and save the approved answers' {
    Reset-Server
    Answer $global:StdAnswers
    $r = Read-NmNewForestPlan 6>$null
    $a = (Get-NmBuildState).Answers
    $r.Resume -and $script:TestAnswers.Count -eq 0 -and $a.Domain -eq 'clientx.local' -and $a.NetBIOS -eq 'CLIENTX' -and $a.FunctionalLevel -eq 'Win2025' -and
        $a.MoreDCs -eq $false -and $a.ComputerName -eq 'DC01' -and $a.TimeZone -eq 'Eastern Standard Time' -and $a.IPAddress -eq '192.0.2.50' -and
        [int]$a.PrefixLength -eq 24 -and $a.Gateway -eq '192.0.2.1' -and (@($a.DnsServers) -join ',') -eq '192.0.2.1' -and $a.DatabasePath -eq 'C:\Windows\NTDS' -and
        $script:Calls.Count -eq 0
}

Test-That 'Enter at the time zone takes Eastern Standard Time, not the server''s own (UTC here)' {
    Reset-Server
    Answer (@($global:StdAnswers[0..4]) + '' + @($global:StdAnswers[6..11]))
    $null = Read-NmNewForestPlan 6>$null
    (Get-NmBuildState).Answers.TimeZone -eq 'Eastern Standard Time'
}

Test-That 'The default time zone follows Settings' {
    Reset-Server
    Set-NmSetting -Key BuildTimeZone -Value 'Central Standard Time' 6>$null
    try {
        Answer (@($global:StdAnswers[0..4]) + '' + @($global:StdAnswers[6..11]))
        $null = Read-NmNewForestPlan 6>$null
    } finally { Clear-NmSetting -Key BuildTimeZone 6>$null }
    (Get-NmBuildState).Answers.TimeZone -eq 'Central Standard Time'
}

Test-That 'The sign-in task starts in the toolkit folder, and the launcher moves there itself' {
    $global:TaskAction = $null
    $file = Join-Path (Join-Path $script:NmModuleRoot 'Core') 'Server.ps1'
    $def = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null).FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Register-NmResumeTask' }, $true)[0]
    $folder = Join-Path ([System.IO.Path]::GetTempPath()) 'DomainController-Security'
    & {
        # The real function from the file, with the ScheduledTasks cmdlets standing in.
        function New-ScheduledTaskAction { param($Execute, $Argument, $WorkingDirectory) $global:TaskAction = [pscustomobject]@{ Argument = $Argument; WorkingDirectory = $WorkingDirectory }; 'action' }
        function New-ScheduledTaskTrigger { param([switch]$AtLogOn) 'trigger' }
        function New-ScheduledTaskPrincipal { param($GroupId, $RunLevel) 'principal' }
        function Register-ScheduledTask { param($TaskName, $Action, $Trigger, $Principal, [switch]$Force, $ErrorAction) }
        . ([scriptblock]::Create($def.Extent.Text))
        Register-NmResumeTask -LauncherPath (Join-Path $folder 'Start-NutmegAD.ps1')
    }
    $launcher = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:NmModuleRoot) 'Start-NutmegAD.ps1') -Raw
    $global:TaskAction.WorkingDirectory -eq $folder -and $global:TaskAction.Argument -match '-NewForest' -and
        $launcher -match 'Set-Location -LiteralPath \$PSScriptRoot'
}

Test-That 'A bad answer is asked again' {
    Reset-Server
    Answer (@('clientx', 'clientx.local', 'CLIENT.X', '') + $global:StdAnswers[2..11])
    $r = Read-NmNewForestPlan 6>$null
    $r.Resume -and (Get-NmBuildState).Answers.NetBIOS -eq 'CLIENTX' -and $script:TestAnswers.Count -eq 0
}

Test-That 'The plan needs the domain short name typed; anything else saves nothing' {
    Reset-Server
    Answer (@($global:StdAnswers[0..10]) + 'yes')
    $r = Read-NmNewForestPlan 6>$null
    ($null -eq $r) -and -not (Get-NmBuildState)
}

Test-That 'A domain that already answers on the network is refused' {
    Reset-Server
    $script:FakeDomainAnswers = $true
    Answer (@($global:StdAnswers[0..10]) + '')
    $r = Read-NmNewForestPlan 6>$null
    ($null -eq $r) -and -not (Get-NmBuildState) -and $script:Calls.Count -eq 0
}

Test-That 'An address something already answers on is refused' {
    Reset-Server
    $script:FakeIpInUse = $true
    Answer (@($global:StdAnswers[0..10]) + '')
    $r = Read-NmNewForestPlan 6>$null
    ($null -eq $r) -and -not (Get-NmBuildState)
}

Test-That 'With two adapters, the DC''s adapter is picked from a list' {
    Reset-Server
    $script:FakeNics = @($script:FakeNics[0], [pscustomobject]@{ Name = 'Ethernet 2'; Index = 7; IPv4 = '198.51.100.9'; PrefixLength = 24; Gateway = '198.51.100.1'; Dns = @(); Dhcp = $true; Mac = 'x'; Description = 'y' })
    Answer (@($global:StdAnswers[0..5]) + '2' + @($global:StdAnswers[6..11]))
    $null = Read-NmNewForestPlan 6>$null
    $a = (Get-NmBuildState).Answers
    [int]$a.AdapterIndex -eq 7 -and $a.IPAddress -eq '198.51.100.50' -and (@($a.DnsServers) -join ',') -eq '198.51.100.1'
}

# ---------------------------------------------------------------------------
# Phase 0
# ---------------------------------------------------------------------------
Test-That 'Phase 0: time zone, name, sign-in task, then the IP last, then a restart; nothing asked' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $rows = @(Invoke-NmNewForestBuild -Resume 6>$null)
    $c = @($script:Calls)
    $c.Count -eq 5 -and $c[0] -eq 'TimeZone Eastern Standard Time' -and $c[1] -eq 'Rename DC01' -and $c[2] -like 'ResumeTask *Start-NutmegAD.ps1' -and
        $c[3] -eq 'StaticIp 4 192.0.2.50/24 gw 192.0.2.1 dns 192.0.2.1' -and $c[4] -eq 'Restart 60' -and
        @($rows | Where-Object Result -eq 'Failed').Count -eq 0 -and $script:TestAnswers.Count -eq 0
}

Test-That 'Phase 0 in the window: the sign-in task reopens the window (-Gui)' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $script:NmGui.Active = $true
    try { $rows = @(Invoke-NmNewForestBuild -Resume) } finally { $script:NmGui.Active = $false; Clear-NmGuiBuffer }
    $c = @($script:Calls)
    ($c[2] -like 'ResumeTask *Start-NutmegAD.ps1 -Gui') -and (@($rows | Where-Object Result -eq 'Failed').Count -eq 0) -and
        ((@($rows | Where-Object Step -eq 'Sign-in task')[0].Detail) -like '*in the window*')
}

Test-That 'The log says what each step did, and when the time zone moves the log''s clock' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    $log = Get-Content -LiteralPath (Get-NmLogPath) -Raw
    $log -match 'Build step done: Static IP - 192\.0\.2\.50/24 via 192\.0\.2\.1' -and $log -match 'Build step done: Computer name - DC01 \(was WIN-7Q2B4K9' -and
        $log -match 'Time zone changed from UTC to Eastern Standard Time: log times from here on' -and $log -notmatch '\(\(no domain\)\)'
}

Test-That 'One log for the whole build: after each restart the session carries on in it' {
    Reset-Server
    $script:NmLogPath = $null
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $first = Get-NmLogPath
    $recorded = (Get-NmBuildState).LogPath
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake
    $script:NmLogPath = $null                      # a new PowerShell after the restart
    Secret @('Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    $second = $script:NmLogPath
    Restart-Fake -Promoted
    $script:NmLogPath = $null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    $third = $script:NmLogPath
    $text = Get-Content -LiteralPath $first -Raw
    $recorded -eq $first -and $second -eq $first -and $third -eq $first -and
        ([regex]::Matches($text, '---- Session continued').Count -eq 2) -and $text -match 'Build step done: Static IP' -and $text -match 'Build step done: Finish'
}

Test-That 'Once the build is finished, the next session starts its own log' {
    $before = $script:NmLogPath
    $script:NmLogPath = $null
    $next = Get-NmLogPath
    (Get-NmBuildState).Finished -and $next -ne $before -and (Split-Path -Leaf $next) -like 'NutmegAD_*.txt'
}

Test-That 'Phase 0 with the name unchanged: no restart, straight on to phase 1 in the same run' {
    Reset-Server
    Answer (@($global:StdAnswers[0..3]) + '' + @($global:StdAnswers[5..11]))   # keep the current name
    $null = Read-NmNewForestPlan 6>$null
    Secret @('Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $rows = @(Invoke-NmNewForestBuild -Resume 6>$null)
    $c = @($script:Calls)
    ($c -notcontains 'Rename WIN-7Q2B4K9') -and ($rows | Where-Object Step -eq 'Restart' | Select-Object -First 1).Detail -like 'not needed*' -and
        ($c -contains 'Features') -and ($c -contains 'Promote') -and $c[-1] -eq 'Restart 60'
}

# ---------------------------------------------------------------------------
# Phase 1
# ---------------------------------------------------------------------------
Test-That 'Phase 1 after the restart: roles, DSRM asked twice, Microsoft''s pre-checks, the forest, a restart' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake
    Secret @('Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $rows = @(Invoke-NmNewForestBuild -Resume 6>$null)
    $c = @($script:Calls)
    $fa = $script:ForestArgsSeen
    (@($rows | Where-Object Phase -eq '0 Prepare').Count -eq 0) -and (($c -join '|') -eq 'Features|PreCheck|Promote|Restart 60') -and
        $fa.DomainName -eq 'clientx.local' -and $fa.DomainNetbiosName -eq 'CLIENTX' -and $fa.ForestMode -eq 'Win2025' -and $fa.DomainMode -eq 'Win2025' -and
        $fa.InstallDns -and $fa.NoRebootOnCompletion -and $fa.Force -and ($fa.SafeModeAdministratorPassword -is [securestring]) -and $script:SecretAnswers.Count -eq 0
}

Test-That 'DSRM: two that do not match are asked again' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake
    Secret @('one', 'two', 'Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    ($script:Calls -contains 'Promote') -and $script:SecretAnswers.Count -eq 0
}

Test-That 'A failed pre-check stops before the forest is made; the re-run skips what is done' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake
    $script:FakePreCheck = 'Error'
    Secret @('Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $first = @(Invoke-NmNewForestBuild -Resume 6>$null)
    $stopped = ($first | Where-Object Result -eq 'Failed').Detail
    $noPromote = $script:Calls -notcontains 'Promote'
    $script:FakePreCheck = 'Success'; $script:Calls.Clear()
    Secret @('Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $second = @(Invoke-NmNewForestBuild -Resume 6>$null)
    $stopped -match 'pre-checks failed' -and $stopped -match 'run the build again' -and $noPromote -and
        ($second | Where-Object Step -eq 'AD DS, DNS and GPMC').Result -eq 'Already done' -and ($script:Calls -contains 'Promote')
}

Test-That 'A domain that starts answering between phases stops the promotion' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake
    $script:FakeDomainAnswers = $true
    $rows = @(Invoke-NmNewForestBuild -Resume 6>$null)
    (($rows | Where-Object Result -eq 'Failed').Detail -match 'answer on the network') -and ($script:Calls -notcontains 'Promote') -and $script:SecretAnswers.Count -eq 0
}

Test-That 'The DSRM password is never written to the state file or the log' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake
    Secret @('Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    $stateText = Get-Content -LiteralPath (Get-NmBuildStatePath) -Raw
    $logText = Get-Content -LiteralPath (Get-NmLogPath) -Raw
    ($stateText -notmatch 'Dsrm-Pass') -and ($logText -notmatch 'Dsrm-Pass')
}

# ---------------------------------------------------------------------------
# After promotion
# ---------------------------------------------------------------------------
Test-That 'After the second restart: the new DC is checked, the sign-in task removed, a record saved' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake
    Secret @('Dsrm-Pass-1!', 'Dsrm-Pass-1!')
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Restart-Fake -Promoted
    $rows = @(Invoke-NmNewForestBuild -Resume 6>$null)
    $verify = $rows | Where-Object Step -eq 'Check the new DC'
    $recordPath = if (($rows | Where-Object Step -eq 'Finish').Detail -match 'record of the build: (.+)$') { $Matches[1] } else { '' }
    $record = @(if ($recordPath -and (Test-Path -LiteralPath $recordPath)) { Get-Item -LiteralPath $recordPath })
    $verify.Result -eq 'Done' -and $verify.Detail -match 'DC01\.clientx\.local is a DC of clientx\.local' -and ($script:Calls -contains 'ResumeTask removed') -and
        (Get-NmBuildState).Finished -and $record.Count -eq 1 -and ($rows | Where-Object Step -eq 'More DCs').Result -eq 'Not planned'
}

Test-That 'A finished build only reports that it is finished' {
    $script:Calls.Clear()
    $rows = @(Invoke-NmNewForestBuild -Resume 6>$null)
    $rows.Count -eq 1 -and $rows[0].Result -eq 'Finished' -and $script:Calls.Count -eq 0
}

Test-That 'Opening a finished build says so and runs nothing (no loop back into it)' {
    Answer @('')
    $r = Read-NmNewForestPlan 6>$null
    ($null -eq $r) -and $script:TestAnswers.Count -eq 0
}

Test-That 'A saved build is offered to continue, not asked again' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    Answer @('')
    $r = Read-NmNewForestPlan 6>$null
    $r.Resume -and $script:TestAnswers.Count -eq 0
}

Test-That 'WhatIf lists the plan and changes nothing' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $rows = @(Invoke-NmNewForestBuild -Resume -WhatIf 6>$null)
    $rows.Count -ge 9 -and @($rows | Where-Object Result -ne 'WhatIf: not changed').Count -eq 0 -and $script:Calls.Count -eq 0
}

Test-That 'The build refuses to run in PowerShell 7' {
    Reset-Server
    $script:FakeWinPs = $false
    $threw = $false
    try { $null = Invoke-NmNewForestBuild -Answers @{ Domain = 'clientx.local' } } catch { $threw = $_.Exception.Message -match 'Windows PowerShell' }
    $threw -and -not (Get-NmBuildState)
}

Test-That 'Plan approval ends with the run: later changes ask again' {
    Reset-Server
    Answer $global:StdAnswers
    $null = Read-NmNewForestPlan 6>$null
    $null = Invoke-NmNewForestBuild -Resume 6>$null
    Answer @('n')
    $asked = -not (Confirm-NmChange -Action 'Something later' -Targets @('x') 6>$null)
    $asked -and $script:TestAnswers.Count -eq 0 -and -not $script:NmPlanApproved
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
