# ---------------------------------------------------------------------------
# Server.ps1 - this server before and during the New Forest Build
# ---------------------------------------------------------------------------
# Small wrappers around the Windows cmdlets the build uses (network, name, time zone, features,
# promotion, the resume task, restarts). Each does one thing, so tests can stand in for it and the
# build reads as a list of steps. Nothing here runs unless the build calls it.

# ---------------------------------------------------------------------------
# What this server is
# ---------------------------------------------------------------------------
function Get-NmOsInfo {
    # Caption, Version, Build and ProductType (1 workstation, 2 domain controller, 3 server).
    [CmdletBinding()]
    param()
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    return [pscustomobject]@{
        Caption     = "$($os.Caption)"
        Version     = "$($os.Version)"
        Build       = [int]$os.BuildNumber
        ProductType = [int]$os.ProductType
    }
}

function Test-NmWindowsPowerShell {
    # True in Windows PowerShell 5.1. The build runs there: ServerManager and ADDSDeployment are
    # Windows PowerShell modules, and a fresh server has nothing else.
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    return ($PSVersionTable.PSVersion.Major -lt 6)
}

function Get-NmHypervisor {
    # 'Hyper-V', 'VMware', another vendor's name, or 'None' (physical).
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $text = "$($cs.Manufacturer) $($cs.Model)"
    if ($text -match 'Microsoft Corporation.*Virtual Machine') { return 'Hyper-V' }
    if ($text -match 'VMware') { return 'VMware' }
    if ($text -match 'QEMU|KVM|Xen|VirtualBox|innotek|Nutanix|Parallels') { return ($text -replace '\s+', ' ').Trim() }
    return 'None'
}

function Test-NmPendingReboot {
    # True when Windows is waiting for a restart (servicing, Windows Update or a pending file rename).
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { return $true }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { return $true }
    $sm = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    return [bool]($sm -and $sm.PendingFileRenameOperations)
}

function Get-NmFreeSpaceGB {
    # Free space on the system drive, in GB.
    [CmdletBinding()]
    param([string]$Drive = $(if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }))
    $d = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$Drive'" -ErrorAction Stop
    return [math]::Round(([double]$d.FreeSpace / 1GB), 1)
}

function Get-NmBlockedFile {
    # Toolkit files still marked as downloaded from the internet (they will not run under RemoteSigned).
    [CmdletBinding()]
    param([string]$Root = (Split-Path -Parent $script:NmModuleRoot))
    @(Get-ChildItem -Path $Root -Include *.ps1, *.psm1, *.psd1 -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue })
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
function Get-NmNetAdapterInfo {
    <#
    .SYNOPSIS
        The connected network adapters: Name, Index, Mac, Description, IPv4, PrefixLength, Gateway, Dns, Dhcp.
    #>
    [CmdletBinding()]
    param()
    foreach ($a in @(Get-NetAdapter -ErrorAction Stop | Where-Object { "$($_.Status)" -eq 'Up' } | Sort-Object ifIndex)) {
        $cfg = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue
        $ip = @($cfg.IPv4Address | Where-Object { $_ })[0]
        $gw = @($cfg.IPv4DefaultGateway | Where-Object { $_ })[0]
        $ipIf = Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Name         = "$($a.Name)"
            Index        = [int]$a.ifIndex
            Mac          = "$($a.MacAddress)"
            Description  = "$($a.InterfaceDescription)"
            IPv4         = $(if ($ip) { "$($ip.IPAddress)" } else { '' })
            PrefixLength = $(if ($ip) { [int]$ip.PrefixLength } else { 24 })
            Gateway      = $(if ($gw) { "$($gw.NextHop)" } else { '' })
            Dns          = @($cfg.DNSServer | Where-Object { "$($_.AddressFamily)" -eq '2' -or "$($_.AddressFamily)" -eq 'IPv4' } | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
            Dhcp         = ("$($ipIf.Dhcp)" -eq 'Enabled')
        }
    }
}

function Test-NmIPv4Text {
    # True for a dotted IPv4 address (192.0.2.50).
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Text)
    $ip = $null
    return ("$Text".Trim() -match '^\d{1,3}(\.\d{1,3}){3}$' -and [System.Net.IPAddress]::TryParse("$Text".Trim(), [ref]$ip))
}

function Get-NmSuggestedDcIp {
    # Cliff's standard: the DC is .50 in its subnet. 192.0.2.37 -> 192.0.2.50.
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$CurrentIp, [int]$Last = 50)
    if (-not (Test-NmIPv4Text $CurrentIp)) { return '' }
    $parts = "$CurrentIp".Trim() -split '\.'
    return "$($parts[0]).$($parts[1]).$($parts[2]).$Last"
}

function Test-NmIpInUse {
    # True when something answers on the address (one ping, short wait).
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$IPAddress)
    try { return [bool](Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction Stop) } catch { return $false }
}

