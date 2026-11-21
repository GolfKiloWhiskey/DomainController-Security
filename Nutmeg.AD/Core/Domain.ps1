# ---------------------------------------------------------------------------
# Domain.ps1 - the session: which domain, which DC, what is loaded (replaces M365's connections)
# ---------------------------------------------------------------------------
# The toolkit runs on a DC, as a domain admin. There is nothing to sign in to: "connecting" a
# service means its Windows module is loaded and the domain has been read once. Every AD and GPO
# call goes to one DC, the session's Server, so a run reads and writes one copy of the directory.
# Tools splat Get-NmADParams (AD cmdlets) or Get-NmGPParams (GroupPolicy cmdlets) onto each call.

$script:NmKnownServices = @('AD', 'GPO')

function New-NmSessionObject {
    [pscustomobject]@{
        Domain      = $null   # DNS name, clientx.local
        NetBIOS     = $null   # CLIENTX
        Forest      = $null   # forest root DNS name
        DomainSid   = $null   # S-1-5-21-...
        DomainDN    = $null   # DC=clientx,DC=local
        DomainMode  = $null
        ForestMode  = $null
        PdcEmulator = $null
        Server      = $null   # the DC every call goes to
        Services    = @{ AD = $false; GPO = $false }
    }
}
$script:NmSession = New-NmSessionObject

function Get-NmSession {
    <#
    .SYNOPSIS
        The current session: Domain, NetBIOS, Forest, DomainSid, DomainDN, levels, PDC, Server, Services.
    #>
    [CmdletBinding()]
    param()
    return $script:NmSession
}

function Reset-NmSession {
    # Forgets the domain and what is loaded (tests, and Domain > Reload).
    $script:NmSession = New-NmSessionObject
}

# ---------------------------------------------------------------------------
# This computer and the person running the toolkit
# ---------------------------------------------------------------------------
function Get-NmLocalComputer {
    <#
    .SYNOPSIS
        This computer: Name, Domain, PartOfDomain, IsDC, IsPdc. Off Windows (tests): not joined.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:NmOnWindows) {
        return [pscustomobject]@{ Name = [Environment]::MachineName; Domain = ''; PartOfDomain = $false; IsDC = $false; IsPdc = $false; DnsHostName = [Environment]::MachineName }
    }
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    # DomainRole: 4 = backup DC, 5 = primary DC (the PDC emulator).
    $role = [int]$cs.DomainRole
    $dns = if ($cs.PartOfDomain) { "$($cs.DNSHostName).$($cs.Domain)" } else { "$($cs.DNSHostName)" }
    return [pscustomobject]@{
        Name         = "$($cs.Name)"
        Domain       = $(if ($cs.PartOfDomain) { "$($cs.Domain)" } else { '' })
        PartOfDomain = [bool]$cs.PartOfDomain
        IsDC         = ($role -ge 4)
        IsPdc        = ($role -eq 5)
        DnsHostName  = $dns
    }
}

function Test-NmElevated {
    # True when PowerShell runs as administrator (an elevated token).
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (-not $script:NmOnWindows) { return $false }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-NmCurrentIdentity {
    <#
    .SYNOPSIS
        Who is running the toolkit: Name and the SIDs of every group in their token.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:NmOnWindows) {
        return [pscustomobject]@{ Name = [Environment]::UserName; Sids = @() }
    }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return [pscustomobject]@{
        Name = $id.Name
        Sids = @($id.Groups | ForEach-Object { $_.Value })
    }
}

# Well-known domain groups, by the last part of their SID (domain SID + RID).
$script:NmAdminGroupRids = [ordered]@{
    'Domain Admins'     = 512
    'Schema Admins'     = 518
    'Enterprise Admins' = 519
}

