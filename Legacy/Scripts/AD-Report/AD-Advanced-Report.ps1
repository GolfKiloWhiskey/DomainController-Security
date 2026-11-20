<#
.NOTES
    Author:  Cliff Waite
    Date:    11/13/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 4.5

.SYNOPSIS
    Generates a branded, single-file HTML Active Directory health and inventory report with an executive summary.

.DESCRIPTION
    - Asks for client name, client logo and output folder at start (Enter for defaults), or takes them as parameters
    - Collects data and writes one self-contained HTML file to C:\Temp\<ClientName> (default) plus findings JSON and a .log file
    - No external modules or internet access needed to view the report: HTML, CSS, charts and scripts are all in the one file
    - Executive summary page for the client: health score, top risks in plain language, how the environment is set up, roadmap
    - Technical pages with a sidebar: findings with why-it-matters / fix / link to the affected items, OU structure tree
    - Every tile and chart bar is clickable and filters the table it describes; tables have views, search, sort, paging and CSV export
    - Findings are also written to a JSON file next to the report for import into other tools
    - Findings dashboard with Critical / Warning / Info / OK items and recommendations
    - Environment overview: functional levels, FSMO roles, schema version, tombstone lifetime, Recycle Bin, SYSVOL replication state (FRS vs DFSR)
    - DC health: reachability, NTDS/DFSR/DNS/Netlogon/KDC/W32Time/ADWS services, SYSVOL/NETLOGON shares, uptime, C: free space
    - Replication: per-DC summary, per-partner/partition detail, replication failures
    - Sites and DNS: sites, subnets, site links, DNS zones, forwarders, scavenging, insecure dynamic updates
    - Users: stale (incl. never logged on), passwords expiring/expired, accounts expiring, new, locked out, default container, full list
    - Groups: type/scope/membership breakdown with charts (primary-group members counted correctly)
    - Privileged access: recursive membership of all built-in privileged groups (SID based, language independent),
      orphaned adminCount, Protected Users coverage, krbtgt and built-in Administrator password age
    - Security: password policy + fine-grained policies, kerberoastable and AS-REP roastable accounts, unconstrained delegation,
      password-not-required, reversible encryption, duplicate SPNs, account lockouts and failed authentications from all DCs
    - Computers: OS breakdown and support status, stale computers, LAPS coverage (legacy and Windows LAPS), default container
    - OUs and Group Policy: link map (domain root, OUs, sites), enforced/disabled links, unlinked/empty GPOs,
      AD vs SYSVOL version mismatches, WMI filters, permissions/security filtering, optional embedded GPO settings reports
    - Logos are embedded into the report (URL, local, or UNC path) and auto-sized so any logo/SVG fits the header
    - Print / PDF button on every page with a print layout (navigation and controls hidden)

.EXAMPLE
    .\Generate-ADReport.ps1
    Asks for the client name, client logo and output folder (Enter accepts each default), then runs.

.EXAMPLE
    .\Generate-ADReport.ps1 -ClientName "Contoso Healthcare" -RightLogo "https://www.contoso.com/images/logo.svg"
    Report title becomes "Contoso Healthcare - Active Directory Report"; files go to C:\Temp\Contoso Healthcare.
    Only the values not given on the command line are asked for.

.EXAMPLE
    .\Generate-ADReport.ps1 -ClientName "Contoso Healthcare" -RightLogo "\\server\share\clientlogo.png" -SavePath "D:\Reports" -NoPrompt
    Fully unattended (scheduled task / RMM): no questions at the start or the end.

.VERSIONING
    v4.5 - 11/14/2026
        - Performance: each DC's Security log is now read once (new "DC Security Logs" step) and shared by the modified
                       objects and authentication sections; events are read with EventLogReader and only the needed
                       fields, instead of Get-WinEvent formatting every message. Capped at 30,000 events per DC
        - Performance: when AD does not return change history in the bulk query, each object is read with a direct
                       base query instead of Get-ADReplicationAttributeMetadata
        - Added: log lines showing events read and seconds per DC, and how the change history was collected
        - Fixed: Get-ADReplicationFailure used -EnumerationServer (that cmdlet's parameter is -EnumeratingServer), so
                 replication failures were never collected
    v4.4 - 11/13/2026
        - Added: -ClientName parameter; the report title is always "<ClientName> - Active Directory Report"
        - Added: start-up questions for client name (required), client logo and output folder, each skipped when
                 given as a parameter; Enter accepts the default; a client logo path that does not exist is asked again
        - Changed: default output folder is C:\Temp\<ClientName>; report, JSON and log file names start with the client name
        - Changed: the NetBIOS name is no longer used as the client name; unattended runs without -ClientName use the
                   DNS domain name and log a warning
        - Changed: -NoPrompt now also skips the start-up questions; -ReportTitle is still accepted (client name is taken from it)
    v4.3 - 11/13/2026
        - Changed: a site with domain controllers but no subnets is now a Warning (was Advisory); a site with
                   no subnets and no DCs stays Advisory
        - Added: domain controller subnet check - each DC's IP must fall in a subnet of its own site (Warning if not)
        - Added: Passed finding when sites and subnets are correct; plain-language wording for the subnet findings
        - Added: Subnets = 0 highlighted in the sites table, No subnets / Has subnets views, Warning label on the
                 executive summary Sites line
        - Fixed: findings JSON was written with a UTF-8 byte-order mark, which strict JSON parsers reject
    v4.2 - 11/13/2026
        - Added: modified objects now show what changed (from AD replication metadata), a change type
                 (Directory change / Password change / Routine) and who changed it (from DC security log events, when audited)
        - Added: Change detail table, one row per changed attribute, group member added/removed and matching security event;
                 clicking an object name in the modified objects table filters the detail to that object
    v4.1 - 11/13/2026
        - Added: prompt at the end of the run to open the report, the output folder, or both (Enter opens the report)
        - Added: -NoPrompt switch for unattended runs; the prompt is also skipped automatically in non-interactive sessions
        - Changed: the closing "Findings" summary line is logged as WARN instead of ERROR when critical findings exist
    v4.0 - 11/13/2026
        - New report design, rendered by the script itself: the ReportHtml module and its CDN-hosted scripts are no longer used
        - Added: Executive summary page (health score, severity counts, top risks in plain language, environment setup, roadmap)
        - Added: Sidebar navigation with a critical/warning count per section
        - Added: Findings list with severity filter; each finding expands to why it matters, the fix and a link to the affected items
        - Added: OU structure tree with user, computer and GPO link counts per OU
        - Added: Clickable tiles and chart bars that filter the related table (pie charts replaced by bar charts)
        - Added: Table views, per-table search, column sorting, paging and CSV export of the current view
        - Added: Findings JSON export next to the report (-NoFindingsJson to skip), -AccentColor parameter
        - Changed: Separate user / computer sub-tables (stale, expiring, new, locked out, default container, unsupported OS,
                   missing LAPS) are now views of one user table and one computer table - same rows and columns
        - Changed: GPO settings reports load on demand when a GPO is opened (faster page load)
        - Changed: Default -LogoHeight is now 60
        - Fixed: stale-user count in v3.0 could include every enabled user (a loop variable overwrote the -Days threshold)
        - Unchanged: all other data collection and findings logic from v3.0
    v3.0 - 11/09/2026
        - Fixed: Enterprise Admins query passed -Server twice (table always empty, message said members "were" found)
        - Fixed: Group membership query passed -Identity twice (every group showed zero members)
        - Fixed: ActiveDirectory / GroupPolicy were being "installed" from PSGallery; now detected via -ListAvailable and installed from RSAT
        - Fixed: ReportHtml and NuGet were re-installed on every run
        - Fixed: Privileged Accounts tab was always empty ($PrivGroupMembers never populated)
        - Fixed: GPO User/Computer versions always 0; now read from AD versionNumber
        - Fixed: Stale users used non-replicated lastLogon and silently dropped never-logged-on accounts; now LastLogonDate
        - Fixed: Dashboard counts showed 1 when the real value was 0 (placeholder rows counted)
        - Fixed: Password expiry broke for fine-grained policies; now msDS-UserPasswordExpiryTimeComputed
        - Fixed: WMI filter output, <details open="false"> rendering, GPO reports breaking page CSS (now isolated iframes)
        - Fixed: Linked GPO counts ignored domain root and site links; link order/enforced/disabled now shown
        - Fixed: Replication summary used wrong property names; failures now detected correctly
        - Fixed: Security events read from the local machine only; now lockouts/failures collected from every DC
        - Fixed: Get-Service -ComputerName (not available in PowerShell 7) replaced with CIM (WSMan with DCOM fallback)
        - Fixed: Logo auto-sizing; logos embedded as base64 so the report works offline / in IT Glue
        - Added: Findings dashboard, DFSR/FRS SYSVOL state, functional levels, schema version, tombstone lifetime,
                 krbtgt / built-in Administrator checks, kerberoasting / AS-REP / delegation checks, LAPS coverage,
                 OS support status, stale computers, fine-grained password policies, site links, DNS forwarders/scavenging,
                 GPO AD/SYSVOL version mismatch, unlinked/empty GPOs, UPN suffix usage, collection error log
        - Added: Write-Log (console + .log file), timestamped file names, progress bar, per-section error handling
        - Performance: explicit property lists instead of -Properties *, GPO data cached, no per-user policy lookups
        - Removed: unused -ADRegion parameter (privileged groups are now resolved by SID, so any language works)
    v2.0 - 07/19/2024
        - Added extended health sections: replication, DNS, sites/subnets, trusts, SYSVOL/DFSR, authentication, SPN audit, privileged accounts
    v1.0
        - Initial AD report: users, groups, OUs, GPOs, computers with ReportHtml charts
#>

[CmdletBinding()]
param (
    # Logo shown on the left of the header (URL, local path or UNC path)
    [string]$CompanyLogo = "https://nutmegtech.com/wp-content/uploads/2025/09/logo-1.png",

    # Client name shown on the report. The title becomes "<ClientName> - Active Directory Report". Asked for at start if not given
    [string]$ClientName,

    # Logo shown on the right of the header, usually the client's (URL, local path or UNC path). Asked for at start if not given
    [string]$RightLogo,

    # Full report title override. Normally leave this empty and use -ClientName
    [string]$ReportTitle,

    # Users that have not logged on in X days (stale users)
    [ValidateRange(1, 1825)]
    [int]$Days = 365,

    # Users created in the last X days
    [ValidateRange(1, 365)]
    [int]$UserCreatedDays = 30,

    # Users whose password expires in X days or less
    [ValidateRange(1, 365)]
    [int]$DaysUntilPWExpireINT = 30,

    # AD objects modified in the last X days
    [ValidateRange(1, 365)]
    [int]$ADModNumber = 30,

    # User accounts that expire in X days or less
    [ValidateRange(1, 365)]
    [int]$AccountExpiringDays = 30,

    # Computers that have not logged on in X days (stale computers)
    [ValidateRange(1, 1825)]
    [int]$StaleComputerDays = 90,

    # Days of DC security logs to scan for lockouts / failed authentications
    [ValidateRange(1, 30)]
    [int]$EventLogDays = 3,

    # Height in pixels for both header logos
    [ValidateRange(30, 300)]
    [int]$LogoHeight = 60,

    # Accent color (hex) for the stripe and highlights, e.g. a brand color
    [string]$AccentColor = '#C8102E',

    # Folder the report, findings JSON and log are written to. Default: C:\Temp\<ClientName>. Asked for at start if not given
    [string]$SavePath,

    # Domain controller to query. Defaults to the PDC Emulator
    [string]$Server,

    # Skip embedding the full settings report of every GPO (smaller, faster report)
    [switch]$SkipGPOSettings,

    # Skip collecting lockout / failed authentication events from DCs
    [switch]$SkipEventLogs,

    # Do not write the findings JSON file next to the report
    [switch]$NoFindingsJson,

    # Open the report in the default browser when finished, without asking
    [switch]$OpenReport,

    # Do not ask anything at the start or the end (for scheduled or RMM runs)
    [switch]$NoPrompt
)

$ScriptVersion = '4.5'
$RunStart      = Get-Date
$RunStamp      = $RunStart.ToString('yyyyMMdd-HHmm-ss')
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Helpers - Logging and section handling
# ---------------------------------------------------------------------------

$script:LogFile = $null

function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DETAIL')][string]$Level = 'INFO'
    )
    $line  = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $color = switch ($Level) {
        'INFO'    { 'Cyan' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
        'DETAIL'  { 'DarkGray' }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:LogFile) {
        try { Add-Content -Path $script:LogFile -Value $line -ErrorAction Stop } catch { }
    }
}

$script:SectionIndex = 0
$script:SectionTotal = 17

function Invoke-Section {
    param (
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )
    $script:SectionIndex++
    $pct = [math]::Min(100, [int](($script:SectionIndex / $script:SectionTotal) * 100))
    Write-Progress -Activity "Active Directory Report v$ScriptVersion" -Status $Name -PercentComplete $pct
    Write-Log "Collecting: $Name"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ErrorActionPreference = 'Stop'
    try {
        & $ScriptBlock
        Write-Log ("  Done: {0} ({1}s)" -f $Name, [math]::Round($sw.Elapsed.TotalSeconds, 1)) 'SUCCESS'
    }
    catch {
        Write-Log ("  Failed: {0} - {1}" -f $Name, $_.Exception.Message) 'ERROR'
        $script:R.Errors.Add([PSCustomObject]@{ Section = $Name; Item = ''; Error = $_.Exception.Message })
    }
}

function Add-CollectionError {
    param ([string]$Section, [string]$Item, [string]$Message)
    Write-Log ("  {0}: {1} - {2}" -f $Section, $Item, $Message) 'WARN'
    $script:R.Errors.Add([PSCustomObject]@{ Section = $Section; Item = $Item; Error = $Message })
}

function Invoke-Check {
    param ([scriptblock]$Check)
    try { & $Check } catch { Write-Log "Findings check failed: $($_.Exception.Message)" 'WARN' }
}

# ---------------------------------------------------------------------------
# Helpers - Data formatting
# ---------------------------------------------------------------------------

function Format-Date {
    param ($Date, [string]$Empty = '')
    if ($null -eq $Date -or $Date -isnot [datetime]) { if ($Date) { return [string]$Date } else { return $Empty } }
    return $Date.ToString('yyyy-MM-dd HH:mm')
}

function ConvertTo-YesNo {
    param ($Value)
    if ($null -eq $Value) { return '' }
    if ([bool]$Value) { return 'Yes' } else { return 'No' }
}

function Get-NameFromDN {
    param ([string]$DN)
    if ([string]::IsNullOrEmpty($DN)) { return $null }
    if ($DN -match '^(?:CN|OU)=((?:[^,\\]|\\.)+)') { return ($Matches[1] -replace '\\(.)', '$1') }
    return $DN
}

function Get-ParentDN {
    param ([string]$DN)
    if ($DN -match '^(?:[^,\\]|\\.)+,(.+)$') { return $Matches[1] }
    return $null
}

function Get-RID {
    param ([string]$Sid)
    if ($Sid -match '-(\d+)$') { return [int]$Matches[1] }
    return $null
}

function Get-Rows {
    # Returns the data as an array, or a single "Information" row when empty (keeps real counts separate)
    param ($Data, [string]$EmptyMessage = 'No data found')
    $arr = @($Data | Where-Object { $null -ne $_ })
    if ($arr.Count -eq 0) { return , @([PSCustomObject]@{ Information = "Information: $EmptyMessage" }) }
    return , $arr
}

function Get-PasswordExpiry {
    param ($User)
    if ($User.PasswordNeverExpires) { return 'Never' }
    $raw = $User.'msDS-UserPasswordExpiryTimeComputed'
    if ($null -eq $raw) { return $null }
    $raw = [int64]$raw
    if ($raw -eq 0) { return 'Must change at next logon' }
    if ($raw -ge [int64]::MaxValue -or $raw -lt 0) { return 'Never' }
    try { return [DateTime]::FromFileTime($raw) } catch { return $null }
}

function Get-OSFamily {
    param ([string]$OS)
    if ([string]::IsNullOrWhiteSpace($OS)) { return 'Unknown' }
    if ($OS -match '(Windows (Server )?(\d+|XP|Vista)?( R2)?)') { return $Matches[1].Trim() }
    return $OS
}

function Get-OSSupportStatus {
    param ([string]$OS)
    if ([string]::IsNullOrWhiteSpace($OS)) { return 'Unknown' }
    if ($OS -match 'Windows (XP|Vista|7|8)\b|Windows 8\.1|Server 2003|Server 2008|Server 2012') { return 'Unsupported' }
    if ($OS -match 'Windows 10.*LTSC') { return 'Supported (LTSC - check edition date)' }
    if ($OS -match 'Windows 10') { return 'Unsupported (ESU only)' }
    if ($OS -match 'Server 2016') { return 'Support ends Jan 2027' }
    if ($OS -match 'Windows') { return 'Supported' }
    return 'Non-Windows'
}

function Get-TrusteeName {
    param ($Permission)
    if ($Permission.Trustee -and $Permission.Trustee.Name) { return [string]$Permission.Trustee.Name }
    return [string]$Permission.Trustee
}

function Get-PropValue {
    # Returns the first property that exists on the object (guards against property-name differences between OS versions)
    param ($Object, [string[]]$Names)
    foreach ($n in $Names) {
        if ($Object.PSObject.Properties.Name -contains $n) { return $Object.$n }
    }
    return $null
}

function Test-IPv4InSubnet {
    # True when an IPv4 address falls inside a CIDR subnet such as 10.0.0.0/24 (IPv6 subnets are ignored)
    param([string]$IP, [string]$Cidr)
    if ($IP -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or $Cidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') { return $false }
    $net  = $Matches[1]
    $bits = [int]$Matches[2]
    if ($bits -gt 32) { return $false }
    $toInt = { param($a) $b = ([System.Net.IPAddress]::Parse($a)).GetAddressBytes(); ([uint32]$b[0] -shl 24) -bor ([uint32]$b[1] -shl 16) -bor ([uint32]$b[2] -shl 8) -bor [uint32]$b[3] }
    try {
        $mask = if ($bits -eq 0) { [uint32]0 } else { [uint32]([uint32]::MaxValue -shl (32 - $bits)) }
        return (((& $toInt $IP) -band $mask) -eq ((& $toInt $net) -band $mask))
    }
    catch { return $false }
}

function Read-DCSecurityLog {
    # Reads matching Security log events from one computer without formatting message text.
    # Returns objects with Id, Time and Data (hashtable of the requested EventData fields).
    param([string]$Computer, [string]$Query, [string[]]$Fields, [int]$Max = 30000, [string]$Label)
    $local = @($env:COMPUTERNAME, "$env:COMPUTERNAME.$env:USERDNSDOMAIN") -contains $Computer -or $Computer -eq 'localhost'
    $session = if ($local) { $null } else { [System.Diagnostics.Eventing.Reader.EventLogSession]::new($Computer) }
    $q = [System.Diagnostics.Eventing.Reader.EventLogQuery]::new('Security', [System.Diagnostics.Eventing.Reader.PathType]::LogName, $Query)
    $q.ReverseDirection = $true
    if ($session) { $q.Session = $session }
    $xpaths   = [string[]]@($Fields | ForEach-Object { "Event/EventData/Data[@Name='$_']" })
    $selector = [System.Diagnostics.Eventing.Reader.EventLogPropertySelector]::new($xpaths)
    $reader   = [System.Diagnostics.Eventing.Reader.EventLogReader]::new($q)
    $out = [System.Collections.Generic.List[object]]::new()
    try {
        while ($out.Count -lt $Max) {
            $rec = $reader.ReadEvent()
            if ($null -eq $rec) { break }
            try {
                $vals = $rec.GetPropertyValues($selector)
                $data = @{}
                for ($i = 0; $i -lt $Fields.Count; $i++) { if ($null -ne $vals[$i]) { $data[$Fields[$i]] = [string]$vals[$i] } }
                $out.Add([PSCustomObject]@{ Id = [int]$rec.Id; Time = $rec.TimeCreated; Data = $data })
            }
            finally { $rec.Dispose() }
            if ($out.Count % 1000 -eq 0) { Write-Progress -Id 2 -ParentId 0 -Activity "Reading Security log on $Label" -Status "$($out.Count) events" }
        }
    }
    finally {
        $reader.Dispose()
        if ($session) { $session.Dispose() }
        Write-Progress -Id 2 -Activity "Reading Security log on $Label" -Completed
    }
    return , $out
}

function Get-PartitionName {
    param ([string]$Partition)
    if ($Partition -eq $Ctx.DomainDN) { return 'Domain' }
    if ($Partition -eq $Ctx.ConfigNC) { return 'Configuration' }
    if ($Partition -eq $Ctx.SchemaNC) { return 'Schema' }
    if ($Partition -like 'DC=DomainDnsZones*') { return 'DomainDnsZones' }
    if ($Partition -like 'DC=ForestDnsZones*') { return 'ForestDnsZones' }
    return $Partition
}

function Get-GPLinks {
    # Parses a gPLink attribute into link objects (link order 1 = highest precedence)
    param ([string]$GPLink)
    $links = @()
    if ([string]::IsNullOrWhiteSpace($GPLink)) { return , $links }
    $found = [regex]::Matches($GPLink, '\[LDAP://([^;\]]+);(\d+)\]')
    $count = $found.Count
    for ($i = 0; $i -lt $count; $i++) {
        $m    = $found[$i]
        $opt  = [int]$m.Groups[2].Value
        $guid = $null
        if ($m.Groups[1].Value -match '\{([0-9A-Fa-f\-]{36})\}') { $guid = $Matches[1].ToUpper() }
        $links += [PSCustomObject]@{
            Guid      = $guid
            LinkOrder = $count - $i
            Enabled   = -not [bool]($opt -band 1)
            Enforced  = [bool]($opt -band 2)
        }
    }
    return , $links
}

$StatusMap = @{
    '0x6'        = 'Unknown username'
    '0x12'       = 'Account disabled, expired or locked out'
    '0x17'       = 'Password expired'
    '0x18'       = 'Bad password'
    '0x25'       = 'Clock skew'
    '0xc0000064' = 'Unknown username'
    '0xc000006a' = 'Bad password'
    '0xc000006d' = 'Bad username or password'
    '0xc000006e' = 'Account restriction'
    '0xc000006f' = 'Outside logon hours'
    '0xc0000070' = 'Workstation restriction'
    '0xc0000071' = 'Password expired'
    '0xc0000072' = 'Account disabled'
    '0xc0000133' = 'Clock skew'
    '0xc000015b' = 'Logon type not granted'
    '0xc0000193' = 'Account expired'
    '0xc0000224' = 'Must change password'
    '0xc0000234' = 'Account locked out'
}

function Get-StatusText {
    param ([string]$Code)
    if ([string]::IsNullOrEmpty($Code)) { return '' }
    $c = $Code.ToLower()
    if ($StatusMap.ContainsKey($c)) { return $StatusMap[$c] }
    return $Code
}

# ---------------------------------------------------------------------------
# Helpers - Logos
# ---------------------------------------------------------------------------

function Get-ImageMime {
    param ([byte[]]$Bytes, [string]$Name)
    if ($Bytes.Length -ge 4) {
        if ($Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50) { return 'image/png' }
        if ($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8) { return 'image/jpeg' }
        if ($Bytes[0] -eq 0x47 -and $Bytes[1] -eq 0x49) { return 'image/gif' }
        if ($Bytes[0] -eq 0x52 -and $Bytes[1] -eq 0x49) { return 'image/webp' }
    }
    $head = [System.Text.Encoding]::UTF8.GetString($Bytes, 0, [Math]::Min(1024, $Bytes.Length))
    if ($head -match '<svg') { return 'image/svg+xml' }
    switch -Regex ($Name) {
        '\.svg'    { return 'image/svg+xml' }
        '\.jpe?g'  { return 'image/jpeg' }
        '\.gif'    { return 'image/gif' }
        default    { return 'image/png' }
    }
}

function Get-LogoSource {
    # Embeds the logo as a base64 data URI so the report is self-contained; falls back to the original link
    param ([string]$Logo)
    $blank = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'
    if ([string]::IsNullOrWhiteSpace($Logo)) { return $blank }
    if ($Logo -like 'data:*') { return $Logo }
    $bytes = $null
    try {
        if ($Logo -match '^https?://') {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
            $bytes = $wc.DownloadData($Logo)
            $wc.Dispose()
        }
        elseif (Test-Path -LiteralPath $Logo) {
            $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Logo).ProviderPath)
        }
        else {
            Write-Log "Logo not found: $Logo" 'WARN'
            return $blank
        }
    }
    catch {
        Write-Log "Could not embed logo '$Logo' ($($_.Exception.Message)). Linking to it instead." 'WARN'
        return $Logo
    }
    if (-not $bytes -or $bytes.Length -eq 0) { return $Logo }
    $mime = Get-ImageMime -Bytes $bytes -Name $Logo
    return "data:$mime;base64,$([Convert]::ToBase64String($bytes))"
}

# ---------------------------------------------------------------------------
# Helpers - Modules
# ---------------------------------------------------------------------------

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Install-RsatComponent {
    param ([ValidateSet('AD', 'GP')][string]$Component)
    if (-not $IsAdmin) {
        Write-Log "RSAT $Component tools are missing and the session is not elevated - cannot install them." 'WARN'
        return
    }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    try {
        if ($os.ProductType -ne 1) {
            $feature = @{ AD = 'RSAT-AD-PowerShell'; GP = 'GPMC' }[$Component]
            Write-Log "Installing Windows feature $feature..." 'INFO'
            Install-WindowsFeature -Name $feature -ErrorAction Stop | Out-Null
        }
        else {
            $cap = @{ AD = 'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'; GP = 'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0' }[$Component]
            Write-Log "Installing Windows capability $cap (this can take a few minutes)..." 'INFO'
            Add-WindowsCapability -Online -Name $cap -ErrorAction Stop | Out-Null
        }
        Write-Log "RSAT $Component tools installed." 'SUCCESS'
    }
    catch {
        Write-Log "Failed to install RSAT $Component tools: $($_.Exception.Message)" 'ERROR'
    }
}

function Import-WindowsModule {
    # Imports a Windows module natively; under PowerShell 7 tries -SkipEditionCheck first, then Windows compatibility
    param ([string]$Name)
    if ($PSVersionTable.PSEdition -eq 'Core') {
        try { Import-Module -Name $Name -SkipEditionCheck -ErrorAction Stop -WarningAction SilentlyContinue; return $true } catch { }
    }
    try { Import-Module -Name $Name -ErrorAction Stop -WarningAction SilentlyContinue; return $true } catch { return $false }
}

# ---------------------------------------------------------------------------
# Main Logic - Pre-flight
# ---------------------------------------------------------------------------

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   ACTIVE DIRECTORY HEALTH REPORT            " -ForegroundColor Yellow
Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
Write-Host "   Email:cliff.ps@nutmegtech.com             " -ForegroundColor DarkGray
Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
Write-Host "=============================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Main Logic - Report settings (asked for at start unless given as parameters)
# ---------------------------------------------------------------------------

$script:CanPrompt = [Environment]::UserInteractive -and -not ([Environment]::GetCommandLineArgs() -match '^-NonI') -and -not $NoPrompt
$TitleSuffix = ' - Active Directory Report'

function Read-Setting {
    # Prompt with a default; Enter keeps the default
    param([string]$Prompt, [string]$Default, [string]$DefaultLabel)
    $label = if ($DefaultLabel) { $DefaultLabel } elseif ($Default) { $Default } else { 'none' }
    $answer = $null
    try { $answer = Read-Host "$Prompt (Press Enter for Default: $label)" } catch { return $Default }
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim().Trim('"').Trim("'")
}

