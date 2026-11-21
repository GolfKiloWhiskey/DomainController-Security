<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.5

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
    Version  = '0.5'
    Kind     = 'Change'
    Services = @()
    Roles    = @('Local administrator on a workgroup server')
    Prompt   = 'Read-NmNewForestPlan'
    Entry    = 'Invoke-NmNewForestBuild'
    Columns  = @('Phase', 'Step', 'Result', 'Detail')
}

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
    & $row 'No restart pending' $(if ($pending) { 'Warning' } else { 'OK' }) $(if ($pending) { 'Windows is waiting for a restart: restart first, or the role install may fail' } else { 'none' })

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
    # Read-NmInput until the answer passes the test; shows why when it does not.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Prompt, [string]$Default, [Parameter(Mandatory)][scriptblock]$Test, [Parameter(Mandatory)][string]$Why)
    while ($true) {
        $a = "$(Read-NmInput -Prompt $Prompt -Default $Default)".Trim()
        if ($a -and (& $Test $a)) { return $a }
        Write-Host $Why -ForegroundColor Red
    }
}

function Read-NmNewForestAnswer {
    <#
    .SYNOPSIS
        Asks every question of the build, with defaults from this server. Returns a hashtable, or $null.
    #>
    [CmdletBinding()]
    param()
    $pc = Get-NmLocalComputer
    $a = [ordered]@{}

    Write-Host ''
    Write-Host 'The new forest' -ForegroundColor Cyan
    $a.Domain = (Read-NmCheckedInput -Prompt 'Domain name (DNS, for example clientx.local)' -Test { param($x) Test-NmDomainNameText $x } -Why 'Use a DNS name with at least two parts, such as clientx.local.').ToLower()
    $nbDefault = (($a.Domain -split '\.')[0]).ToUpper()
    if ($nbDefault.Length -gt 15) { $nbDefault = $nbDefault.Substring(0, 15) }
    $a.NetBIOS = (Read-NmCheckedInput -Prompt 'NetBIOS name' -Default $nbDefault -Test { param($x) Test-NmNetbiosText $x.ToUpper() } -Why 'Up to 15 letters, digits or hyphens, no dots.').ToUpper()

    $lv = @($script:NmForestLevels.Keys)
    $opts = @(for ($i = 0; $i -lt $lv.Count; $i++) { [pscustomobject]@{ Key = "$($i + 1)"; Label = $script:NmForestLevels[$lv[$i]] } })
    $pick = Show-NmMenu -Title 'Forest and domain functional level' -Back -NoClear -Options $opts
    if ($pick -eq 'B') { return $null }
    $a.FunctionalLevel = $lv[[int]$pick - 1]
    $a.MoreDCs = Read-NmYesNo -Prompt 'Will this domain have more than one DC?' -Default 'Y'

    Write-Host ''
    Write-Host 'This server' -ForegroundColor Cyan
    $a.ComputerName = (Read-NmCheckedInput -Prompt 'Computer name' -Default "$($pc.Name)" -Test { param($x) Test-NmComputerNameText $x } -Why '1 to 15 letters, digits or hyphens, not only digits.').ToUpper()
    $tzDefault = "$(Get-NmSetting -Key BuildTimeZone)"   # Eastern Standard Time unless Settings say otherwise
    if (-not (Test-NmTimeZoneId $tzDefault)) { $tzDefault = Get-NmTimeZoneId }
    $a.TimeZone = Read-NmCheckedInput -Prompt 'Time zone (Windows ID)' -Default $tzDefault -Test { param($x) Test-NmTimeZoneId $x } -Why 'Not a Windows time zone ID. Get-TimeZone -ListAvailable lists them (for example Eastern Standard Time).'

    $nics = @(Get-NmNetAdapterInfo)
    if (-not $nics.Count) { Write-NmLog 'No connected network adapter.' -Level ERROR; return $null }
    $nic = $nics[0]
    if ($nics.Count -gt 1) {
        $i = 0
        $nOpts = @(foreach ($n in $nics) { $i++; [pscustomobject]@{ Key = "$i"; Label = $n.Name; Detail = "$($n.IPv4)/$($n.PrefixLength), $($n.Mac), $($n.Description)" } })
        $p = Show-NmMenu -Title 'Network adapter for the DC' -Back -NoClear -Options $nOpts
        if ($p -eq 'B') { return $null }
        $nic = $nics[[int]$p - 1]
    }
    $a.AdapterIndex = $nic.Index
    $a.AdapterName = $nic.Name
    $a.CurrentIp = $nic.IPv4

    Write-Host ''
    Write-Host "Network ($($nic.Name), now $(if ($nic.Dhcp) { 'DHCP' } else { 'static' }) $($nic.IPv4)/$($nic.PrefixLength))" -ForegroundColor Cyan
    $a.IPAddress = Read-NmCheckedInput -Prompt 'Static IP for the DC' -Default (Get-NmSuggestedDcIp -CurrentIp $nic.IPv4) -Test { param($x) Test-NmIPv4Text $x } -Why 'Type an IPv4 address such as 192.0.2.50.'
    $a.PrefixLength = [int](Read-NmCheckedInput -Prompt 'Prefix length' -Default "$($nic.PrefixLength)" -Test { param($x) $x -match '^\d+$' -and [int]$x -ge 8 -and [int]$x -le 30 } -Why 'A number from 8 to 30 (24 for 255.255.255.0).')
    $a.Gateway = Read-NmCheckedInput -Prompt 'Default gateway' -Default $nic.Gateway -Test { param($x) Test-NmIPv4Text $x } -Why 'Type an IPv4 address.'
    $dnsDefault = if (@($nic.Dns).Count) { @($nic.Dns) -join ', ' } else { $a.Gateway }
    $dnsText = Read-NmCheckedInput -Prompt 'DNS servers until promotion, comma-separated' -Default $dnsDefault -Test { param($x) @($x -split '[,\s]+' | Where-Object { $_ } | Where-Object { -not (Test-NmIPv4Text $_) }).Count -eq 0 } -Why 'IPv4 addresses, comma-separated.'
    $a.DnsServers = @($dnsText -split '[,\s]+' | Where-Object { $_ })

    Write-Host ''
    Write-Host 'Folders' -ForegroundColor Cyan
    $a.DatabasePath = 'C:\Windows\NTDS'; $a.LogPath = 'C:\Windows\NTDS'; $a.SysvolPath = 'C:\Windows\SYSVOL'
    if (-not (Read-NmYesNo -Prompt 'Use the default database, log and SYSVOL folders (C:\Windows\NTDS, C:\Windows\SYSVOL)?' -Default 'Y')) {
        $a.DatabasePath = Read-NmInput -Prompt 'Database folder' -Default $a.DatabasePath
        $a.LogPath = Read-NmInput -Prompt 'Log folder' -Default $a.LogPath
        $a.SysvolPath = Read-NmInput -Prompt 'SYSVOL folder' -Default $a.SysvolPath
    }
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
        $(if ($rename) { 'Restart (for the new name)' } else { 'No restart needed yet' })
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
    $checks | Format-Table Check, Result, Detail -AutoSize -Wrap | Out-Host
    if (@($checks | Where-Object Result -eq 'Not ready').Count) {
        Write-NmLog 'This server is not ready for the build (see Not ready above). Nothing was changed.' -Level ERROR
        Wait-NmKey
        return $null
    }

    $a = Read-NmNewForestAnswer
    if (-not $a) { return $null }

    if (Test-NmDomainAnswers -Domain $a.Domain) {
        Write-NmLog "Domain controllers for $($a.Domain) already answer on this network. The build only creates new forests; nothing was changed." -Level ERROR
        Wait-NmKey
        return $null
    }
    if ($a.IPAddress -ne $a.CurrentIp -and (Test-NmIpInUse -IPAddress $a.IPAddress)) {
        Write-NmLog "Something already answers on $($a.IPAddress). Pick another address; nothing was changed." -Level ERROR
        Wait-NmKey
        return $null
    }

    $plan = @(Get-NmNewForestPlanText -Answers $a)
    $word = ($a.Domain -split '\.')[0]
    if (-not (Confirm-NmChange -Action "New Forest Build: $($a.Domain)" -Targets $plan -DomainWide -ConfirmWord $word)) { return $null }

    $state = New-NmBuildState
    $state.Answers = [pscustomobject]$a
    Save-NmBuildState -State $state
    return @{ Resume = $true }
}