function Get-NmAdminMembership {
    <#
    .SYNOPSIS
        Which of Domain, Schema and Enterprise Admins the current account is in (from its token).
    .DESCRIPTION
        Schema and Enterprise Admins live in the forest root domain; in a single-domain forest that
        is this domain. Returns one row per group: Group, Member (true/false).
    #>
    [CmdletBinding()]
    param([string]$DomainSid = "$((Get-NmSession).DomainSid)")
    $sids = @((Get-NmCurrentIdentity).Sids)
    foreach ($g in $script:NmAdminGroupRids.Keys) {
        $member = if ($DomainSid) { $sids -contains "$DomainSid-$($script:NmAdminGroupRids[$g])" } else { $false }
        [pscustomobject]@{ Group = $g; Member = [bool]$member }
    }
}

# ---------------------------------------------------------------------------
# The domain and the DC
# ---------------------------------------------------------------------------
function Get-NmDefaultServer {
    # The DC to talk to when none is chosen: this computer if it is a DC, else one AD finds.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $local = Get-NmLocalComputer
    if ($local.IsDC) { return "$($local.DnsHostName)" }
    $dc = Get-ADDomainController -Discover -ErrorAction Stop
    return "$(@($dc.HostName)[0])"
}

function Initialize-NmDomainContext {
    <#
    .SYNOPSIS
        Reads the domain and forest from one DC and fills the session. Needs the AD module loaded.
    .OUTPUTS
        $true when the domain was read.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Server)
    try {
        if (-not $Server) { $Server = if ($script:NmSession.Server) { $script:NmSession.Server } else { Get-NmDefaultServer } }
        $d = Get-ADDomain -Server $Server -ErrorAction Stop
        $f = Get-ADForest -Server $Server -ErrorAction Stop
        $s = $script:NmSession
        $s.Domain      = "$($d.DNSRoot)"
        $s.NetBIOS     = "$($d.NetBIOSName)"
        $s.DomainDN    = "$($d.DistinguishedName)"
        $s.DomainSid   = "$($d.DomainSID)"
        $s.DomainMode  = "$($d.DomainMode)"
        $s.PdcEmulator = "$($d.PDCEmulator)"
        $s.Forest      = "$($f.RootDomain)"
        $s.ForestMode  = "$($f.ForestMode)"
        $s.Server      = $Server
        Write-NmLog "Domain $($s.Domain) ($($s.NetBIOS)) read from $Server." -Level INFO -NoConsole
        return $true
    } catch {
        Write-NmLog "Could not read the domain$(if ($Server) { " from $Server" }): $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Assert-NmConnection {
    <#
    .SYNOPSIS
        Gets ready what a tool needs: loads the modules for its services and reads the domain once.
    .OUTPUTS
        $true when everything is ready.
    .EXAMPLE
        if (-not (Assert-NmConnection -Services AD, GPO)) { return }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyCollection()][string[]]$Services = @())
    $wanted = @($Services | Where-Object { $_ })
    if (-not $wanted.Count) { return $true }
    $bad = @($wanted | Where-Object { $script:NmKnownServices -notcontains $_ })
    if ($bad.Count) { Write-NmLog "Unknown service(s): $($bad -join ', ')." -Level ERROR; return $false }

    # The domain is read with the AD module, so every service needs it.
    $need = @('AD') + @($wanted | Where-Object { $_ -ne 'AD' })
    $ok = $true
    foreach ($svc in $need) {
        if ($script:NmSession.Services[$svc]) { continue }
        if (Assert-NmServiceModule -Services @($svc)) { $script:NmSession.Services[$svc] = $true } else { $ok = $false }
    }
    if (-not $ok) { return $false }
    if (-not $script:NmSession.Domain) { return (Initialize-NmDomainContext) }
    return $true
}

function Get-NmServiceState {
    # True when a service's module is loaded in this session.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Service)
    return [bool]$script:NmSession.Services[$Service]
}