function Get-SafeFolderName {
    param([string]$Name)
    # Characters Windows does not allow in file or folder names, plus control characters
    $safe = (($Name -replace '[\\/:*?"<>|\x00-\x1F]', '') -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($safe) { return $safe } else { return 'Client' }
}

# Client name: from -ClientName, else from a -ReportTitle that was given, else asked for
if ([string]::IsNullOrWhiteSpace($ClientName) -and -not [string]::IsNullOrWhiteSpace($ReportTitle)) {
    $ClientName = ($ReportTitle -replace '\s*[-|]\s*Active Directory Report\s*$', '').Trim()
}
if ([string]::IsNullOrWhiteSpace($ClientName) -and $script:CanPrompt) {
    Write-Host ""
    Write-Host "Report settings" -ForegroundColor Cyan
    Write-Host "Use the client's real business name - the AD domain name is often not meaningful (e.g. DOMAIN1, NTDOMAIN)." -ForegroundColor DarkGray
    while ([string]::IsNullOrWhiteSpace($ClientName)) {
        try { $ClientName = (Read-Host "Client name (required, e.g. Contoso Healthcare)").Trim() } catch { break }
        if ([string]::IsNullOrWhiteSpace($ClientName)) { Write-Host "A client name is required." -ForegroundColor Red }
    }
}
$ClientNameFromDomain = [string]::IsNullOrWhiteSpace($ClientName)   # filled in from the domain later if still empty

# Client logo
if (-not $PSBoundParameters.ContainsKey('RightLogo') -and $script:CanPrompt) {
    while ($true) {
        $RightLogo = Read-Setting -Prompt 'Client logo - URL, local or UNC path' -Default '' -DefaultLabel 'no client logo'
        if (-not $RightLogo -or $RightLogo -match '^(https?://|data:)' -or (Test-Path -LiteralPath $RightLogo -PathType Leaf)) { break }
        Write-Host "File not found: $RightLogo  (Enter to skip the client logo)" -ForegroundColor Red
    }
}

# Output folder: default C:\Temp\<Client name>
$defaultFolder = if ($ClientNameFromDomain) { 'C:\Temp' } else { 'C:\Temp\' + (Get-SafeFolderName $ClientName) }
if ([string]::IsNullOrWhiteSpace($SavePath)) {
    $SavePath = if ($script:CanPrompt) { Read-Setting -Prompt 'Output folder' -Default $defaultFolder } else { $defaultFolder }
}

if (-not [string]::IsNullOrWhiteSpace($ClientName)) { $ReportTitle = "$ClientName$TitleSuffix" }
Write-Host ""

if (-not (Test-Path -LiteralPath $SavePath)) {
    try { New-Item -Path $SavePath -ItemType Directory -Force | Out-Null }
    catch { Write-Host "Cannot create $SavePath : $($_.Exception.Message)" -ForegroundColor Red; return }
}
$script:LogFile = Join-Path $SavePath "ADReport-$RunStamp.log"

Write-Log "Report settings:"
Write-Log ("  Client: {0}" -f $(if ($ClientNameFromDomain) { '(not given - the domain name will be used)' } else { $ClientName })) 'DETAIL'
Write-Log ("  Left logo: {0}" -f $CompanyLogo) 'DETAIL'
Write-Log ("  Right logo: {0}" -f $(if ($RightLogo) { $RightLogo } else { '(none)' })) 'DETAIL'
Write-Log ("  Stale users: {0} days | New users: {1} days | Password expiry: {2} days | Modified objects: {3} days" -f $Days, $UserCreatedDays, $DaysUntilPWExpireINT, $ADModNumber) 'DETAIL'
Write-Log ("  Account expiry: {0} days | Stale computers: {1} days | Event logs: {2} days" -f $AccountExpiringDays, $StaleComputerDays, $EventLogDays) 'DETAIL'
Write-Log ("  Output folder: {0}" -f $SavePath) 'DETAIL'

if (-not $IsAdmin) {
    Write-Log "Not running elevated. DC security logs and some health checks may be unavailable." 'WARN'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ActiveDirectory (RSAT) - required
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) { Install-RsatComponent -Component AD }
if (-not (Import-WindowsModule -Name ActiveDirectory)) {
    Write-Log "The ActiveDirectory module is not available. Install RSAT AD tools (or run on a DC) and try again." 'ERROR'
    return
}

# GroupPolicy (RSAT) - optional (permissions, security filtering, settings reports)
$GPModule = $false
if (-not (Get-Module -ListAvailable -Name GroupPolicy)) { Install-RsatComponent -Component GP }
if (Get-Module -ListAvailable -Name GroupPolicy) { $GPModule = Import-WindowsModule -Name GroupPolicy }
if (-not $GPModule) { Write-Log "GroupPolicy module unavailable - GPO permissions and settings reports will be skipped." 'WARN' }

# DnsServer - optional, never auto-installed
$DnsModule = $false
if (Get-Module -ListAvailable -Name DnsServer) { $DnsModule = Import-WindowsModule -Name DnsServer }
if (-not $DnsModule) { Write-Log "DnsServer module unavailable - DNS section skipped (add the RSAT-DNS-Server feature to include it)." 'WARN' }

# ---------------------------------------------------------------------------
# Main Logic - Domain context
# ---------------------------------------------------------------------------

$script:R = @{
    Errors   = [System.Collections.Generic.List[object]]::new()
    Findings = [System.Collections.Generic.List[object]]::new()
}
$R = $script:R

try {
    if ($Server) {
        $ADDomain = Get-ADDomain -Server $Server -ErrorAction Stop
        $DC = $Server
    }
    else {
        $ADDomain = Get-ADDomain -ErrorAction Stop
        $DC = $ADDomain.PDCEmulator
        try { $null = Get-ADDomain -Server $DC -ErrorAction Stop }
        catch {
            Write-Log "PDC Emulator $DC is not reachable - using the nearest DC instead." 'WARN'
            $DC = [string](Get-ADDomainController -Discover -DomainName $ADDomain.DNSRoot -ErrorAction Stop).HostName
        }
    }
    $ADForest = Get-ADForest -Server $DC -ErrorAction Stop
    $RootDSE  = Get-ADRootDSE -Server $DC -ErrorAction Stop
}
catch {
    Write-Log "Unable to contact Active Directory: $($_.Exception.Message)" 'ERROR'
    return
}

$Ctx = @{
    DC         = $DC
    DomainDN   = $ADDomain.DistinguishedName
    DomainDNS  = $ADDomain.DNSRoot
    NetBIOS    = $ADDomain.NetBIOSName
    DomainSID  = $ADDomain.DomainSID.Value
    ConfigNC   = $RootDSE.configurationNamingContext
    SchemaNC   = $RootDSE.schemaNamingContext
    RootDomain = $ADForest.RootDomain
    RootServer = $DC
    RootSID    = $ADDomain.DomainSID.Value
}
if ($ADForest.RootDomain -ne $ADDomain.DNSRoot) {
    try {
        $rootDom = Get-ADDomain -Identity $ADForest.RootDomain -Server $ADForest.RootDomain -ErrorAction Stop
        $Ctx.RootServer = $ADForest.RootDomain
        $Ctx.RootSID    = $rootDom.DomainSID.Value
    }
    catch { Add-CollectionError -Section 'Context' -Item 'Forest root domain' -Message $_.Exception.Message }
}

if ($ClientNameFromDomain) {
    # Unattended run with no -ClientName: use the DNS domain name (more readable than NetBIOS), and say so
    $ClientName  = $Ctx.DomainDNS
    $ReportTitle = "$ClientName$TitleSuffix"
    Write-Log "No client name given - the report is labelled '$ClientName'. Use -ClientName to set the business name." 'WARN'
}

Write-Log ("Domain: {0} | Forest: {1} | Querying DC: {2}" -f $Ctx.DomainDNS, $ADForest.Name, $DC)

#Array of default Security Groups (used together with RID < 1000 to flag built-in groups)
$DefaultSGs = @(
    "Access Control Assistance Operators", "Account Operators", "Administrators", "Allowed RODC Password Replication Group",
    "Backup Operators", "Certificate Service DCOM Access", "Cert Publishers", "Cloneable Domain Controllers",
    "Cryptographic Operators", "Denied RODC Password Replication Group", "Distributed COM Users", "DnsUpdateProxy",
    "DnsAdmins", "Domain Admins", "Domain Computers", "Domain Controllers", "Domain Guests", "Domain Users",
    "Enterprise Admins", "Enterprise Key Admins", "Enterprise Read-only Domain Controllers", "Event Log Readers",
    "Group Policy Creator Owners", "Guests", "Hyper-V Administrators", "IIS_IUSRS", "Incoming Forest Trust Builders",
    "Key Admins", "Network Configuration Operators", "Performance Log Users", "Performance Monitor Users",
    "Print Operators", "Pre-Windows 2000 Compatible Access", "Protected Users", "RAS and IAS Servers",
    "RDS Endpoint Servers", "RDS Management Servers", "RDS Remote Access Servers", "Read-only Domain Controllers",
    "Remote Desktop Users", "Remote Management Users", "Replicator", "Schema Admins", "Server Operators",
    "Storage Replica Administrators", "System Managed Accounts Group", "Terminal Server License Servers", "Users",
    "Windows Authorization Access Group", "WinRMRemoteWMIUsers__", "WinRMRemoteWMIUsers", "OpenSSH Users"
)

# ---------------------------------------------------------------------------
# Main Logic - Data collection
# ---------------------------------------------------------------------------

Invoke-Section 'Environment' {
    $info = [ordered]@{}
    $info['Domain']                = $Ctx.DomainDNS
    $info['NetBIOS Name']          = $Ctx.NetBIOS
    $info['Forest']                = $ADForest.Name
    $info['Domain Functional Level'] = [string]$ADDomain.DomainMode
    $info['Forest Functional Level'] = [string]$ADForest.ForestMode

    $schemaMap = @{ 13 = 'Windows 2000'; 30 = 'Server 2003'; 31 = 'Server 2003 R2'; 44 = 'Server 2008'; 47 = 'Server 2008 R2';
                    56 = 'Server 2012'; 69 = 'Server 2012 R2'; 87 = 'Server 2016'; 88 = 'Server 2019 / 2022'; 91 = 'Server 2025' }
    $schemaVer = (Get-ADObject -Identity $Ctx.SchemaNC -Server $DC -Properties objectVersion).objectVersion
    $schemaTxt = if ($schemaMap.ContainsKey([int]$schemaVer)) { $schemaMap[[int]$schemaVer] } else { 'Unknown' }
    $info['Schema Version'] = "$schemaVer ($schemaTxt)"
    $R.SchemaVersion = [int]$schemaVer

    $info['PDC Emulator']          = $ADDomain.PDCEmulator
    $info['RID Master']            = $ADDomain.RIDMaster
    $info['Infrastructure Master'] = $ADDomain.InfrastructureMaster
    $info['Schema Master']         = $ADForest.SchemaMaster
    $info['Domain Naming Master']  = $ADForest.DomainNamingMaster

    $rb = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'" -Server $DC
    $R.RecycleBin = (@($rb.EnabledScopes).Count -gt 0)
    $info['AD Recycle Bin'] = if ($R.RecycleBin) { 'Enabled' } else { 'Disabled' }

    $tsl = $null
    try { $tsl = (Get-ADObject -Identity "CN=Directory Service,CN=Windows NT,CN=Services,$($Ctx.ConfigNC)" -Server $DC -Properties tombstoneLifetime).tombstoneLifetime } catch { }
    $R.Tombstone = if ($tsl) { [int]$tsl } else { 60 }
    $info['Tombstone Lifetime (days)'] = if ($tsl) { $tsl } else { '60 (not set - legacy default)' }

    # SYSVOL replication engine
    $sysvolState = 'Unknown'
    $flags = $null
    try { $flags = (Get-ADObject -Identity "CN=DFSR-GlobalSettings,CN=System,$($Ctx.DomainDN)" -Server $DC -Properties 'msDFSR-Flags').'msDFSR-Flags' } catch { }
    $dfsrSysvol = $false
    $frsSysvol  = $false
    try { $null = Get-ADObject -Identity "CN=Domain System Volume,CN=DFSR-GlobalSettings,CN=System,$($Ctx.DomainDN)" -Server $DC; $dfsrSysvol = $true } catch { }
    try { $null = Get-ADObject -Identity "CN=Domain System Volume (SYSVOL share),CN=File Replication Service,CN=System,$($Ctx.DomainDN)" -Server $DC; $frsSysvol = $true } catch { }
    if ($null -ne $flags) {
        $sysvolState = switch ([int]$flags) {
            0  { 'FRS - DFSR migration at Start state' }
            16 { 'Migration in progress - Prepared' }
            32 { 'Migration in progress - Redirected' }
            48 { 'DFSR (migration Eliminated)' }
            default { "Unknown (msDFSR-Flags = $flags)" }
        }
    }
    elseif ($dfsrSysvol) { $sysvolState = 'DFSR' }
    elseif ($frsSysvol)  { $sysvolState = 'FRS - migration to DFSR required' }
    $R.SysvolState = $sysvolState
    $info['SYSVOL Replication'] = $sysvolState

    $info['Domain Controllers'] = ''
    $info['UPN Suffixes'] = (@($ADDomain.DNSRoot) + @($ADForest.UPNSuffixes)) -join ', '

    $R.EnvironmentRaw = $info
}

Invoke-Section 'Domain Controllers' {
    $dcs = @(Get-ADDomainController -Filter * -Server $DC)
    $R.DCNames = @($dcs | ForEach-Object { $_.Name })
    $R.DCs = @(foreach ($d in $dcs) {
        [PSCustomObject]@{
            'Name'             = $d.Name
            'Host Name'        = $d.HostName
            'IP Address'       = $d.IPv4Address
            'Operating System' = $d.OperatingSystem
            'Site'             = $d.Site
            'Global Catalog'   = ConvertTo-YesNo $d.IsGlobalCatalog
            'Read Only'        = ConvertTo-YesNo $d.IsReadOnly
            'FSMO Roles'       = (@($d.OperationMasterRoles) -join ', ')
        }
    })
    $R.DCObjects = $dcs
    $R.EnvironmentRaw['Domain Controllers'] = $dcs.Count

    $health = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $dcs) {
        $hostName = $d.HostName
        $session  = $null
        $protocol = ''
        try { $session = New-CimSession -ComputerName $hostName -OperationTimeoutSec 20 -ErrorAction Stop; $protocol = 'WSMan' }
        catch {
            try {
                $session = New-CimSession -ComputerName $hostName -SessionOption (New-CimSessionOption -Protocol Dcom) -OperationTimeoutSec 20 -ErrorAction Stop
                $protocol = 'DCOM'
            }
            catch { }
        }

        $svc = @{}
        $uptime = ''
        $freeC  = ''
        if ($session) {
            try {
                Get-CimInstance -CimSession $session -ClassName Win32_Service -Filter "Name='NTDS' OR Name='DFSR' OR Name='DNS' OR Name='Netlogon' OR Name='Kdc' OR Name='W32Time' OR Name='ADWS'" -ErrorAction Stop |
                    ForEach-Object { $svc[$_.Name] = $_.State }
                $os = Get-CimInstance -CimSession $session -ClassName Win32_OperatingSystem -ErrorAction Stop
                if ($os.LastBootUpTime) { $uptime = [int]((Get-Date) - $os.LastBootUpTime).TotalDays }
                $disk = Get-CimInstance -CimSession $session -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
                if ($disk -and $disk.Size) { $freeC = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 0) }
            }
            catch { Add-CollectionError -Section 'DC Health' -Item $d.Name -Message $_.Exception.Message }
            finally { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
        }
        else {
            Add-CollectionError -Section 'DC Health' -Item $d.Name -Message 'CIM (WSMan and DCOM) connection failed'
        }

        $getSvc = { param($n) if ($svc.ContainsKey($n)) { $svc[$n] } elseif ($session) { 'Not installed' } else { 'Unknown' } }
        $health.Add([PSCustomObject]@{
            'Domain Controller' = $d.Name
            'Reachable'         = if ($session) { "Yes ($protocol)" } else { 'No' }
            'SYSVOL Share'      = ConvertTo-YesNo (Test-Path -LiteralPath "\\$hostName\SYSVOL" -ErrorAction SilentlyContinue)
            'NETLOGON Share'    = ConvertTo-YesNo (Test-Path -LiteralPath "\\$hostName\NETLOGON" -ErrorAction SilentlyContinue)
            'NTDS'              = & $getSvc 'NTDS'
            'DFSR'              = & $getSvc 'DFSR'
            'DNS'               = & $getSvc 'DNS'
            'Netlogon'          = & $getSvc 'Netlogon'
            'KDC'               = & $getSvc 'Kdc'
            'W32Time'           = & $getSvc 'W32Time'
            'ADWS'              = & $getSvc 'ADWS'
            'Uptime (days)'     = $uptime
            'C: Free %'         = $freeC
        })
    }
    $R.DCHealth = $health
}

Invoke-Section 'Replication' {
    $meta = @(Get-ADReplicationPartnerMetadata -Target $Ctx.DomainDNS -Scope Domain -Partition * -EnumerationServer $DC -ErrorAction Stop)
    $detail = @(foreach ($m in $meta) {
        $partnerDN = [string]$m.Partner
        $partner   = if ($partnerDN -match 'CN=NTDS Settings,CN=([^,]+)') { $Matches[1] } else { $partnerDN }
        $fails     = Get-PropValue $m @('ConsecutiveReplicationFailures', 'ConsecutiveFailureCount')
        [PSCustomObject]@{
            'Server'            = ([string]$m.Server).Split('.')[0]
            'Inbound Partner'   = $partner
            'Partition'         = Get-PartitionName ([string]$m.Partition)
            'Last Attempt'      = Format-Date $m.LastReplicationAttempt
            'Last Success'      = Format-Date $m.LastReplicationSuccess 'Never'
            'Last Result'       = $m.LastReplicationResult
            'Consecutive Failures' = [int]$fails
            '_LastSuccess'      = $m.LastReplicationSuccess
        }
    })
    $R.ReplDetail = @($detail | Select-Object * -ExcludeProperty _LastSuccess)
    $R.ReplRaw    = @($detail)

    $R.ReplSummary = @(foreach ($g in ($detail | Group-Object Server)) {
        $succ = @($g.Group | Where-Object { $_._LastSuccess } | ForEach-Object { $_._LastSuccess } | Sort-Object)
        [PSCustomObject]@{
            'Server'                   = $g.Name
            'Partner Links'            = $g.Count
            'Links With Failures'      = @($g.Group | Where-Object { $_.'Consecutive Failures' -gt 0 -or ($_.'Last Result' -ne 0 -and $null -ne $_.'Last Result') }).Count
            'Oldest Successful Sync'   = Format-Date ($succ | Select-Object -First 1) 'Never'
            'Newest Successful Sync'   = Format-Date ($succ | Select-Object -Last 1) 'Never'
        }
    })

    $R.ReplFailures = @()
    try {
        $fails = @(Get-ADReplicationFailure -Target $Ctx.DomainDNS -Scope Domain -EnumeratingServer $DC -ErrorAction Stop)
        $R.ReplFailures = @(foreach ($f in $fails) {
            [PSCustomObject]@{
                'Server'        = ([string]$f.Server).Split('.')[0]
                'Partner'       = if ([string]$f.Partner -match 'CN=NTDS Settings,CN=([^,]+)') { $Matches[1] } else { [string]$f.Partner }
                'First Failure' = Format-Date $f.FirstFailureTime
                'Failure Count' = $f.FailureCount
                'Failure Type'  = [string]$f.FailureType
                'Last Error'    = $f.LastError
            }
        })
    }
    catch { Add-CollectionError -Section 'Replication' -Item 'Get-ADReplicationFailure' -Message $_.Exception.Message }
}

Invoke-Section 'Sites, Subnets and Trusts' {
    $sites   = @(Get-ADReplicationSite -Filter * -Server $DC -Properties Description)
    $subnets = @(Get-ADReplicationSubnet -Filter * -Server $DC -Properties Location, Description)
    $R.Subnets = @(foreach ($s in $subnets) {
        [PSCustomObject]@{
            'Subnet'      = $s.Name
            'Site'        = Get-NameFromDN ([string]$s.Site)
            'Location'    = $s.Location
            'Description' = $s.Description
        }
    })
    $R.Sites = @(foreach ($s in $sites) {
        [PSCustomObject]@{
            'Site'        = $s.Name
            'DCs'         = @($R.DCObjects | Where-Object { $_.Site -eq $s.Name }).Count
            'Subnets'     = @($R.Subnets | Where-Object { $_.Site -eq $s.Name }).Count
            'Description' = $s.Description
        }
    })
    # Which subnet (and site) each DC's IP address falls in; most specific subnet wins
    $R.DCSubnetCheck = @(foreach ($d in @($R.DCObjects | Where-Object { $null -ne $_ })) {
        $ip    = [string]$d.IPv4Address
        $match = @($R.Subnets | Where-Object { Test-IPv4InSubnet $ip $_.Subnet } |
                   Sort-Object { [int](([string]$_.Subnet).Split('/')[1]) } -Descending) | Select-Object -First 1
        $status = if (-not $ip) { 'No IPv4 address' }
                  elseif (-not $match) { 'Not in any subnet' }
                  elseif ($match.Site -ne $d.Site) { "Subnet is in site $($match.Site)" }
                  else { 'OK' }
        [PSCustomObject]@{
            'Domain Controller' = $d.Name
            'IP Address'        = $ip
            'DC Site'           = $d.Site
            'Matching Subnet'   = if ($match) { $match.Subnet } else { 'None' }
            'Subnet Check'      = $status
        }
    })

    $R.SiteLinks = @(foreach ($l in @(Get-ADReplicationSiteLink -Filter * -Server $DC -Properties Cost, ReplicationFrequencyInMinutes, SitesIncluded)) {
        [PSCustomObject]@{
            'Site Link'            = $l.Name
            'Cost'                 = $l.Cost
            'Interval (minutes)'   = $l.ReplicationFrequencyInMinutes
            'Sites'                = (@($l.SitesIncluded) | ForEach-Object { Get-NameFromDN ([string]$_) }) -join ', '
        }
    })

    $R.Trusts = @(foreach ($t in @(Get-ADTrust -Filter * -Server $DC)) {
        [PSCustomObject]@{
            'Name'                  = $t.Name
            'Direction'             = [string]$t.Direction
            'Trust Type'            = [string]$t.TrustType
            'Forest Transitive'     = ConvertTo-YesNo $t.ForestTransitive
            'Intra-Forest'          = ConvertTo-YesNo $t.IntraForest
            'SID Filtering'         = ConvertTo-YesNo $t.SIDFilteringQuarantined
            'Selective Auth'        = ConvertTo-YesNo $t.SelectiveAuthentication
            '_External'             = (-not $t.IntraForest -and -not $t.ForestTransitive)
            '_SidFilter'            = [bool]$t.SIDFilteringQuarantined
        }
    })
}

Invoke-Section 'DNS' {
    if (-not $DnsModule) { $R.DNSSkipped = $true; return }
    $zonesDone = $false
    $zones = [System.Collections.Generic.List[object]]::new()
    $fwd   = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $R.DCObjects) {
        $h = $d.HostName
        try {
            if (-not $zonesDone) {
                foreach ($z in @(Get-DnsServerZone -ComputerName $h -ErrorAction Stop | Where-Object { -not $_.IsAutoCreated -and $_.ZoneName -ne 'TrustAnchors' })) {
                    $zones.Add([PSCustomObject]@{
                        'Zone'             = $z.ZoneName
                        'Type'             = [string]$z.ZoneType
                        'AD Integrated'    = ConvertTo-YesNo $z.IsDsIntegrated
                        'Replication Scope'= [string]$z.ReplicationScope
                        'Dynamic Update'   = [string]$z.DynamicUpdate
                        'Reverse Lookup'   = ConvertTo-YesNo $z.IsReverseLookupZone
                        'Source DC'        = $d.Name
                    })
                }
                $zonesDone = $true
            }
            $f  = Get-DnsServerForwarder -ComputerName $h -ErrorAction Stop
            $sc = $null
            try { $sc = Get-DnsServerScavenging -ComputerName $h -ErrorAction Stop } catch { }
            $fwd.Add([PSCustomObject]@{
                'DNS Server'          = $d.Name
                'Forwarders'          = (@($f.IPAddress) | ForEach-Object { [string]$_ }) -join ', '
                'Use Root Hints'      = ConvertTo-YesNo $f.UseRootHint
                'Scavenging Enabled'  = if ($sc) { ConvertTo-YesNo $sc.ScavengingState } else { 'Unknown' }
                'Scavenging Interval' = if ($sc) { [string]$sc.ScavengingInterval } else { '' }
            })
        }
        catch { Add-CollectionError -Section 'DNS' -Item $d.Name -Message $_.Exception.Message }
    }
    $R.DNSZones      = $zones
    $R.DNSForwarders = $fwd
}

Invoke-Section 'Password Policies' {
    $p = Get-ADDefaultDomainPasswordPolicy -Server $DC
    $R.PwdPolicy = $p
    $R.PwdPolicyTable = [PSCustomObject]@{
        'Min Password Length'        = $p.MinPasswordLength
        'Max Password Age (days)'    = $p.MaxPasswordAge.Days
        'Min Password Age (days)'    = $p.MinPasswordAge.Days
        'Password History'           = $p.PasswordHistoryCount
        'Complexity Enabled'         = ConvertTo-YesNo $p.ComplexityEnabled
        'Reversible Encryption'      = ConvertTo-YesNo $p.ReversibleEncryptionEnabled
        'Lockout Threshold'          = $p.LockoutThreshold
        'Lockout Duration (mins)'    = $p.LockoutDuration.TotalMinutes
        'Lockout Window (mins)'      = $p.LockoutObservationWindow.TotalMinutes
    }
    $R.FGPP = @(foreach ($f in @(Get-ADFineGrainedPasswordPolicy -Filter * -Server $DC -Properties AppliesTo)) {
        [PSCustomObject]@{
            'Policy'                  = $f.Name
            'Precedence'              = $f.Precedence
            'Min Length'              = $f.MinPasswordLength
            'Max Age (days)'          = $f.MaxPasswordAge.Days
            'Complexity'              = ConvertTo-YesNo $f.ComplexityEnabled
            'Lockout Threshold'       = $f.LockoutThreshold
            'Applies To'              = (@($f.AppliesTo) | ForEach-Object { Get-NameFromDN ([string]$_) }) -join ', '
        }
    })
}

Invoke-Section 'Users' {
    $props = @('DisplayName', 'EmailAddress', 'proxyAddresses', 'LastLogonDate', 'PasswordLastSet', 'PasswordNeverExpires',
               'PasswordNotRequired', 'LockedOut', 'AccountExpirationDate', 'whenCreated', 'ProtectedFromAccidentalDeletion',
               'msDS-UserPasswordExpiryTimeComputed', 'servicePrincipalName', 'adminCount', 'DoesNotRequirePreAuth',
               'TrustedForDelegation', 'TrustedToAuthForDelegation', 'AllowReversiblePasswordEncryption', 'primaryGroupID', 'Description')
    $raw  = @(Get-ADUser -Filter * -Server $DC -Properties $props)
    $now  = Get-Date
    $list = [System.Collections.Generic.List[object]]::new()
    $byDN = @{}
    foreach ($u in $raw) {
        $exp  = Get-PasswordExpiry $u
        $daysLeft = $null
        if ($exp -is [datetime]) { $daysLeft = [int][math]::Floor(($exp - $now).TotalDays) }
        $rec = [PSCustomObject]@{
            Name            = $u.Name
            Sam             = $u.SamAccountName
            UPN             = $u.UserPrincipalName
            DN              = $u.DistinguishedName
            SID             = $u.SID.Value
            Enabled         = [bool]$u.Enabled
            LastLogon       = $u.LastLogonDate
            PwdLastSet      = $u.PasswordLastSet
            PwdNeverExpires = [bool]$u.PasswordNeverExpires
            PwdNotRequired  = [bool]$u.PasswordNotRequired
            PwdExpires      = $exp
            DaysToExpire    = $daysLeft
            LockedOut       = [bool]$u.LockedOut
            AccountExpires  = $u.AccountExpirationDate
            Created         = $u.whenCreated
            Email           = $u.EmailAddress
            Proxy           = (@($u.proxyAddresses | Where-Object { $_ }) -join '; ')
            Protected       = [bool]$u.ProtectedFromAccidentalDeletion
            SPNs            = @($u.servicePrincipalName | Where-Object { $_ })
            AdminCount      = [int]$u.adminCount
            NoPreAuth       = [bool]$u.DoesNotRequirePreAuth
            Unconstrained   = [bool]$u.TrustedForDelegation
            ProtocolTransition = [bool]$u.TrustedToAuthForDelegation
            Reversible      = [bool]$u.AllowReversiblePasswordEncryption
            PrimaryGroupID  = [int]$u.primaryGroupID
            Description     = $u.Description
            ParentDN        = Get-ParentDN $u.DistinguishedName
        }
        $list.Add($rec)
        $byDN[$rec.DN] = $rec
    }
    $R.Users    = $list
    $R.UserByDN = $byDN

    $staleCut   = $now.AddDays(-$Days)
    $newCut     = $now.AddDays(-$UserCreatedDays).Date
    $acctCut    = $now.AddDays($AccountExpiringDays)
    $enabled    = @($list | Where-Object { $_.Enabled })

    $R.StaleUsers = @(foreach ($u in $enabled) {
        $isStale = if ($u.LastLogon) { $u.LastLogon -lt $staleCut } else { $u.Created -lt $staleCut }
        if ($isStale) {
            [PSCustomObject]@{
                'Name'                   = $u.Name
                'UserPrincipalName'      = $u.UPN
                'Last Logon'             = Format-Date $u.LastLogon 'Never'
                'Created'                = Format-Date $u.Created
                'Password Last Set'      = Format-Date $u.PwdLastSet 'Never'
                'Password Never Expires' = ConvertTo-YesNo $u.PwdNeverExpires
                'Protected from Deletion'= ConvertTo-YesNo $u.Protected
            }
        }
    })

    $R.PwdExpiring = @(foreach ($u in ($enabled | Where-Object { $null -ne $_.DaysToExpire -and $_.DaysToExpire -le $DaysUntilPWExpireINT } | Sort-Object DaysToExpire)) {
        [PSCustomObject]@{
            'Name'                        = $u.Name
            'UserPrincipalName'           = $u.UPN
            'Password Expires'            = Format-Date $u.PwdExpires
            'Days Until Password Expires' = $u.DaysToExpire
            'Status'                      = if ($u.DaysToExpire -lt 0) { 'Expired' } else { 'Expiring' }
        }
    })
    $R.PwdExpiringCount = @($R.PwdExpiring | Where-Object { $_.Status -eq 'Expiring' }).Count
    $R.PwdExpiredCount  = @($R.PwdExpiring | Where-Object { $_.Status -eq 'Expired' }).Count

    $R.AcctExpiring = @(foreach ($u in ($list | Where-Object { $_.AccountExpires -and $_.AccountExpires -le $acctCut } | Sort-Object AccountExpires)) {
        if ($u.AccountExpires -lt $now -and -not $u.Enabled) { continue }
        [PSCustomObject]@{
            'Name'              = $u.Name
            'UserPrincipalName' = $u.UPN
            'Expiration Date'   = Format-Date $u.AccountExpires
            'Enabled'           = ConvertTo-YesNo $u.Enabled
            'Status'            = if ($u.AccountExpires -lt $now) { 'Expired (still enabled)' } else { 'Expiring' }
        }
    })

    $R.NewUsers = @(foreach ($u in ($list | Where-Object { $_.Created -ge $newCut } | Sort-Object Created -Descending)) {
        [PSCustomObject]@{
            'Name'              = $u.Name
            'UserPrincipalName' = $u.UPN
            'Enabled'           = ConvertTo-YesNo $u.Enabled
            'Creation Date'     = Format-Date $u.Created
        }
    })

    $R.LockedUsers = @(foreach ($u in ($list | Where-Object { $_.LockedOut })) {
        [PSCustomObject]@{ 'Name' = $u.Name; 'UserPrincipalName' = $u.UPN; 'Enabled' = ConvertTo-YesNo $u.Enabled; 'Last Logon' = Format-Date $u.LastLogon 'Never' }
    })

    $R.DefaultContainerUsers = @(foreach ($u in ($list | Where-Object { $_.ParentDN -eq $ADDomain.UsersContainer })) {
        [PSCustomObject]@{
            'Name'                    = $u.Name
            'UserPrincipalName'       = $u.UPN
            'Enabled'                 = ConvertTo-YesNo $u.Enabled
            'Protected from Deletion' = ConvertTo-YesNo $u.Protected
            'Last Logon'              = Format-Date $u.LastLogon 'Never'
            'Email Address'           = $u.Email
        }
    })

    $R.PwdNeverExpiresUsers = @($enabled | Where-Object { $_.PwdNeverExpires })

    $R.AllUsersTable = @(foreach ($u in ($list | Sort-Object Name)) {
        [PSCustomObject]@{
            'Name'                     = $u.Name
            'SamAccountName'           = $u.Sam
            'UserPrincipalName'        = $u.UPN
            'Enabled'                  = ConvertTo-YesNo $u.Enabled
            'Last Logon'               = Format-Date $u.LastLogon 'Never'
            'Password Last Set'        = Format-Date $u.PwdLastSet 'Never'
            'Password Expires'         = Format-Date $u.PwdExpires
            'Days Until Expiry'        = $u.DaysToExpire
            'Password Never Expires'   = ConvertTo-YesNo $u.PwdNeverExpires
            'Password Not Required'    = ConvertTo-YesNo $u.PwdNotRequired
            'Locked Out'               = ConvertTo-YesNo $u.LockedOut
            'Account Expires'          = Format-Date $u.AccountExpires 'Never'
            'Email Address'            = $u.Email
            'Proxy Addresses'          = $u.Proxy
            'Created'                  = Format-Date $u.Created
            'Protected from Deletion'  = ConvertTo-YesNo $u.Protected
            'Location'                 = $u.ParentDN
        }
    })

    # UPN suffix usage
    $suffixes = @($Ctx.DomainDNS) + @($ADForest.UPNSuffixes)
    $R.UPNSuffixes = @(foreach ($s in $suffixes) {
        [PSCustomObject]@{
            'UPN Suffix'  = $s
            'Type'        = if ($s -eq $Ctx.DomainDNS) { 'Default (domain)' } else { 'Alternate' }
            'Users Using' = @($list | Where-Object { $_.UPN -like "*@$s" }).Count
        }
    })
}

