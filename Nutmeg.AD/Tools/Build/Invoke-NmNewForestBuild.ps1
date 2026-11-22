<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.7.5

.SYNOPSIS
    Builds the first DC of a brand-new forest on a freshly installed Windows Server (phases 0 and 1).

.DESCRIPTION
    - Runs only on a workgroup server, in Windows PowerShell 5.1, as administrator, and only when no
      domain of the chosen name answers. Existing domains use the individual tools.
    - Checks the server first (pre-flight), then asks everything once: domain and NetBIOS name,
      computer name, network adapter, static IP (default .50 in the current subnet), prefix,
      gateway, DNS before promotion, time zone, functional level, database folders, and whether
      more DCs are planned. Shows the whole plan; typing the domain's short name approves it.
    - Phase 0: time zone, computer name, a sign-in task that resumes the build, then the static IP
      (last, because it drops an RDP session to the old address). Restarts if the name changed.
    - Phase 1: installs AD DS, DNS, GPMC and the AD module; asks for the DSRM password (never
      saved); runs Microsoft's pre-checks; creates the forest; restarts.
    - After the restart: checks the new DC answers for the domain, removes the sign-in task and
      saves the answers as a record of the build (C:\Temp).
    - Each step is recorded in C:\Temp\NutmegAD\NewForest\State.json. Run it again after a failure
      or a restart and it skips what is done. Phases 2 to 5 (DNS, time, OUs, GPOs, report) come in
      later versions.

.EXAMPLE
    .\Start-NutmegAD.ps1 -NewForest

.EXAMPLE
    Invoke-NmTool -Id new-forest

.VERSIONING
    0.7.5 - The build ends with a report (HTML and PDF): the build, network, server, server check, every step with its times,
            the new DC's health and dcdiag (new step), next steps.
    0.7.4 - A live step list while the build runs (Start-NmStepList), with what the installs report as they go.
    0.7.3 - Restart steps saved as done before their notice (a restart loop on the VM); one that finds the server already
            restarted counts as done. Results start with what is being built (Build: <domain>) and end with the steps still to do.
    0.7.2 - Server check first in its own pop-up (window); a pending restart ends phase 0; before AD DS a pending restart stops
            the build with Restart now / in 30 minutes (reminders every 5 minutes).
    0.7.1 - Answers saved as they are given and checked again when the build carries on; domain and IP checked at their
          question; time zone from a list of names; clearer questions; the plan shows the new forest; a card per phase;
          a restart notice.
    0.7 - The server check has a heading (the window shows it as a table in the first question).
    0.6 - Runs in the window too (Start-NutmegAD.ps1 -NewForest -Gui); the sign-in task then reopens the window.
    0.5 - Sign-in task starts in the toolkit folder; the finished message says what to run next.
    0.4 - Time zone defaults to Eastern Standard Time (Settings > New forest build), not the server's own.
    0.3 - The log says what each step did, and when the time zone change moves the log's clock.
    0.2 - Opens on a clean screen with the toolkit header (issue #6).
    0.1 - Pre-flight, questions, phase 0 (prepare the server) and phase 1 (promote), then a check of the new DC.
#>

$NmTool = @{
    Name     = 'New Forest Build (first DC)'
    Id       = 'new-forest'
    Category = 'Build'
    Area     = 'build/First DC'
    Synopsis = 'A fresh workgroup server to the first DC of a new forest: IP, name, AD DS, promotion'
    Version  = '0.7.5'
    Kind     = 'Change'
    Services = @()
    Roles    = @('Local administrator on a workgroup server')
    Prompt   = 'Read-NmNewForestPlan'
    Entry    = 'Invoke-NmNewForestBuild'
    Columns  = @('Phase', 'Step', 'Result', 'Detail')
    CardGroup = @('Phase', 'Step')   # the window: a card per phase, a line per step
}

# The phases as the results show them (the window draws a card per phase).
$script:NmPhase0 = 'Phase 0: Prepare the server'
$script:NmPhase1 = 'Phase 1: Promote to the first DC'

$script:NmForestLevels = [ordered]@{
    Win2025      = 'Windows Server 2025 (every DC will run 2025)'
    WinThreshold = 'Windows Server 2016 (older DCs can join later)'
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
function Get-NmNewForestPreflight {
    <#
    .SYNOPSIS
        The checks a server must pass before the build changes anything. Rows: Check, Result, Detail.
        Result is OK, Warning or Not ready; any Not ready stops the build.
    #>
    [CmdletBinding()]
    param()
    $row = { param($c, $r, $d) [pscustomobject]@{ Check = $c; Result = $r; Detail = "$d" } }

    $winPs = Test-NmWindowsPowerShell
    & $row 'Windows PowerShell 5.1' $(if ($winPs) { 'OK' } else { 'Not ready' }) $(if ($winPs) { "$($PSVersionTable.PSVersion)" } else { 'start it with Start-NutmegAD.ps1 -NewForest, which uses Windows PowerShell for the server roles' })
    $elev = Test-NmElevated
    & $row 'Running as administrator' $(if ($elev) { 'OK' } else { 'Not ready' }) $(if ($elev) { 'yes' } else { 'start PowerShell as administrator' })

    try {
        $os = Get-NmOsInfo
        $okOs = ($os.ProductType -eq 3 -and $os.Build -ge 14393)
        $why = if ($os.ProductType -eq 2) { 'this is already a domain controller' } elseif ($os.ProductType -ne 3) { 'not Windows Server' } elseif ($os.Build -lt 14393) { 'Windows Server 2016 or later is needed' } else { '' }
        & $row 'Windows Server 2016 or later' $(if ($okOs) { 'OK' } else { 'Not ready' }) "$($os.Caption) (build $($os.Build))$(if ($why) { ": $why" })"
    } catch { & $row 'Windows Server 2016 or later' 'Not ready' $_.Exception.Message }

    try {
        $pc = Get-NmLocalComputer
        & $row 'Not joined to a domain' $(if (-not $pc.PartOfDomain) { 'OK' } else { 'Not ready' }) $(if ($pc.PartOfDomain) { "joined to $($pc.Domain): use the individual tools on existing domains" } else { "$($pc.Name) is in a workgroup" })
    } catch { & $row 'Not joined to a domain' 'Not ready' $_.Exception.Message }

    $pending = $false
    try { $pending = Test-NmPendingReboot } catch { $pending = $false }
    & $row 'No restart pending' $(if ($pending) { 'Warning' } else { 'OK' }) $(if ($pending) { 'Windows is waiting for a restart: the build restarts the server before installing AD DS' } else { 'none' })

    try {
        $free = Get-NmFreeSpaceGB
        & $row 'Free space on the system drive' $(if ($free -ge 20) { 'OK' } else { 'Warning' }) "$free GB$(if ($free -lt 20) { ' (20 GB or more recommended)' })"
    } catch { & $row 'Free space on the system drive' 'Warning' $_.Exception.Message }

    $blocked = @(Get-NmBlockedFile)
    & $row 'Toolkit files unblocked' $(if ($blocked.Count) { 'Not ready' } else { 'OK' }) $(if ($blocked.Count) { "$($blocked.Count) file(s) still marked as downloaded: the restart would not run them. Run: Get-ChildItem -Recurse | Unblock-File" } else { 'yes' })

    $nics = @()
    try { $nics = @(Get-NmNetAdapterInfo) } catch { $nics = @() }
    $nicResult = if ($nics.Count -eq 0) { 'Not ready' } elseif ($nics.Count -gt 1) { 'Warning' } else { 'OK' }
    $nicDetail = if ($nics.Count -eq 0) { 'no connected network adapter' } elseif ($nics.Count -gt 1) { "$($nics.Count) connected: Microsoft advises one network for a DC (nothing is changed)" } else { "$($nics[0].Name), $(if ($nics[0].Dhcp) { 'DHCP' } else { 'static' }) $($nics[0].IPv4)" }
    & $row 'Network adapter' $nicResult $nicDetail

    try { & $row 'Hypervisor' 'OK' (Get-NmHypervisor) } catch { & $row 'Hypervisor' 'OK' 'unknown' }
}

# ---------------------------------------------------------------------------
# The questions
# ---------------------------------------------------------------------------
function Test-NmDomainNameText {
    # A DNS name with at least two labels (clientx.local). Single-label names are refused.
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Text)
    $t = "$Text".Trim().ToLower()
    return ($t.Length -le 64 -and $t -match '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$' -and $t -notmatch '^\d+(\.\d+)+$')
}

function Test-NmNetbiosText {
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Text)
    return ("$Text".Trim() -cmatch '^[A-Z0-9][A-Z0-9-]{0,14}$')
}