# ---------------------------------------------------------------------------
# The build
# ---------------------------------------------------------------------------
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
    try {
        # ---- Phase 0: prepare the server ----
        if (-not (Test-NmBuildStepDone -State $state -Name 'PrepareRestart')) {
            if ((Get-NmLocalComputer).PartOfDomain) { throw 'This server has joined a domain since the build started; the build stops here.' }
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'TimeZone' -Phase '0 Prepare' -Label 'Time zone' -Action {
                if ((Get-NmTimeZoneId) -eq $a.TimeZone) { return "$($a.TimeZone) (already set)" }
                $null = Confirm-NmChange -Action "Set the time zone to $($a.TimeZone)"
                $was = Get-NmTimeZoneId
                Set-NmTimeZone -Id $a.TimeZone
                Write-NmLog "Time zone changed from $was to $($a.TimeZone): log times from here on are in the new zone." -Level INFO -NoConsole
                return "$($a.TimeZone) (was $was)"
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'ComputerName' -Phase '0 Prepare' -Label 'Computer name' -Action {
                $now = "$((Get-NmLocalComputer).Name)"
                if ($now -eq $a.ComputerName) { return "$now (unchanged)" }
                $null = Confirm-NmChange -Action "Rename this computer from $now to $($a.ComputerName)"
                Set-NmComputerName -NewName $a.ComputerName
                return "$($a.ComputerName) (was $now; takes effect after the restart)"
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'ResumeTask' -Phase '0 Prepare' -Label 'Sign-in task' -Action {
                $launcher = Join-Path (Split-Path -Parent $script:NmModuleRoot) 'Start-NutmegAD.ps1'
                $null = Confirm-NmChange -Action 'Add a sign-in task that reopens the build after a restart'
                Register-NmResumeTask -LauncherPath $launcher
                return 'reopens the build at the next administrator sign-in'
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'StaticIp' -Phase '0 Prepare' -Label 'Static IP' -Action {
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
            $renamed = ("$((Get-NmLocalComputer).Name)" -ne "$($a.ComputerName)")
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'PrepareRestart' -Phase '0 Prepare' -Label 'Restart' -Action {
                if (-not $renamed) { return 'not needed (the name did not change)' }
                Restart-NmServer -Seconds 60
                return 'restarting in 60 seconds; the build reopens when you sign in'
            }))
            if ($renamed) { return $rows.ToArray() }
        }

        # ---- Phase 1: promote ----
        if (-not (Test-NmBuildStepDone -State $state -Name 'PromoteRestart')) {
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'Features' -Phase '1 Promote' -Label 'AD DS, DNS and GPMC' -Action {
                $null = Confirm-NmChange -Action 'Install AD DS, DNS, Group Policy Management and the AD module'
                $r = Install-NmAddsFeature
                if (-not $r.Success) { throw 'Windows did not install the roles (see Server Manager).' }
                return "installed (restart needed: $($r.RestartNeeded))"
            }))
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'Promote' -Phase '1 Promote' -Label "New forest $($a.Domain)" -Action {
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
            $rows.Add((Invoke-NmBuildStep -State $state -Name 'PromoteRestart' -Phase '1 Promote' -Label 'Restart' -Action {
                Restart-NmServer -Seconds 60
                return "restarting in 60 seconds; sign in as $($a.NetBIOS)\Administrator and the build reopens"
            }))
            return $rows.ToArray()
        }

        # ---- After promotion: check and finish ----
        $rows.Add((Invoke-NmBuildStep -State $state -Name 'Verify' -Phase '1 Promote' -Label 'Check the new DC' -Action {
            Reset-NmSession
            if (-not (Assert-NmConnection -Services AD)) { throw 'the AD module did not load or the domain did not answer' }
            $s = Get-NmSession
            if ($s.Domain -ne $a.Domain) { throw "this DC answers for $($s.Domain), not $($a.Domain)" }
            if (-not (Get-NmLocalComputer).IsDC) { throw 'this server is not a domain controller' }
            return "$($s.Server) is a DC of $($s.Domain) ($($s.NetBIOS)), $($s.DomainMode)"
        }))
        $rows.Add((Invoke-NmBuildStep -State $state -Name 'Finish' -Phase '1 Promote' -Label 'Finish' -Action {
            Unregister-NmResumeTask
            $state.Finished = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Save-NmBuildState -State $state
            $folder = $script:NmConfig.ExportRoot
            if (-not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
            $record = Join-Path $folder (Get-NmExportFileName -ToolId 'new-forest' -Domain $a.Domain -Extension txt).Replace('.txt', '.json')
            Copy-Item -LiteralPath (Get-NmBuildStatePath) -Destination $record -Force
            return "sign-in task removed; record of the build: $record"
        }))
        $next = if ($a.MoreDCs) { 'Promote the next DC with the individual tools, then point each DC''s DNS at its partner first and itself second.' } else { 'Single DC: keep its DNS on its own IP, then 127.0.0.1.' }
        $rows.Add([pscustomobject]@{ Phase = 'Next'; Step = 'Phases 2 to 5'; Result = 'Not built yet'; Detail = 'DNS, time, OUs, GPOs and the report come in later versions of the build.' })
        $rows.Add([pscustomobject]@{ Phase = 'Next'; Step = 'More DCs'; Result = $(if ($a.MoreDCs) { 'Planned' } else { 'Not planned' }); Detail = $next })
        return $rows.ToArray()
    } catch {
        $rows.Add([pscustomobject]@{ Phase = 'Stopped'; Step = 'The build stopped'; Result = 'Failed'; Detail = "$($_.Exception.Message) Fix it and run the build again: finished steps are skipped." })
        return $rows.ToArray()
    } finally {
        Set-NmPlanApproved -Plan $null
    }
}