Invoke-Section 'Computers' {
    $lapsLegacy = [bool](Get-ADObject -SearchBase $Ctx.SchemaNC -LDAPFilter '(lDAPDisplayName=ms-Mcs-AdmPwdExpirationTime)' -Server $DC)
    $lapsNew    = [bool](Get-ADObject -SearchBase $Ctx.SchemaNC -LDAPFilter '(lDAPDisplayName=msLAPS-PasswordExpirationTime)' -Server $DC)
    $R.LapsSchema = ($lapsLegacy -or $lapsNew)
    $props = @('OperatingSystem', 'OperatingSystemVersion', 'LastLogonDate', 'PasswordLastSet', 'whenCreated',
               'ProtectedFromAccidentalDeletion', 'TrustedForDelegation', 'primaryGroupID', 'Description')
    if ($lapsLegacy) { $props += 'ms-Mcs-AdmPwdExpirationTime' }
    if ($lapsNew)    { $props += 'msLAPS-PasswordExpirationTime' }

    $raw  = @(Get-ADComputer -Filter * -Server $DC -Properties $props)
    $now  = Get-Date
    $cut  = $now.AddDays(-$StaleComputerDays)
    $list = @(foreach ($c in $raw) {
        $isDC = ([int]$c.primaryGroupID -in 516, 521)
        $laps = $false
        if ($lapsLegacy -and $c.'ms-Mcs-AdmPwdExpirationTime') { $laps = $true }
        if ($lapsNew -and $c.'msLAPS-PasswordExpirationTime')  { $laps = $true }
        [PSCustomObject]@{
            Name        = $c.Name
            DN          = $c.DistinguishedName
            Enabled     = [bool]$c.Enabled
            OS          = $c.OperatingSystem
            OSVersion   = $c.OperatingSystemVersion
            OSFamily    = Get-OSFamily $c.OperatingSystem
            Support     = Get-OSSupportStatus $c.OperatingSystem
            LastLogon   = $c.LastLogonDate
            PwdLastSet  = $c.PasswordLastSet
            Created     = $c.whenCreated
            Protected   = [bool]$c.ProtectedFromAccidentalDeletion
            Unconstrained = [bool]$c.TrustedForDelegation
            IsDC        = $isDC
            IsServer    = ($c.OperatingSystem -match 'Server')
            Laps        = $laps
            ParentDN    = Get-ParentDN $c.DistinguishedName
            Stale       = ([bool]$c.Enabled -and $(if ($c.LastLogonDate) { $c.LastLogonDate -lt $cut } else { $c.whenCreated -lt $cut }))
        }
    })
    $R.Computers = @($list)

    $R.ComputersTable = @(foreach ($c in ($R.Computers | Sort-Object Name)) {
        [PSCustomObject]@{
            'Name'                  = $c.Name
            'Enabled'               = ConvertTo-YesNo $c.Enabled
            'Operating System'      = $c.OS
            'OS Version'            = $c.OSVersion
            'Support Status'        = $c.Support
            'Last Logon'            = Format-Date $c.LastLogon 'Never'
            'Password Last Set'     = Format-Date $c.PwdLastSet 'Never'
            'LAPS'                  = if ($c.IsDC) { 'N/A (DC)' } else { ConvertTo-YesNo $c.Laps }
            'Protected from Deletion' = ConvertTo-YesNo $c.Protected
            'Location'              = $c.ParentDN
        }
    })

    $R.StaleComputers = @(foreach ($c in ($R.Computers | Where-Object { $_.Stale } | Sort-Object LastLogon)) {
        [PSCustomObject]@{
            'Name'             = $c.Name
            'Operating System' = $c.OS
            'Last Logon'       = Format-Date $c.LastLogon 'Never'
            'Password Last Set'= Format-Date $c.PwdLastSet 'Never'
            'Created'          = Format-Date $c.Created
            'Location'         = $c.ParentDN
        }
    })

    $R.UnsupportedOS = @(foreach ($c in ($R.Computers | Where-Object { $_.Enabled -and $_.Support -like 'Unsupported*' -or ($_.Enabled -and $_.Support -like 'Support ends*') } | Sort-Object OS, Name)) {
        [PSCustomObject]@{
            'Name'             = $c.Name
            'Operating System' = $c.OS
            'OS Version'       = $c.OSVersion
            'Support Status'   = $c.Support
            'Last Logon'       = Format-Date $c.LastLogon 'Never'
        }
    })

    $lapsScope = @($R.Computers | Where-Object { $_.Enabled -and -not $_.IsDC -and $_.OS -match 'Windows' })
    $R.LapsScopeCount   = $lapsScope.Count
    $R.LapsCovered      = @($lapsScope | Where-Object { $_.Laps }).Count
    $R.LapsMissing = @(foreach ($c in ($lapsScope | Where-Object { -not $_.Laps } | Sort-Object Name)) {
        [PSCustomObject]@{
            'Name'             = $c.Name
            'Operating System' = $c.OS
            'Last Logon'       = Format-Date $c.LastLogon 'Never'
            'Location'         = $c.ParentDN
        }
    })

    $R.DefaultContainerComputers = @(foreach ($c in ($R.Computers | Where-Object { $_.ParentDN -eq $ADDomain.ComputersContainer })) {
        [PSCustomObject]@{
            'Name'                  = $c.Name
            'Enabled'               = ConvertTo-YesNo $c.Enabled
            'Operating System'      = $c.OS
            'Last Logon'            = Format-Date $c.LastLogon 'Never'
            'Protected from Deletion' = ConvertTo-YesNo $c.Protected
        }
    })

    $R.OSBreakdown = @($R.Computers | Group-Object OSFamily | Sort-Object Count -Descending | ForEach-Object {
        [PSCustomObject]@{ 'Name' = $_.Name; 'Count' = $_.Count }
    })
}

Invoke-Section 'Groups' {
    $props = @('Description', 'mail', 'ManagedBy', 'member', 'ProtectedFromAccidentalDeletion', 'whenCreated', 'isCriticalSystemObject')
    $raw = @(Get-ADGroup -Filter * -Server $DC -Properties $props)

    # Primary-group members are not stored in the member attribute (e.g. Domain Users)
    $primary = @{}
    foreach ($u in $R.Users)     { $k = [string]$u.PrimaryGroupID; if ($primary.ContainsKey($k)) { $primary[$k]++ } else { $primary[$k] = 1 } }
    $compPrimary = @($R.Computers | Group-Object { if ($_.IsDC) { 516 } else { 515 } })
    foreach ($g in $compPrimary) { $k = [string]$g.Name; if ($primary.ContainsKey($k)) { $primary[$k] += $g.Count } else { $primary[$k] = $g.Count } }

    $list = @(foreach ($g in $raw) {
        $rid      = Get-RID $g.SID.Value
        $isDomainGroup = $g.SID.Value.StartsWith("$($Ctx.DomainSID)-")
        $members  = @($g.member | Where-Object { $_ })
        $primCnt  = if ($isDomainGroup -and $primary.ContainsKey([string]$rid)) { $primary[[string]$rid] } else { 0 }
        $count    = $members.Count + $primCnt
        $isDefault = ($rid -lt 1000) -or ($DefaultSGs -contains $g.Name) -or [bool]$g.isCriticalSystemObject

        $type = if ($g.GroupCategory -eq 'Distribution') { 'Distribution Group' }
                elseif ($g.mail) { 'Mail-Enabled Security Group' }
                else { 'Security Group' }

        $names = @($members | Select-Object -First 50 | ForEach-Object { Get-NameFromDN $_ })
        $memberText = ($names | Sort-Object) -join ', '
        if ($members.Count -gt 50) { $memberText += " ... (+$($members.Count - 50) more)" }
        if ($primCnt -gt 0) { $memberText = ("$memberText (+$primCnt via primary group)").Trim() }

        [PSCustomObject]@{
            Name       = $g.Name
            Type       = $type
            Scope      = [string]$g.GroupScope
            Count      = $count
            Members    = $memberText
            ManagedBy  = Get-NameFromDN ([string]$g.ManagedBy)
            Mail       = $g.mail
            Protected  = [bool]$g.ProtectedFromAccidentalDeletion
            IsDefault  = $isDefault
            Description= $g.Description
        }
    })
    $R.Groups = @($list)

    $R.GroupsTable = @(foreach ($g in ($R.Groups | Sort-Object Name)) {
        [PSCustomObject]@{
            'Name'                    = $g.Name
            'Type'                    = $g.Type
            'Scope'                   = $g.Scope
            'Member Count'            = $g.Count
            'Members'                 = $g.Members
            'Managed By'              = if ($g.ManagedBy) { $g.ManagedBy } else { 'None' }
            'E-mail Address'          = $g.Mail
            'Protected from Deletion' = ConvertTo-YesNo $g.Protected
            'Default AD Group'        = ConvertTo-YesNo $g.IsDefault
            'Description'             = $g.Description
        }
    })
}

Invoke-Section 'Privileged Access' {
    $D = $Ctx.DomainSID
    $F = $Ctx.RootSID
    $defs = @(
        @{ SID = "$D-512";       Server = $DC }               # Domain Admins
        @{ SID = "$F-519";       Server = $Ctx.RootServer }   # Enterprise Admins
        @{ SID = "$F-518";       Server = $Ctx.RootServer }   # Schema Admins
        @{ SID = 'S-1-5-32-544'; Server = $DC }               # Administrators
        @{ SID = 'S-1-5-32-548'; Server = $DC }               # Account Operators
        @{ SID = 'S-1-5-32-549'; Server = $DC }               # Server Operators
        @{ SID = 'S-1-5-32-550'; Server = $DC }               # Print Operators
        @{ SID = 'S-1-5-32-551'; Server = $DC }               # Backup Operators
        @{ SID = "$D-520";       Server = $DC }               # Group Policy Creator Owners
        @{ SID = "$D-526";       Server = $DC }               # Key Admins
        @{ SID = "$F-527";       Server = $Ctx.RootServer }   # Enterprise Key Admins
        @{ Name = 'DnsAdmins';   Server = $DC }
    )

    $gcServer = "$($Ctx.RootDomain):3268"
    function Get-MembersRecursive {
        param ([string]$GroupDN, [string]$Srv, [string]$Via, [hashtable]$Seen)
        $grp = Get-ADObject -Identity $GroupDN -Server $Srv -Properties member
        foreach ($m in @($grp.member | Where-Object { $_ })) {
            if ($Seen.ContainsKey($m)) { continue }
            $Seen[$m] = $true
            $o = $null
            try { $o = Get-ADObject -Identity $m -Server $Srv -Properties samAccountName, objectSid }
            catch { try { $o = Get-ADObject -Identity $m -Server $gcServer -Properties samAccountName, objectSid } catch { } }
            if (-not $o) {
                [PSCustomObject]@{ DN = $m; Class = 'unknown'; Sam = ''; Via = $Via }
                continue
            }
            if ($o.ObjectClass -eq 'group') {
                Get-MembersRecursive -GroupDN $m -Srv $Srv -Via (Get-NameFromDN $m) -Seen $Seen
            }
            else {
                [PSCustomObject]@{ DN = $m; Class = $o.ObjectClass; Sam = $o.samAccountName; Via = $Via }
            }
        }
    }

    # Protected Users membership (for the "In Protected Users" column)
    $protectedSet = @{}
    try {
        $pu = Get-ADGroup -Identity "$D-525" -Server $DC
        foreach ($m in @(Get-MembersRecursive -GroupDN $pu.DistinguishedName -Srv $DC -Via '' -Seen @{})) { $protectedSet[$m.DN] = $true }
    }
    catch { }

    $rows     = [System.Collections.Generic.List[object]]::new()
    $privDNs  = @{}
    $groupSummary = [System.Collections.Generic.List[object]]::new()
    foreach ($def in $defs) {
        try {
            $g = if ($def.SID) { Get-ADGroup -Identity $def.SID -Server $def.Server } else { Get-ADGroup -Identity $def.Name -Server $def.Server }
        }
        catch {
            # Some groups only exist on newer schemas (e.g. Key Admins) - not an error
            Write-Log ("  Privileged group not present: {0}" -f $(if ($def.SID) { $def.SID } else { $def.Name })) 'DETAIL'
            continue
        }

        $members = @(Get-MembersRecursive -GroupDN $g.DistinguishedName -Srv $def.Server -Via '' -Seen @{})

        # Users whose primary group is this group
        if ($g.SID.Value.StartsWith("$($Ctx.DomainSID)-")) {
            $rid = Get-RID $g.SID.Value
            foreach ($u in @($R.Users | Where-Object { $_.PrimaryGroupID -eq $rid })) {
                if (-not ($members | Where-Object { $_.DN -eq $u.DN })) {
                    $members += [PSCustomObject]@{ DN = $u.DN; Class = 'user'; Sam = $u.Sam; Via = 'Primary group' }
                }
            }
        }

        $groupSummary.Add([PSCustomObject]@{ Group = $g.Name; SID = $g.SID.Value; Count = $members.Count })
        foreach ($m in $members) {
            $privDNs[$m.DN] = $true
            $u = $R.UserByDN[$m.DN]
            $rows.Add([PSCustomObject]@{
                'Group'                  = $g.Name
                'Member'                 = Get-NameFromDN $m.DN
                'SamAccountName'         = $m.Sam
                'Type'                   = $m.Class
                'Membership'             = if ($m.Via) { "Nested via $($m.Via)" } else { 'Direct' }
                'Enabled'                = if ($u) { ConvertTo-YesNo $u.Enabled } else { '' }
                'Last Logon'             = if ($u) { Format-Date $u.LastLogon 'Never' } else { '' }
                'Password Last Set'      = if ($u) { Format-Date $u.PwdLastSet 'Never' } else { '' }
                'Password Never Expires' = if ($u) { ConvertTo-YesNo $u.PwdNeverExpires } else { '' }
                'Has SPN'                = if ($u) { ConvertTo-YesNo ($u.SPNs.Count -gt 0) } else { '' }
                'In Protected Users'     = if ($m.Class -eq 'user') { ConvertTo-YesNo $protectedSet.ContainsKey($m.DN) } else { '' }
                '_DN'                    = $m.DN
                '_SID'                   = $g.SID.Value
            })
        }
    }
    $R.PrivRows       = $rows
    $R.PrivTable      = @($rows | Select-Object * -ExcludeProperty _DN, _SID)
    $R.PrivGroupCount = $groupSummary
    $R.PrivDNs        = $privDNs
    $R.ProtectedSet   = $protectedSet
    $R.DomainAdmins   = @($rows | Where-Object { $_._SID -eq "$D-512" } | Select-Object Member, Type, Membership, Enabled, 'Last Logon')
    $R.EnterpriseAdmins = @($rows | Where-Object { $_._SID -eq "$F-519" } | Select-Object Member, Type, Membership, Enabled, 'Last Logon')

    # Privileged user records (unique)
    $R.PrivUsers = @($privDNs.Keys | ForEach-Object { $R.UserByDN[$_] } | Where-Object { $_ })

    # Orphaned adminCount
    $R.OrphanAdminCount = @(foreach ($u in ($R.Users | Where-Object { $_.AdminCount -eq 1 -and -not $privDNs.ContainsKey($_.DN) -and $_.Sam -ne 'krbtgt' })) {
        [PSCustomObject]@{ 'Name' = $u.Name; 'SamAccountName' = $u.Sam; 'Enabled' = ConvertTo-YesNo $u.Enabled; 'Last Logon' = Format-Date $u.LastLogon 'Never' }
    })

    # krbtgt and built-in Administrator
    $krb   = $R.Users | Where-Object { $_.Sam -eq 'krbtgt' } | Select-Object -First 1
    $admin = $R.Users | Where-Object { $_.SID -eq "$D-500" } | Select-Object -First 1
    $R.Krbtgt = $krb
    $R.BuiltinAdmin = $admin
    $R.KeyAccounts = @(
        if ($krb) {
            [PSCustomObject]@{ 'Account' = 'krbtgt'; 'Enabled' = ConvertTo-YesNo $krb.Enabled; 'Password Last Set' = Format-Date $krb.PwdLastSet 'Never'
                'Password Age (days)' = if ($krb.PwdLastSet) { [int]((Get-Date) - $krb.PwdLastSet).TotalDays } else { '' }; 'Last Logon' = 'N/A' }
        }
        if ($admin) {
            [PSCustomObject]@{ 'Account' = "$($admin.Sam) (built-in Administrator, RID 500)"; 'Enabled' = ConvertTo-YesNo $admin.Enabled; 'Password Last Set' = Format-Date $admin.PwdLastSet 'Never'
                'Password Age (days)' = if ($admin.PwdLastSet) { [int]((Get-Date) - $admin.PwdLastSet).TotalDays } else { '' }; 'Last Logon' = Format-Date $admin.LastLogon 'Never' }
        }
    )
}

Invoke-Section 'Kerberos and Account Security' {
    $enabled = @($R.Users | Where-Object { $_.Enabled })
    $priv = if ($R.PrivDNs) { $R.PrivDNs } else { @{} }
    $R.Kerberoastable = @(foreach ($u in ($enabled | Where-Object { $_.SPNs.Count -gt 0 -and $_.Sam -ne 'krbtgt' })) {
        [PSCustomObject]@{
            'Name'              = $u.Name
            'SamAccountName'    = $u.Sam
            'Privileged'        = ConvertTo-YesNo $priv.ContainsKey($u.DN)
            'Password Last Set' = Format-Date $u.PwdLastSet 'Never'
            'SPNs'              = $u.SPNs -join '; '
        }
    })
    $R.ASREP = @(foreach ($u in ($enabled | Where-Object { $_.NoPreAuth })) {
        [PSCustomObject]@{ 'Name' = $u.Name; 'SamAccountName' = $u.Sam; 'Privileged' = ConvertTo-YesNo $priv.ContainsKey($u.DN); 'Last Logon' = Format-Date $u.LastLogon 'Never' }
    })
    $deleg = @()
    $deleg += @(foreach ($u in ($enabled | Where-Object { $_.Unconstrained -or $_.ProtocolTransition })) {
        [PSCustomObject]@{ 'Name' = $u.Name; 'Object Type' = 'User'; 'Delegation' = $(if ($u.Unconstrained) { 'Unconstrained' } else { 'Constrained with protocol transition' }) }
    })
    $deleg += @(foreach ($c in ($R.Computers | Where-Object { $_.Enabled -and $_.Unconstrained -and -not $_.IsDC })) {
        [PSCustomObject]@{ 'Name' = $c.Name; 'Object Type' = 'Computer'; 'Delegation' = 'Unconstrained' }
    })
    $R.Delegation = $deleg
    $R.PwdNotRequired = @(foreach ($u in ($enabled | Where-Object { $_.PwdNotRequired })) {
        [PSCustomObject]@{ 'Name' = $u.Name; 'SamAccountName' = $u.Sam; 'Password Last Set' = Format-Date $u.PwdLastSet 'Never'; 'Last Logon' = Format-Date $u.LastLogon 'Never' }
    })
    $R.Reversible = @(foreach ($u in ($enabled | Where-Object { $_.Reversible })) {
        [PSCustomObject]@{ 'Name' = $u.Name; 'SamAccountName' = $u.Sam; 'Password Last Set' = Format-Date $u.PwdLastSet 'Never' }
    })

    # Duplicate SPNs (all object types)
    $spnHash = @{}
    foreach ($o in @(Get-ADObject -LDAPFilter '(servicePrincipalName=*)' -SearchBase $Ctx.DomainDN -Server $DC -Properties servicePrincipalName)) {
        foreach ($spn in @($o.servicePrincipalName)) {
            if (-not $spnHash.ContainsKey($spn)) { $spnHash[$spn] = [System.Collections.Generic.List[string]]::new() }
            $spnHash[$spn].Add((Get-NameFromDN $o.DistinguishedName))
        }
    }
    $R.DuplicateSPNs = @(foreach ($k in $spnHash.Keys) {
        if ($spnHash[$k].Count -gt 1) {
            [PSCustomObject]@{ 'SPN' = $k; 'Count' = $spnHash[$k].Count; 'Accounts' = ($spnHash[$k] -join '; ') }
        }
    })
}