function Get-NmADParams {
    <#
    .SYNOPSIS
        Splat for AD cmdlets: @{ Server = <the session's DC> }.
    .EXAMPLE
        $p = Get-NmADParams; Get-ADOrganizationalUnit -Filter * @p
    #>
    [CmdletBinding()]
    param()
    $p = @{}
    if ($script:NmSession.Server) { $p.Server = $script:NmSession.Server }
    return $p
}

function Get-NmGPParams {
    <#
    .SYNOPSIS
        Splat for GroupPolicy cmdlets: @{ Domain = <domain>; Server = <the session's DC> }.
    #>
    [CmdletBinding()]
    param()
    $p = @{}
    if ($script:NmSession.Domain) { $p.Domain = $script:NmSession.Domain }
    if ($script:NmSession.Server) { $p.Server = $script:NmSession.Server }
    return $p
}

function Set-NmServer {
    <#
    .SYNOPSIS
        Points the session at another DC of the same domain and reads the domain from it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Server)
    if (-not (Assert-NmConnection -Services AD)) { return $false }
    $old = $script:NmSession.Server
    if (Initialize-NmDomainContext -Server $Server) {
        Write-NmLog "Now working against $Server." -Level SUCCESS
        return $true
    }
    $script:NmSession.Server = $old
    return $false
}

function Get-NmBannerText {
    # The line under every header: domain, DC, what is loaded, PowerShell and elevation.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $s = $script:NmSession
    $where = if ($s.Domain) { "Domain: $($s.Domain) ($($s.NetBIOS)) | DC: $($s.Server)" } else { 'Domain: not read yet (tools read it when they need it)' }
    $svc = @(foreach ($k in $script:NmKnownServices) { "$k $(if ($s.Services[$k]) { 'loaded' } else { '-' })" }) -join ', '
    $ps = "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
    $elev = if (Test-NmElevated) { 'elevated' } else { 'NOT elevated' }
    return "$where | $svc | $ps, $elev"
}

function Show-NmDomainMenu {
    # Main menu > Domain and DC: status, pick the DC, read the domain again.
    [CmdletBinding()]
    param()
    while ($true) {
        $choice = Show-NmMenu -Title 'Domain and DC' -Back -Options @(
            [pscustomobject]@{ Key = '1'; Label = 'Status'; Detail = 'domain, levels, DC, PDC, modules' }
            [pscustomobject]@{ Key = '2'; Label = 'Work against another DC' }
            [pscustomobject]@{ Key = '3'; Label = 'Read the domain again' }
        )
        switch ($choice) {
            'B' { return }
            '1' {
                $null = Assert-NmConnection -Services AD
                $s = $script:NmSession
                [pscustomobject]@{
                    Domain = $s.Domain; NetBIOS = $s.NetBIOS; Forest = $s.Forest
                    'Domain level' = $s.DomainMode; 'Forest level' = $s.ForestMode
                    'PDC emulator' = $s.PdcEmulator; 'Working against' = $s.Server
                    'AD module' = $(if ($s.Services.AD) { 'loaded' } else { 'not loaded' })
                    'GroupPolicy module' = $(if ($s.Services.GPO) { 'loaded' } else { 'not loaded (loads when a tool needs it)' })
                } | Format-List | Out-Host
                Wait-NmKey
            }
            '2' {
                if (-not (Assert-NmConnection -Services AD)) { Wait-NmKey; continue }
                $adp = Get-NmADParams
                $dcs = @(Get-ADDomainController -Filter * @adp -ErrorAction SilentlyContinue | Sort-Object HostName)
                if (-not $dcs.Count) { Write-NmLog 'No domain controllers found.' -Level WARN; Wait-NmKey; continue }
                $i = 0
                $opts = @(foreach ($dc in $dcs) {
                    $i++
                    $tag = if ("$($dc.HostName)" -eq "$($script:NmSession.Server)") { '(current)' } else { $null }
                    [pscustomobject]@{ Key = "$i"; Label = "$($dc.HostName)"; Tag = $tag; Detail = "site $($dc.Site)$(if ($dc.IsReadOnly) { ', read-only' })" }
                })
                $pick = Show-NmMenu -Title 'Work against which DC?' -Back -Options $opts
                if ($pick -eq 'B') { continue }
                $null = Set-NmServer -Server "$($dcs[[int]$pick - 1].HostName)"
                Wait-NmKey
            }
            '3' {
                $script:NmSession.Domain = $null   # the same DC is asked again
                if (Assert-NmConnection -Services AD) {
                    Write-NmLog "Domain $($script:NmSession.Domain) read again from $($script:NmSession.Server)." -Level SUCCESS
                }
                Wait-NmKey
            }
        }
    }
}