function Set-NmStaticIp {
    <#
    .SYNOPSIS
        Gives one adapter a static IPv4 address, gateway and DNS servers, replacing what it had.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$InterfaceIndex,
        [Parameter(Mandatory)][string]$IPAddress,
        [Parameter(Mandatory)][int]$PrefixLength,
        [string]$Gateway,
        [string[]]$DnsServers = @()
    )
    Set-NetIPInterface -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
    Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceIndex $InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
    $ipArgs = @{ InterfaceIndex = $InterfaceIndex; IPAddress = $IPAddress; PrefixLength = $PrefixLength; AddressFamily = 'IPv4'; ErrorAction = 'Stop' }
    if ($Gateway) { $ipArgs.DefaultGateway = $Gateway }
    $null = New-NetIPAddress @ipArgs
    if (@($DnsServers).Count) { Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses $DnsServers -ErrorAction Stop }
}

# ---------------------------------------------------------------------------
# Name, time zone, restarts
# ---------------------------------------------------------------------------
function Set-NmComputerName {
    # Renames this computer (takes effect after the restart).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$NewName)
    Rename-Computer -NewName $NewName -Force -ErrorAction Stop -WarningAction SilentlyContinue
}

function Get-NmTimeZoneId { [CmdletBinding()] param() return "$((Get-TimeZone).Id)" }

function Test-NmTimeZoneId {
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Id)
    try { $null = Get-TimeZone -Id $Id -ErrorAction Stop; return $true } catch { return $false }
}

function Set-NmTimeZone { [CmdletBinding()] param([Parameter(Mandatory)][string]$Id) Set-TimeZone -Id $Id -ErrorAction Stop }

function Restart-NmServer {
    # Restarts after a countdown the person sees (and can still read over a dropped RDP session).
    [CmdletBinding()]
    param([int]$Seconds = 60, [string]$Reason = 'Nutmeg AD Toolkit: New Forest Build')
    & shutdown.exe /r /t $Seconds /c $Reason /d p:4:1 | Out-Null
}

# ---------------------------------------------------------------------------
# Picking the build up after a restart
# ---------------------------------------------------------------------------
$script:NmResumeTaskName = 'Nutmeg AD Toolkit - New Forest Build'

function Register-NmResumeTask {
    <#
    .SYNOPSIS
        At the next sign-in of any administrator, opens Windows PowerShell on the build again.
    .DESCRIPTION
        The task runs for the Administrators group (S-1-5-32-544), so it still works after promotion,
        when the local Administrator has become the domain's. It is removed when the build finishes.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LauncherPath)
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoExit -NoProfile -File `"$LauncherPath`" -NewForest"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-544' -RunLevel Highest
    $null = Register-ScheduledTask -TaskName $script:NmResumeTaskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop
}

function Unregister-NmResumeTask {
    [CmdletBinding()]
    param()
    Unregister-ScheduledTask -TaskName $script:NmResumeTaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# The domain
# ---------------------------------------------------------------------------
function Test-NmDomainAnswers {
    # True when DNS finds domain controllers for the name (the forest already exists somewhere).
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Domain)
    try {
        $r = @(Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$Domain" -Type SRV -DnsOnly -QuickTimeout -ErrorAction Stop)
        return ($r.Count -gt 0)
    } catch { return $false }
}

function Install-NmAddsFeature {
    # AD DS, DNS, Group Policy Management and the AD module. Returns Success and RestartNeeded.
    [CmdletBinding()]
    param()
    $r = Install-WindowsFeature -Name AD-Domain-Services, DNS, GPMC, RSAT-AD-PowerShell -IncludeManagementTools -ErrorAction Stop
    return [pscustomobject]@{ Success = [bool]$r.Success; RestartNeeded = "$($r.RestartNeeded)" }
}

function Get-NmForestArgs {
    # The Install-ADDSForest / Test-ADDSForestInstallation arguments from the build's answers.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Answers, [Parameter(Mandatory)][securestring]$DsrmPassword)
    return @{
        DomainName                    = $Answers.Domain
        DomainNetbiosName             = $Answers.NetBIOS
        ForestMode                    = $Answers.FunctionalLevel
        DomainMode                    = $Answers.FunctionalLevel
        InstallDns                    = $true
        DatabasePath                  = $Answers.DatabasePath
        LogPath                       = $Answers.LogPath
        SysvolPath                    = $Answers.SysvolPath
        SafeModeAdministratorPassword = $DsrmPassword
        NoRebootOnCompletion          = $true
        Force                         = $true
    }
}

function Test-NmForestInstallation {
    # Microsoft's own pre-checks for the new forest. Returns Status ('Success' or 'Error') and Message.
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$ForestArgs)
    Import-Module ADDSDeployment -ErrorAction Stop
    $a = $ForestArgs.Clone(); $a.Remove('NoRebootOnCompletion')
    $r = Test-ADDSForestInstallation @a -WarningAction SilentlyContinue -ErrorAction Stop
    return [pscustomobject]@{ Status = "$($r.Status)"; Message = "$($r.Message)" }
}

function Install-NmForest {
    # Promotes this server to the first DC of the new forest. No restart: the build restarts it.
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$ForestArgs)
    Import-Module ADDSDeployment -ErrorAction Stop
    $r = Install-ADDSForest @ForestArgs -WarningAction SilentlyContinue -ErrorAction Stop
    return [pscustomobject]@{ Status = "$($r.Status)"; Message = "$($r.Message)" }
}