Invoke-Section 'Organizational Units and GPO Links' {
    # GPO containers (from AD - no GroupPolicy module needed)
    $gpcs = @(Get-ADObject -SearchBase "CN=Policies,CN=System,$($Ctx.DomainDN)" -LDAPFilter '(objectClass=groupPolicyContainer)' -Server $DC `
                -Properties displayName, versionNumber, flags, whenCreated, whenChanged, gPCWQLFilter, gPCFileSysPath, gPCMachineExtensionNames, gPCUserExtensionNames)
    $R.GPCs = $gpcs
    $gpoName = @{}
    foreach ($g in $gpcs) { $gpoName[([string]$g.Name).Trim('{}').ToUpper()] = $g.displayName }
    $R.GPOName = $gpoName

    $linkRows = [System.Collections.Generic.List[object]]::new()
    $addLinks = {
        param ([string]$TargetName, [string]$TargetType, [string]$GPLink, [bool]$BlockInheritance)
        foreach ($l in (Get-GPLinks $GPLink)) {
            $n = if ($l.Guid -and $gpoName.ContainsKey($l.Guid)) { $gpoName[$l.Guid] } else { "{$($l.Guid)} (not found in this domain)" }
            $linkRows.Add([PSCustomObject]@{
                'GPO'               = $n
                'Linked To'         = $TargetName
                'Target Type'       = $TargetType
                'Link Order'        = $l.LinkOrder
                'Link Enabled'      = ConvertTo-YesNo $l.Enabled
                'Enforced'          = ConvertTo-YesNo $l.Enforced
                'Block Inheritance' = ConvertTo-YesNo $BlockInheritance
                '_Guid'             = $l.Guid
                '_Enabled'          = $l.Enabled
            })
        }
    }

    $root = Get-ADObject -Identity $Ctx.DomainDN -Server $DC -Properties gPLink, gPOptions
    & $addLinks $Ctx.DomainDNS 'Domain' ([string]$root.gPLink) ([int]$root.gPOptions -eq 1)

    $ous = @(Get-ADOrganizationalUnit -Filter * -Server $DC -Properties gPLink, gPOptions, ProtectedFromAccidentalDeletion, whenChanged, Description, CanonicalName)
    $usersByParent = @{}
    foreach ($u in $R.Users) { $k = $u.ParentDN; if ($usersByParent.ContainsKey($k)) { $usersByParent[$k]++ } else { $usersByParent[$k] = 1 } }
    $compsByParent = @{}
    foreach ($c in $R.Computers) { $k = $c.ParentDN; if ($compsByParent.ContainsKey($k)) { $compsByParent[$k]++ } else { $compsByParent[$k] = 1 } }

    $R.OUs = @(foreach ($ou in $ous) {
        $block = ([int]$ou.gPOptions -eq 1)
        & $addLinks ([string]$ou.CanonicalName) 'OU' ([string]$ou.gPLink) $block
        $links = Get-GPLinks ([string]$ou.gPLink)
        $names = @($links | ForEach-Object {
            $n = if ($_.Guid -and $gpoName.ContainsKey($_.Guid)) { $gpoName[$_.Guid] } else { "{$($_.Guid)}" }
            if ($_.Enforced) { $n += ' (Enforced)' }
            if (-not $_.Enabled) { $n += ' (Link disabled)' }
            $n
        })
        [PSCustomObject]@{
            'Name'                    = $ou.Name
            'Path'                    = $ou.CanonicalName
            'Linked GPOs'             = if ($names.Count) { $names -join ', ' } else { 'None' }
            'Users'                   = if ($usersByParent.ContainsKey($ou.DistinguishedName)) { $usersByParent[$ou.DistinguishedName] } else { 0 }
            'Computers'               = if ($compsByParent.ContainsKey($ou.DistinguishedName)) { $compsByParent[$ou.DistinguishedName] } else { 0 }
            'Block Inheritance'       = ConvertTo-YesNo $block
            'Protected from Deletion' = ConvertTo-YesNo $ou.ProtectedFromAccidentalDeletion
            'Modified Date'           = Format-Date $ou.whenChanged
            '_HasLinks'               = ($names.Count -gt 0)
            '_Protected'              = [bool]$ou.ProtectedFromAccidentalDeletion
        }
    })

    # Site-linked GPOs
    try {
        foreach ($s in @(Get-ADObject -SearchBase "CN=Sites,$($Ctx.ConfigNC)" -LDAPFilter '(&(objectClass=site)(gPLink=*))' -Server $DC -Properties gPLink)) {
            & $addLinks ([string]$s.Name) 'Site' ([string]$s.gPLink) $false
        }
    }
    catch { Add-CollectionError -Section 'GPO Links' -Item 'Sites' -Message $_.Exception.Message }

    $R.GPLinks = $linkRows
    $R.OUTable = @($R.OUs | Sort-Object Path | Select-Object * -ExcludeProperty _HasLinks, _Protected)
}

Invoke-Section 'Group Policy' {
    # WMI filters
    $wmi = @{}
    try {
        foreach ($w in @(Get-ADObject -SearchBase "CN=SOM,CN=WMIPolicy,CN=System,$($Ctx.DomainDN)" -LDAPFilter '(objectClass=msWMI-Som)' -Server $DC -Properties 'msWMI-Name', 'msWMI-ID')) {
            $wmi[([string]$w.'msWMI-ID').Trim('{}').ToUpper()] = $w.'msWMI-Name'
        }
    }
    catch { }

    $permRows = [System.Collections.Generic.List[object]]::new()
    $gpoRows  = [System.Collections.Generic.List[object]]::new()
    $reports  = [System.Collections.Generic.List[object]]::new()
    $authUsersSid = 'S-1-5-11'
    $domCompSid   = "$($Ctx.DomainSID)-515"
    $sysvolReachable = Test-Path -LiteralPath "\\$DC\SYSVOL" -ErrorAction SilentlyContinue
    if (-not $sysvolReachable) { Add-CollectionError -Section 'Group Policy' -Item "\\$DC\SYSVOL" -Message 'SYSVOL not reachable from this machine - AD/SYSVOL version check skipped' }

    $i = 0
    foreach ($g in ($R.GPCs | Sort-Object displayName)) {
        $i++
        Write-Progress -Id 1 -ParentId 0 -Activity 'Group Policy' -Status $g.displayName -PercentComplete ([int](($i / [math]::Max(1, $R.GPCs.Count)) * 100))
        $guid = ([string]$g.Name).Trim('{}').ToUpper()
        $ver  = [int64]$g.versionNumber
        $userVer = [int]($ver -shr 16)
        $compVer = [int]($ver -band 0xFFFF)
        $status = switch ([int]$g.flags) { 0 { 'All settings enabled' } 1 { 'User settings disabled' } 2 { 'Computer settings disabled' } 3 { 'All settings disabled' } default { "Flags $($g.flags)" } }

        # SYSVOL (GPT.INI) version on the same DC
        $sysvolVer = $null
        $sysvolState = 'OK'
        $path = ([string]$g.gPCFileSysPath) -replace '^\\\\[^\\]+', "\\$DC"
        if (-not $sysvolReachable) { $sysvolState = 'Not checked' }
        else {
        try {
            $ini = Get-Content -LiteralPath (Join-Path $path 'GPT.INI') -ErrorAction Stop
            $line = $ini | Where-Object { $_ -match '^\s*Version\s*=\s*(\d+)' } | Select-Object -First 1
            if ($line -match '(\d+)') { $sysvolVer = [int64]$Matches[1] }
            if ($null -ne $sysvolVer -and $sysvolVer -ne $ver) { $sysvolState = 'Version mismatch (AD vs SYSVOL)' }
        }
        catch {
            if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { $sysvolState = 'SYSVOL folder missing' } else { $sysvolState = 'GPT.INI unreadable' }
        }
        }

        $links    = @($R.GPLinks | Where-Object { $_._Guid -eq $guid })
        $wmiName  = 'None'
        if ($g.gPCWQLFilter -and ([string]$g.gPCWQLFilter -match '\{([0-9A-Fa-f\-]{36})\}')) {
            $wk = $Matches[1].ToUpper()
            $wmiName = if ($wmi.ContainsKey($wk)) { $wmi[$wk] } else { "{$wk}" }
        }

        $secFilter = 'N/A'
        $readOk    = $null
        if ($GPModule) {
            try {
                $perms = @(Get-GPPermission -Guid $guid -All -DomainName $Ctx.DomainDNS -Server $DC -ErrorAction Stop)
                foreach ($p in $perms) {
                    $permRows.Add([PSCustomObject]@{
                        'GPO'        = $g.displayName
                        'Trustee'    = Get-TrusteeName $p
                        'Permission' = [string]$p.Permission
                        'Inherited'  = ConvertTo-YesNo $p.Inherited
                        'Denied'     = ConvertTo-YesNo $p.Denied
                    })
                }
                $applyTo = @($perms | Where-Object { [string]$_.Permission -eq 'GpoApply' } | ForEach-Object { Get-TrusteeName $_ })
                $secFilter = if ($applyTo.Count) { $applyTo -join ', ' } else { 'None (applies to no one)' }
                $readOk = [bool]($perms | Where-Object { ("$($_.Trustee.Sid)" -eq $authUsersSid -or "$($_.Trustee.Sid)" -eq $domCompSid) -and [string]$_.Permission -in @('GpoRead', 'GpoApply', 'GpoEdit', 'GpoEditDeleteModifySecurity') })
            }
            catch { Add-CollectionError -Section 'Group Policy' -Item $g.displayName -Message "Permissions: $($_.Exception.Message)" }

            if (-not $SkipGPOSettings) {
                try {
                    $html = Get-GPOReport -Guid $guid -ReportType Html -Domain $Ctx.DomainDNS -Server $DC -ErrorAction Stop
                    $reports.Add([PSCustomObject]@{ Name = $g.displayName; Guid = $guid; Html = [string]$html })
                }
                catch { Add-CollectionError -Section 'Group Policy' -Item $g.displayName -Message "Settings report: $($_.Exception.Message)" }
            }
        }

        $gpoRows.Add([PSCustomObject]@{
            'Name'               = $g.displayName
            'Status'             = $status
            'Links'              = $links.Count
            'Enabled Links'      = @($links | Where-Object { $_._Enabled }).Count
            'User Version'       = $userVer
            'Computer Version'   = $compVer
            'SYSVOL Check'       = $sysvolState
            'Security Filtering' = $secFilter
            'WMI Filter'         = $wmiName
            'Created'            = Format-Date $g.whenCreated
            'Modified'           = Format-Date $g.whenChanged
            'GPO ID'             = $guid
            '_Empty'             = ($userVer -eq 0 -and $compVer -eq 0)
            '_ReadOk'            = $readOk
        })
    }
    Write-Progress -Id 1 -Activity 'Group Policy' -Completed

    $R.GPOs        = $gpoRows
    $R.GPOTable    = @($gpoRows | Select-Object * -ExcludeProperty _Empty, _ReadOk)
    $R.GPOPerms    = $permRows
    $R.GPOReports  = $reports
    $R.GPLinkTable = @($R.GPLinks | Sort-Object 'Linked To', 'Link Order' | Select-Object * -ExcludeProperty _Guid, _Enabled)
}

Invoke-Section 'DC Security Logs' {
    # One pass per DC over the Security log for everything the report needs (account changes for the modified
    # objects table, lockouts and failed sign-ins). Uses EventLogReader and reads only the named fields:
    # Get-WinEvent formats the full message text of every event, which is what made this slow.
    $R.SecEvents   = [System.Collections.Generic.List[object]]::new()
    $R.SecLogRead  = @{}
    if ($SkipEventLogs) { $R.EventsSkipped = $true; return }

    $authMs   = [int64]$EventLogDays * 86400000
    $changeMs = [int64]$ADModNumber * 86400000
    $query = @"
<QueryList><Query Id="0" Path="Security">
<Select Path="Security">*[System[(EventID=4740 or EventID=4771 or EventID=4625) and TimeCreated[timediff(@SystemTime) &lt;= $authMs]]]</Select>
<Select Path="Security">*[System[EventID=4776 and TimeCreated[timediff(@SystemTime) &lt;= $authMs]] and EventData[Data[@Name='Status']!='0x0']]</Select>
<Select Path="Security">*[System[((EventID &gt;= 4720 and EventID &lt;= 4763) or EventID=4781 or (EventID &gt;= 5136 and EventID &lt;= 5141)) and TimeCreated[timediff(@SystemTime) &lt;= $changeMs]]]</Select>
</Query></QueryList>
"@
    $fields = @('TargetUserName', 'TargetDomainName', 'TargetSid', 'SubjectUserName', 'IpAddress', 'Status', 'SubStatus', 'Workstation',
                'WorkstationName', 'MemberName', 'MemberSid', 'ObjectDN', 'OldObjectDN', 'NewObjectDN', 'AttributeLDAPDisplayName', 'OperationType')
    $maxPerDC = 30000

    foreach ($d in $R.DCObjects) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $list = Read-DCSecurityLog -Computer $d.HostName -Query $query -Fields $fields -Max $maxPerDC -Label $d.Name
        }
        catch {
            Add-CollectionError -Section 'DC Security Logs' -Item $d.Name -Message $_.Exception.Message
            continue
        }
        foreach ($e in $list) { $e | Add-Member -NotePropertyName DC -NotePropertyValue $d.Name; $R.SecEvents.Add($e) }
        $R.SecLogRead[$d.Name] = $true
        $capNote = if ($list.Count -ge $maxPerDC) { " (limit of $maxPerDC reached - oldest events not read)" } else { '' }
        Write-Log ("  {0}: {1} events in {2}s{3}" -f $d.Name, $list.Count, [math]::Round($sw.Elapsed.TotalSeconds, 1), $capNote) 'DETAIL'
    }
}

Invoke-Section 'Recently Modified Objects' {
    # AD itself records WHAT changed and WHEN (replication metadata). WHO is only in the DC security logs,
    # and only if auditing was on and the log still holds that day.
    $sinceDate = (Get-Date).AddDays(-$ADModNumber)
    $since     = $sinceDate.ToUniversalTime().ToString('yyyyMMddHHmmss.0Z')
    $filter    = "(&(whenChanged>=$since)(!(objectClass=domainDNS))(!(objectClass=rIDManager))(!(objectClass=rIDSet)))"
    $metaInQuery = $true
    try {
        $objs = @(Get-ADObject -LDAPFilter $filter -SearchBase $Ctx.DomainDN -Server $DC -Properties whenChanged, displayName, objectSid, 'msDS-ReplAttributeMetaData', 'msDS-ReplValueMetaData')
    }
    catch {
        $metaInQuery = $false
        $objs = @(Get-ADObject -LDAPFilter $filter -SearchBase $Ctx.DomainDN -Server $DC -Properties whenChanged, displayName, objectSid)
    }
    $objs = @($objs | Sort-Object whenChanged -Descending)
    # Some DCs omit these constructed attributes from a subtree search; then read each object directly (capped)
    if ($metaInQuery -and $objs.Count -and -not @($objs | Where-Object { $_.'msDS-ReplAttributeMetaData' }).Count) { $metaInQuery = $false }
    $metaMode = if ($metaInQuery) { 'bulk query' } else { "per object (first $([math]::Min(300, $objs.Count)) of $($objs.Count))" }
    Write-Log ("  {0} modified objects; change history read by {1}" -f $objs.Count, $metaMode) 'DETAIL'

    $parseTime = {
        param([string]$Text)
        try { return [datetime]::Parse($Text, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal).ToLocalTime() }
        catch { return $null }
    }
    $parseXml = {
        param($Values)
        foreach ($x in @($Values)) {
            if (-not $x) { continue }
            $t = ([string]$x).Trim([char]0, ' ', "`r", "`n")
            try { ([xml]$t).DocumentElement } catch { }
        }
    }
    $dsaName = { param([string]$Dsa) if ($Dsa -match 'CN=NTDS Settings,CN=([^,]+)') { $Matches[1] } else { '' } }

    # Attributes that the system updates by itself
    $routineAny  = @('lastLogonTimestamp', 'lockoutTime', 'operatingSystem', 'operatingSystemVersion', 'operatingSystemServicePack', 'operatingSystemHotfix',
                     'dNSHostName', 'msDS-SupportedEncryptionTypes', 'userCertificate', 'ms-Mcs-AdmPwd', 'ms-Mcs-AdmPwdExpirationTime',
                     'msLAPS-PasswordExpirationTime', 'msLAPS-EncryptedPassword', 'msLAPS-Password', 'msLAPS-EncryptedPasswordHistory',
                     'msLAPS-EncryptedDSRMPassword', 'msLAPS-EncryptedDSRMPasswordHistory', 'msTPM-OwnerInformation', 'msTPM-TpmInformationForComputer',
                     'msDS-LastSuccessfulInteractiveLogonTime', 'msDS-LastFailedInteractiveLogonTime', 'msDS-FailedInteractiveLogonCount',
                     'msDS-FailedInteractiveLogonCountAtLastSuccessfulLogon', 'msDS-RevealedUsers', 'msDS-RevealedDSAs', 'msDFSR-ComputerReferenceBL')
    $passwordSet = @('unicodePwd', 'ntPwdHistory', 'lmPwdHistory', 'dBCSPwd', 'supplementalCredentials', 'pwdLastSet')
    $friendly    = @{ 'lastLogonTimestamp' = 'Last logon time'; 'lockoutTime' = 'Lockout state'; 'userAccountControl' = 'Account flags (enable / disable / options)';
                      'member' = 'Group members'; 'versionNumber' = 'GPO settings version'; 'gPLink' = 'Linked GPOs'; 'servicePrincipalName' = 'Service principal names';
                      'nTSecurityDescriptor' = 'Permissions'; 'adminCount' = 'adminCount'; 'accountExpires' = 'Account expiry'; 'memberOf' = 'Group membership' }

    # Security log events, keyed by target SID and by object DN
    $evByKey  = @{}
    $evNames  = @{
        4720 = 'Account created'; 4722 = 'Account enabled'; 4723 = 'Password change attempted'; 4724 = 'Password reset by an administrator'; 4725 = 'Account disabled'; 4726 = 'Account deleted'
        4738 = 'User account changed'; 4741 = 'Computer account created'; 4742 = 'Computer account changed'; 4743 = 'Computer account deleted'; 4781 = 'Account renamed'
        5137 = 'Object created'; 5139 = 'Object moved'; 5141 = 'Object deleted'
    }
    foreach ($id in 4727, 4731, 4744, 4749, 4754, 4759) { $evNames[$id] = 'Group created' }
    foreach ($id in 4728, 4732, 4746, 4751, 4756, 4761) { $evNames[$id] = 'Member added' }
    foreach ($id in 4729, 4733, 4747, 4752, 4757, 4762) { $evNames[$id] = 'Member removed' }
    foreach ($id in 4735, 4737, 4745, 4750, 4755, 4760) { $evNames[$id] = 'Group changed' }
    foreach ($id in 4730, 4734, 4748, 4753, 4758, 4763) { $evNames[$id] = 'Group deleted' }
    $eventsRead = (@($R.SecLogRead.Keys).Count -gt 0)
    foreach ($e in @($R.SecEvents | Where-Object { $_.Time -ge $sinceDate -and ($_.Id -eq 5136 -or $evNames.ContainsKey($_.Id)) })) {
        $id   = $e.Id
        $data = $e.Data
        $what = if ($id -eq 5136) {
            $op = switch ($data['OperationType']) { '%%14674' { 'value added' } '%%14675' { 'value removed' } default { 'changed' } }
            "Attribute $($data['AttributeLDAPDisplayName']) $op"
        } else { $evNames[$id] }
        if ($what -like 'Member *') {
            $mem = if ($data['MemberName'] -and $data['MemberName'] -ne '-') { Get-NameFromDN $data['MemberName'] } else { $data['MemberSid'] }
            $what = "$what`: $mem"
        }
        $actor  = [string]$data['SubjectUserName']
        $system = (-not $actor) -or $actor.EndsWith('$') -or $actor -in 'ANONYMOUS LOGON', 'SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE'
        $rec = [PSCustomObject]@{ Time = $e.Time; Id = $id; What = $what; Actor = $actor; System = $system; DC = $e.DC }
        foreach ($key in @($data['TargetSid'], $data['ObjectDN'], $data['OldObjectDN'], $data['NewObjectDN'])) {
            if (-not $key -or $key -eq '-') { continue }
            $k = $key.ToLower()
            if (-not $evByKey.ContainsKey($k)) { $evByKey[$k] = [System.Collections.Generic.List[object]]::new() }
            $evByKey[$k].Add($rec)
        }
    }
    $R.ModifiedEventsRead = $eventsRead

    $detail  = [System.Collections.Generic.List[object]]::new()
    $summary = [System.Collections.Generic.List[object]]::new()
    $idx = 0
    foreach ($o in $objs) {
        $idx++
        $key      = "o$idx"
        $name     = if ($o.ObjectClass -eq 'groupPolicyContainer' -and $o.displayName) { $o.displayName } else { $o.Name }
        $isComp   = ($o.ObjectClass -eq 'computer')
        $labels   = [System.Collections.Generic.List[string]]::new()
        $hasReal  = $false; $hasPwd = $false; $hasMeta = $false
        $rows     = [System.Collections.Generic.List[object]]::new()

        # Attribute metadata
        $attrMeta = @()
        $attrXml  = $o.'msDS-ReplAttributeMetaData'
        $valXml   = $o.'msDS-ReplValueMetaData'
        if (-not $metaInQuery -and $idx -le 300) {
            try {
                $mo = Get-ADObject -Identity $o.DistinguishedName -Server $DC -Properties 'msDS-ReplAttributeMetaData', 'msDS-ReplValueMetaData'
                $attrXml = $mo.'msDS-ReplAttributeMetaData'
                $valXml  = $mo.'msDS-ReplValueMetaData'
            }
            catch { }
        }
        if ($attrXml) {
            $attrMeta = @(& $parseXml $attrXml | ForEach-Object {
                [PSCustomObject]@{ Attr = [string]$_.pszAttributeName; Time = (& $parseTime ([string]$_.ftimeLastOriginatingChange)); Dsa = (& $dsaName ([string]$_.pszLastOriginatingDsaDN)); Ver = [string]$_.dwVersion }
            })
        }
        foreach ($a in @($attrMeta | Where-Object { $_.Time -and $_.Time -ge $sinceDate } | Sort-Object Time -Descending)) {
            $hasMeta = $true
            $isPwd   = $passwordSet -contains $a.Attr
            $routine = ($routineAny -contains $a.Attr) -or ($isComp -and ($isPwd -or $a.Attr -eq 'servicePrincipalName'))
            $label   = if ($isPwd) { 'Password' } elseif ($friendly.ContainsKey($a.Attr)) { $friendly[$a.Attr] } else { $a.Attr }
            if (-not $labels.Contains($label)) { $labels.Add($label) }
            if ($routine) { } elseif ($isPwd) { $hasPwd = $true } else { $hasReal = $true }
            $rows.Add([PSCustomObject]@{ Time = $a.Time; Change = "$label ($($a.Attr), version $($a.Ver))"; Source = 'AD metadata'; By = ''; DC = $a.Dsa; Kind = $(if ($routine) { 'routine' } else { 'change' }) })
        }
        # Linked-value metadata (group members added / removed)
        if ($valXml) {
            foreach ($v in @(& $parseXml $valXml)) {
                $t = & $parseTime ([string]$v.ftimeLastOriginatingChange)
                if (-not $t -or $t -lt $sinceDate) { continue }
                $removed = ([string]$v.ftimeDeleted) -notlike '1601-*'
                $hasMeta = $true; $hasReal = $true
                $vAttr  = [string]$v.pszAttributeName
                $vLabel = if ($friendly.ContainsKey($vAttr)) { $friendly[$vAttr] } else { $vAttr }
                if (-not $labels.Contains($vLabel)) { $labels.Add($vLabel) }
                $rows.Add([PSCustomObject]@{ Time = $t; Change = "$([string]$v.pszAttributeName) $(if ($removed) { 'removed' } else { 'added' }): $(Get-NameFromDN ([string]$v.pszObjectDn))"; Source = 'AD metadata'; By = ''; DC = (& $dsaName ([string]$v.pszLastOriginatingDsaDN)); Kind = 'change' })
            }
        }
        # Security log events
        $actors = [System.Collections.Generic.List[string]]::new()
        $sysEvt = $false
        $evs    = [System.Collections.Generic.List[object]]::new()
        foreach ($k in @($(if ($o.objectSid) { [string]$o.objectSid.Value }), $o.DistinguishedName)) {
            if ($k -and $evByKey.ContainsKey($k.ToLower())) { foreach ($e in $evByKey[$k.ToLower()]) { if (-not $evs.Contains($e)) { $evs.Add($e) } } }
        }
        foreach ($e in $evs) {
            if ($e.System) { $sysEvt = $true } else { if (-not $actors.Contains($e.Actor)) { $actors.Add($e.Actor) }; $hasReal = $true }
            $rows.Add([PSCustomObject]@{ Time = $e.Time; Change = $e.What; Source = "Event $($e.Id)"; By = $(if ($e.Actor) { $e.Actor } else { 'System' }); DC = $e.DC; Kind = $(if ($e.System) { 'routine' } else { 'change' }) })
        }

        $type = if ($hasReal) { 'Directory change' } elseif ($hasPwd) { 'Password change' } elseif ($hasMeta -or $sysEvt) { 'Routine (system)' } else { 'Unknown' }
        $by   = if ($actors.Count) { $actors -join ', ' } elseif ($sysEvt -and -not $hasReal -and -not $hasPwd) { 'System' } else { 'Not recorded' }
        $v    = @($(if ($type -eq 'Routine (system)') { 'routine' } elseif ($type -eq 'Unknown') { 'unknown' } else { 'admin' }))
        if ($actors.Count) { $v += 'has-actor' }
        $shown = @($labels | Select-Object -First 6) -join ', '
        if ($labels.Count -gt 6) { $shown += " (+$($labels.Count - 6) more)" }
        $summary.Add([PSCustomObject]@{
            'Name'         = $name
            'Object Type'  = $o.ObjectClass
            'When Changed' = Format-Date $o.whenChanged
            'Change Type'  = $type
            'What Changed' = $shown
            'Changed By'   = $by
            'Location'     = Get-ParentDN $o.DistinguishedName
            '_v'           = ($v -join ' ')
            '_jump'        = $(if ($rows.Count) { "tChangeDetail|$key" } else { $null })
        })
        foreach ($r2 in @($rows | Sort-Object Time -Descending | Select-Object -First 40)) {
            $detail.Add([PSCustomObject]@{
                'Object'         = $name
                'Object Type'    = $o.ObjectClass
                'Time'           = Format-Date $r2.Time
                'Change'         = $r2.Change
                'Source'         = $r2.Source
                'Changed By'     = $r2.By
                'Originating DC' = $r2.DC
                '_v'             = "$key $($r2.Kind) $(if ($r2.Source -eq 'AD metadata') { 'meta' } else { 'event' })"
            })
        }
    }
    $R.Modified       = $summary
    $R.ModifiedDetail = $detail
}

Invoke-Section 'Authentication Events' {
    if ($SkipEventLogs) { $R.EventsSkipped = $true; return }
    $authSince = (Get-Date).AddDays(-$EventLogDays)
    $events = [System.Collections.Generic.List[object]]::new()
    foreach ($e in @($R.SecEvents | Where-Object { $_.Id -in 4740, 4771, 4776, 4625 -and $_.Time -ge $authSince })) {
        $data = $e.Data
        $type = ''; $source = ''; $reason = ''
        switch ($e.Id) {
            4740 { $type = 'Account lockout';           $source = $data['TargetDomainName'];                   $reason = 'Locked out' }
            4771 { $type = 'Kerberos pre-auth failure'; $source = ($data['IpAddress'] -replace '^::ffff:', ''); $reason = Get-StatusText $data['Status'] }
            4776 { $type = 'NTLM validation failure';   $source = $data['Workstation'];                        $reason = Get-StatusText $data['Status'] }
            4625 {
                $type = 'Logon failure'
                $source = if ($data['WorkstationName'] -and $data['WorkstationName'] -ne '-') { $data['WorkstationName'] } else { $data['IpAddress'] }
                $code = if ($data['Status'] -eq '0xc000006d' -and $data['SubStatus']) { $data['SubStatus'] } else { $data['Status'] }
                $reason = Get-StatusText $code
            }
        }
        $events.Add([PSCustomObject]@{ Time = $e.Time; DC = $e.DC; EventID = $e.Id; Type = $type; Account = $data['TargetUserName']; Source = $source; Reason = $reason })
    }

    $R.Lockouts = @(foreach ($e in ($events | Where-Object { $_.EventID -eq 4740 } | Sort-Object Time -Descending)) {
        [PSCustomObject]@{ 'Time' = Format-Date $e.Time; 'Account' = $e.Account; 'Caller Computer' = $e.Source; 'Reported By' = $e.DC }
    })

    $fails = @($events | Where-Object { $_.EventID -ne 4740 -and $_.Account -and $_.Account -notlike '*$' })
    $R.FailureSummary = @(foreach ($g in ($fails | Group-Object Account | Sort-Object Count -Descending | Select-Object -First 100)) {
        $srcs = @($g.Group | Where-Object { $_.Source } | Group-Object Source | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count))" })
        [PSCustomObject]@{
            'Account'     = $g.Name
            'Failures'    = $g.Count
            'Top Sources' = $srcs -join ', '
            'Reasons'     = (@($g.Group | Where-Object { $_.Reason } | Select-Object -ExpandProperty Reason -Unique) -join ', ')
            'Last Seen'   = Format-Date (($g.Group | Sort-Object Time -Descending | Select-Object -First 1).Time)
        }
    })
    $R.FailureEvents = @(foreach ($e in ($fails | Sort-Object Time -Descending | Select-Object -First 500)) {
        [PSCustomObject]@{ 'Time' = Format-Date $e.Time; 'DC' = $e.DC; 'Event ID' = $e.EventID; 'Type' = $e.Type; 'Account' = $e.Account; 'Source' = $e.Source; 'Reason' = $e.Reason }
    })
    $R.FailureTotal = $fails.Count
}

# ---------------------------------------------------------------------------
# Main Logic - Findings
# ---------------------------------------------------------------------------

function Add-Finding {
    param (
        [ValidateSet('Critical', 'Warning', 'Info', 'OK')][string]$Severity,
        [string]$Category,
        [string]$Finding,
        $Count = '',
        [string]$Recommendation = ''
    )
    $R.Findings.Add([PSCustomObject]@{
        'Severity'       = $Severity
        'Category'       = $Category
        'Finding'        = $Finding
        'Count'          = $Count
        'Recommendation' = $Recommendation
        'RowColor'       = @{ Critical = 'Red'; Warning = 'Yellow'; Info = 'None'; OK = 'Green' }[$Severity]
        '_Order'         = @{ Critical = 0; Warning = 1; Info = 2; OK = 3 }[$Severity]
    })
}