function Test-NmComputerNameText {
    # 1 to 15 letters, digits and hyphens, not all digits.
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Text)
    $t = "$Text".Trim()
    return ($t -match '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$' -and $t -notmatch '^\d+$')
}

function Read-NmCheckedInput {
    # Read-NmInput until the answer passes the test; shows why when it does not. The test returns
    # $true, $false (the -Why message is shown), or a text that says why this answer is refused.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Prompt, [string]$Default, [Parameter(Mandatory)][scriptblock]$Test, [Parameter(Mandatory)][string]$Why)
    while ($true) {
        $a = "$(Read-NmInput -Prompt $Prompt -Default $Default)".Trim()
        $r = if ($a) { & $Test $a } else { $false }
        if ($r -is [string]) { Write-Host $r -ForegroundColor Red; continue }
        if ($a -and $r) { return $a }
        Write-Host $Why -ForegroundColor Red
    }
}

function Test-NmDraftAnswer {
    # A saved answer is used again only if it still passes its question's test.
    param($Value, [scriptblock]$Test)
    if ($null -eq $Value -or "$Value" -eq '') { return $false }
    $r = & $Test $Value
    return ($r -is [bool] -and $r)
}

function Get-NmTimeZoneChoice {
    <#
    .SYNOPSIS
        The time zones offered by name, the default first: Eastern, Central, Mountain, Arizona,
        Pacific, Alaska, Hawaii, Atlantic and UTC, each with Windows's own display name. Only
        zones this server knows are listed.
    #>
    [CmdletBinding()]
    param([string]$Default)
    $ids = @('Eastern Standard Time', 'Central Standard Time', 'Mountain Standard Time', 'US Mountain Standard Time', 'Pacific Standard Time',
             'Alaskan Standard Time', 'Hawaiian Standard Time', 'Atlantic Standard Time', 'UTC')
    if ($Default) { $ids = @($Default) + @($ids | Where-Object { $_ -ne $Default }) }
    foreach ($id in $ids) {
        if (-not (Test-NmTimeZoneId $id)) { continue }
        $name = $id
        try { $name = [System.TimeZoneInfo]::FindSystemTimeZoneById($id).DisplayName } catch { $null = $_ }
        if (-not $name -or $name -eq $id) { $name = $id }
        [pscustomobject]@{ Id = $id; Name = $name }
    }
}