Invoke-Section 'Findings' {
    $now = Get-Date

    # --- Domain controllers and replication
    Invoke-Check {
        $bad = @($R.DCHealth | Where-Object { $_.Reachable -eq 'No' })
        if ($bad.Count) { Add-Finding Warning 'Domain Controllers' "DCs not reachable over CIM/WMI: $(($bad.'Domain Controller') -join ', ')" $bad.Count 'Confirm the DC is online and WinRM/WMI is allowed from this machine.' }
        $svcCols = 'NTDS', 'DFSR', 'Netlogon', 'KDC', 'ADWS'
        $down = @($R.DCHealth | Where-Object { $row = $_; $row.Reachable -ne 'No' -and ($svcCols | Where-Object { $row.$_ -notin @('Running', 'Not installed') }) })
        if ($down.Count) { Add-Finding Critical 'Domain Controllers' "Core AD services not running on: $(($down.'Domain Controller') -join ', ')" $down.Count 'Check the DC Health table and start/repair the stopped services.' }
        $shares = @($R.DCHealth | Where-Object { $_.Reachable -ne 'No' -and ($_.'SYSVOL Share' -eq 'No' -or $_.'NETLOGON Share' -eq 'No') })
        if ($shares.Count) { Add-Finding Critical 'Domain Controllers' "SYSVOL/NETLOGON share not reachable on: $(($shares.'Domain Controller') -join ', ')" $shares.Count 'DC is not advertising SYSVOL - check DFSR health and the SysvolReady registry value.' }
        $disk = @($R.DCHealth | Where-Object { $_.'C: Free %' -ne '' -and [int]$_.'C: Free %' -lt 15 })
        if ($disk.Count) { Add-Finding Warning 'Domain Controllers' "Low free space on C: (< 15%): $(($disk.'Domain Controller') -join ', ')" $disk.Count 'Free up disk space on the DC system drive.' }
        if (-not $bad.Count -and -not $down.Count -and -not $shares.Count) { Add-Finding OK 'Domain Controllers' 'All DCs reachable with core services running and SYSVOL shared.' }
    }
    Invoke-Check {
        $fails = @($R.ReplFailures).Count
        $badLinks = @($R.ReplRaw | Where-Object { $_.'Consecutive Failures' -gt 0 })
        $old = @($R.ReplRaw | Where-Object { $_._LastSuccess -and $_._LastSuccess -lt $now.AddHours(-24) })
        if ($badLinks.Count -or $fails) { Add-Finding Critical 'Replication' 'Replication failures detected between DCs.' ([math]::Max($badLinks.Count, $fails)) 'Review the Replication tables; run repadmin /replsummary and repadmin /showrepl to diagnose.' }
        elseif ($old.Count) { Add-Finding Warning 'Replication' 'Replication links with no successful sync in the last 24 hours.' $old.Count 'Check site link schedules and connectivity between the affected DCs.' }
        elseif ($R.ReplRaw) { Add-Finding OK 'Replication' 'No replication failures detected.' }
    }
    Invoke-Check {
        if ($R.SysvolState -like 'FRS*' -or $R.SysvolState -like 'Migration*') { Add-Finding Critical 'SYSVOL' "SYSVOL replication: $($R.SysvolState)" '' 'Complete the FRS to DFSR migration (dfsrmig). FRS is not supported on Server 2019 and later DCs.' }
        elseif ($R.SysvolState -like 'DFSR*') { Add-Finding OK 'SYSVOL' 'SYSVOL replicates with DFSR.' }
    }

    # --- Environment
    Invoke-Check {
        if ($R.RecycleBin -eq $false) { Add-Finding Warning 'Environment' 'AD Recycle Bin is disabled.' '' 'Enable it (Enable-ADOptionalFeature) so deleted objects can be restored with attributes and group memberships.' }
        if ([string]$ADForest.ForestMode -notmatch '2016|2025') { Add-Finding Info 'Environment' "Forest functional level is $($ADForest.ForestMode)." '' 'Raise to Windows2016Forest once all DCs run Server 2016 or later.' }
        if ($R.Tombstone -lt 180) { Add-Finding Info 'Environment' "Tombstone lifetime is $($R.Tombstone) days." '' 'Microsoft recommends 180 days.' }
        $oldDCs = @($R.DCObjects | Where-Object { (Get-OSSupportStatus $_.OperatingSystem) -like 'Unsupported*' })
        if ($oldDCs.Count) { Add-Finding Critical 'Environment' "DCs on unsupported operating systems: $(($oldDCs.Name) -join ', ')" $oldDCs.Count 'Replace or upgrade these DCs.' }
    }

    # --- Sites and DNS
    Invoke-Check {
        $noSub     = @($R.Sites | Where-Object { $_.Subnets -eq 0 })
        $noSubDC   = @($noSub | Where-Object { $_.DCs -gt 0 })
        $noSubIdle = @($noSub | Where-Object { $_.DCs -eq 0 })
        if (@($R.Subnets).Count -eq 0) {
            Add-Finding Warning 'Sites' 'No AD subnets are defined in Sites and Services.' '' 'Create a subnet for every network that has domain-joined devices (including VPN and server networks) and assign each to the correct site.'
        }
        elseif ($noSubDC.Count) {
            Add-Finding Warning 'Sites' "Sites with domain controllers but no subnets: $(($noSubDC.Site) -join ', ')" $noSubDC.Count 'Assign the subnets for those locations to the site so clients there use their local DC.'
        }
        if (@($R.Subnets).Count -gt 0 -and $noSubIdle.Count) {
            Add-Finding Info 'Sites' "Sites without subnets or domain controllers: $(($noSubIdle.Site) -join ', ')" $noSubIdle.Count 'Assign subnets to these sites or remove them if they are no longer used.'
        }
        $dcOut = @($R.DCSubnetCheck | Where-Object { $_.'Subnet Check' -ne 'OK' -and $_.'Subnet Check' -ne 'No IPv4 address' })
        if (@($R.Subnets).Count -gt 0 -and $dcOut.Count) {
            Add-Finding Warning 'Sites' "Domain controllers whose IP is not in a subnet of their own site: $(($dcOut.'Domain Controller') -join ', ')" $dcOut.Count 'Add or correct the subnet for each DC so it is in the same site the DC belongs to.'
        }
        if (@($R.Subnets).Count -gt 0 -and -not $noSubDC.Count -and -not $dcOut.Count) {
            Add-Finding OK 'Sites' 'Every site with a domain controller has subnets, and each DC is in a subnet of its own site.'
        }
        $insecure = @($R.DNSZones | Where-Object { $_.'Dynamic Update' -eq 'NonsecureAndSecure' -and $_.'AD Integrated' -eq 'Yes' })
        if ($insecure.Count) { Add-Finding Warning 'DNS' "AD-integrated zones allow non-secure dynamic updates: $(($insecure.Zone) -join ', ')" $insecure.Count 'Set Dynamic Updates to Secure only.' }
        $noScav = @($R.DNSForwarders | Where-Object { $_.'Scavenging Enabled' -eq 'No' })
        if ($R.DNSForwarders -and $noScav.Count -eq @($R.DNSForwarders).Count) { Add-Finding Info 'DNS' 'DNS scavenging is not enabled on any DNS server.' '' 'Enable scavenging on one DC to remove stale records.' }
    }
    Invoke-Check {
        $ext = @($R.Trusts | Where-Object { $_._External -and -not $_._SidFilter })
        if ($ext.Count) { Add-Finding Warning 'Trusts' "External trusts without SID filtering: $(($ext.Name) -join ', ')" $ext.Count 'Enable SID filtering (quarantine) on external trusts.' }
    }

    # --- Password policy
    Invoke-Check {
        $p = $R.PwdPolicy
        if ($p) {
            if ($p.MinPasswordLength -lt 12) { Add-Finding Warning 'Password Policy' "Minimum password length is $($p.MinPasswordLength)." '' 'Increase to at least 12-14 characters (or use a fine-grained policy).' }
            if (-not $p.ComplexityEnabled) { Add-Finding Warning 'Password Policy' 'Password complexity is disabled.' '' 'Enable complexity or enforce long passphrases.' }
            if ($p.LockoutThreshold -eq 0) { Add-Finding Warning 'Password Policy' 'Account lockout is disabled (threshold 0).' '' 'Set a lockout threshold (e.g. 10) to slow password guessing.' }
            if ($p.ReversibleEncryptionEnabled) { Add-Finding Critical 'Password Policy' 'Reversible password encryption is enabled in the default domain policy.' '' 'Disable reversible encryption and reset affected passwords.' }
        }
    }

    # --- Privileged access
    Invoke-Check {
        $da = @($R.DomainAdmins | Where-Object { $_.Type -eq 'user' })
        if ($da.Count -gt 5) { Add-Finding Warning 'Privileged Access' 'More than 5 user accounts in Domain Admins.' $da.Count 'Reduce standing Domain Admin membership; use delegated roles.' }
        $sa = @($R.PrivRows | Where-Object { $_._SID -eq "$($Ctx.RootSID)-518" })
        if ($sa.Count) { Add-Finding Warning 'Privileged Access' 'Schema Admins is not empty.' $sa.Count 'Keep Schema Admins empty except during schema changes.' }
        $ea = @($R.EnterpriseAdmins | Where-Object { $_.Type -eq 'user' })
        if ($ea.Count -gt 1) { Add-Finding Info 'Privileged Access' 'Enterprise Admins has standing user members.' $ea.Count 'Keep Enterprise Admins empty or limited to break-glass accounts.' }
        $neverExp = @($R.PrivUsers | Where-Object { $_.Enabled -and $_.PwdNeverExpires })
        if ($neverExp.Count) { Add-Finding Warning 'Privileged Access' 'Privileged accounts with passwords that never expire.' $neverExp.Count 'Rotate these passwords regularly or move service accounts to gMSAs.' }
        $stalePriv = @($R.PrivUsers | Where-Object { $_.Enabled -and (-not $_.LastLogon -or $_.LastLogon -lt $now.AddDays(-90)) })
        if ($stalePriv.Count) { Add-Finding Warning 'Privileged Access' 'Enabled privileged accounts with no logon in 90 days.' $stalePriv.Count 'Disable or remove unused privileged accounts.' }
        $notProt = @($R.PrivUsers | Where-Object { $_.Enabled -and -not $R.ProtectedSet.ContainsKey($_.DN) -and $_.SPNs.Count -eq 0 })
        if ($notProt.Count) { Add-Finding Info 'Privileged Access' 'Privileged user accounts not in Protected Users.' $notProt.Count 'Add admin (non-service) accounts to Protected Users after testing.' }
        if (@($R.OrphanAdminCount).Count) { Add-Finding Info 'Privileged Access' 'Accounts with adminCount=1 that are no longer in a privileged group.' @($R.OrphanAdminCount).Count 'Clear adminCount and re-enable inheritance on these accounts.' }
        if ($R.Krbtgt -and $R.Krbtgt.PwdLastSet -and $R.Krbtgt.PwdLastSet -lt $now.AddDays(-180)) {
            Add-Finding Warning 'Privileged Access' "krbtgt password is $([int]($now - $R.Krbtgt.PwdLastSet).TotalDays) days old." '' 'Reset the krbtgt password twice (allowing replication between resets).'
        }
        if ($R.BuiltinAdmin -and $R.BuiltinAdmin.PwdLastSet -and $R.BuiltinAdmin.PwdLastSet -lt $now.AddDays(-365)) {
            Add-Finding Warning 'Privileged Access' "Built-in Administrator password is $([int]($now - $R.BuiltinAdmin.PwdLastSet).TotalDays) days old." '' 'Rotate the built-in Administrator password and store it in your vault.'
        }
    }

    # --- Kerberos / account security
    Invoke-Check {
        $kr = @($R.Kerberoastable)
        $krPriv = @($kr | Where-Object { $_.Privileged -eq 'Yes' })
        if ($krPriv.Count) { Add-Finding Critical 'Kerberos' 'Privileged accounts with SPNs (kerberoastable).' $krPriv.Count 'Remove privileged rights from service accounts or convert them to gMSAs with long random passwords.' }
        if ($kr.Count -gt $krPriv.Count) { Add-Finding Warning 'Kerberos' 'User accounts with SPNs (kerberoastable).' ($kr.Count - $krPriv.Count) 'Use gMSAs or 25+ character passwords for service accounts.' }
        if (@($R.ASREP).Count) { Add-Finding Critical 'Kerberos' 'Accounts that do not require Kerberos pre-authentication (AS-REP roastable).' @($R.ASREP).Count 'Enable Kerberos pre-authentication on these accounts.' }
        if (@($R.Delegation | Where-Object { $_.Delegation -eq 'Unconstrained' }).Count) { Add-Finding Critical 'Kerberos' 'Non-DC accounts trusted for unconstrained delegation.' @($R.Delegation | Where-Object { $_.Delegation -eq 'Unconstrained' }).Count 'Switch to constrained or resource-based constrained delegation.' }
        if (@($R.PwdNotRequired).Count) { Add-Finding Warning 'Accounts' 'Enabled accounts flagged Password Not Required.' @($R.PwdNotRequired).Count 'Clear the PASSWD_NOTREQD flag and confirm a password is set.' }
        if (@($R.Reversible).Count) { Add-Finding Critical 'Accounts' 'Accounts storing passwords with reversible encryption.' @($R.Reversible).Count 'Disable reversible encryption and reset these passwords.' }
        if (@($R.DuplicateSPNs).Count) { Add-Finding Warning 'Kerberos' 'Duplicate SPNs found (Kerberos authentication failures).' @($R.DuplicateSPNs).Count 'Remove the duplicate SPN from the wrong account (setspn -X to verify).' }
    }

    # --- Users
    Invoke-Check {
        if (@($R.StaleUsers).Count) { Add-Finding Warning 'Users' "Enabled users with no logon in $Days days (including never logged on)." @($R.StaleUsers).Count 'Disable stale accounts and move them to a disabled-users OU.' }
        else { Add-Finding OK 'Users' "No enabled users inactive for $Days days." }
        $pne = @($R.PwdNeverExpiresUsers).Count
        if ($pne) { Add-Finding Info 'Users' 'Enabled users with passwords that never expire.' $pne 'Limit to service accounts; prefer gMSAs.' }
        if ($R.PwdExpiredCount) { Add-Finding Info 'Users' 'Enabled users with expired passwords.' $R.PwdExpiredCount 'Review whether these accounts are still needed.' }
        $acctExp = @($R.AcctExpiring | Where-Object { $_.Status -like 'Expired*' }).Count
        if ($acctExp) { Add-Finding Info 'Users' 'Expired accounts that are still enabled.' $acctExp 'Disable accounts that have passed their expiration date.' }
        if (@($R.DefaultContainerUsers | Where-Object { $_.Enabled -eq 'Yes' }).Count -gt 0) { Add-Finding Info 'Users' 'Enabled users in the default Users container (GPOs cannot be linked there).' @($R.DefaultContainerUsers | Where-Object { $_.Enabled -eq 'Yes' }).Count 'Move users into managed OUs; consider redirusr.' }
    }

    # --- Computers
    Invoke-Check {
        if (-not $R.LapsSchema) { Add-Finding Critical 'Computers' 'LAPS is not deployed (schema not extended).' '' 'Deploy Windows LAPS to randomize local Administrator passwords.' }
        elseif ($R.LapsScopeCount -gt 0 -and $R.LapsCovered -lt $R.LapsScopeCount) {
            $pct = [math]::Round(($R.LapsCovered / $R.LapsScopeCount) * 100, 0)
            Add-Finding Warning 'Computers' "LAPS coverage is $pct% of enabled Windows computers." ($R.LapsScopeCount - $R.LapsCovered) 'Apply the LAPS policy to the computers listed in the LAPS Missing table.'
        }
        elseif ($R.LapsScopeCount -gt 0) { Add-Finding OK 'Computers' 'All enabled Windows computers have LAPS passwords.' }
        $uns = @($R.UnsupportedOS | Where-Object { $_.'Support Status' -like 'Unsupported*' })
        if ($uns.Count) { Add-Finding Warning 'Computers' 'Enabled computers running unsupported operating systems.' $uns.Count 'Upgrade or isolate these systems.' }
        $soon = @($R.UnsupportedOS | Where-Object { $_.'Support Status' -like 'Support ends*' })
        if ($soon.Count) { Add-Finding Info 'Computers' 'Windows Server 2016 systems (extended support ends January 2027).' $soon.Count 'Plan upgrades.' }
        if (@($R.StaleComputers).Count) { Add-Finding Warning 'Computers' "Enabled computers with no logon in $StaleComputerDays days." @($R.StaleComputers).Count 'Disable and later delete stale computer objects.' }
        if (@($R.DefaultContainerComputers).Count) { Add-Finding Info 'Computers' 'Computers in the default Computers container (GPOs cannot be linked there).' @($R.DefaultContainerComputers).Count 'Move into managed OUs; consider redircmp.' }
    }

    # --- OUs and GPOs
    Invoke-Check {
        $unprot = @($R.OUs | Where-Object { -not $_._Protected })
        if ($unprot.Count) { Add-Finding Info 'Organizational Units' 'OUs not protected from accidental deletion.' $unprot.Count 'Enable protection on all OUs.' }
        $unlinked = @($R.GPOs | Where-Object { $_.Links -eq 0 })
        if ($unlinked.Count) { Add-Finding Info 'Group Policy' 'GPOs that are not linked anywhere.' $unlinked.Count 'Back up and delete unused GPOs.' }
        $empty = @($R.GPOs | Where-Object { $_._Empty })
        if ($empty.Count) { Add-Finding Info 'Group Policy' 'GPOs with no settings (version 0).' $empty.Count 'Delete empty GPOs.' }
        $mismatch = @($R.GPOs | Where-Object { $_.'SYSVOL Check' -like 'Version mismatch*' })
        if ($mismatch.Count) { Add-Finding Warning 'Group Policy' 'GPOs where the AD and SYSVOL versions differ.' $mismatch.Count 'Check SYSVOL/DFSR replication; re-save the GPO once replication is healthy.' }
        $missing = @($R.GPOs | Where-Object { $_.'SYSVOL Check' -eq 'SYSVOL folder missing' })
        if ($missing.Count) { Add-Finding Critical 'Group Policy' 'GPOs whose SYSVOL folder is missing.' $missing.Count 'Restore the GPO from backup or delete the orphaned AD object.' }
        $noRead = @($R.GPOs | Where-Object { $_._ReadOk -eq $false })
        if ($noRead.Count) { Add-Finding Warning 'Group Policy' 'GPOs where neither Authenticated Users nor Domain Computers can read the GPO (MS16-072).' $noRead.Count 'Grant Authenticated Users or Domain Computers Read on these GPOs.' }
    }

    # --- Authentication events
    Invoke-Check {
        if (-not $R.EventsSkipped) {
            if (@($R.Lockouts).Count) { Add-Finding Info 'Authentication' "Account lockouts in the last $EventLogDays days." @($R.Lockouts).Count 'Review the Account Lockouts table for repeat offenders and their caller computers.' }
            $noisy = @($R.FailureSummary | Where-Object { $_.Failures -ge 50 })
            if ($noisy.Count) { Add-Finding Warning 'Authentication' "Accounts with 50+ failed authentications in the last $EventLogDays days." $noisy.Count 'Look for stale saved credentials or password-spray activity.' }
        }
    }
}

# ---------------------------------------------------------------------------
# Main Logic - Build HTML report (self-rendered, no external modules or CDNs)
# ---------------------------------------------------------------------------

Write-Progress -Activity "Active Directory Report v$ScriptVersion" -Status 'Compiling report' -PercentComplete 99
Write-Log "Compiling report..."

$script:sb = [System.Text.StringBuilder]::new(1048576)

function Out-H { param([string]$Text) [void]$script:sb.AppendLine($Text) }

function Get-Count { param($Items) return @($Items | Where-Object { $null -ne $_ }).Count }