function Read-NmNewForestAnswer {
    <#
    .SYNOPSIS
        Asks every question of the build, with defaults from this server. Returns a hashtable, or $null.
    .DESCRIPTION
        - Each answer is saved as it is given (Save-NmBuildDraft), so a run that stops (Cancel, a
          closed window) carries on from there.
        - -Draft: the answers saved before. Each is checked again (the domain must still be free, the
          IP must still not answer, and so on); one that still passes is used without asking.
        - The domain and the IP are checked at their question: an answer already in use on the
          network is refused there and asked again.
    #>
    [CmdletBinding()]
    param([System.Collections.IDictionary]$Draft)
    if ($null -eq $Draft) { $Draft = @{} }
    $pc = Get-NmLocalComputer
    $a = [ordered]@{}
    $script:NmDraftUsed = 0
    # Saved answer still good: use it and say so; otherwise ask. Each answer is saved straight away.
    $answer = {
        param([string]$Name, [string]$Label, [scriptblock]$Test, [scriptblock]$Ask, [scriptblock]$Show)
        $v = $null
        if ($Draft.Contains($Name) -and (Test-NmDraftAnswer -Value $Draft[$Name] -Test $Test)) {
            $v = $Draft[$Name]
            $shown = if ($Show) { & $Show $v } else { "$v" }
            Write-Host "$($Label): $shown (saved answer)" -ForegroundColor DarkGray
            $script:NmDraftUsed++
        } else {
            $v = & $Ask
        }
        $a[$Name] = $v
        Save-NmBuildDraft -Answers $a
        return $v
    }

    Write-Host ''
    Write-Host 'The new forest' -ForegroundColor Cyan
    $domainTest = {
        param($x)
        if (-not (Test-NmDomainNameText "$x")) { return $false }
        if (Test-NmDomainAnswers -Domain "$x".ToLower()) { return "Domain controllers for $("$x".ToLower()) already answer on this network. The build only creates new forests: use another name." }
        return $true
    }
    $null = & $answer 'Domain' 'Domain name' $domainTest {
        (Read-NmCheckedInput -Prompt 'Domain name (DNS, for example clientx.local)' -Test $domainTest -Why 'Use a DNS name with at least two parts, such as clientx.local.').ToLower()
    }
    # A new domain name: the saved NetBIOS name went with the old one, so it is asked again.
    if ($Draft.Contains('Domain') -and "$($Draft['Domain'])" -ne "$($a.Domain)" -and $Draft.Contains('NetBIOS')) { $Draft.Remove('NetBIOS') }
    $nbDefault = (($a.Domain -split '\.')[0]).ToUpper()
    if ($nbDefault.Length -gt 15) { $nbDefault = $nbDefault.Substring(0, 15) }
    $nbTest = { param($x) Test-NmNetbiosText "$x".ToUpper() }
    $null = & $answer 'NetBIOS' 'NetBIOS name' $nbTest {
        (Read-NmCheckedInput -Prompt 'NetBIOS name' -Default $nbDefault -Test $nbTest -Why 'Up to 15 letters, digits or hyphens, no dots.').ToUpper()
    }

    $lv = @($script:NmForestLevels.Keys)
    $null = & $answer 'FunctionalLevel' 'Functional level' { param($x) $lv -contains "$x" } {
        $opts = @(for ($i = 0; $i -lt $lv.Count; $i++) { [pscustomobject]@{ Key = "$($i + 1)"; Label = $script:NmForestLevels[$lv[$i]] } })
        $pick = Show-NmMenu -Title 'Forest and domain functional level' -Back -NoClear -Options $opts -Default '1'
        if ($pick -eq 'B') { throw (New-Object System.OperationCanceledException 'Back from the questions.') }
        $lv[[int]$pick - 1]
    } { param($x) $script:NmForestLevels["$x"] }
    $null = & $answer 'MoreDCs' 'More than one DC' { param($x) $x -is [bool] } {
        Read-NmYesNo -Prompt 'Will this domain have more than one DC?' -Default 'Y'
    } { param($x) if ($x) { 'yes' } else { 'no' } }

    Write-Host ''
    Write-Host 'This server' -ForegroundColor Cyan
    $nameTest = { param($x) Test-NmComputerNameText "$x" }
    $null = & $answer 'ComputerName' 'Computer name' $nameTest {
        (Read-NmCheckedInput -Prompt 'Computer name' -Default "$($pc.Name)" -Test $nameTest -Why '1 to 15 letters, digits or hyphens, not only digits.').ToUpper()
    }
    $tzDefault = "$(Get-NmSetting -Key BuildTimeZone)"   # Eastern Standard Time unless Settings say otherwise
    if (-not (Test-NmTimeZoneId $tzDefault)) { $tzDefault = Get-NmTimeZoneId }
    $null = & $answer 'TimeZone' 'Time zone' { param($x) Test-NmTimeZoneId "$x" } {
        $zones = @(Get-NmTimeZoneChoice -Default $tzDefault)
        $i = 0
        $opts = @(foreach ($z in $zones) { $i++; [pscustomobject]@{ Key = "$i"; Label = $z.Name } })
        $opts += [pscustomobject]@{ Key = 'A'; Label = 'Another time zone (type its name)' }
        $pick = Show-NmMenu -Title 'Time zone' -Back -NoClear -Options $opts -Default '1'
        if ($pick -eq 'B') { throw (New-Object System.OperationCanceledException 'Back from the questions.') }
        if ($pick -eq 'A') {
            Read-NmCheckedInput -Prompt 'Time zone name, as Get-TimeZone -ListAvailable shows it (for example Eastern Standard Time)' -Default $tzDefault -Test { param($x) Test-NmTimeZoneId $x } -Why 'Windows has no time zone by that name. Get-TimeZone -ListAvailable lists them.'
        } else { $zones[[int]$pick - 1].Id }
    }

    $nics = @(Get-NmNetAdapterInfo)
    if (-not $nics.Count) { Write-NmLog 'No connected network adapter.' -Level ERROR; return $null }
    $nic = $nics[0]
    if ($nics.Count -gt 1) {
        $saved = @($nics | Where-Object { $Draft.Contains('AdapterIndex') -and $_.Index -eq [int]$Draft['AdapterIndex'] })
        if ($saved.Count) {
            $nic = $saved[0]
            Write-Host "Network adapter: $($nic.Name) (saved answer)" -ForegroundColor DarkGray
        } else {
            $i = 0
            $nOpts = @(foreach ($n in $nics) { $i++; [pscustomobject]@{ Key = "$i"; Label = $n.Name; Detail = "$($n.IPv4)/$($n.PrefixLength), $($n.Mac), $($n.Description)" } })
            $p = Show-NmMenu -Title 'Network adapter for the DC' -Back -NoClear -Options $nOpts -Default '1'
            if ($p -eq 'B') { throw (New-Object System.OperationCanceledException 'Back from the questions.') }
            $nic = $nics[[int]$p - 1]
        }
    }
    # Another adapter than the saved answers were for: its network answers are asked again.
    if ($Draft.Contains('AdapterIndex') -and [int]$Draft['AdapterIndex'] -ne [int]$nic.Index) {
        foreach ($k in @('IPAddress', 'PrefixLength', 'Gateway', 'DnsServers')) { if ($Draft.Contains($k)) { $Draft.Remove($k) } }
    }
    $a.AdapterIndex = $nic.Index
    $a.AdapterName = $nic.Name
    $a.CurrentIp = $nic.IPv4
    Save-NmBuildDraft -Answers $a

    Write-Host ''
    Write-Host "Network ($($nic.Name), now $(if ($nic.Dhcp) { 'DHCP' } else { 'static' }) $($nic.IPv4)/$($nic.PrefixLength))" -ForegroundColor Cyan
    $ipTest = {
        param($x)
        if (-not (Test-NmIPv4Text "$x")) { return $false }
        if ("$x" -ne "$($nic.IPv4)" -and (Test-NmIpInUse -IPAddress "$x")) { return "Something already answers on $x. Pick another address." }
        return $true
    }
    $null = & $answer 'IPAddress' 'Static IP' $ipTest {
        Read-NmCheckedInput -Prompt 'Static IP for the DC' -Default (Get-NmSuggestedDcIp -CurrentIp $nic.IPv4) -Test $ipTest -Why 'Type an IPv4 address such as 192.0.2.50.'
    }
    $prefixTest = { param($x) "$x" -match '^\d+$' -and [int]$x -ge 8 -and [int]$x -le 30 }
    $null = & $answer 'PrefixLength' 'Prefix length' $prefixTest {
        [int](Read-NmCheckedInput -Prompt 'Prefix length (24 = 255.255.255.0)' -Default "$($nic.PrefixLength)" -Test $prefixTest -Why 'A number from 8 to 30 (24 for 255.255.255.0).')
    }
    $gwTest = { param($x) Test-NmIPv4Text "$x" }
    $null = & $answer 'Gateway' 'Default gateway' $gwTest {
        Read-NmCheckedInput -Prompt 'Default gateway' -Default $nic.Gateway -Test $gwTest -Why 'Type an IPv4 address.'
    }
    $dnsDefault = if (@($nic.Dns).Count) { @($nic.Dns) -join ', ' } else { $a.Gateway }
    $dnsListTest = { param($x) @($x).Count -gt 0 -and @(@($x) | Where-Object { -not (Test-NmIPv4Text "$_") }).Count -eq 0 }
    $null = & $answer 'DnsServers' 'DNS servers until promotion' $dnsListTest {
        Write-Host 'Separate several with commas. After promotion the DC uses its own DNS.' -ForegroundColor DarkGray
        $dnsText = Read-NmCheckedInput -Prompt 'DNS servers until promotion' -Default $dnsDefault -Test { param($x) @($x -split '[,\s]+' | Where-Object { $_ } | Where-Object { -not (Test-NmIPv4Text $_) }).Count -eq 0 } -Why 'IPv4 addresses, separated by commas.'
        , @($dnsText -split '[,\s]+' | Where-Object { $_ })
    } { param($x) @($x) -join ', ' }
    $a.DnsServers = @($a.DnsServers)

    Write-Host ''
    Write-Host 'Folders' -ForegroundColor Cyan
    $folderTest = { param($x) "$x" -match '^[A-Za-z]:\\' }
    if ($Draft.Contains('DatabasePath') -and (Test-NmDraftAnswer $Draft['DatabasePath'] $folderTest) -and (Test-NmDraftAnswer $Draft['LogPath'] $folderTest) -and (Test-NmDraftAnswer $Draft['SysvolPath'] $folderTest)) {
        $a.DatabasePath = $Draft['DatabasePath']; $a.LogPath = $Draft['LogPath']; $a.SysvolPath = $Draft['SysvolPath']
        Write-Host "Folders: database $($a.DatabasePath), logs $($a.LogPath), SYSVOL $($a.SysvolPath) (saved answer)" -ForegroundColor DarkGray
        $script:NmDraftUsed++
    } else {
        $a.DatabasePath = 'C:\Windows\NTDS'; $a.LogPath = 'C:\Windows\NTDS'; $a.SysvolPath = 'C:\Windows\SYSVOL'
        Write-Host 'Database and logs in C:\Windows\NTDS, SYSVOL in C:\Windows\SYSVOL.' -ForegroundColor DarkGray
        if (-not (Read-NmYesNo -Prompt 'Use the default database, log and SYSVOL folders?' -Default 'Y')) {
            $a.DatabasePath = Read-NmInput -Prompt 'Database folder' -Default $a.DatabasePath
            $a.LogPath = Read-NmInput -Prompt 'Log folder' -Default $a.LogPath
            $a.SysvolPath = Read-NmInput -Prompt 'SYSVOL folder' -Default $a.SysvolPath
        }
    }
    Save-NmBuildDraft -Answers $a
    return $a
}

function Get-NmNewForestPlanText {
    # The plan, one line per step, for the approval screen.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Answers)
    $a = $Answers
    $rename = ("$($a.ComputerName)" -ne "$((Get-NmLocalComputer).Name)")
    @(
        "Time zone: $($a.TimeZone)"
        "Computer name: $($a.ComputerName)$(if ($rename) { " (now $((Get-NmLocalComputer).Name))" } else { ' (unchanged)' })"
        'Sign-in task: reopens the build after each restart (removed at the end)'
        "Static IP on $($a.AdapterName): $($a.IPAddress)/$($a.PrefixLength), gateway $($a.Gateway), DNS $(@($a.DnsServers) -join ', ') (now $($a.CurrentIp))"
        $(if ($rename) { 'Restart (for the new name)' } elseif (Test-NmPendingRebootSafe) { 'Restart (Windows is waiting for one)' } else { 'No restart needed yet' })
        'Install AD DS, DNS, Group Policy Management and the AD module'
        "New forest $($a.Domain) ($($a.NetBIOS)), level $($a.FunctionalLevel), DNS on this DC; DSRM password asked then, never saved"
        "Database $($a.DatabasePath), logs $($a.LogPath), SYSVOL $($a.SysvolPath)"
        'Restart, then check the new DC and remove the sign-in task'
        "More DCs planned: $(if ($a.MoreDCs) { 'yes' } else { 'no' })"
    )
}

function Read-NmNewForestPlan {
    <#
    .SYNOPSIS
        The tool's questions: continues a saved build, or checks the server, asks everything and
        shows the plan for approval. Returns the entry's parameters, or $null.
    #>
    [CmdletBinding()]
    param()
    Show-NmHeader -Title 'New Forest Build (first DC)' -Clear
    $state = Get-NmBuildState
    if ($state -and $state.Answers) {
        $done = @($state.Steps.PSObject.Properties | Where-Object { "$($_.Value.Status)" -eq 'Done' }).Count
        Write-Host "A build of $($state.Answers.Domain) is saved on this server (started $($state.Started), $done step(s) done$(if ($state.Finished) { ", finished $($state.Finished)" }))." -ForegroundColor Cyan
        if ($state.Finished) {
            Write-Host 'This server''s build is finished.' -ForegroundColor Green
            Write-Host 'For the toolkit''s other tools, run: .\Start-NutmegAD.ps1' -ForegroundColor DarkGray
            Wait-NmKey
            return $null
        }
        if (Read-NmYesNo -Prompt 'Continue it?' -Default 'Y') { return @{ Resume = $true } }
        return $null
    }

    Write-NmLog 'Checking this server before anything changes...' -Level INFO
    $checks = @(Get-NmNewForestPreflight)
    Write-Host ''
    Write-Host 'Server check' -ForegroundColor Cyan
    $checks | Format-Table Check, Result, Detail -AutoSize -Wrap | Out-Host
    # In the window the check is its own pop-up, first, before any question.
    if ($script:NmGui -and $script:NmGui.Active -and -not @($checks | Where-Object Result -eq 'Not ready').Count) { Wait-NmKey }
    if (@($checks | Where-Object Result -eq 'Not ready').Count) {
        Write-NmLog 'This server is not ready for the build (see Not ready above). Nothing was changed.' -Level ERROR
        Wait-NmKey
        return $null
    }

    # Answers from a run that stopped before the plan was approved: carry on with them (each is
    # checked again as it comes up), or start the questions again.
    $draft = Get-NmBuildDraft
    if ($draft -and $draft.Contains('Domain')) {
        Write-Host ''
        Write-Host "Answers saved on $($draft.Saved): $($draft.Domain)$(if ($draft.Contains('ComputerName')) { ", $($draft.ComputerName)" })$(if ($draft.Contains('IPAddress')) { ", $($draft.IPAddress)" })." -ForegroundColor White
        if (-not (Read-NmYesNo -Prompt 'Carry on with those answers (each is checked again)?' -Default 'Y')) {
            Remove-NmBuildDraft
            $draft = $null
            Write-NmLog 'Saved answers cleared: the questions start again.' -Level INFO -NoConsole
        }
    } else { $draft = $null }

    try {
        $a = Read-NmNewForestAnswer -Draft $draft
    } catch [System.OperationCanceledException] {
        Write-NmLog "Questions stopped. The answers so far are saved: run the build again to carry on." -Level INFO
        if ("$($_.Exception.Message)" -eq 'Back from the questions.') { return $null }
        throw
    }
    if (-not $a) { return $null }
    if ($script:NmDraftUsed) { Write-NmLog "$script:NmDraftUsed saved answer(s) checked again and used." -Level INFO -NoConsole }

    $plan = @(Get-NmNewForestPlanText -Answers $a)
    $word = ($a.Domain -split '\.')[0]
    $facts = @("New forest: $($a.Domain) ($($a.NetBIOS))", "This server: $((Get-NmLocalComputer).Name)$(if ("$($a.ComputerName)" -ne "$((Get-NmLocalComputer).Name)") { " > $($a.ComputerName)" })")
    if (-not (Confirm-NmChange -Action "New Forest Build: $($a.Domain)" -Targets $plan -DomainWide -ConfirmWord $word -Facts $facts)) { return $null }

    $state = New-NmBuildState
    $state.Answers = [pscustomobject]$a
    # For the report: the server check as it was, and who ran the build.
    $state | Add-Member -NotePropertyName Preflight -NotePropertyValue @($checks | ForEach-Object { [pscustomobject]@{ Check = $_.Check; Result = $_.Result; Detail = $_.Detail } }) -Force
    $state | Add-Member -NotePropertyName RunBy -NotePropertyValue "$([Environment]::UserDomainName)\$([Environment]::UserName)" -Force
    Save-NmBuildState -State $state
    Remove-NmBuildDraft   # approved: the build's own state takes over
    return @{ Resume = $true }
}

# ---------------------------------------------------------------------------
# The build
# ---------------------------------------------------------------------------
function Test-NmPendingRebootSafe {
    # Test-NmPendingReboot, false when it cannot be read.
    try { return [bool](Test-NmPendingReboot) } catch { return $false }
}