function Enc {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-Slug {
    param([string]$Text)
    $s = (([string]$Text).ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($s) { return $s } else { return 'none' }
}

function Get-JumpAttr {
    # Attributes that make an element jump to a table (and optionally switch it to a view)
    param([string]$Tbl, [string]$View)
    if (-not $Tbl) { return '' }
    $a = " href='#$Tbl' data-tbl='$Tbl'"
    if ($View) { $a += " data-view='$View'" }
    return $a
}

# Column name -> scriptblock returning a tone (crit / warn / info / ok) for a cell value
$CellTone = @{
    'Severity'             = { param($v) switch ($v) { 'Critical' { 'crit' } 'Warning' { 'warn' } 'Info' { 'info' } 'OK' { 'ok' } } }
    'Support Status'       = { param($v) if ($v -like 'Unsupported*') { 'crit' } elseif ($v -like 'Support ends*') { 'warn' } elseif ($v -like 'Supported*') { 'ok' } }
    'Status'               = { param($v) if ($v -like 'Expired*') { 'crit' } elseif ($v -eq 'Expiring') { 'warn' } elseif ($v -like '*disabled*') { 'warn' } }
    'Reachable'            = { param($v) if ($v -eq 'No') { 'crit' } else { 'ok' } }
    'SYSVOL Check'         = { param($v) if ($v -eq 'OK') { 'ok' } elseif ($v -eq 'Not checked') { 'info' } elseif ($v -like '*missing*') { 'crit' } else { 'warn' } }
    'Last Result'          = { param($v) if ("$v" -ne '' -and "$v" -ne '0') { 'crit' } }
    'Privileged'           = { param($v) if ($v -eq 'Yes') { 'crit' } }
    'Delegation'           = { param($v) if ($v -eq 'Unconstrained') { 'crit' } else { 'warn' } }
    'Dynamic Update'       = { param($v) if ($v -eq 'NonsecureAndSecure') { 'warn' } }
    'Link Enabled'         = { param($v) if ($v -eq 'No') { 'warn' } }
    'Enforced'             = { param($v) if ($v -eq 'Yes') { 'info' } }
    'LAPS'                 = { param($v) if ($v -eq 'No') { 'warn' } elseif ($v -eq 'Yes') { 'ok' } }
    'Locked Out'           = { param($v) if ($v -eq 'Yes') { 'warn' } }
    'Password Not Required' = { param($v) if ($v -eq 'Yes') { 'warn' } }
    'Denied'               = { param($v) if ($v -eq 'Yes') { 'warn' } }
    'Subnets'              = { param($v) if ("$v" -eq '0') { 'warn' } }
    'Subnet Check'         = { param($v) if ($v -eq 'OK') { 'ok' } elseif ($v -eq 'No IPv4 address') { 'info' } else { 'warn' } }
    'Matching Subnet'      = { param($v) if ($v -eq 'None') { 'warn' } }
}
foreach ($c in 'SYSVOL Share', 'NETLOGON Share') { $CellTone[$c] = { param($v) if ($v -eq 'No') { 'crit' } else { 'ok' } } }
foreach ($c in 'Consecutive Failures', 'Links With Failures', 'Failure Count') { $CellTone[$c] = { param($v) if ("$v" -match '^\d+$' -and [int]$v -gt 0) { 'crit' } } }
foreach ($c in 'Last Logon', 'Last Success', 'Oldest Successful Sync') { $CellTone[$c] = { param($v) if ($v -eq 'Never') { 'warn' } } }
foreach ($c in 'NTDS', 'DFSR', 'DNS', 'Netlogon', 'KDC', 'W32Time', 'ADWS') {
    $CellTone[$c] = { param($v) if ($v -eq 'Running') { 'ok' } elseif ($v -eq 'Not installed') { $null } elseif ($v -eq 'Unknown') { 'warn' } else { 'crit' } }
}

function Get-Cell {
    param([string]$Column, $Value)
    $text = if ($null -eq $Value) { '' } elseif ($Value -is [array]) { $Value -join ', ' } else { [string]$Value }
    if ($text -ne '' -and $CellTone.ContainsKey($Column)) {
        $tone = & $CellTone[$Column] $text
        if ($tone) { return "<span class='pill $tone'>$(Enc $text)</span>" }
    }
    return (Enc $text)
}

function Add-Table {
    # Renders a table. Properties starting with "_" are not shown; "_v" holds the view keys a row belongs to.
    param(
        [string]$Id,
        [string]$Title,
        $Data,
        [string]$Empty = 'No items found',
        [array]$Views,
        [switch]$Plain,
        [string]$Note
    )
    $rows = @($Data | Where-Object { $null -ne $_ })
    $cls  = if ($Plain) { 'card tbl plain' } else { 'card tbl' }
    Out-H "<section class='$cls' id='$Id'>"
    Out-H "<div class='card-h'><h3>$(Enc $Title) <span class='cnt'>$($rows.Count)</span></h3>"
    if (-not $Plain -and $rows.Count) {
        Out-H "<div class='tools'><input type='search' class='q' placeholder='Filter rows' aria-label='Filter $(Enc $Title)'><button type='button' class='btn csv'>Export CSV</button></div>"
    }
    Out-H '</div>'
    if ($Note) { Out-H "<p class='note'>$(Enc $Note)</p>" }
    if (-not $rows.Count) { Out-H "<p class='empty'>$(Enc $Empty)</p></section>"; return }

    if ($Views) {
        $tally = @{}
        foreach ($row in $rows) {
            $p = $row.PSObject.Properties['_v']
            if ($p -and $p.Value) { foreach ($k in ([string]$p.Value).Split(' ')) { if ($k) { if ($tally.ContainsKey($k)) { $tally[$k]++ } else { $tally[$k] = 1 } } } }
        }
        Out-H "<div class='views' role='group' aria-label='Views of $(Enc $Title)'>"
        Out-H "<button type='button' data-view='all'>All <b>$($rows.Count)</b></button>"
        foreach ($v in $Views) {
            $n = if ($tally.ContainsKey($v.K)) { $tally[$v.K] } else { 0 }
            Out-H "<button type='button' data-view='$($v.K)'>$(Enc $v.L) <b>$n</b></button>"
        }
        Out-H '</div>'
    }

    $cols = @($rows[0].PSObject.Properties.Name | Where-Object { $_ -notlike '_*' })
    Out-H "<div class='scroll'><table><thead><tr>"
    foreach ($c in $cols) {
        if ($Plain) { Out-H "<th scope='col'>$(Enc $c)</th>" }
        else { Out-H "<th scope='col'><button type='button' class='sort'>$(Enc $c)</button></th>" }
    }
    Out-H '</tr></thead><tbody>'
    foreach ($row in $rows) {
        $line = [System.Text.StringBuilder]::new()
        $p = $row.PSObject.Properties['_v']
        if ($p -and $p.Value) { [void]$line.Append("<tr data-v='$($p.Value)'>") } else { [void]$line.Append('<tr>') }
        $jump  = $row.PSObject.Properties['_jump']
        $first = $true
        foreach ($c in $cols) {
            $cell = Get-Cell $c $row.$c
            if ($first -and $jump -and $jump.Value) {
                $jp   = ([string]$jump.Value).Split('|')
                $cell = "<a$(Get-JumpAttr $jp[0] $jp[1]) title='Show what changed'>$cell</a>"
            }
            $first = $false
            [void]$line.Append('<td>').Append($cell).Append('</td>')
        }
        [void]$line.Append('</tr>')
        Out-H $line.ToString()
    }
    Out-H '</tbody></table></div>'
    if (-not $Plain) {
        Out-H "<div class='foot'><span class='info'>$($rows.Count) rows</span><span class='pager'><label>Rows per page <select class='size'><option>25</option><option>100</option><option value='0'>All</option></select></label><button type='button' class='btn prev'>Previous</button><button type='button' class='btn next'>Next</button></span></div>"
    }
    Out-H '</section>'
}

function Add-KeyValue {
    # Pairs: ordered dictionary. With -Raw the values are already HTML.
    param([string]$Title, $Pairs, [switch]$Raw, [string]$Id)
    $idAttr = if ($Id) { " id='$Id'" } else { '' }
    Out-H "<section class='card'$idAttr><div class='card-h'><h3>$(Enc $Title)</h3></div><dl class='kv'>"
    foreach ($k in $Pairs.Keys) {
        $val = if ($Raw) { [string]$Pairs[$k] } else { Enc $Pairs[$k] }
        Out-H "<div><dt>$(Enc $k)</dt><dd>$val</dd></div>"
    }
    Out-H '</dl></section>'
}

function Add-Tiles {
    # Each tile: @{ L = label; N = number; S = sub text; Tone = crit|warn|info|ok; Tbl = table id; View = view key; Sev = severity filter }
    param([array]$Tiles)
    Out-H "<div class='tiles'>"
    foreach ($t in $Tiles) {
        $tone  = if ($t.Tone) { " $($t.Tone)" } else { '' }
        $inner = "<span class='t-l'>$(Enc $t.L)</span><span class='t-n'>$(Enc $t.N)</span>"
        if ($t.S) { $inner += "<span class='t-s'>$(Enc $t.S)</span>" }
        if ($t.Tbl) { Out-H "<a class='tile$tone'$(Get-JumpAttr $t.Tbl $t.View)>$inner</a>" }
        elseif ($t.Sev) { Out-H "<a class='tile$tone' href='#findings' data-sevlink='$($t.Sev)'>$inner</a>" }
        else { Out-H "<div class='tile$tone'>$inner</div>" }
    }
    Out-H '</div>'
}

function Add-Bars {
    # Each item: @{ L = label; N = number; Tone = warn|crit|ok; Tbl = table id; View = view key }. Bars with a table are clickable.
    param([string]$Title, [array]$Items, [string]$Note)
    $max = 1
    foreach ($i in $Items) { if ([int]$i.N -gt $max) { $max = [int]$i.N } }
    Out-H "<section class='card'><div class='card-h'><h3>$(Enc $Title)</h3></div><div class='bars'>"
    foreach ($i in $Items) {
        $n = [int]$i.N
        $w = if ($n -gt 0) { [math]::Max(2, [int][math]::Round(($n / $max) * 100)) } else { 0 }
        $tone  = if ($i.Tone) { " $($i.Tone)" } else { '' }
        $inner = "<span class='b-l'>$(Enc $i.L)</span><span class='b-t'><span style='width:$w%'></span></span><span class='b-n'>$n</span>"
        if ($i.Tbl) { Out-H "<a class='bar$tone'$(Get-JumpAttr $i.Tbl $i.View)>$inner</a>" }
        else { Out-H "<div class='bar$tone'>$inner</div>" }
    }
    if ($Note) { Out-H "<p class='note'>$(Enc $Note)</p>" }
    Out-H '</div></section>'
}

function Open-Page {
    param([string]$Id, [string]$Title, [string]$Sub)
    Out-H "<section class='page' id='p-$Id'><header class='page-h'><div><h1>$(Enc $Title)</h1><span class='sub'>$(Enc $Sub)</span></div><div class='tools'><button type='button' class='btn' data-print>Print / PDF</button></div></header><div class='page-b'>"
}
function Close-Page { Out-H '</div></section>' }

function Add-OUTree {
    param([string]$Title = 'OU structure', [int]$MaxDepth = 99)
    $linkCount = @{}
    foreach ($l in @($R.GPLinks)) {
        if ($null -eq $l) { continue }
        $k = [string]$l.'Linked To'
        if ($linkCount.ContainsKey($k)) { $linkCount[$k]++ } else { $linkCount[$k] = 1 }
    }
    $ous = @($R.OUs | Where-Object { $null -ne $_ } | Sort-Object Path)
    Out-H "<section class='card'><div class='card-h'><h3>$(Enc $Title) <span class='cnt'>$($ous.Count)</span></h3></div><div class='scroll'><table class='tree'><thead><tr><th scope='col'>OU</th><th scope='col'>Users</th><th scope='col'>Computers</th><th scope='col'>GPO links</th></tr></thead><tbody>"
    $rootLinks = if ($linkCount.ContainsKey($Ctx.DomainDNS)) { $linkCount[$Ctx.DomainDNS] } else { 0 }
    Out-H "<tr><td><b class='mono'>$(Enc $Ctx.DomainDNS)</b></td><td>&ndash;</td><td>&ndash;</td><td>$rootLinks</td></tr>"
    $hidden = 0
    foreach ($ou in $ous) {
        $path  = [string]$ou.Path
        $parts = @($path -split '(?<!\\)/')
        $depth = $parts.Count - 1
        if ($depth -gt $MaxDepth) { $hidden++; continue }
        $links = if ($linkCount.ContainsKey($path)) { $linkCount[$path] } else { 0 }
        $pad   = 16 * $depth
        Out-H "<tr><td style='padding-left:${pad}px'>$(Enc $ou.Name)</td><td>$($ou.Users)</td><td>$($ou.Computers)</td><td>$links</td></tr>"
    }
    $du = @($R.Users | Where-Object { $_.ParentDN -eq $ADDomain.UsersContainer }).Count
    $dcomp = @($R.Computers | Where-Object { $_.ParentDN -eq $ADDomain.ComputersContainer }).Count
    $duCls = if ($du) { " class='flag'" } else { '' }
    $dcCls = if ($dcomp) { " class='flag'" } else { '' }
    Out-H "<tr$duCls><td style='padding-left:16px'><a$(Get-JumpAttr 'tUsers' 'default-container')>Users (default container)</a></td><td>$du</td><td>0</td><td>n/a</td></tr>"
    Out-H "<tr$dcCls><td style='padding-left:16px'><a$(Get-JumpAttr 'tComputers' 'default-container')>Computers (default container)</a></td><td>0</td><td>$dcomp</td><td>n/a</td></tr>"
    Out-H '</tbody></table></div>'
    $note = 'Counts are objects directly in each OU. GPO links are policies linked directly to that OU. Default containers cannot take GPO links.'
    if ($hidden) { $note = "$hidden deeper OUs are not shown here; the full tree is on the Organizational units page. $note" }
    Out-H "<p class='note'>$(Enc $note)</p></section>"
}

# ---------------------------------------------------------------------------
# Findings: score, plain-language text and links to the affected data
# ---------------------------------------------------------------------------

$CatPage = @{
    'Domain Controllers' = 'dc'; 'Replication' = 'dc'; 'SYSVOL' = 'dc'; 'Environment' = 'dc'
    'Sites' = 'sites'; 'DNS' = 'sites'; 'Trusts' = 'sites'
    'Password Policy' = 'security'; 'Kerberos' = 'security'; 'Accounts' = 'security'; 'Authentication' = 'security'
    'Privileged Access' = 'priv'; 'Users' = 'users'; 'Computers' = 'computers'
    'Organizational Units' = 'ous'; 'Group Policy' = 'gpo'
}

# M = regex on the finding text; T = plain-language title; W = why it matters (client wording); Tbl / View = where the affected items are
$PlainMap = @(
    @{ M = '^Replication failures'; T = 'Domain controllers have stopped syncing changes'; W = 'Password resets, disabled accounts and group changes made on one server are not reaching the others, so a departed employee could still sign in.'; Tbl = 'tReplDetail'; View = 'failing' }
    @{ M = 'no successful sync in the last 24 hours'; T = 'Domain controllers are syncing late'; W = 'Account and policy changes are taking more than a day to reach every server.'; Tbl = 'tReplDetail' }
    @{ M = '^Core AD services not running'; T = 'A domain controller has core services stopped'; W = 'Sign-ins and policy updates can fail for anyone who reaches that server.'; Tbl = 'tDCHealth' }
    @{ M = '^SYSVOL/NETLOGON share'; T = 'A domain controller is not sharing policies and logon scripts'; W = 'Computers that reach that server may miss security policies and drive mappings.'; Tbl = 'tDCHealth' }
    @{ M = '^DCs not reachable'; T = 'A domain controller could not be checked'; W = 'Its health could not be confirmed remotely. It may be offline or blocking management traffic.'; Tbl = 'tDCHealth' }
    @{ M = '^Low free space'; T = 'A domain controller is running out of disk space'; W = 'A full system drive stops the directory database and takes sign-ins down with it.'; Tbl = 'tDCHealth' }
    @{ M = '^SYSVOL replication: (FRS|Migration)'; T = 'Policies replicate using a retired technology (FRS)'; W = 'FRS is no longer supported and blocks adding modern domain controllers such as Windows Server 2025.' }
    @{ M = '^DCs on unsupported operating systems'; T = 'A domain controller runs an unsupported version of Windows'; W = 'It no longer receives security updates, and it holds every password in the organization.'; Tbl = 'tDCs' }
    @{ M = '^AD Recycle Bin is disabled'; T = 'Deleted accounts cannot be easily restored'; W = 'An accidental deletion means rebuilding the account and its access by hand.' }
    @{ M = '^Minimum password length'; T = 'Short passwords are allowed'; W = 'Short passwords are quick to guess or crack.'; Tbl = 'tPwdPolicy' }
    @{ M = '^Password complexity is disabled'; T = 'Simple passwords are allowed'; W = 'Users can choose passwords that are trivial to guess.'; Tbl = 'tPwdPolicy' }
    @{ M = '^Account lockout is disabled'; T = 'Unlimited password guessing is allowed'; W = 'Automated attacks can try passwords against every account indefinitely.'; Tbl = 'tPwdPolicy' }
    @{ M = '^Reversible password encryption'; T = 'Passwords are stored in a recoverable form'; W = 'Anyone who copies the directory database can read these passwords.'; Tbl = 'tPwdPolicy' }
    @{ M = '^Accounts storing passwords with reversible'; T = 'Some passwords are stored in a recoverable form'; W = 'Anyone who copies the directory database can read these passwords.'; Tbl = 'tPwdFlags' }
    @{ M = '^More than 5 user accounts in Domain Admins'; T = 'Too many accounts have full administrative control'; W = 'Every extra administrator account is another way for an attacker to take over the whole network.'; Tbl = 'tPriv' }
    @{ M = '^Schema Admins is not empty'; Tbl = 'tPriv' }
    @{ M = '^Enterprise Admins has standing'; Tbl = 'tPriv' }
    @{ M = '^Privileged accounts with passwords that never expire'; T = 'Administrator passwords never expire'; W = 'A stolen administrator password keeps working until someone changes it by hand.'; Tbl = 'tPriv'; View = 'pwd-never' }
    @{ M = '^Enabled privileged accounts with no logon'; T = 'Unused administrator accounts are still active'; W = 'Nobody would notice if one of these accounts were taken over.'; Tbl = 'tPriv'; View = 'stale' }
    @{ M = '^Privileged user accounts not in Protected Users'; Tbl = 'tPriv'; View = 'not-protected' }
    @{ M = 'adminCount=1'; Tbl = 'tOrphan' }
    @{ M = '^krbtgt password'; T = 'The master sign-in key has not been rotated'; W = 'If this key was ever stolen, an attacker can forge sign-ins for any account until it is reset.'; Tbl = 'tKeyAccounts' }
    @{ M = '^Built-in Administrator password'; T = 'The built-in Administrator password is old'; W = 'This account cannot be locked out, so an old password is a standing risk.'; Tbl = 'tKeyAccounts' }
    @{ M = '^Privileged accounts with SPNs'; T = 'An administrator account is exposed to offline password cracking'; W = 'Any signed-in user can request data that lets them guess this password offline, without triggering alerts.'; Tbl = 'tKerberoast' }
    @{ M = '^User accounts with SPNs'; T = 'Service accounts are exposed to offline password cracking'; W = 'Any signed-in user can request data that lets them guess these passwords offline.'; Tbl = 'tKerberoast' }
    @{ M = 'do not require Kerberos pre-authentication'; T = 'Some accounts can be attacked without signing in'; W = 'Anyone on the network can request data to crack these passwords offline.'; Tbl = 'tASREP' }
    @{ M = 'unconstrained delegation'; T = 'A server or account can impersonate any user'; W = 'If it is compromised, the attacker can act as anyone who connects to it, including administrators.'; Tbl = 'tDelegation' }
    @{ M = 'Password Not Required'; T = 'Some accounts may have blank passwords'; W = 'These accounts are exempt from the password policy.'; Tbl = 'tPwdFlags' }
    @{ M = '^Duplicate SPNs'; Tbl = 'tDupSPN' }
    @{ M = '^Enabled users with no logon'; T = '{n} active accounts have not been used in a long time'; W = 'Unused accounts are a common way in for attackers.'; Tbl = 'tUsers'; View = 'inactive' }
    @{ M = '^Enabled users with passwords that never expire'; Tbl = 'tUsers'; View = 'pwd-never' }
    @{ M = '^Enabled users with expired passwords'; Tbl = 'tUsers'; View = 'pwd-expired' }
    @{ M = '^Expired accounts that are still enabled'; Tbl = 'tUsers'; View = 'acct-expiring' }
    @{ M = '^Enabled users in the default Users'; Tbl = 'tUsers'; View = 'default-container' }
    @{ M = '^LAPS is not deployed'; T = 'Computers may share the same local administrator password'; W = 'One stolen local password can unlock every workstation.'; Tbl = 'tComputers'; View = 'laps-missing' }
    @{ M = '^LAPS coverage'; T = 'Some computers lack managed local administrator passwords'; W = 'One stolen local password can unlock every computer that shares it.'; Tbl = 'tComputers'; View = 'laps-missing' }
    @{ M = '^Enabled computers running unsupported'; T = '{n} computers run unsupported versions of Windows'; W = 'They no longer receive security updates.'; Tbl = 'tComputers'; View = 'unsupported' }
    @{ M = '^Windows Server 2016 systems'; Tbl = 'tComputers'; View = 'eol-soon' }
    @{ M = '^Enabled computers with no logon'; T = '{n} computer accounts are no longer in use'; W = 'Old computer accounts clutter the directory and can be reused by an attacker.'; Tbl = 'tComputers'; View = 'stale' }
    @{ M = '^Computers in the default Computers'; Tbl = 'tComputers'; View = 'default-container' }
    @{ M = '^OUs not protected'; Tbl = 'tOUs'; View = 'unprotected' }
    @{ M = '^GPOs that are not linked'; Tbl = 'tGPOs'; View = 'unlinked' }
    @{ M = '^GPOs with no settings'; Tbl = 'tGPOs'; View = 'empty' }
    @{ M = 'AD and SYSVOL versions differ'; Tbl = 'tGPOs'; View = 'sysvol-issue' }
    @{ M = 'SYSVOL folder is missing'; Tbl = 'tGPOs'; View = 'sysvol-issue' }
    @{ M = 'neither Authenticated Users'; Tbl = 'tGPOs'; View = 'no-read' }
    @{ M = '^Account lockouts in the last'; Tbl = 'tLockouts' }
    @{ M = 'failed authentications in the last'; Tbl = 'tFailSummary' }
    @{ M = 'non-secure dynamic updates'; Tbl = 'tDNSZones' }
    @{ M = '^External trusts'; Tbl = 'tTrusts' }
    @{ M = '^No AD subnets'; T = 'No network subnets are mapped to sites'; W = 'Without subnets, devices cannot tell which domain controller is closest. Sign-ins and policy processing can go to any DC, including one across a slow link or one that is down, and some services (DFS, Exchange, Kerberos site awareness) behave unpredictably.'; Tbl = 'tSites' }
    @{ M = '^Sites with domain controllers but no subnets'; T = 'A site has domain controllers but no subnets'; W = 'Devices at that location are not tied to their local DC, so sign-ins may cross the WAN or fail when the link is down.'; Tbl = 'tSites'; View = 'no-subnets' }
    @{ M = '^Sites without subnets or domain controllers'; Tbl = 'tSites'; View = 'no-subnets' }
    @{ M = '^Domain controllers whose IP is not in a subnet'; T = 'A domain controller is not in a subnet of its own site'; W = 'The DC and the devices around it may be treated as belonging to different locations.'; Tbl = 'tDCSubnets' }
)

$SevLabel = @{ Critical = 'Critical'; Warning = 'Warning'; Info = 'Advisory'; OK = 'Passed' }
$SevTone  = @{ Critical = 'crit'; Warning = 'warn'; Info = 'info'; OK = 'ok' }

$Findings = @(foreach ($f in @($R.Findings | Sort-Object _Order, Category)) {
    $meta = $null
    foreach ($m in $PlainMap) { if ([string]$f.Finding -match $m.M) { $meta = $m; break } }
    $title = [string]$f.Finding
    if ($meta -and $meta.T) { $title = $meta.T -replace '\{n\}', [string]$f.Count }
    [PSCustomObject]@{
        Severity       = $f.Severity
        Category       = $f.Category
        Finding        = $f.Finding
        Count          = $f.Count
        Recommendation = $f.Recommendation
        PlainTitle     = $title
        Why            = if ($meta) { $meta.W } else { $null }
        Table          = if ($meta) { $meta.Tbl } else { $null }
        View           = if ($meta) { $meta.View } else { $null }
        Page           = if ($CatPage.ContainsKey([string]$f.Category)) { $CatPage[[string]$f.Category] } else { 'overview' }
    }
})
$nCrit = @($Findings | Where-Object Severity -eq 'Critical').Count
$nWarn = @($Findings | Where-Object Severity -eq 'Warning').Count
$nInfo = @($Findings | Where-Object Severity -eq 'Info').Count
$nOk   = @($Findings | Where-Object Severity -eq 'OK').Count

# Health score: each Critical costs 10, Warning 3, Advisory 1; the curve flattens so the score never reaches 0
$penalty     = (10 * $nCrit) + (3 * $nWarn) + $nInfo
$HealthScore = [int][math]::Round(100 * 150 / (150 + $penalty))
$HealthLabel = if ($HealthScore -ge 85) { 'Good' } elseif ($HealthScore -ge 65) { 'Fair' } elseif ($HealthScore -ge 45) { 'Needs attention' } else { 'At risk' }
$HealthTone  = if ($HealthScore -ge 85) { 'ok' } elseif ($HealthScore -ge 45) { 'warn' } else { 'crit' }

function Get-FindingLink {
    param($Finding, [string]$Text = 'View affected items')
    if ($Finding.Table) { return "<a class='more'$(Get-JumpAttr $Finding.Table $Finding.View)>$Text</a>" }
    return "<a class='more' href='#p-$($Finding.Page)'>Open section</a>"
}

# ---------------------------------------------------------------------------
# Row sets with view keys (one table per object type; views replace the separate tables)
# ---------------------------------------------------------------------------

$now        = Get-Date
$privDNs    = if ($R.PrivDNs) { $R.PrivDNs } else { @{} }
$protSet    = if ($R.ProtectedSet) { $R.ProtectedSet } else { @{} }
$staleCut   = $now.AddDays(-$Days)
$newCut     = $now.AddDays(-$UserCreatedDays).Date
$acctCut    = $now.AddDays($AccountExpiringDays)

$UserRows = @(foreach ($u in @($R.Users | Where-Object { $null -ne $_ } | Sort-Object Name)) {
    $v = [System.Collections.Generic.List[string]]::new()
    if ($u.Enabled) { $v.Add('enabled') } else { $v.Add('disabled') }
    if ($u.Enabled) {
        if (-not $u.LastLogon) { $v.Add('b-never') }
        else {
            $age = ($now - $u.LastLogon).TotalDays
            if ($age -lt 30) { $v.Add('b-30') } elseif ($age -lt 90) { $v.Add('b-90') } elseif ($age -lt 365) { $v.Add('b-365') } else { $v.Add('b-old') }
        }
        $isStale = if ($u.LastLogon) { $u.LastLogon -lt $staleCut } else { $u.Created -lt $staleCut }
        if ($isStale) { $v.Add('inactive') }
        if ($null -ne $u.DaysToExpire) {
            if ($u.DaysToExpire -lt 0) { $v.Add('pwd-expired') } elseif ($u.DaysToExpire -le $DaysUntilPWExpireINT) { $v.Add('pwd-expiring') }
        }
        if ($u.PwdNeverExpires) { $v.Add('pwd-never') }
        if ($u.PwdNotRequired)  { $v.Add('pwd-notreq') }
    }
    if ($u.AccountExpires -and $u.AccountExpires -le $acctCut -and -not ($u.AccountExpires -lt $now -and -not $u.Enabled)) { $v.Add('acct-expiring') }
    if ($u.Created -ge $newCut) { $v.Add('new') }
    if ($u.LockedOut) { $v.Add('locked') }
    if ($u.ParentDN -eq $ADDomain.UsersContainer) { $v.Add('default-container') }
    if ($privDNs.ContainsKey($u.DN)) { $v.Add('privileged') }
    if ($u.Protected) { $v.Add('protected') } else { $v.Add('unprotected') }
    [PSCustomObject]@{
        'Name'                    = $u.Name
        'SamAccountName'          = $u.Sam
        'UserPrincipalName'       = $u.UPN
        'Enabled'                 = ConvertTo-YesNo $u.Enabled
        'Last Logon'              = Format-Date $u.LastLogon 'Never'
        'Password Last Set'       = Format-Date $u.PwdLastSet 'Never'
        'Password Expires'        = Format-Date $u.PwdExpires
        'Days Until Expiry'       = $u.DaysToExpire
        'Password Never Expires'  = ConvertTo-YesNo $u.PwdNeverExpires
        'Password Not Required'   = ConvertTo-YesNo $u.PwdNotRequired
        'Locked Out'              = ConvertTo-YesNo $u.LockedOut
        'Account Expires'         = Format-Date $u.AccountExpires 'Never'
        'Privileged'              = ConvertTo-YesNo $privDNs.ContainsKey($u.DN)
        'Email Address'           = $u.Email
        'Proxy Addresses'         = $u.Proxy
        'Created'                 = Format-Date $u.Created
        'Protected from Deletion' = ConvertTo-YesNo $u.Protected
        'Location'                = $u.ParentDN
        '_v'                      = ($v -join ' ')
    }
})
function Get-ViewCount { param($Rows, [string]$Key) return @($Rows | Where-Object { (" $($_._v) ") -like "* $Key *" }).Count }

$ComputerRows = @(foreach ($c in @($R.Computers | Where-Object { $null -ne $_ } | Sort-Object Name)) {
    $v = [System.Collections.Generic.List[string]]::new()
    if ($c.Enabled) { $v.Add('enabled') } else { $v.Add('disabled') }
    if ($c.IsDC) { $v.Add('dc') } elseif ($c.IsServer) { $v.Add('server') } else { $v.Add('workstation') }
    if ($c.Stale) { $v.Add('stale') }
    if ($c.Enabled -and $c.Support -like 'Unsupported*') { $v.Add('unsupported') }
    if ($c.Enabled -and $c.Support -like 'Support ends*') { $v.Add('eol-soon') }
    if ($c.Enabled -and -not $c.IsDC -and $c.OS -match 'Windows') { if ($c.Laps) { $v.Add('laps-ok') } else { $v.Add('laps-missing') } }
    if ($c.ParentDN -eq $ADDomain.ComputersContainer) { $v.Add('default-container') }
    if ($c.Protected) { $v.Add('protected') } else { $v.Add('unprotected') }
    $v.Add("os-$(ConvertTo-Slug $c.OSFamily)")
    $v.Add("sup-$(ConvertTo-Slug $c.Support)")
    [PSCustomObject]@{
        'Name'                    = $c.Name
        'Enabled'                 = ConvertTo-YesNo $c.Enabled
        'Operating System'        = $c.OS
        'OS Version'              = $c.OSVersion
        'Support Status'          = $c.Support
        'Last Logon'              = Format-Date $c.LastLogon 'Never'
        'Password Last Set'       = Format-Date $c.PwdLastSet 'Never'
        'Created'                 = Format-Date $c.Created
        'LAPS'                    = if ($c.IsDC) { 'N/A (DC)' } else { ConvertTo-YesNo $c.Laps }
        'Protected from Deletion' = ConvertTo-YesNo $c.Protected
        'Location'                = $c.ParentDN
        '_v'                      = ($v -join ' ')
    }
})

$GroupRows = @(foreach ($g in @($R.Groups | Where-Object { $null -ne $_ } | Sort-Object Name)) {
    $v = [System.Collections.Generic.List[string]]::new()
    $v.Add("type-$(ConvertTo-Slug $g.Type)")
    if ($g.Count -gt 0) { $v.Add('has-members') } else { $v.Add('empty') }
    if ($g.IsDefault) { $v.Add('default') } else { $v.Add('custom') }
    if ($g.Protected) { $v.Add('protected') } else { $v.Add('unprotected') }
    [PSCustomObject]@{
        'Name'                    = $g.Name
        'Type'                    = $g.Type
        'Scope'                   = $g.Scope
        'Member Count'            = $g.Count
        'Members'                 = $g.Members
        'Managed By'              = if ($g.ManagedBy) { $g.ManagedBy } else { 'None' }
        'E-mail Address'          = $g.Mail
        'Protected from Deletion' = ConvertTo-YesNo $g.Protected
        'Default AD Group'        = ConvertTo-YesNo $g.IsDefault
        'Description'             = $g.Description
        '_v'                      = ($v -join ' ')
    }
})

$PrivRows = @(foreach ($p in @($R.PrivRows | Where-Object { $null -ne $_ })) {
    $v = [System.Collections.Generic.List[string]]::new()
    $v.Add("g-$(ConvertTo-Slug $p.Group)")
    $u = if ($R.UserByDN) { $R.UserByDN[$p._DN] } else { $null }
    if ($u -and $u.Enabled) {
        if ($u.PwdNeverExpires) { $v.Add('pwd-never') }
        if (-not $u.LastLogon -or $u.LastLogon -lt $now.AddDays(-90)) { $v.Add('stale') }
        if (-not $protSet.ContainsKey($u.DN) -and $u.SPNs.Count -eq 0) { $v.Add('not-protected') }
        if ($u.SPNs.Count -gt 0) { $v.Add('has-spn') }
    }
    $p | Select-Object * -ExcludeProperty _DN, _SID, _v | Add-Member -NotePropertyName '_v' -NotePropertyValue ($v -join ' ') -PassThru
})

$GPORows = @(foreach ($g in @($R.GPOs | Where-Object { $null -ne $_ })) {
    $v = [System.Collections.Generic.List[string]]::new()
    if ($g.Links -eq 0) { $v.Add('unlinked') } else { $v.Add('linked') }
    if ($g._Empty) { $v.Add('empty') }
    if ($g.'SYSVOL Check' -like 'Version mismatch*' -or $g.'SYSVOL Check' -like '*missing*' -or $g.'SYSVOL Check' -like '*unreadable*') { $v.Add('sysvol-issue') }
    if ($g._ReadOk -eq $false) { $v.Add('no-read') }
    if ($g.Status -ne 'All settings enabled') { $v.Add('partly-disabled') }
    if ($g.'WMI Filter' -ne 'None') { $v.Add('wmi') }
    $g | Select-Object * -ExcludeProperty _Empty, _ReadOk, _v | Add-Member -NotePropertyName '_v' -NotePropertyValue ($v -join ' ') -PassThru
})

$OURows = @(foreach ($o in @($R.OUs | Where-Object { $null -ne $_ } | Sort-Object Path)) {
    $v = [System.Collections.Generic.List[string]]::new()
    if ($o._HasLinks) { $v.Add('has-links') } else { $v.Add('no-links') }
    if ($o._Protected) { $v.Add('protected') } else { $v.Add('unprotected') }
    if ($o.'Block Inheritance' -eq 'Yes') { $v.Add('block') }
    if (([int]$o.Users + [int]$o.Computers) -eq 0) { $v.Add('no-objects') }
    $o | Select-Object * -ExcludeProperty _HasLinks, _Protected, _v | Add-Member -NotePropertyName '_v' -NotePropertyValue ($v -join ' ') -PassThru
})

$ReplRows = @(foreach ($rp in @($R.ReplDetail | Where-Object { $null -ne $_ })) {
    $bad = ([int]$rp.'Consecutive Failures' -gt 0) -or ("$($rp.'Last Result')" -ne '' -and "$($rp.'Last Result')" -ne '0')
    $rp | Select-Object * -ExcludeProperty _v | Add-Member -NotePropertyName '_v' -NotePropertyValue $(if ($bad) { 'failing' } else { 'healthy' }) -PassThru
})

$LinkRows = @(foreach ($l in @($R.GPLinkTable | Where-Object { $null -ne $_ })) {
    $v = [System.Collections.Generic.List[string]]::new()
    $v.Add("t-$(ConvertTo-Slug $l.'Target Type')")
    if ($l.Enforced -eq 'Yes') { $v.Add('enforced') }
    if ($l.'Link Enabled' -eq 'No') { $v.Add('link-disabled') }
    $l | Select-Object * -ExcludeProperty _v | Add-Member -NotePropertyName '_v' -NotePropertyValue ($v -join ' ') -PassThru
})

# ---------------------------------------------------------------------------
# Page shell: styles, navigation
# ---------------------------------------------------------------------------

$leftLogoSrc  = Get-LogoSource $CompanyLogo
$rightLogoSrc = if ($RightLogo) { Get-LogoSource $RightLogo } else { $null }
$ReportDate   = Get-Date -Format 'MMMM d, yyyy'
$IncludeGpoSettings = ($GPModule -and -not $SkipGPOSettings -and (Get-Count $R.GPOReports) -gt 0)

$Pages = [ordered]@{
    summary   = 'Executive summary'
    overview  = 'Overview'
    dc        = 'DC health'
    sites     = 'Sites and DNS'
    users     = 'Users'
    groups    = 'Groups'
    priv      = 'Privileged access'
    security  = 'Security'
    computers = 'Computers'
    ous       = 'Organizational units'
    gpo       = 'Group Policy'
}
if ($IncludeGpoSettings) { $Pages['gposet'] = 'GPO settings' }

$Css = @'
:root{--ink:#17191D;--mut:#5B6068;--line:#E3E3DF;--soft:#EDEDE9;--bg:#F5F5F2;--crit:#A4161A;--critbg:#FDE8E8;--warn:#8A4B00;--warnbg:#FDF0D5;--info:#1D4F91;--infobg:#E5EEF9;--ok:#0B6B3A;--okbg:#E3F4EA}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 "Segoe UI",system-ui,-apple-system,Roboto,Arial,sans-serif}
a{color:var(--ink)}a:hover{color:var(--mut)}
h1,h2,h3,h4,p{margin:0}h1,h2,h3{line-height:1.2}
h1{font-size:26px}h2{font-size:20px}h3{font-size:16px}
.mono{font-family:Consolas,"Cascadia Mono",monospace;font-size:12.5px}
.app{display:flex;flex-wrap:wrap;align-items:stretch;min-height:100vh}
.nav{flex:1 1 230px;max-width:250px;background:var(--ink);color:#E6E7E9;display:flex;flex-direction:column;gap:16px;padding-bottom:18px}
.js .nav{position:sticky;top:0;height:100vh;overflow:auto;align-self:flex-start}
.nav .stripe,.stripe{height:6px;background:var(--accent);flex:none}
.nav .brand{padding:6px 18px 0;display:flex;flex-direction:column;gap:12px}
.nav .chip{background:#fff;border-radius:8px;padding:8px 10px;display:flex;justify-content:center}
.nav .chip img{max-height:44px;max-width:100%;object-fit:contain}
.nav .client{font-weight:700;font-size:15px;color:#fff}
.nav .dom{font-size:12px;color:#A9ACB2}
.nav ul{list-style:none;margin:0;padding:0 10px;display:flex;flex-direction:column;gap:2px}
.nav li a{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:9px 12px;border-radius:6px;color:#E6E7E9;text-decoration:none;font-weight:500}
.nav li a:hover{background:#24272C;color:#fff}
.nav li a.on{background:#2C2F35;color:#fff;font-weight:600}
.badge{font-size:11px;font-weight:700;padding:1px 8px;border-radius:999px}
.badge.crit{background:#F3B4B4;color:#5C0B0D}.badge.warn{background:#F5D9A0;color:#4A2A00}
.nav .meta{margin-top:auto;padding:14px 18px 0;border-top:1px solid #2C2F35;display:flex;flex-direction:column;gap:3px;font-size:12px;color:#A9ACB2}
.main{flex:999 1 560px;min-width:0}
.page{border-bottom:1px solid var(--line)}
.js .page{display:none;border:0}.js .page.active{display:block}
.page-h{background:#fff;border-bottom:1px solid var(--line);padding:18px 32px;display:flex;flex-wrap:wrap;justify-content:space-between;align-items:center;gap:12px}
.page-h .sub{color:var(--mut);font-size:13px}
.page-b{padding:24px 32px 40px;display:flex;flex-direction:column;gap:24px}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:24px;align-items:start}
.grid3{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px;align-items:start}
.split{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);gap:24px;align-items:start}
.stack{display:flex;flex-direction:column;gap:24px;min-width:0}
.card{background:#fff;border:1px solid var(--line);border-radius:12px;min-width:0;overflow:hidden}
.card-h{padding:14px 20px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:10px;justify-content:space-between;align-items:center}
.cnt{font-size:12px;font-weight:600;color:var(--mut);background:var(--soft);border-radius:999px;padding:1px 8px;margin-left:4px;vertical-align:middle}
.note{padding:10px 20px;font-size:12px;color:var(--mut)}
.empty{padding:16px 20px;color:var(--mut)}
.tools{display:none;gap:8px;align-items:center;flex-wrap:wrap}.js .tools{display:flex}
.btn{min-height:36px;padding:0 14px;border:1px solid #D5D6D1;background:#fff;border-radius:8px;font:inherit;font-weight:600;cursor:pointer;color:var(--ink)}
.btn:hover{background:#FAFAF8}.btn:disabled{opacity:.45;cursor:default}
.q{height:36px;width:220px;max-width:100%;padding:0 12px;border:1px solid #D5D6D1;border-radius:8px;font:inherit;background:#FAFAF8}
.views{display:none;flex-wrap:wrap;gap:6px;padding:12px 20px;border-bottom:1px solid var(--line)}.js .views{display:flex}
.views button,.sevf button{min-height:32px;padding:0 12px;border-radius:999px;border:1px solid #D5D6D1;background:#fff;font:inherit;font-size:13px;font-weight:600;cursor:pointer;color:var(--ink)}
.views button b,.sevf button b{font-weight:700;color:var(--mut);margin-left:2px}
.views button[aria-pressed=true],.sevf button[aria-pressed=true]{background:var(--ink);border-color:var(--ink);color:#fff}
.views button[aria-pressed=true] b,.sevf button[aria-pressed=true] b{color:#C4C6CA}
.scroll{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:#FAFAF8;text-align:left;padding:9px 12px;border-bottom:1px solid var(--line);font-size:12px;color:var(--mut);font-weight:700;white-space:nowrap}
td{padding:9px 12px;border-bottom:1px solid var(--soft);vertical-align:top}
th:first-child,td:first-child{padding-left:20px}th:last-child,td:last-child{padding-right:20px}
tbody tr:last-child td{border-bottom:0}
tbody tr:hover td{background:#FAFAF8}
td:first-child{font-weight:600}
.sort{border:0;background:none;font:inherit;color:inherit;padding:0;cursor:pointer}
th[aria-sort] .sort{color:var(--ink)}
th[aria-sort=ascending] .sort:after{content:" \2191"}th[aria-sort=descending] .sort:after{content:" \2193"}
tr.f,tr.pg{display:none}
.foot{display:none;padding:10px 20px;border-top:1px solid var(--line);justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;font-size:13px;color:var(--mut)}.js .foot{display:flex}
.pager{display:flex;gap:8px;align-items:center}.size{height:32px;border:1px solid #D5D6D1;border-radius:6px;font:inherit;background:#fff}
.tree td:not(:first-child),.tree th:not(:first-child){text-align:right;width:90px}
.tree td:first-child{font-weight:400}.tree tr.flag td{color:var(--warn);font-weight:600}.tree tr.flag a{color:var(--warn)}
.flash{outline:3px solid var(--accent);outline-offset:2px}
.pill{display:inline-block;font-size:12px;font-weight:700;padding:1px 9px;border-radius:999px;white-space:nowrap}
.pill.crit{background:var(--critbg);color:var(--crit)}.pill.warn{background:var(--warnbg);color:var(--warn)}.pill.info{background:var(--infobg);color:var(--info)}.pill.ok{background:var(--okbg);color:var(--ok)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:14px}
.tile{background:#fff;border:1px solid var(--line);border-radius:10px;padding:14px 16px;display:flex;flex-direction:column;gap:2px;text-decoration:none;color:var(--ink)}
a.tile:hover,a.bar:hover{border-color:var(--ink);color:var(--ink)}
.t-l{font-size:12px;font-weight:600;color:var(--mut);text-transform:uppercase;letter-spacing:.04em}
.t-n{font-size:28px;font-weight:700;line-height:1.15}
.t-s{font-size:12px;color:var(--mut)}
.tile.crit .t-l,.tile.crit .t-n{color:var(--crit)}.tile.warn .t-l,.tile.warn .t-n{color:var(--warn)}.tile.info .t-l,.tile.info .t-n{color:var(--info)}.tile.ok .t-l,.tile.ok .t-n{color:var(--ok)}
.bars{padding:14px 20px;display:flex;flex-direction:column;gap:4px}.bars .note{padding:8px 0 0}
.bar{display:grid;grid-template-columns:minmax(110px,38%) minmax(0,1fr) 48px;gap:12px;align-items:center;padding:5px 8px;margin:0 -8px;border:1px solid transparent;border-radius:6px;text-decoration:none;color:var(--ink);font-size:13px}
.b-t{height:14px;background:var(--soft);border-radius:3px;overflow:hidden}.b-t span{display:block;height:14px;background:var(--ink);border-radius:3px}
.b-n{text-align:right;font-weight:700}
.bar.warn .b-t span{background:#E0A33A}.bar.warn .b-l,.bar.warn .b-n{color:var(--warn);font-weight:600}
.bar.crit .b-t span{background:#C42B2F}.bar.crit .b-l,.bar.crit .b-n{color:var(--crit);font-weight:600}
.bar.ok .b-t span{background:#2E8B57}
.kv{margin:0;padding:6px 20px 10px}.kv>div{display:grid;grid-template-columns:minmax(120px,38%) minmax(0,1fr);gap:12px;padding:8px 0;border-bottom:1px solid var(--soft)}.kv>div:last-child{border-bottom:0}
.kv dt{color:var(--mut)}.kv dd{margin:0;overflow-wrap:anywhere}
.sevf{display:none;flex-wrap:wrap;gap:6px}.js .sevf{display:flex}
.finding{border-bottom:1px solid var(--soft)}.finding:last-of-type{border-bottom:0}.finding.h{display:none}
.finding summary{list-style:none;cursor:pointer;padding:12px 20px;display:grid;grid-template-columns:84px minmax(0,1fr) auto;gap:14px;align-items:center}
.finding summary::-webkit-details-marker{display:none}
.finding summary:hover{background:#FAFAF8}
.finding summary .pill{text-align:center}
.f-t{display:flex;flex-direction:column}.f-t b{font-weight:600}.f-t small{font-size:12px;color:var(--mut)}
.f-c{font-size:13px;font-weight:700;color:#33363B}
.f-b{padding:0 20px 16px 118px;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}
.f-b h4{font-size:12px;font-weight:700;color:var(--mut);text-transform:uppercase;letter-spacing:.05em;margin-bottom:4px}
.more{font-weight:600;font-size:13px;display:inline-block;margin-top:6px}
.dcc{padding:12px 20px;border-bottom:1px solid var(--soft);display:flex;flex-direction:column;gap:4px}.dcc:last-child{border-bottom:0}
.dcc div{display:flex;justify-content:space-between;align-items:center;gap:8px}.dcc small{color:var(--mut);font-size:12px}
.x-head{background:#fff;border-bottom:1px solid var(--line)}
.x-head>div{max-width:1120px;margin:0 auto;padding:18px 32px;display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:16px}
.x-head img{height:var(--logo);max-width:280px;object-fit:contain}
.x-head .for{display:flex;align-items:center;gap:12px;color:var(--mut);font-size:13px}
.x{max-width:1120px;margin:0 auto;padding:36px 32px 48px;display:flex;flex-direction:column;gap:28px;font-size:15px}
.x .eyebrow{font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--accent)}
.x h1{font-size:40px;line-height:1.1}
.x .facts{display:flex;flex-wrap:wrap;gap:6px 24px;color:var(--mut);font-size:14px}.x .facts b{color:var(--ink);font-weight:600}
.x .card{padding:0}.x .pad{padding:24px 28px}
.score{display:flex;flex-wrap:wrap;align-items:center;gap:28px}
.score .lbl{font-size:13px;font-weight:600;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}
.score .word{font-size:28px;font-weight:700}.score .word.ok{color:var(--ok)}.score .word.warn{color:var(--warn)}.score .word.crit{color:var(--crit)}
.sev4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:16px}
.sev4 div{border-radius:8px;padding:12px;display:flex;flex-direction:column}.sev4 b{font-size:28px;line-height:1.1}.sev4 span{font-size:13px;font-weight:600}
.sev4 .crit{background:var(--critbg);color:var(--crit)}.sev4 .warn{background:var(--warnbg);color:var(--warn)}.sev4 .info{background:var(--infobg);color:var(--info)}.sev4 .ok{background:var(--okbg);color:var(--ok)}
.risk{padding:18px 28px;border-bottom:1px solid var(--soft);display:grid;grid-template-columns:32px minmax(0,1fr) auto;gap:14px;align-items:start}.risk:last-child{border-bottom:0}
.risk .n{font-size:20px;font-weight:700;color:#8A8D93}.risk .t{font-weight:600;font-size:16px}.risk .w{color:var(--mut);font-size:14px}
.figs{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px 24px}.figs div{display:flex;flex-direction:column}.figs b{font-size:26px;line-height:1.15}.figs span{font-size:13px;color:var(--mut)}
.road{background:var(--ink);color:#fff;border-radius:12px;padding:28px;display:flex;flex-direction:column;gap:18px}
.road .cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px}
.road .col{background:#24272C;border-radius:10px;padding:16px 18px}
.road .col h3{display:flex;align-items:center;gap:8px;font-size:15px;margin-bottom:8px}.road .dot{width:10px;height:10px;border-radius:50%}
.road ul{margin:0;padding-left:18px;display:flex;flex-direction:column;gap:6px;font-size:14px;color:#E6E7E9}
.road .none{color:#C4C6CA;font-size:14px}
.x-foot{font-size:13px;color:var(--mut);border-top:1px solid var(--line);padding-top:16px}
details.gpo{border-bottom:1px solid var(--soft)}details.gpo summary{cursor:pointer;padding:10px 20px;font-weight:600}details.gpo summary small{font-weight:400;color:var(--mut)}
.gpof{width:100%;height:650px;border:0;border-top:1px solid var(--line);background:#fff}
@media(max-width:900px){.split{grid-template-columns:minmax(0,1fr)}.nav{max-width:none}.js .nav{position:static;height:auto}.page-h,.page-b{padding-left:16px;padding-right:16px}.f-b{padding-left:20px}.finding summary{grid-template-columns:84px minmax(0,1fr)}.f-c{display:none}.risk{grid-template-columns:24px minmax(0,1fr)}}
@media print{body{background:#fff}.nav,.tools,.views,.sevf,.pager,.btn{display:none!important}.app{display:block}.page-b,.x{padding:12px 0}.page-h{padding:8px 0}.card,.risk,.road .col{break-inside:avoid}.tbl{break-inside:auto}tr.pg{display:table-row}.road{background:#fff;color:var(--ink);border:1px solid var(--line)}.road .col{background:#fff;border:1px solid var(--line)}.road ul{color:var(--ink)}}
'@

$Js = @'
(function(){
var d=document;d.documentElement.classList.add('js');
function all(s,c){return Array.prototype.slice.call((c||d).querySelectorAll(s));}
var pages=all('.page');
function show(id,keep){
  var p=d.getElementById('p-'+id);if(!p){p=pages[0];id=p.id.slice(2);}
  pages.forEach(function(x){x.classList.toggle('active',x===p);});
  all('.nav a[data-page]').forEach(function(a){var on=a.getAttribute('data-page')===id;a.classList.toggle('on',on);if(on){a.setAttribute('aria-current','page');}else{a.removeAttribute('aria-current');}});
  if(!keep){window.scrollTo(0,0);}
}
function flash(el){el.classList.add('flash');setTimeout(function(){el.classList.remove('flash');},1400);}
function initTable(t){
  var body=t.querySelector('tbody');if(!body){return;}
  var rows=all('tr',body),plain=t.classList.contains('plain');
  var st={view:'all',q:'',col:-1,dir:1,page:0,size:plain?0:25,m:rows};
  rows.forEach(function(r){r._t=r.textContent.toLowerCase();r._v=' '+(r.getAttribute('data-v')||'')+' ';});
  var info=t.querySelector('.info'),prev=t.querySelector('.prev'),next=t.querySelector('.next');
  var num=/^-?[\d.,]+%?$/;
  function apply(){
    var m=rows.filter(function(r){return (st.view==='all'||r._v.indexOf(' '+st.view+' ')>=0)&&(!st.q||r._t.indexOf(st.q)>=0);});
    if(st.col>=0){
      m.sort(function(a,b){var x=a.cells[st.col].textContent.trim(),y=b.cells[st.col].textContent.trim();
        if(num.test(x)&&num.test(y)){return (parseFloat(x.replace(/,/g,''))-parseFloat(y.replace(/,/g,'')))*st.dir;}
        return x.localeCompare(y,undefined,{numeric:true,sensitivity:'base'})*st.dir;});
      m.forEach(function(r){body.appendChild(r);});
    }
    st.m=m;
    var n=st.size?Math.max(1,Math.ceil(m.length/st.size)):1;if(st.page>=n){st.page=n-1;}
    var from=st.size?st.page*st.size:0,to=st.size?Math.min(m.length,from+st.size):m.length;
    rows.forEach(function(r){r.className='f';});
    m.forEach(function(r,i){r.className=(i>=from&&i<to)?'':'pg';});
    if(info){info.textContent=m.length?('Showing '+(from+1)+' to '+to+' of '+m.length+(m.length<rows.length?' (filtered from '+rows.length+')':'')):'No rows match';}
    if(prev){prev.disabled=st.page<=0;}if(next){next.disabled=st.page>=n-1;}
    all('.views button',t).forEach(function(b){b.setAttribute('aria-pressed',b.getAttribute('data-view')===st.view?'true':'false');});
  }
  t._set=function(v){st.view=v||'all';st.page=0;var q=t.querySelector('.q');if(q){q.value='';}st.q='';apply();};
  all('.views button',t).forEach(function(b){b.addEventListener('click',function(){st.view=b.getAttribute('data-view');st.page=0;apply();});});
  var q=t.querySelector('.q');if(q){q.addEventListener('input',function(){st.q=q.value.toLowerCase().trim();st.page=0;apply();});}
  var size=t.querySelector('.size');if(size){size.addEventListener('change',function(){st.size=parseInt(size.value,10)||0;st.page=0;apply();});}
  if(prev){prev.addEventListener('click',function(){st.page--;apply();});}
  if(next){next.addEventListener('click',function(){st.page++;apply();});}
  all('thead th',t).forEach(function(th,i){var b=th.querySelector('.sort');if(!b){return;}
    b.addEventListener('click',function(){if(st.col===i){st.dir=-st.dir;}else{st.col=i;st.dir=1;}
      all('thead th',t).forEach(function(x){x.removeAttribute('aria-sort');});
      th.setAttribute('aria-sort',st.dir>0?'ascending':'descending');apply();});});
  var csv=t.querySelector('.csv');
  if(csv){csv.addEventListener('click',function(){
    var lines=[all('thead th',t).map(function(h){return h.textContent.trim();})];
    st.m.forEach(function(r){lines.push(all('td',r).map(function(c){return c.textContent.trim();}));});
    var txt=lines.map(function(l){return l.map(function(c){return '"'+c.replace(/"/g,'""')+'"';}).join(',');}).join('\r\n');
    var a=d.createElement('a');a.href=URL.createObjectURL(new Blob([String.fromCharCode(65279)+txt],{type:'text/csv'}));
    a.download=t.id+(st.view!=='all'?'-'+st.view:'')+'.csv';d.body.appendChild(a);a.click();d.body.removeChild(a);});}
  apply();
}
all('.tbl').forEach(initTable);
function sevFilter(s){
  all('.sevf button').forEach(function(b){b.setAttribute('aria-pressed',b.getAttribute('data-sev')===s?'true':'false');});
  all('.finding').forEach(function(f){f.classList.toggle('h',s!=='all'&&f.getAttribute('data-sev')!==s);});
}
function goTable(id,view){
  var t=d.getElementById(id);if(!t){return false;}
  var p=t.closest('.page');if(p){show(p.id.slice(2),true);}
  if(t._set&&view){t._set(view);}
  t.scrollIntoView({block:'start'});flash(t);return true;
}
d.addEventListener('click',function(e){
  var el=e.target.closest?e.target.closest('[data-tbl],[data-sev],[data-sevlink],[data-print],[data-expand]'):null;if(!el){return;}
  if(el.hasAttribute('data-tbl')){if(goTable(el.getAttribute('data-tbl'),el.getAttribute('data-view'))){e.preventDefault();}}
  else if(el.hasAttribute('data-sev')){sevFilter(el.getAttribute('data-sev'));}
  else if(el.hasAttribute('data-sevlink')){e.preventDefault();show('overview',true);sevFilter(el.getAttribute('data-sevlink'));var f=d.getElementById('findings');if(f){f.scrollIntoView({block:'start'});}}
  else if(el.hasAttribute('data-print')){window.print();}
  else if(el.hasAttribute('data-expand')){var open=el.getAttribute('data-expand')!=='1';el.setAttribute('data-expand',open?'1':'0');el.textContent=open?'Collapse all':'Expand all';all('.finding').forEach(function(x){x.open=open;});}
});
all('details.gpo').forEach(function(g){g.addEventListener('toggle',function(){
  if(g.open&&!g._l){g._l=1;var f=d.createElement('iframe');f.className='gpof';f.setAttribute('sandbox','allow-scripts');f.setAttribute('title','GPO settings report');f.srcdoc=g.getAttribute('data-doc');g.appendChild(f);}});});
function route(){
  var h=location.hash.replace('#','');
  if(h.indexOf('p-')===0){show(h.slice(2));}
  else if(h&&d.getElementById(h)){var p=d.getElementById(h).closest('.page');if(p){show(p.id.slice(2),true);d.getElementById(h).scrollIntoView();}}
  else{show(pages[0].id.slice(2));}
}
window.addEventListener('hashchange',route);route();sevFilter('all');
})();
'@

$safeAccent = if ($AccentColor -match '^#[0-9A-Fa-f]{3,8}$') { $AccentColor } else { '#C8102E' }

Out-H '<!DOCTYPE html>'
Out-H "<html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
Out-H "<title>$(Enc $ReportTitle)</title>"
Out-H "<style>:root{--accent:$safeAccent;--logo:${LogoHeight}px}"
Out-H $Css
Out-H '</style></head><body><div class="app">'

# Navigation
Out-H "<nav class='nav' aria-label='Report sections'><div class='stripe'></div><div class='brand'>"
Out-H "<div class='chip'><img src='$(Enc $leftLogoSrc)' alt='Company logo'></div>"
Out-H "<div><div class='client'>$(Enc $ClientName)</div><div class='dom mono'>$(Enc $Ctx.DomainDNS)</div></div></div><ul>"
foreach ($k in $Pages.Keys) {
    $badge = ''
    $mine  = @($Findings | Where-Object { $_.Page -eq $k -and $_.Severity -in 'Critical', 'Warning' })
    if ($mine.Count -and $k -notin 'summary', 'overview') {
        $tone  = if (@($mine | Where-Object Severity -eq 'Critical').Count) { 'crit' } else { 'warn' }
        $badge = "<span class='badge $tone' title='Critical and warning findings'>$($mine.Count)</span>"
    }
    Out-H "<li><a href='#p-$k' data-page='$k'>$(Enc $Pages[$k])$badge</a></li>"
}
Out-H "</ul><div class='meta'><span>Generated $(Get-Date -Format 'MMM d, yyyy HH:mm')</span><span>Queried $(Enc $DC)</span><span>Generate-ADReport.ps1 v$ScriptVersion</span></div></nav>"
Out-H "<div class='main'>"

# ---------------------------------------------------------------------------
# Page: Executive summary
# ---------------------------------------------------------------------------

$topRisks = @($Findings | Where-Object { $_.Severity -in 'Critical', 'Warning' } | Select-Object -First 5)
$dash     = [math]::Round(($HealthScore / 100) * 364.4, 1)
$ringCol  = @{ ok = '#0B6B3A'; warn = '#C77700'; crit = '#A4161A' }[$HealthTone]

Out-H "<section class='page' id='p-summary'><div class='stripe'></div><div class='x-head'><div><img src='$(Enc $leftLogoSrc)' alt='Company logo'>"
if ($rightLogoSrc) { Out-H "<div class='for'><span>Prepared for</span><img src='$(Enc $rightLogoSrc)' alt='Client logo'></div>" }
Out-H "</div></div><div class='x'>"
Out-H "<div class='stack' style='gap:10px'><div class='eyebrow'>Executive Summary &middot; Active Directory Health</div><h1>$(Enc $ClientName)</h1>"
Out-H "<div class='facts'><span>Domain: <b>$(Enc $Ctx.DomainDNS)</b></span><span>Assessed: <b>$ReportDate</b></span><span>Prepared by: <b>Nutmeg Technologies</b></span></div></div>"

$sumText = "This assessment reviewed the Active Directory domain $(Enc $Ctx.DomainDNS) and produced $($Findings.Count) findings: $nCrit critical, $nWarn warning, $nInfo advisory and $nOk passed."
if ($nCrit) { $sumText += ' The critical items carry the most risk and should be addressed first; the most important are listed below.' }
elseif ($nWarn) { $sumText += ' Nothing critical was found. The warning items below are worth planning for.' }
else { $sumText += ' No critical or warning items were found.' }

Out-H "<div class='grid2'><div class='card'><div class='pad score'>"
Out-H "<svg width='148' height='148' viewBox='0 0 148 148' role='img' aria-label='Health score $HealthScore out of 100'><circle cx='74' cy='74' r='58' fill='none' stroke='#EDEDE9' stroke-width='14'></circle><circle cx='74' cy='74' r='58' fill='none' stroke='$ringCol' stroke-width='14' stroke-linecap='round' stroke-dasharray='$dash 364.4' transform='rotate(-90 74 74)'></circle><text x='74' y='80' text-anchor='middle' font-size='40' font-weight='700' fill='#17191D'>$HealthScore</text><text x='74' y='102' text-anchor='middle' font-size='12' fill='#5B6068'>out of 100</text></svg>"
Out-H "<div class='stack' style='gap:6px;flex:1 1 160px'><span class='lbl'>Health score</span><span class='word $HealthTone'>$HealthLabel</span><span style='font-size:14px;color:var(--mut)'>Based on $($Findings.Count) findings, weighted by severity.</span></div></div></div>"
Out-H "<div class='card'><div class='pad'><div class='sev4'><div class='crit'><b>$nCrit</b><span>Critical</span></div><div class='warn'><b>$nWarn</b><span>Warning</span></div><div class='info'><b>$nInfo</b><span>Advisory</span></div><div class='ok'><b>$nOk</b><span>Passed</span></div></div><p>$sumText</p></div></div></div>"

Out-H "<div class='card'><div class='card-h' style='padding:20px 28px'><h2>Top risks</h2><span style='font-size:13px;color:var(--mut)'>Most severe first</span></div>"
if (-not $topRisks.Count) { Out-H "<p class='empty' style='padding:20px 28px'>No critical or warning items were found.</p>" }
$i = 0
foreach ($f in $topRisks) {
    $i++
    $why = if ($f.Why) { $f.Why } else { $f.Recommendation }
    Out-H "<div class='risk'><span class='n'>$i</span><div class='stack' style='gap:4px'><span class='t'>$(Enc $f.PlainTitle)</span><span class='w'>$(Enc $why)</span>$(Get-FindingLink $f)</div><span class='pill $($SevTone[$f.Severity])'>$($SevLabel[$f.Severity])</span></div>"
}
Out-H '</div>'

# How the environment is set up
$envPairs = [ordered]@{}
$envPairs['Domain'] = "<b>$(Enc $Ctx.DomainDNS)</b> &middot; forest $(Enc $ADForest.Name) ($(@($ADForest.Domains).Count) domain$(if (@($ADForest.Domains).Count -ne 1) { 's' }))"
$envPairs['Functional level'] = "Domain $(Enc (([string]$ADDomain.DomainMode) -replace '^Windows|Domain$', '')) &middot; Forest $(Enc (([string]$ADForest.ForestMode) -replace '^Windows|Forest$', ''))"
$dcBits = @(foreach ($d in @($R.DCObjects | Where-Object { $null -ne $_ })) {
    $flag = if ((Get-OSSupportStatus $d.OperatingSystem) -like 'Unsupported*') { " <span class='pill crit'>Unsupported OS</span>" } else { '' }
    "<a$(Get-JumpAttr 'tDCs')>$(Enc $d.Name)</a> ($(Enc (([string]$d.OperatingSystem) -replace '^Windows ', '')))$flag"
})
$envPairs['Domain controllers'] = if ($dcBits.Count) { $dcBits -join '<br>' } else { 'Not collected' }
$envPairs['Sites'] = "<a$(Get-JumpAttr 'tSites')>$((Get-Count $R.Sites)) site$(if ((Get-Count $R.Sites) -ne 1) { 's' }), $((Get-Count $R.Subnets)) subnet$(if ((Get-Count $R.Subnets) -ne 1) { 's' })</a> defined"
if ((Get-Count $R.Subnets) -eq 0 -or @($R.Sites | Where-Object { $_ -and $_.Subnets -eq 0 -and $_.DCs -gt 0 }).Count) { $envPairs['Sites'] += " <span class='pill warn'>Warning</span>" }
$duN = Get-ViewCount $UserRows 'default-container'
$dcN = Get-ViewCount $ComputerRows 'default-container'
$userOUs = @($R.OUs | Where-Object { $_ -and [int]$_.Users -gt 0 }).Count
$compOUs = @($R.OUs | Where-Object { $_ -and [int]$_.Computers -gt 0 }).Count
$envPairs['Where users live'] = "$userOUs OU$(if ($userOUs -ne 1) { 's' }) &middot; <a$(Get-JumpAttr 'tUsers' 'default-container')>$duN account$(if ($duN -ne 1) { 's' })</a> in the default Users container"
$envPairs['Where computers live'] = "$compOUs OU$(if ($compOUs -ne 1) { 's' }) &middot; <a$(Get-JumpAttr 'tComputers' 'default-container')>$dcN computer$(if ($dcN -ne 1) { 's' })</a> in the default Computers container"
$gpoUnlinked = Get-ViewCount $GPORows 'unlinked'
$envPairs['Group policies'] = "<a$(Get-JumpAttr 'tGPOs' 'all')>$($GPORows.Count) total</a> &middot; $($GPORows.Count - $gpoUnlinked) linked &middot; <a$(Get-JumpAttr 'tGPOs' 'unlinked')>$gpoUnlinked unused</a>"
if ($R.PwdPolicy) {
    $pp   = $R.PwdPolicy
    $age  = if ($pp.MaxPasswordAge.Days -gt 0) { "$($pp.MaxPasswordAge.Days)-day expiry" } else { 'passwords never expire' }
    $lock = if ($pp.LockoutThreshold -gt 0) { "<a$(Get-JumpAttr 'tPwdPolicy')>lockout after $($pp.LockoutThreshold) attempts</a>" } else { "<a$(Get-JumpAttr 'tPwdPolicy')>no lockout</a> <span class='pill warn'>Warning</span>" }
    $envPairs['Password policy'] = "$($pp.MinPasswordLength) characters minimum &middot; $age &middot; $lock"
}

Out-H "<div class='grid2'>"
Add-KeyValue -Title 'How the environment is set up' -Pairs $envPairs -Raw
Out-H "<div class='card'><div class='card-h'><h3>Environment at a glance</h3></div><div class='pad figs'>"
Out-H "<div><b>$(Get-ViewCount $UserRows 'enabled')</b><span>Active user accounts (of $($UserRows.Count))</span></div>"
Out-H "<div><b>$(Get-ViewCount $ComputerRows 'enabled')</b><span>Active computers (of $($ComputerRows.Count))</span></div>"
Out-H "<div><b>$((Get-Count $R.DCObjects))</b><span>Domain controllers</span></div>"
Out-H "<div><b>$((Get-Count $R.PrivUsers))</b><span>Accounts with administrative rights</span></div>"
Out-H "<div><b>$($GPORows.Count)</b><span>Group policies</span></div>"
Out-H "<div><b>$($GroupRows.Count)</b><span>Groups</span></div>"
Out-H '</div></div></div>'

# Roadmap
Out-H "<div class='road'><h2>Recommended roadmap</h2><div class='cols'>"
$buckets = @(
    @{ T = 'Now'; S = 'Critical'; C = 'var(--accent)' }
    @{ T = 'Next 30 days'; S = 'Warning'; C = '#E0A33A' }
    @{ T = 'This quarter'; S = 'Info'; C = '#8FB3E0' }
)
foreach ($b in $buckets) {
    $items = @($Findings | Where-Object { $_.Severity -eq $b.S -and $_.Recommendation })
    Out-H "<div class='col'><h3><span class='dot' style='background:$($b.C)'></span>$($b.T)</h3>"
    if (-not $items.Count) { Out-H "<p class='none'>Nothing in this group.</p>" }
    else {
        Out-H '<ul>'
        foreach ($it in ($items | Select-Object -First 5)) { Out-H "<li><b>$(Enc $it.PlainTitle)</b><br>$(Enc $it.Recommendation)</li>" }
        Out-H '</ul>'
        if ($items.Count -gt 5) { Out-H "<p class='none' style='margin-top:8px'>Plus $($items.Count - 5) more in the <a href='#p-overview' style='color:#fff'>technical findings</a>.</p>" }
    }
    Out-H '</div>'
}
Out-H '</div></div>'
Out-H "<div class='x-foot'>Prepared by Nutmeg Technologies &middot; nutmegtech.com &middot; Confidential, prepared for $(Enc $ClientName). The health score is an indicative measure based on the number and severity of findings.</div>"
Out-H '</div></section>'

# ---------------------------------------------------------------------------
# Page: Overview
# ---------------------------------------------------------------------------

Open-Page 'overview' 'Overview' "Active Directory health for $($Ctx.DomainDNS), snapshot taken $(Get-Date -Format 'MMM d, yyyy HH:mm')"
Add-Tiles @(
    @{ L = 'Health score'; N = "$HealthScore / 100"; S = $HealthLabel; Tone = $HealthTone }
    @{ L = 'Critical'; N = $nCrit; S = 'Fix first'; Tone = 'crit'; Sev = 'Critical' }
    @{ L = 'Warning'; N = $nWarn; S = 'Plan within 30 days'; Tone = 'warn'; Sev = 'Warning' }
    @{ L = 'Advisory'; N = $nInfo; S = 'Best practice'; Tone = 'info'; Sev = 'Info' }
    @{ L = 'Passed'; N = $nOk; S = 'No action needed'; Tone = 'ok'; Sev = 'OK' }
)
Out-H "<div class='split'>"
Out-H "<section class='card' id='findings'><div class='card-h'><h3>Findings <span class='cnt'>$($Findings.Count)</span></h3><div class='sevf' role='group' aria-label='Filter findings by severity'>"
Out-H "<button type='button' data-sev='all'>All <b>$($Findings.Count)</b></button><button type='button' data-sev='Critical'>Critical <b>$nCrit</b></button><button type='button' data-sev='Warning'>Warning <b>$nWarn</b></button><button type='button' data-sev='Info'>Advisory <b>$nInfo</b></button><button type='button' data-sev='OK'>Passed <b>$nOk</b></button><button type='button' class='btn' data-expand='0' style='min-height:32px;border-radius:999px'>Expand all</button></div></div>"
if (-not $Findings.Count) { Out-H "<p class='empty'>No findings were generated.</p>" }
foreach ($f in $Findings) {
    $cnt = if ("$($f.Count)" -ne '') { "<span class='f-c'>$(Enc $f.Count)</span>" } else { '' }
    Out-H "<details class='finding' data-sev='$($f.Severity)'><summary><span class='pill $($SevTone[$f.Severity])'>$($SevLabel[$f.Severity])</span><span class='f-t'><b>$(Enc $f.Finding)</b><small>$(Enc $f.Category)</small></span>$cnt</summary><div class='f-b'>"
    if ($f.Why) { Out-H "<div><h4>Why it matters</h4><p>$(Enc $f.Why)</p></div>" }
    if ($f.Recommendation) { Out-H "<div><h4>Recommended fix</h4><p>$(Enc $f.Recommendation)</p>$(Get-FindingLink $f)</div>" }
    else { Out-H "<div><p>No action needed.</p>$(Get-FindingLink $f 'View details')</div>" }
    Out-H '</div></details>'
}
Out-H '</section>'

Out-H "<div class='stack'>"
Out-H "<section class='card'><div class='card-h'><h3>Domain controllers <span class='cnt'>$((Get-Count $R.DCObjects))</span></h3></div>"
foreach ($d in @($R.DCObjects | Where-Object { $null -ne $_ })) {
    $h = @($R.DCHealth | Where-Object { $_.'Domain Controller' -eq $d.Name }) | Select-Object -First 1
    $issues = 0
    if ((Get-OSSupportStatus $d.OperatingSystem) -like 'Unsupported*') { $issues++ }
    if ($h) {
        if ($h.Reachable -eq 'No') { $issues++ }
        else {
            foreach ($svc in 'NTDS', 'DFSR', 'Netlogon', 'KDC', 'ADWS') { if ($h.$svc -notin 'Running', 'Not installed') { $issues++ } }
            if ($h.'SYSVOL Share' -eq 'No' -or $h.'NETLOGON Share' -eq 'No') { $issues++ }
            if ("$($h.'C: Free %')" -ne '' -and [int]$h.'C: Free %' -lt 15) { $issues++ }
        }
    }
    $issues += @($R.ReplRaw | Where-Object { $_.Server -eq $d.Name -and $_.'Consecutive Failures' -gt 0 }).Count
    $pill = if ($issues) { "<span class='pill crit'>$issues issue$(if ($issues -ne 1) { 's' })</span>" } else { "<span class='pill ok'>Healthy</span>" }
    $bits = @(([string]$d.OperatingSystem) -replace '^Windows ', '')
    if (@($d.OperationMasterRoles).Count) { $bits += "$(@($d.OperationMasterRoles).Count) FSMO role$(if (@($d.OperationMasterRoles).Count -ne 1) { 's' })" }
    if ($d.IsGlobalCatalog) { $bits += 'GC' }
    if ($h -and "$($h.'Uptime (days)')" -ne '') { $bits += "up $($h.'Uptime (days)') days" }
    if ($h -and "$($h.'C: Free %')" -ne '') { $bits += "C: $($h.'C: Free %')% free" }
    Out-H "<div class='dcc'><div><a$(Get-JumpAttr 'tDCHealth')><b>$(Enc $d.Name)</b></a>$pill</div><small>$(Enc ($bits -join ' | '))</small></div>"
}
if (-not (Get-Count $R.DCObjects)) { Out-H "<p class='empty'>Domain controller data was not collected.</p>" }
Out-H "<div class='dcc'><small>SYSVOL replication: $(Enc $R.SysvolState)</small></div></section>"
Add-OUTree -Title 'OU structure' -MaxDepth 2
Out-H '</div></div>'

$envRows = [ordered]@{}
if ($R.EnvironmentRaw) { foreach ($k in $R.EnvironmentRaw.Keys) { $envRows[$k] = [string]$R.EnvironmentRaw[$k] } }
$countRows = [ordered]@{
    'Users (enabled / total)'     = "$(Get-ViewCount $UserRows 'enabled') / $($UserRows.Count)"
    'Computers (enabled / total)' = "$(Get-ViewCount $ComputerRows 'enabled') / $($ComputerRows.Count)"
    'Groups'                      = $GroupRows.Count
    'Organizational Units'        = $OURows.Count
    'Group Policy Objects'        = $GPORows.Count
    'Domain Controllers'          = (Get-Count $R.DCObjects)
    'Sites'                       = (Get-Count $R.Sites)
}
$runRows = [ordered]@{
    'Script Version'    = $ScriptVersion
    'Run By'            = "$env:USERDOMAIN\$env:USERNAME"
    'Run From'          = $env:COMPUTERNAME
    'Queried DC'        = $DC
    'PowerShell'        = "$($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    'Thresholds (days)' = "Stale users $Days | New users $UserCreatedDays | Password expiry $DaysUntilPWExpireINT | Account expiry $AccountExpiringDays | Stale computers $StaleComputerDays | Modified objects $ADModNumber | Event logs $EventLogDays"
    'Run Time'          = "{0:N0} seconds" -f ((Get-Date) - $RunStart).TotalSeconds
}
Out-H "<div class='grid2'>"
Add-KeyValue -Title 'Domain and forest' -Pairs $envRows
Out-H "<div class='stack'>"
Add-KeyValue -Title 'Object counts' -Pairs $countRows
Add-KeyValue -Title 'Run details' -Pairs $runRows
Out-H '</div></div>'
Out-H "<div class='grid2'>"
Add-Table -Id 'tDomainAdmins' -Title 'Domain Admins' -Data $R.DomainAdmins -Empty 'No Domain Admin members were found' -Plain
Add-Table -Id 'tEnterpriseAdmins' -Title 'Enterprise Admins' -Data $R.EnterpriseAdmins -Empty 'No Enterprise Admin members were found' -Plain
Out-H '</div>'
Add-Table -Id 'tModified' -Title "AD objects modified in the last $ADModNumber days" -Data $R.Modified -Empty 'No AD objects have been modified recently' -Views @(
    @{ K = 'admin'; L = 'Directory and password changes' }, @{ K = 'routine'; L = 'Routine (system)' }, @{ K = 'has-actor'; L = 'Changed by a known account' }
) -Note 'Click an object name to see exactly what changed. Routine (system) means only automatic updates such as last logon time or a computer changing its own password.'
$whoNote = if ($SkipEventLogs) { 'Security logs were skipped (-SkipEventLogs), so Changed By is not available.' }
           elseif ($R.ModifiedEventsRead) { 'What changed and when comes from AD replication metadata. Changed By comes from the DC security logs, so it is only filled in where account-management or directory-service auditing was enabled and the log still covers that date.' }
           else { 'What changed and when comes from AD replication metadata. The DC security logs could not be read, so Changed By is not available.' }
Add-Table -Id 'tChangeDetail' -Title 'Change detail (what changed, when and by whom)' -Data $R.ModifiedDetail -Empty 'No change detail was found for the modified objects' -Views @(
    @{ K = 'change'; L = 'Directory and password changes' }, @{ K = 'routine'; L = 'Routine (system)' }, @{ K = 'event'; L = 'From security log' }, @{ K = 'meta'; L = 'From AD metadata' }
) -Note $whoNote
Add-Table -Id 'tErrors' -Title 'Collection errors' -Data $R.Errors -Empty 'No collection errors' -Plain -Note 'Sections or items the script could not read. Data in the affected area may be incomplete.'
Close-Page

# ---------------------------------------------------------------------------
# Page: DC health
# ---------------------------------------------------------------------------

Open-Page 'dc' 'DC health' 'Domain controllers, services and replication'
Add-Table -Id 'tDCs' -Title 'Domain controllers' -Data $R.DCs -Empty 'No domain controllers were found' -Plain
Add-Table -Id 'tDCHealth' -Title 'Services, shares and resources' -Data $R.DCHealth -Empty 'Unable to collect DC health' -Plain
Add-Table -Id 'tReplSummary' -Title 'Replication summary (per DC)' -Data $R.ReplSummary -Empty 'No replication metadata available' -Plain
Add-Table -Id 'tReplFail' -Title 'Replication failures' -Data $R.ReplFailures -Empty 'No replication failures were reported' -Plain
Add-Table -Id 'tReplDetail' -Title 'Replication detail (per partner and partition)' -Data $ReplRows -Empty 'No replication metadata available' -Views @(@{ K = 'failing'; L = 'Failing' }, @{ K = 'healthy'; L = 'Healthy' })
Close-Page

# ---------------------------------------------------------------------------
# Page: Sites and DNS
# ---------------------------------------------------------------------------

Open-Page 'sites' 'Sites and DNS' 'Sites, subnets, site links, DNS and trusts'
Out-H "<div class='grid2'>"
$SiteRows = @(foreach ($st in @($R.Sites | Where-Object { $null -ne $_ })) {
    $st | Select-Object * -ExcludeProperty _v | Add-Member -NotePropertyName '_v' -NotePropertyValue $(if ($st.Subnets -eq 0) { 'no-subnets' } else { 'has-subnets' }) -PassThru
})
Add-Table -Id 'tSites' -Title 'AD sites' -Data $SiteRows -Empty 'No sites found' -Views @(@{ K = 'no-subnets'; L = 'No subnets' }, @{ K = 'has-subnets'; L = 'Has subnets' })
Add-Table -Id 'tSiteLinks' -Title 'Site links' -Data $R.SiteLinks -Empty 'No site links found' -Plain
Out-H '</div>'
Add-Table -Id 'tSubnets' -Title 'AD subnets' -Data $R.Subnets -Empty 'No subnets are defined in Sites and Services. Every network with domain-joined devices should have a subnet assigned to the correct site.'
Add-Table -Id 'tDCSubnets' -Title 'Domain controller subnet check' -Data $R.DCSubnetCheck -Empty 'No domain controllers to check' -Plain -Note 'Each DC should sit in a subnet that belongs to its own site.'
if ($R.DNSSkipped) {
    Add-Table -Id 'tDNSZones' -Title 'DNS' -Data $null -Empty 'DNS data not collected: the DnsServer module is not available on the machine that ran the report (add the RSAT-DNS-Server feature).' -Plain
}
else {
    Add-Table -Id 'tDNSFwd' -Title 'DNS servers: forwarders and scavenging' -Data $R.DNSForwarders -Empty 'No DNS server data collected' -Plain
    Add-Table -Id 'tDNSZones' -Title 'DNS zones' -Data $R.DNSZones -Empty 'No DNS zones found'
}
Add-Table -Id 'tTrusts' -Title 'Domain and forest trusts' -Data $R.Trusts -Empty 'No trusts are defined' -Plain
Close-Page

# ---------------------------------------------------------------------------
# Page: Users
# ---------------------------------------------------------------------------

Open-Page 'users' 'Users' 'Click a tile, bar or view button to filter the user table'
Add-Tiles @(
    @{ L = 'Total accounts'; N = $UserRows.Count; S = "$(Get-ViewCount $UserRows 'enabled') enabled"; Tbl = 'tUsers'; View = 'all' }
    @{ L = "Inactive $Days+ days"; N = (Get-ViewCount $UserRows 'inactive'); S = 'Enabled, includes never signed in'; Tone = $(if (Get-ViewCount $UserRows 'inactive') { 'warn' }); Tbl = 'tUsers'; View = 'inactive' }
    @{ L = "Password expiring ($DaysUntilPWExpireINT days)"; N = (Get-ViewCount $UserRows 'pwd-expiring'); S = "$(Get-ViewCount $UserRows 'pwd-expired') already expired"; Tbl = 'tUsers'; View = 'pwd-expiring' }
    @{ L = 'Password never expires'; N = (Get-ViewCount $UserRows 'pwd-never'); S = 'Enabled accounts'; Tbl = 'tUsers'; View = 'pwd-never' }
    @{ L = 'Locked out now'; N = (Get-ViewCount $UserRows 'locked'); Tbl = 'tUsers'; View = 'locked' }
    @{ L = "New ($UserCreatedDays days)"; N = (Get-ViewCount $UserRows 'new'); Tbl = 'tUsers'; View = 'new' }
)
Out-H "<div class='grid2'>"
Add-Bars -Title 'Enabled accounts by last sign-in' -Note 'Uses LastLogonDate, which is accurate to about 14 days.' -Items @(
    @{ L = 'Under 30 days'; N = (Get-ViewCount $UserRows 'b-30'); Tbl = 'tUsers'; View = 'b-30' }
    @{ L = '30 to 90 days'; N = (Get-ViewCount $UserRows 'b-90'); Tbl = 'tUsers'; View = 'b-90' }
    @{ L = '90 to 365 days'; N = (Get-ViewCount $UserRows 'b-365'); Tbl = 'tUsers'; View = 'b-365' }
    @{ L = 'Over 365 days'; N = (Get-ViewCount $UserRows 'b-old'); Tone = 'warn'; Tbl = 'tUsers'; View = 'b-old' }
    @{ L = 'Never signed in'; N = (Get-ViewCount $UserRows 'b-never'); Tone = 'warn'; Tbl = 'tUsers'; View = 'b-never' }
)
Add-Bars -Title 'Account breakdown' -Items @(
    @{ L = 'Enabled'; N = (Get-ViewCount $UserRows 'enabled'); Tbl = 'tUsers'; View = 'enabled' }
    @{ L = 'Disabled'; N = (Get-ViewCount $UserRows 'disabled'); Tbl = 'tUsers'; View = 'disabled' }
    @{ L = 'Privileged'; N = (Get-ViewCount $UserRows 'privileged'); Tbl = 'tUsers'; View = 'privileged' }
    @{ L = 'Protected from deletion'; N = (Get-ViewCount $UserRows 'protected'); Tbl = 'tUsers'; View = 'protected' }
    @{ L = 'Not protected from deletion'; N = (Get-ViewCount $UserRows 'unprotected'); Tbl = 'tUsers'; View = 'unprotected' }
)
Out-H '</div>'
Add-Table -Id 'tUsers' -Title 'Active Directory users' -Data $UserRows -Empty 'No users were found' -Views @(
    @{ K = 'enabled'; L = 'Enabled' }, @{ K = 'disabled'; L = 'Disabled' }, @{ K = 'inactive'; L = "Inactive $Days+ days" },
    @{ K = 'pwd-expiring'; L = 'Password expiring' }, @{ K = 'pwd-expired'; L = 'Password expired' }, @{ K = 'pwd-never'; L = 'Password never expires' },
    @{ K = 'pwd-notreq'; L = 'Password not required' }, @{ K = 'acct-expiring'; L = 'Account expiring' }, @{ K = 'new'; L = "New ($UserCreatedDays days)" },
    @{ K = 'locked'; L = 'Locked out' }, @{ K = 'default-container'; L = 'Default container' }, @{ K = 'privileged'; L = 'Privileged' }
)
Add-Table -Id 'tUPN' -Title 'UPN suffixes' -Data $R.UPNSuffixes -Empty 'No UPN suffixes found' -Plain
Close-Page

# ---------------------------------------------------------------------------
# Page: Groups
# ---------------------------------------------------------------------------

Open-Page 'groups' 'Groups' 'Click a bar or view button to filter the group table'
Out-H "<div class='grid2'>"
Add-Bars -Title 'Group types' -Items @(
    @{ L = 'Security'; N = (Get-ViewCount $GroupRows 'type-security-group'); Tbl = 'tGroups'; View = 'type-security-group' }
    @{ L = 'Mail-enabled security'; N = (Get-ViewCount $GroupRows 'type-mail-enabled-security-group'); Tbl = 'tGroups'; View = 'type-mail-enabled-security-group' }
    @{ L = 'Distribution'; N = (Get-ViewCount $GroupRows 'type-distribution-group'); Tbl = 'tGroups'; View = 'type-distribution-group' }
)
Add-Bars -Title 'Group breakdown' -Items @(
    @{ L = 'Custom'; N = (Get-ViewCount $GroupRows 'custom'); Tbl = 'tGroups'; View = 'custom' }
    @{ L = 'Default (built-in)'; N = (Get-ViewCount $GroupRows 'default'); Tbl = 'tGroups'; View = 'default' }
    @{ L = 'With members'; N = (Get-ViewCount $GroupRows 'has-members'); Tbl = 'tGroups'; View = 'has-members' }
    @{ L = 'No members'; N = (Get-ViewCount $GroupRows 'empty'); Tbl = 'tGroups'; View = 'empty' }
    @{ L = 'Protected from deletion'; N = (Get-ViewCount $GroupRows 'protected'); Tbl = 'tGroups'; View = 'protected' }
    @{ L = 'Not protected from deletion'; N = (Get-ViewCount $GroupRows 'unprotected'); Tbl = 'tGroups'; View = 'unprotected' }
)
Out-H '</div>'
Add-Table -Id 'tGroups' -Title 'Active Directory groups' -Data $GroupRows -Empty 'No groups were found' -Views @(
    @{ K = 'type-security-group'; L = 'Security' }, @{ K = 'type-mail-enabled-security-group'; L = 'Mail-enabled security' }, @{ K = 'type-distribution-group'; L = 'Distribution' },
    @{ K = 'custom'; L = 'Custom' }, @{ K = 'default'; L = 'Default' }, @{ K = 'has-members'; L = 'With members' }, @{ K = 'empty'; L = 'No members' }, @{ K = 'unprotected'; L = 'Not protected' }
)
Close-Page

# ---------------------------------------------------------------------------
# Page: Privileged access
# ---------------------------------------------------------------------------

Open-Page 'priv' 'Privileged access' 'Recursive membership of the built-in privileged groups'
$privBars  = @(foreach ($g in @($R.PrivGroupCount | Where-Object { $null -ne $_ })) { @{ L = $g.Group; N = $g.Count; Tbl = 'tPriv'; View = "g-$(ConvertTo-Slug $g.Group)" } })
$privViews = @(foreach ($g in @($R.PrivGroupCount | Where-Object { $_ -and $_.Count -gt 0 })) { @{ K = "g-$(ConvertTo-Slug $g.Group)"; L = $g.Group } })
$privViews += @(@{ K = 'pwd-never'; L = 'Password never expires' }, @{ K = 'stale'; L = 'No logon in 90 days' }, @{ K = 'has-spn'; L = 'Has SPN' }, @{ K = 'not-protected'; L = 'Not in Protected Users' })
if ($privBars.Count) { Add-Bars -Title 'Privileged group size (members, including nested)' -Items $privBars }
Add-Table -Id 'tPriv' -Title 'Privileged group members' -Data $PrivRows -Empty 'No privileged group members were discovered' -Views $privViews
Out-H "<div class='grid2'>"
Add-Table -Id 'tKeyAccounts' -Title 'krbtgt and built-in Administrator' -Data $R.KeyAccounts -Empty 'Not found' -Plain
Add-Table -Id 'tOrphan' -Title 'Orphaned adminCount=1 accounts' -Data $R.OrphanAdminCount -Empty 'No orphaned adminCount accounts' -Plain
Out-H '</div>'
Close-Page

# ---------------------------------------------------------------------------
# Page: Security
# ---------------------------------------------------------------------------

Open-Page 'security' 'Security' 'Password policy, Kerberos exposure and authentication events'
$polPairs = [ordered]@{}
if ($R.PwdPolicyTable) { foreach ($p in $R.PwdPolicyTable.PSObject.Properties) { $polPairs[$p.Name] = $p.Value } }
Out-H "<div class='grid2'>"
if ($polPairs.Count) { Add-KeyValue -Title 'Default domain password policy' -Pairs $polPairs -Id 'tPwdPolicy' }
else { Add-Table -Id 'tPwdPolicy' -Title 'Default domain password policy' -Data $null -Empty 'Unable to read the default domain password policy' -Plain }
Add-Table -Id 'tFGPP' -Title 'Fine-grained password policies' -Data $R.FGPP -Empty 'No fine-grained password policies are defined' -Plain
Out-H '</div>'
Out-H "<div class='grid2'>"
Add-Table -Id 'tKerberoast' -Title 'Kerberoastable accounts (user accounts with SPNs)' -Data $R.Kerberoastable -Empty 'No enabled user accounts with SPNs' -Plain
Add-Table -Id 'tASREP' -Title 'AS-REP roastable (no pre-authentication)' -Data $R.ASREP -Empty 'No accounts without Kerberos pre-authentication' -Plain
Out-H '</div>'
$flagRows = @($R.PwdNotRequired | Where-Object { $null -ne $_ } | Select-Object *, @{ n = 'Flag'; e = { 'Password Not Required' } }) + @($R.Reversible | Where-Object { $null -ne $_ } | Select-Object *, @{ n = 'Flag'; e = { 'Reversible Encryption' } })
Out-H "<div class='grid2'>"
Add-Table -Id 'tDelegation' -Title 'Delegation (excluding DCs)' -Data $R.Delegation -Empty 'No unconstrained or protocol-transition delegation found' -Plain
Add-Table -Id 'tPwdFlags' -Title 'Password Not Required / Reversible Encryption' -Data $flagRows -Empty 'No accounts with these flags' -Plain
Out-H '</div>'
Add-Table -Id 'tDupSPN' -Title 'Duplicate SPNs' -Data $R.DuplicateSPNs -Empty 'No duplicate SPNs were detected'
if ($R.EventsSkipped) {
    Add-Table -Id 'tLockouts' -Title 'Authentication events' -Data $null -Empty 'Event log collection skipped (-SkipEventLogs)' -Plain
}
else {
    Add-Table -Id 'tLockouts' -Title "Account lockouts (event 4740, last $EventLogDays days, all DCs)" -Data $R.Lockouts -Empty 'No account lockouts found'
    Add-Table -Id 'tFailSummary' -Title "Failed authentication summary (4625 / 4771 / 4776, last $EventLogDays days)" -Data $R.FailureSummary -Empty 'No failed authentications found'
    Add-Table -Id 'tFailEvents' -Title 'Recent failed authentications (latest 500)' -Data $R.FailureEvents -Empty 'No failed authentications found'
}
Close-Page

# ---------------------------------------------------------------------------
# Page: Computers
# ---------------------------------------------------------------------------

Open-Page 'computers' 'Computers' 'Click a tile, bar or view button to filter the computer table'
$lapsText = if (-not $R.LapsSchema) { 'Not deployed' } elseif ($R.LapsScopeCount) { "$($R.LapsCovered) of $($R.LapsScopeCount)" } else { 'N/A' }
Add-Tiles @(
    @{ L = 'Total computers'; N = $ComputerRows.Count; S = "$(Get-ViewCount $ComputerRows 'enabled') enabled"; Tbl = 'tComputers'; View = 'all' }
    @{ L = 'Servers'; N = (Get-ViewCount $ComputerRows 'server'); S = "plus $(Get-ViewCount $ComputerRows 'dc') domain controllers"; Tbl = 'tComputers'; View = 'server' }
    @{ L = "Inactive $StaleComputerDays+ days"; N = (Get-ViewCount $ComputerRows 'stale'); Tone = $(if (Get-ViewCount $ComputerRows 'stale') { 'warn' }); Tbl = 'tComputers'; View = 'stale' }
    @{ L = 'Unsupported OS'; N = (Get-ViewCount $ComputerRows 'unsupported'); S = 'Enabled computers'; Tone = $(if (Get-ViewCount $ComputerRows 'unsupported') { 'crit' }); Tbl = 'tComputers'; View = 'unsupported' }
    @{ L = 'LAPS coverage'; N = $lapsText; S = 'Enabled Windows computers, excluding DCs'; Tbl = 'tComputers'; View = 'laps-missing' }
)
$osBars = @(foreach ($o in @($R.OSBreakdown | Where-Object { $null -ne $_ })) { @{ L = $o.Name; N = $o.Count; Tbl = 'tComputers'; View = "os-$(ConvertTo-Slug $o.Name)" } })
$supBars = @(foreach ($g in @($R.Computers | Where-Object { $null -ne $_ } | Group-Object Support | Sort-Object Count -Descending)) {
    $tone = if ($g.Name -like 'Unsupported*') { 'crit' } elseif ($g.Name -like 'Support ends*') { 'warn' } elseif ($g.Name -like 'Supported*') { 'ok' } else { $null }
    @{ L = $g.Name; N = $g.Count; Tone = $tone; Tbl = 'tComputers'; View = "sup-$(ConvertTo-Slug $g.Name)" }
})
Out-H "<div class='grid2'>"
if ($osBars.Count) { Add-Bars -Title 'Operating systems' -Items $osBars }
Out-H "<div class='stack'>"
if ($supBars.Count) { Add-Bars -Title 'Support status (all computer accounts)' -Items $supBars }
Add-Bars -Title 'Computer breakdown' -Items @(
    @{ L = 'Enabled'; N = (Get-ViewCount $ComputerRows 'enabled'); Tbl = 'tComputers'; View = 'enabled' }
    @{ L = 'Disabled'; N = (Get-ViewCount $ComputerRows 'disabled'); Tbl = 'tComputers'; View = 'disabled' }
    @{ L = 'Has LAPS password'; N = (Get-ViewCount $ComputerRows 'laps-ok'); Tone = 'ok'; Tbl = 'tComputers'; View = 'laps-ok' }
    @{ L = 'Missing LAPS password'; N = (Get-ViewCount $ComputerRows 'laps-missing'); Tone = 'warn'; Tbl = 'tComputers'; View = 'laps-missing' }
    @{ L = 'Protected from deletion'; N = (Get-ViewCount $ComputerRows 'protected'); Tbl = 'tComputers'; View = 'protected' }
    @{ L = 'Not protected from deletion'; N = (Get-ViewCount $ComputerRows 'unprotected'); Tbl = 'tComputers'; View = 'unprotected' }
)
Out-H '</div></div>'
Add-Table -Id 'tComputers' -Title 'Computers' -Data $ComputerRows -Empty 'No computers were found' -Views @(
    @{ K = 'enabled'; L = 'Enabled' }, @{ K = 'disabled'; L = 'Disabled' }, @{ K = 'workstation'; L = 'Workstations' }, @{ K = 'server'; L = 'Servers' }, @{ K = 'dc'; L = 'Domain controllers' },
    @{ K = 'stale'; L = "Inactive $StaleComputerDays+ days" }, @{ K = 'unsupported'; L = 'Unsupported OS' }, @{ K = 'eol-soon'; L = 'Support ending' },
    @{ K = 'laps-missing'; L = 'Missing LAPS' }, @{ K = 'default-container'; L = 'Default container' }
)
Close-Page

# ---------------------------------------------------------------------------
# Page: Organizational units
# ---------------------------------------------------------------------------

Open-Page 'ous' 'Organizational units' 'OU structure, linked GPOs and protection'
Add-OUTree -Title 'OU structure (full)'
Add-Table -Id 'tOUs' -Title 'Organizational units' -Data $OURows -Empty 'No OUs were found' -Views @(
    @{ K = 'has-links'; L = 'GPOs linked' }, @{ K = 'no-links'; L = 'No GPOs linked' }, @{ K = 'block'; L = 'Block inheritance' },
    @{ K = 'unprotected'; L = 'Not protected' }, @{ K = 'no-objects'; L = 'No users or computers' }
)
Close-Page

# ---------------------------------------------------------------------------
# Page: Group Policy
# ---------------------------------------------------------------------------

Open-Page 'gpo' 'Group Policy' 'GPOs, where they are linked and who can change them'
Add-Tiles @(
    @{ L = 'GPOs'; N = $GPORows.Count; Tbl = 'tGPOs'; View = 'all' }
    @{ L = 'Not linked'; N = (Get-ViewCount $GPORows 'unlinked'); Tbl = 'tGPOs'; View = 'unlinked' }
    @{ L = 'No settings'; N = (Get-ViewCount $GPORows 'empty'); Tbl = 'tGPOs'; View = 'empty' }
    @{ L = 'SYSVOL issues'; N = (Get-ViewCount $GPORows 'sysvol-issue'); Tone = $(if (Get-ViewCount $GPORows 'sysvol-issue') { 'warn' }); Tbl = 'tGPOs'; View = 'sysvol-issue' }
    @{ L = 'Links'; N = $LinkRows.Count; S = "$(Get-ViewCount $LinkRows 'enforced') enforced"; Tbl = 'tGPLinks'; View = 'all' }
)
Add-Table -Id 'tGPOs' -Title 'Group Policy Objects' -Data $GPORows -Empty 'No Group Policy Objects were found' -Views @(
    @{ K = 'linked'; L = 'Linked' }, @{ K = 'unlinked'; L = 'Not linked' }, @{ K = 'empty'; L = 'No settings' }, @{ K = 'partly-disabled'; L = 'Settings disabled' },
    @{ K = 'sysvol-issue'; L = 'SYSVOL issues' }, @{ K = 'no-read'; L = 'Unreadable by computers' }, @{ K = 'wmi'; L = 'WMI filtered' }
)
Add-Table -Id 'tGPLinks' -Title 'GPO links (domain, OUs and sites)' -Data $LinkRows -Empty 'No GPO links were found' -Views @(
    @{ K = 't-domain'; L = 'Domain' }, @{ K = 't-ou'; L = 'OUs' }, @{ K = 't-site'; L = 'Sites' }, @{ K = 'enforced'; L = 'Enforced' }, @{ K = 'link-disabled'; L = 'Link disabled' }
)
if ($GPModule) { Add-Table -Id 'tGPOPerms' -Title 'GPO permissions' -Data $R.GPOPerms -Empty 'No GPO permissions collected' -Note 'Use the filter box to search by GPO name or trustee.' }
else { Add-Table -Id 'tGPOPerms' -Title 'GPO permissions' -Data $null -Empty 'GroupPolicy module not available: permissions were not collected' -Plain }
Close-Page

# ---------------------------------------------------------------------------
# Page: GPO settings (each report loads into an isolated frame when opened)
# ---------------------------------------------------------------------------

if ($IncludeGpoSettings) {
    Open-Page 'gposet' 'GPO settings' 'Full settings report for each GPO. Click a GPO to load its report.'
    Out-H "<section class='card'><div class='card-h'><h3>GPO settings reports <span class='cnt'>$((Get-Count $R.GPOReports))</span></h3></div><noscript><p class='empty'>These reports need JavaScript. Open this file directly in a browser to view them.</p></noscript>"
    foreach ($rep in ($R.GPOReports | Sort-Object Name)) {
        Out-H "<details class='gpo' data-doc=`"$(Enc $rep.Html)`"><summary>$(Enc $rep.Name) <small class='mono'>{$($rep.Guid)}</small></summary></details>"
    }
    Out-H '</section>'
    Close-Page
}

Out-H '</div></div><script>'
Out-H $Js
Out-H '</script></body></html>'

# ---------------------------------------------------------------------------
# Main Logic - Save
# ---------------------------------------------------------------------------

$safeName   = (Get-SafeFolderName $ClientName) -replace '\s+', '-'
$ReportFile = Join-Path $SavePath "$safeName-ADReport-$RunStamp.html"
$utf8Bom    = New-Object System.Text.UTF8Encoding($true)
try {
    [System.IO.File]::WriteAllText($ReportFile, $script:sb.ToString(), $utf8Bom)
}
catch {
    Write-Log "Failed to write report: $($_.Exception.Message)" 'ERROR'
    return
}

# Findings as JSON (for importing into other tools, e.g. an alignment review)
$JsonFile = $null
if (-not $NoFindingsJson) {
    $JsonFile = Join-Path $SavePath "$safeName-ADReport-$RunStamp-findings.json"
    try {
        $export = [ordered]@{
            schema        = 'adreport.findings/1'
            generated     = $RunStart.ToString('s')
            scriptVersion = $ScriptVersion
            client        = $ClientName
            domain        = $Ctx.DomainDNS
            forest        = [string]$ADForest.Name
            healthScore   = $HealthScore
            healthLabel   = $HealthLabel
            counts        = [ordered]@{ critical = $nCrit; warning = $nWarn; advisory = $nInfo; passed = $nOk }
            findings      = @($Findings | ForEach-Object {
                [ordered]@{
                    severity       = [string]$_.Severity
                    category       = [string]$_.Category
                    finding        = [string]$_.Finding
                    count          = [string]$_.Count
                    recommendation = [string]$_.Recommendation
                    plainTitle     = [string]$_.PlainTitle
                    whyItMatters   = [string]$_.Why
                }
            })
        }
        # No byte-order mark: strict JSON parsers (Python, browsers, most web apps) reject it
        [System.IO.File]::WriteAllText($JsonFile, ($export | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    }
    catch {
        Write-Log "Failed to write findings JSON: $($_.Exception.Message)" 'WARN'
        $JsonFile = $null
    }
}
Write-Progress -Activity "Active Directory Report v$ScriptVersion" -Completed

Write-Host "=============================================" -ForegroundColor Cyan
Write-Log ("Findings: {0} Critical, {1} Warning, {2} Advisory, {3} Passed | Health score {4}/100 ({5})" -f $nCrit, $nWarn, $nInfo, $nOk, $HealthScore, $HealthLabel) $(if ($nCrit -or $nWarn) { 'WARN' } else { 'SUCCESS' })
if ($R.Errors.Count) { Write-Log "$($R.Errors.Count) collection error(s) - see the Collection errors table on the Overview page and the log file." 'WARN' }
Write-Log "Report:   $ReportFile" 'SUCCESS'
if ($JsonFile) { Write-Log "Findings: $JsonFile" 'DETAIL' }
Write-Log "Log:      $script:LogFile" 'DETAIL'
Write-Log ("Completed in {0:N0} seconds." -f ((Get-Date) - $RunStart).TotalSeconds) 'SUCCESS'
Write-Host "=============================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Main Logic - Open the report or its folder
# ---------------------------------------------------------------------------

function Open-ReportFolder {
    # Opens the output folder with the report selected (Windows); falls back to opening the folder
    try { Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$ReportFile`"" -ErrorAction Stop }
    catch { try { Invoke-Item -LiteralPath $SavePath } catch { Write-Log "Could not open $SavePath : $($_.Exception.Message)" 'WARN' } }
}

if ($OpenReport) {
    Invoke-Item -LiteralPath $ReportFile
}
elseif ($script:CanPrompt) {
    Write-Host ""
    Write-Host "   [R] Open the report" -ForegroundColor Yellow
    Write-Host "   [F] Open the folder containing the files" -ForegroundColor Yellow
    Write-Host "   [B] Both" -ForegroundColor Yellow
    Write-Host "   [Q] Quit" -ForegroundColor Red
    $choice = $null
    try { $choice = Read-Host "Select an option (Press Enter for Default: R)" } catch { $choice = 'Q' }
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = 'R' }
    switch -Regex ($choice.Trim()) {
        '^[Rr]' { Invoke-Item -LiteralPath $ReportFile }
        '^[Ff]' { Open-ReportFolder }
        '^[Bb]' { Invoke-Item -LiteralPath $ReportFile; Open-ReportFolder }
        default { }
    }
}