function Invoke-NmPendingRestart {
    <#
    .SYNOPSIS
        Windows is still waiting for a restart before AD DS is installed: nothing is installed. The
        technician restarts now, or within 30 minutes with a reminder every 5 minutes, or not at all
        (restarts it later themselves). The sign-in task carries the build on after the restart.
        Returns what was chosen, for the results.
    #>
    [CmdletBinding()]
    param([string]$SignInAs = 'Administrator', [int]$Minutes = 30, [int]$RemindEvery = 5)
    Write-Host ''
    Write-Host 'Windows is waiting for a restart' -ForegroundColor Cyan
    Write-Host 'AD DS cannot be installed until the server restarts. Nothing has been installed.' -ForegroundColor Red
    $pick = Show-NmMenu -Title 'Restart the server' -Back -NoClear -Default '1' -Options @(
        [pscustomobject]@{ Key = '1'; Label = 'Restart now'; Detail = 'in 60 seconds' }
        [pscustomobject]@{ Key = '2'; Label = "Restart in $Minutes minutes"; Detail = "a reminder every $RemindEvery minutes" }
    )
    if ($pick -eq '1') {
        Write-NmLog 'Restart before AD DS: now.' -Level INFO
        Restart-NmServer -Seconds 60
        Show-NmRestartNotice -SignInAs $SignInAs
        return 'restarting in 60 seconds; the build carries on after you sign in'
    }
    if ($pick -ne '2') {
        Write-NmLog 'Restart before AD DS: not now. Restart the server, sign in, and the build carries on.' -Level WARN
        return 'not restarted: restart the server yourself; the build carries on after you sign in'
    }

    Write-NmLog "Restart before AD DS: in $Minutes minutes." -Level INFO
    $deadline = (Get-NmNow).AddMinutes($Minutes)
    Restart-NmServer -Seconds ($Minutes * 60)
    while ($true) {
        $left = [int][Math]::Ceiling(($deadline - (Get-NmNow)).TotalMinutes)
        $wait = [Math]::Min($RemindEvery, $left - 1)
        if ($wait -lt 1) { break }
        Wait-NmRestartReminder -Seconds ($wait * 60) -Status "The server restarts in $left minutes"
        $left = [int][Math]::Ceiling(($deadline - (Get-NmNow)).TotalMinutes)
        if ($left -le 1) { break }
        Write-Host ''
        Write-Host "Reminder: the server restarts in $left minutes" -ForegroundColor Cyan
        Write-Host "Sign in as $SignInAs afterwards and the build carries on." -ForegroundColor Yellow
        $r = Show-NmMenu -Title "The server restarts in $left minutes" -Back -NoClear -Default '1' -Options @(
            [pscustomobject]@{ Key = '1'; Label = 'Remind me again'; Detail = "in $([Math]::Min($RemindEvery, $left - 1)) minutes" }
            [pscustomobject]@{ Key = '2'; Label = 'Restart now'; Detail = 'in 60 seconds' }
        )
        if ($r -eq '2') {
            Write-NmLog 'Restart before AD DS: brought forward to now.' -Level INFO
            Stop-NmScheduledRestart
            Restart-NmServer -Seconds 60
            Show-NmRestartNotice -SignInAs $SignInAs
            return 'restarting in 60 seconds (brought forward); the build carries on after you sign in'
        }
        if ($r -eq 'B') { break }   # no more reminders; the restart stays scheduled
    }
    return "restart scheduled at $($deadline.ToString('HH:mm')); the build carries on after you sign in"
}

function Get-NmNewForestInfoRow {
    <#
    .SYNOPSIS
        What is being built, as result rows (the window's first card, "Build: <domain>"): the
        forest, this server, the network, the folders, and when it started with which log.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Answers, $State)
    $a = $Answers
    $phase = "Build: $($a.Domain)"
    $level = if ($script:NmForestLevels.Contains("$($a.FunctionalLevel)")) { $script:NmForestLevels["$($a.FunctionalLevel)"] } else { "$($a.FunctionalLevel)" }
    $row = { param($step, $detail) [pscustomobject]@{ Phase = $phase; Step = $step; Result = ''; Detail = $detail } }
    & $row 'Forest' "$($a.Domain) ($($a.NetBIOS)), $level; more DCs planned: $(if ($a.MoreDCs) { 'yes' } else { 'no' })"
    & $row 'This server' "$($a.ComputerName), time zone $($a.TimeZone)"
    & $row 'Network' "$($a.IPAddress)/$($a.PrefixLength) on $($a.AdapterName), gateway $($a.Gateway), DNS until promotion $(@($a.DnsServers) -join ', ')"
    & $row 'Folders' "database $($a.DatabasePath), logs $($a.LogPath), SYSVOL $($a.SysvolPath)"
    if ($State) {
        & $row 'Started' "$($State.Started)$(if ($State.LogPath) { "; log $($State.LogPath)" })"
    }
}

# Every step of phases 0 and 1, in order, for the "still to do" card.
$script:NmBuildStepList = @(
    @{ Name = 'TimeZone'; Phase = 0; Label = 'Time zone' }
    @{ Name = 'ComputerName'; Phase = 0; Label = 'Computer name' }
    @{ Name = 'ResumeTask'; Phase = 0; Label = 'Sign-in task' }
    @{ Name = 'StaticIp'; Phase = 0; Label = 'Static IP' }
    @{ Name = 'PrepareRestart'; Phase = 0; Label = 'Restart' }
    @{ Name = 'Features'; Phase = 1; Label = 'AD DS, DNS and GPMC'; Detail = 'install the roles' }
    @{ Name = 'Promote'; Phase = 1; Label = 'New forest'; Detail = 'DSRM password (asked then, never saved), Microsoft''s pre-checks, then the forest' }
    @{ Name = 'PromoteRestart'; Phase = 1; Label = 'Restart'; Detail = 'sign in as <NETBIOS>\Administrator afterwards' }
    @{ Name = 'Verify'; Phase = 1; Label = 'Check the new DC' }
    @{ Name = 'Health'; Phase = 1; Label = 'DC health and dcdiag'; Detail = 'services, SYSVOL, DNS, FSMO roles, time, dcdiag (about a minute)' }
    @{ Name = 'Finish'; Phase = 1; Label = 'Finish'; Detail = 'remove the sign-in task, save a record of the build' }
)

function Get-NmNewForestStepItem {
    # The build's steps for the live step list (Start-NmStepList): phase as the group, done ones ticked.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Answers, [Parameter(Mandatory)]$State)
    foreach ($s in $script:NmBuildStepList) {
        $done = Test-NmBuildStepDone -State $State -Name $s.Name
        [pscustomobject]@{
            Name   = $s.Name
            Label  = $(if ($s.Name -eq 'Promote') { "New forest $($Answers.Domain)" } else { $s.Label })
            Group  = $(if ($s.Phase -eq 0) { $script:NmPhase0 } else { $script:NmPhase1 })
            Status = $(if ($done) { 'Done' } else { 'Waiting' })
            Detail = $(if ($done) { "$($State.Steps.($s.Name).Detail)" } else { "$($s.Detail)".Replace('<NETBIOS>', "$($Answers.NetBIOS)") })
        }
    }
}

function Add-NmBuildToDoRow {
    # Adds the steps not done yet as rows of a "Still to do" card, so the results show what comes next.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Answers, [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Rows)
    foreach ($s in $script:NmBuildStepList) {
        if (Test-NmBuildStepDone -State $State -Name $s.Name) { continue }
        $label = if ($s.Name -eq 'Promote') { "New forest $($Answers.Domain)" } else { $s.Label }
        $phaseName = if ($s.Phase -eq 0) { $script:NmPhase0 } else { $script:NmPhase1 }
        $detail = "$($s.Detail)".Replace('<NETBIOS>', "$($Answers.NetBIOS)")
        $Rows.Add([pscustomobject]@{ Phase = 'Still to do'; Step = $label; Result = 'Next'; Detail = "$(($phaseName -split ':')[0])$(if ($detail) { ": $detail" })" })
    }
}

function Get-NmRestartSince {
    <#
    .SYNOPSIS
        When this server last started, if that was after the build step -After finished (so the
        restart it needed has happened); '' otherwise. A restart step left unrecorded (Windows
        restarted before the step was saved) is then not done twice.
    #>
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$After)
    $step = $State.Steps.$After
    if (-not $step -or "$($step.Status)" -ne 'Done' -or -not $step.At) { return '' }
    try {
        $done = [datetime]::ParseExact("$($step.At)", 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        $boot = Get-NmLastBootTime
    } catch { return '' }
    if ($boot -and $boot -gt $done) { return "started again at $($boot.ToString('yyyy-MM-dd HH:mm'))" }
    return ''
}

function Get-NmHealthSummary {
    # "11 of 12 checks OK; dcdiag: 28 passed, 2 warnings, 0 failed".
    param([object[]]$Checks = @(), [object[]]$DcDiag = @())
    $ok = @($Checks | Where-Object Result -eq 'OK').Count
    $t = "$ok of $(@($Checks).Count) checks OK"
    if (@($DcDiag).Count) {
        $t += "; dcdiag: $(@($DcDiag | Where-Object Result -eq 'Passed').Count) passed, $(@($DcDiag | Where-Object Result -eq 'Warning').Count) warning(s), $(@($DcDiag | Where-Object Result -eq 'Failed').Count) failed"
    }
    return $t
}

function Get-NmStepTook {
    # How long a recorded step took ("6 min 15 s"), from its Began and At.
    param($Step)
    if (-not $Step -or -not $Step.Began -or -not $Step.At) { return '' }
    try {
        $b = [datetime]::ParseExact("$($Step.Began)", 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        $e = [datetime]::ParseExact("$($Step.At)", 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        if ($e -lt $b) { return '' }   # the time zone changed in between
        return (Format-NmStepTime -Span ($e - $b))
    } catch { return '' }
}

function New-NmBuildReport {
    <#
    .SYNOPSIS
        The build's report (HTML, in the reports folder): the build, the network, the server, the
        server check, every step with its times, the new DC's health and dcdiag, and next steps.
        Returns the path. Never holds a password.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $a = $State.Answers
    $level = if ($script:NmForestLevels.Contains("$($a.FunctionalLevel)")) { $script:NmForestLevels["$($a.FunctionalLevel)"] } else { "$($a.FunctionalLevel)" }
    $total = ''
    try {
        $b = [datetime]::ParseExact("$($State.Started)", 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        $e = [datetime]::ParseExact("$($State.Finished)", 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        $total = Format-NmStepTime -Span ($e - $b)
    } catch { $total = '' }
    $fact = { param($n, $v) [pscustomobject]@{ Name = $n; Value = "$v" } }

    $nic = $null; $os = $null; $hw = $null; $hyp = ''; $free = ''
    try { $nic = @(Get-NmNetAdapterInfo | Where-Object { $_.Index -eq [int]$a.AdapterIndex })[0] } catch { $nic = $null }
    try { $os = Get-NmOsInfo } catch { $os = $null }
    try { $hw = Get-NmHardwareInfo } catch { $hw = $null }
    try { $hyp = Get-NmHypervisor } catch { $hyp = '' }
    try { $free = "$(Get-NmFreeSpaceGB) GB" } catch { $free = '' }
    $dnsNow = @()
    try { $dnsNow = @(Get-NmDnsClientServer -IPAddress $a.IPAddress) } catch { $dnsNow = @() }

    $steps = foreach ($s in $script:NmBuildStepList) {
        $st = $State.Steps.($s.Name)
        [pscustomobject]@{
            Phase  = $(if ($s.Phase -eq 0) { 'Phase 0' } else { 'Phase 1' })
            Step   = $(if ($s.Name -eq 'Promote') { "New forest $($a.Domain)" } else { $s.Label })
            Result = $(if ($st) { "$($st.Status)" } else { 'Not run' })
            Began  = "$($st.Began)"
            Finished = "$($st.At)"
            Took   = (Get-NmStepTook -Step $st)
            Detail = "$($st.Detail)"
        }
    }
    $next = @(
        'Phases 2 to 5 of the build (DNS, time, OUs, GPO baselines) come in later versions of the toolkit; run those tools next.'
        $(if ($a.MoreDCs) { 'More DCs are planned: promote each by hand, then point every DC''s DNS at its partner first and itself second, and run the DC report on it.' } else { 'Single DC: keep its DNS on its own IP, then 127.0.0.1.' })
        'Store the DSRM password in the password manager now: the toolkit never records it.'
        'Take a system state backup of the new DC (wbadmin start systemstatebackup) once it has settled.'
    )
    $sections = @(
        @{ Title = 'The build'; Kind = 'Facts'; Rows = @(
            (& $fact 'Forest and domain' "$($a.Domain)"), (& $fact 'NetBIOS name' "$($a.NetBIOS)"), (& $fact 'Functional level' $level),
            (& $fact 'More DCs planned' $(if ($a.MoreDCs) { 'Yes' } else { 'No' })), (& $fact 'Domain controller' "$($a.ComputerName)"),
            (& $fact 'Time zone' "$($a.TimeZone)"), (& $fact 'Database' "$($a.DatabasePath)"), (& $fact 'Logs' "$($a.LogPath)"), (& $fact 'SYSVOL' "$($a.SysvolPath)")) }
        @{ Title = 'Network'; Kind = 'Facts'; Rows = @(
            (& $fact 'Adapter' "$($a.AdapterName)$(if ($nic) { " ($($nic.Mac))" })"), (& $fact 'Static IP' "$($a.IPAddress)/$($a.PrefixLength)"),
            (& $fact 'Default gateway' "$($a.Gateway)"), (& $fact 'DNS before promotion' (@($a.DnsServers) -join ', ')),
            (& $fact 'DNS now' $(if ($dnsNow.Count) { $dnsNow -join ', ' } else { 'not read' })), (& $fact 'Address before the build' "$($a.CurrentIp)")) }
        @{ Title = 'Server'; Kind = 'Facts'; Rows = @(
            (& $fact 'Operating system' $(if ($os) { "$($os.Caption) (build $($os.Build))" } else { 'not read' })),
            (& $fact 'Hypervisor' $(if ($hyp) { $hyp } else { 'not read' })),
            (& $fact 'Processor' $(if ($hw) { "$($hw.Cpu), $($hw.Processors) logical processors" } else { 'not read' })),
            (& $fact 'Memory' $(if ($hw) { "$($hw.MemoryGB) GB" } else { 'not read' })), (& $fact 'Free on the system drive' $free)) }
        @{ Title = 'Server check'; Kind = 'Table'; Note = 'Before anything changed.'; Columns = @('Check', 'Result', 'Detail'); StatusColumn = 'Result'; Rows = @($State.Preflight) }
        @{ Title = 'Steps'; Kind = 'Table'; Columns = @('Phase', 'Step', 'Result', 'Began', 'Finished', 'Took', 'Detail'); StatusColumn = 'Result'; Rows = @($steps) }
        @{ Title = 'Health of the new DC'; Kind = 'Table'; Note = 'Checked at the end of the build.'; Columns = @('Check', 'Result', 'Detail'); StatusColumn = 'Result'; Rows = @($State.Health) }
        @{ Title = 'dcdiag'; Kind = 'Table'; Note = 'Warnings: tests that are often noisy for a while after a promotion.'; Columns = @('Test', 'Target', 'Result', 'Detail'); StatusColumn = 'Result'; Rows = @($State.DcDiag) }
        @{ Title = 'Next steps'; Kind = 'List'; Items = $next }
    )
    $path = Join-Path (Get-NmReportFolder) (Get-NmExportFileName -ToolId 'new-forest-report' -Domain $a.Domain -Extension html)
    return (New-NmHtmlReport -Title "New Forest Build: $($a.Domain)" -Subtitle "First domain controller: $($a.ComputerName)" -Path $path -Sections $sections -Meta @(
        "Run by $($State.RunBy)", "Started $($State.Started)", "Finished $($State.Finished)", $(if ($total) { "Total $total" } else { '' })))
}

function Show-NmRestartNotice {
    # Says the server restarts and who to sign in as. In the window a pop-up (the restart comes in 60
    # seconds whatever is clicked); in the console the lines alone, nothing to press.
    param([string]$SignInAs)
    Write-Host ''
    Write-Host 'The server restarts in 60 seconds' -ForegroundColor Cyan
    Write-Host "Sign in as $SignInAs and the build carries on by itself."
    if ($script:NmGui -and $script:NmGui.Active) { Wait-NmKey }
}

function Read-NmDsrmPassword {
    # Asks twice; returns the SecureString, or throws after three tries.
    [CmdletBinding()]
    [OutputType([securestring])]
    param()
    for ($try = 1; $try -le 3; $try++) {
        $p1 = Read-NmSecret -Prompt 'Directory Services Restore Mode (DSRM) password'
        $p2 = Read-NmSecret -Prompt 'Type it again'
        $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1)
        $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2)
        try {
            $t1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
            $same = ($t1 -ceq [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)); $empty = -not $t1
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
            $t1 = $null
        }
        if ($same -and -not $empty) { return $p1 }
        Write-Host $(if ($empty) { 'The password cannot be empty.' } else { 'The two did not match.' }) -ForegroundColor Red
    }
    throw 'No DSRM password was set.'
}

function Invoke-NmNewForestBuild {
    <#
    .SYNOPSIS
        Runs the saved build from where it stopped. -Answers starts a build without the questions.
    #>
    [CmdletBinding()]
    param([hashtable]$Answers, [switch]$Resume, [switch]$WhatIf)

    if (-not (Test-NmWindowsPowerShell)) { throw 'Run the build in Windows PowerShell: .\Start-NutmegAD.ps1 -NewForest' }
    $state = Get-NmBuildState
    if (-not $state -and $Answers) {
        $state = New-NmBuildState
        $state.Answers = [pscustomobject]$Answers
        Save-NmBuildState -State $state
    }
    if (-not $state -or -not $state.Answers) { throw 'No build has been started on this server. Start it from the menu: New forest build.' }
    $a = $state.Answers
    $rows = New-Object System.Collections.Generic.List[object]

    if ($state.Finished) {
        $rows.Add([pscustomobject]@{ Phase = 'Build'; Step = "First DC of $($a.Domain)"; Result = 'Finished'; Detail = "on $($state.Finished)" })
        return $rows.ToArray()
    }
    if ($WhatIf) {
        foreach ($line in @(Get-NmNewForestPlanText -Answers $a)) { $rows.Add([pscustomobject]@{ Phase = 'Plan'; Step = $line; Result = 'WhatIf: not changed'; Detail = '' }) }
        return $rows.ToArray()
    }

    Set-NmPlanApproved -Plan "New Forest Build: $($a.Domain)"
    # The window draws these as the first card: what is being built.
    foreach ($r in @(Get-NmNewForestInfoRow -Answers $a -State $state)) { $rows.Add($r) }
    # The live step list: every step of both phases, those done earlier already ticked.
    Start-NmStepList -Title "New Forest Build: $($a.Domain)" -Steps @(Get-NmNewForestStepItem -Answers $a -State $state)
    try {
        # ---- Phase 0: prepare the server ----
        if (-not (Test-NmBuildStepDone -State $state -Name 'PrepareRestart')) {
            if ((Get-NmLocalComputer).PartOfDomain) { throw 'This server has joined a domain since the build started; the build stops here.' }
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'TimeZone' -Phase $script:NmPhase0 -Label 'Time zone' -Action {
                if ((Get-NmTimeZoneId) -eq $a.TimeZone) { return "$($a.TimeZone) (already set)" }
                $null = Confirm-NmChange -Action "Set the time zone to $($a.TimeZone)"
                $was = Get-NmTimeZoneId
                Set-NmTimeZone -Id $a.TimeZone
                Write-NmLog "Time zone changed from $was to $($a.TimeZone): log times from here on are in the new zone." -Level INFO
                return "$($a.TimeZone) (was $was)"
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'ComputerName' -Phase $script:NmPhase0 -Label 'Computer name' -Action {
                $now = "$((Get-NmLocalComputer).Name)"
                if ($now -eq $a.ComputerName) { return "$now (unchanged)" }
                $null = Confirm-NmChange -Action "Rename this computer from $now to $($a.ComputerName)"
                Set-NmComputerName -NewName $a.ComputerName
                return "$($a.ComputerName) (was $now; takes effect after the restart)"
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'ResumeTask' -Phase $script:NmPhase0 -Label 'Sign-in task' -Action {
                $launcher = Join-Path (Split-Path -Parent $script:NmModuleRoot) 'Start-NutmegAD.ps1'
                # Started in the window: the task reopens the window; from the console, the console.
                $inWindow = [bool]($script:NmGui -and $script:NmGui.Active)
                $null = Confirm-NmChange -Action "Add a sign-in task that reopens the build$(if ($inWindow) { ' (in the window)' }) after a restart"
                Register-NmResumeTask -LauncherPath $launcher -Gui:$inWindow
                return "reopens the build$(if ($inWindow) { ' in the window' }) at the next administrator sign-in"
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'StaticIp' -Phase $script:NmPhase0 -Label 'Static IP' -Action {
                $nic = @(Get-NmNetAdapterInfo | Where-Object { $_.Index -eq [int]$a.AdapterIndex })[0]
                if ($nic -and -not $nic.Dhcp -and $nic.IPv4 -eq $a.IPAddress) { return "$($a.IPAddress) (already set)" }
                $null = Confirm-NmChange -Action "Set $($a.AdapterName) to $($a.IPAddress)/$($a.PrefixLength), gateway $($a.Gateway), DNS $(@($a.DnsServers) -join ', ')"
                if ($a.IPAddress -ne $a.CurrentIp) {
                    Write-Host ''
                    Write-Host "   The address changes to $($a.IPAddress) now. If you are connected over RDP, reconnect to $($a.IPAddress)." -ForegroundColor Yellow
                    Write-Host ''
                }
                Set-NmStaticIp -InterfaceIndex ([int]$a.AdapterIndex) -IPAddress $a.IPAddress -PrefixLength ([int]$a.PrefixLength) -Gateway $a.Gateway -DnsServers @($a.DnsServers)
                return "$($a.IPAddress)/$($a.PrefixLength) via $($a.Gateway)"
            }))
            # A restart ends phase 0 when the name changed, or when Windows is waiting for one anyway
            # (the role install can fail with a restart pending).
            $renamed = ("$((Get-NmLocalComputer).Name)" -ne "$($a.ComputerName)")
            $waiting = (-not $renamed) -and (Test-NmPendingRebootSafe)
            $renamed = $renamed -or $waiting
            # The step is recorded as done when the restart is scheduled, before the notice: Windows may
            # restart before anyone clicks Continue, and an unrecorded restart step would restart again
            # at every sign-in.
            $restart = @{ Now = $false }   # set inside the step (its own scope), read here
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'PrepareRestart' -Phase $script:NmPhase0 -Label 'Restart' -Action {
                if (-not $renamed) { return 'not needed (the name did not change, and Windows is not waiting for one)' }
                $since = Get-NmRestartSince -State $state -After 'StaticIp'
                if ($since) { return "already restarted ($since)" }
                if ($waiting) { Write-NmLog 'Windows is waiting for a restart: restarting before AD DS is installed.' -Level INFO }
                Restart-NmServer -Seconds 60
                $restart.Now = $true
                return 'restarting in 60 seconds; the build reopens when you sign in'
            }))
            if ($restart.Now) {
                Show-NmRestartNotice -SignInAs 'Administrator (the local one)'
                Add-NmBuildToDoRow -State $state -Answers $a -Rows $rows
                return $rows.ToArray()
            }
        }

        # ---- Phase 1: promote ----
        if (-not (Test-NmBuildStepDone -State $state -Name 'PromoteRestart')) {
            # Windows still waiting for a restart (an update queued one since): stop before the roles,
            # and let the technician restart now or within 30 minutes.
            if (-not (Test-NmBuildStepDone -State $state -Name 'Features') -and (Test-NmPendingRebootSafe)) {
                $rows.Add([pscustomobject]@{ Phase = $script:NmPhase1; Step = 'Restart before AD DS'; Result = 'Waiting'; Detail = (Invoke-NmPendingRestart -SignInAs "$(if ((Get-NmLocalComputer).PartOfDomain) { "$($a.NetBIOS)\" })Administrator") })
                Add-NmBuildToDoRow -State $state -Answers $a -Rows $rows
                return $rows.ToArray()
            }
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'Features' -Phase $script:NmPhase1 -Label 'AD DS, DNS and GPMC' -Action {
                $null = Confirm-NmChange -Action 'Install AD DS, DNS, Group Policy Management and the AD module'
                $r = Install-NmAddsFeature
                if (-not $r.Success) { throw 'Windows did not install the roles (see Server Manager).' }
                return "installed (restart needed: $($r.RestartNeeded))"
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'Promote' -Phase $script:NmPhase1 -Label "New forest $($a.Domain)" -Action {
                if (Test-NmDomainAnswers -Domain $a.Domain) { throw "domain controllers for $($a.Domain) answer on the network now; the build only creates new forests" }
                if ((Get-NmLocalComputer).PartOfDomain) { throw 'this server has joined a domain' }
                $dsrm = Read-NmDsrmPassword
                $forestArgs = Get-NmForestArgs -Answers $a -DsrmPassword $dsrm
                Write-NmLog "Running Microsoft's pre-checks for $($a.Domain)..." -Level INFO
                $t = Test-NmForestInstallation -ForestArgs $forestArgs
                if ($t.Status -ne 'Success') { throw "Microsoft's pre-checks failed: $($t.Message)" }
                $null = Confirm-NmChange -Action "Create the forest $($a.Domain) ($($a.NetBIOS)) and make this server its first DC" -DomainWide
                Write-NmLog "Creating the forest $($a.Domain). This takes several minutes..." -Level INFO
                $r = Install-NmForest -ForestArgs $forestArgs
                $dsrm = $null; $forestArgs = $null
                if ($r.Status -eq 'Error') { throw "$($r.Message)" }
                return "$($a.Domain) ($($a.NetBIOS)), level $($a.FunctionalLevel)"
            }))
            # Recorded as done before the notice (see phase 0's restart). A server that has already
            # restarted since the forest was made does not restart again.
            $restart = @{ Now = $false }
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'PromoteRestart' -Phase $script:NmPhase1 -Label 'Restart' -Action {
                $since = Get-NmRestartSince -State $state -After 'Promote'
                if ($since) { return "already restarted ($since)" }
                Restart-NmServer -Seconds 60
                $restart.Now = $true
                return "restarting in 60 seconds; sign in as $($a.NetBIOS)\Administrator and the build reopens"
            }))
            # Already restarted (a restart step left unrecorded before 0.7.3): straight on to the check.
            if ($restart.Now) {
                Show-NmRestartNotice -SignInAs "$($a.NetBIOS)\Administrator (same password as the local one)"
                Add-NmBuildToDoRow -State $state -Answers $a -Rows $rows
                return $rows.ToArray()
            }
        }

        # ---- After promotion: check and finish ----
        $rows.Add((Invoke-NmBuildStep -State $state -Name 'Verify' -Phase $script:NmPhase1 -Label 'Check the new DC' -Action {
            Reset-NmSession
            if (-not (Assert-NmConnection -Services AD)) { throw 'the AD module did not load or the domain did not answer' }
            $s = Get-NmSession
            if ($s.Domain -ne $a.Domain) { throw "this DC answers for $($s.Domain), not $($a.Domain)" }
            if (-not (Get-NmLocalComputer).IsDC) { throw 'this server is not a domain controller' }
            return "$($s.Server) is a DC of $($s.Domain) ($($s.NetBIOS)), $($s.DomainMode)"
        }))
        $rows.Add((Invoke-NmBuildStep -State $state -Name 'Health' -Phase $script:NmPhase1 -Label 'DC health and dcdiag' -Action {
            $s = Get-NmSession
            $hl = Get-NmDcHealth -Server "$($s.Server)" -Domain $a.Domain -IPAddress $a.IPAddress
            $state | Add-Member -NotePropertyName Health -NotePropertyValue @($hl.Checks) -Force
            $state | Add-Member -NotePropertyName DcDiag -NotePropertyValue @($hl.DcDiag) -Force
            Save-NmBuildState -State $state
            return (Get-NmHealthSummary -Checks $hl.Checks -DcDiag $hl.DcDiag)
        }))
        $rows.Add((Invoke-NmBuildStep -State $state -Name 'Finish' -Phase $script:NmPhase1 -Label 'Finish' -Action {
            Unregister-NmResumeTask
            $state.Finished = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Save-NmBuildState -State $state
            $folder = $script:NmConfig.ExportRoot
            if (-not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
            $record = Join-Path $folder (Get-NmExportFileName -ToolId 'new-forest' -Domain $a.Domain -Extension txt).Replace('.txt', '.json')
            Copy-Item -LiteralPath (Get-NmBuildStatePath) -Destination $record -Force
            # The report: HTML (opened now) and its PDF copy, both in the reports folder.
            $html = New-NmBuildReport -State $state
            $pdf = ConvertTo-NmPdf -HtmlPath $html
            Open-NmReport -Path $html
            return "sign-in task removed; report: $html$(if ($pdf) { " (PDF: $pdf)" } else { ' (no PDF copy: print it from the browser)' })"
        }))
        $next = if ($a.MoreDCs) { 'Promote the next DC with the individual tools, then point each DC''s DNS at its partner first and itself second.' } else { 'Single DC: keep its DNS on its own IP, then 127.0.0.1.' }
        $rows.Add([pscustomobject]@{ Phase = 'Next'; Step = 'Phases 2 to 5'; Result = 'Not built yet'; Detail = 'DNS, time, OUs, GPOs and the report come in later versions of the build.' })
        $rows.Add([pscustomobject]@{ Phase = 'Next'; Step = 'More DCs'; Result = $(if ($a.MoreDCs) { 'Planned' } else { 'Not planned' }); Detail = $next })
        return $rows.ToArray()
    } catch {
        $rows.Add([pscustomobject]@{ Phase = 'Stopped'; Step = 'The build stopped'; Result = 'Failed'; Detail = "$($_.Exception.Message) Fix it and run the build again: finished steps are skipped." })
        Add-NmBuildToDoRow -State $state -Answers $a -Rows $rows
        return $rows.ToArray()
    } finally {
        Set-NmPlanApproved -Plan $null
    }
}
