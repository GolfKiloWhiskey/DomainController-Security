# ---------------------------------------------------------------------------
# GpoFiles.ps1 - a GPO's files in SYSVOL, read and written without GroupPolicy cmdlets
# ---------------------------------------------------------------------------
# Administrative Templates and registry preferences are written with the GroupPolicy cmdlets
# (Set-GPRegistryValue, Set-GPPrefRegistryValue). The security template (GptTmpl.inf) and the
# advanced audit policy (audit.csv) have no cmdlet, so they are written here, the way GPMC
# writes them, and the GPO's extension list and version are updated so clients apply them.
#
# Reading is all file-based, so gpo-compare sees exactly what clients see: Registry.pol (binary
# PReg), Preferences\Registry\Registry.xml, GptTmpl.inf and audit.csv. Every path goes through
# Get-NmGpoFolder, so the tests point it at a temp folder.

# Client-side extensions: [CSE GUID][tool GUID].
$script:NmCseSecurity = @('{827D319E-6EAC-11D2-A4EA-00C04F79F83A}', '{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}')
$script:NmCseAudit    = @('{F3CCC681-B74C-4060-9F26-CD84525DCA2A}', '{0F3F3735-573D-9804-99E4-AB2A69BA5FD4}')

# GptTmpl.inf sections in the order GPMC writes them.
$script:NmInfSectionOrder = @('Unicode', 'System Access', 'Event Audit', 'Kerberos Policy', 'Registry Values', 'Privilege Rights', 'Service General Setting', 'Group Membership', 'Version')
# Services: the permissions GPMC offers by default (Administrators and SYSTEM full control,
# interactive users read), and failed access audited for Everyone. Never a client's own groups.
$script:NmDefaultServiceSddl = 'D:AR(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCLCSWLOCRRC;;;IU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)'
$script:NmStartModeCodes = @{ Automatic = 2; Manual = 3; Disabled = 4 }
$script:NmSecTypeCodes   = @{ String = 1; DWord = 4; MultiString = 7 }
$script:NmRegTypeNames   = @{ 1 = 'String'; 2 = 'ExpandString'; 3 = 'Binary'; 4 = 'DWord'; 7 = 'MultiString'; 11 = 'QWord' }
$script:NmPrefTypeNames  = @{ 'REG_SZ' = 'String'; 'REG_EXPAND_SZ' = 'ExpandString'; 'REG_DWORD' = 'DWord'; 'REG_QWORD' = 'QWord'; 'REG_MULTI_SZ' = 'MultiString'; 'REG_BINARY' = 'Binary' }
$script:NmPrefActionNames = @{ C = 'Create'; R = 'Replace'; U = 'Update'; D = 'Delete' }

# Well-known accounts, so user rights and restricted groups are written as SIDs.
$script:NmWellKnownSids = @{
    'Everyone' = 'S-1-1-0'; 'Authenticated Users' = 'S-1-5-11'; 'SYSTEM' = 'S-1-5-18'; 'Local Service' = 'S-1-5-19'
    'Network Service' = 'S-1-5-20'; 'Interactive' = 'S-1-5-4'; 'Network' = 'S-1-5-2'; 'Service' = 'S-1-5-6'
    'Enterprise Domain Controllers' = 'S-1-5-9'; 'Local account' = 'S-1-5-113'
    'Local account and member of Administrators group' = 'S-1-5-114'
    'Administrators' = 'S-1-5-32-544'; 'Users' = 'S-1-5-32-545'; 'Guests' = 'S-1-5-32-546'; 'Power Users' = 'S-1-5-32-547'
    'Account Operators' = 'S-1-5-32-548'; 'Server Operators' = 'S-1-5-32-549'; 'Print Operators' = 'S-1-5-32-550'
    'Backup Operators' = 'S-1-5-32-551'; 'Pre-Windows 2000 Compatible Access' = 'S-1-5-32-554'
    'Remote Desktop Users' = 'S-1-5-32-555'; 'Performance Log Users' = 'S-1-5-32-559'; 'Remote Management Users' = 'S-1-5-32-580'
    'Window Manager Group' = 'S-1-5-90-0'
    'WdiServiceHost' = 'S-1-5-80-3139157870-2983391045-3678747466-658725712-1809340420'
    'PrintSpoolerService' = 'S-1-5-99-216390572-1995538116-3857911515-2404958512-2623887229'
}
# Domain groups, as RIDs on the domain's SID.
$script:NmDomainRids = @{
    'Domain Admins' = 512; 'Domain Users' = 513; 'Domain Guests' = 514; 'Domain Computers' = 515; 'Domain Controllers' = 516
    'Schema Admins' = 518; 'Enterprise Admins' = 519; 'Group Policy Creator Owners' = 520; 'Read-only Domain Controllers' = 521
    'Protected Users' = 525
}

# ---------------------------------------------------------------------------
# Where a GPO's files are
# ---------------------------------------------------------------------------
function Get-NmGpoFolder {
    <#
    .SYNOPSIS
        The GPO's folder in SYSVOL on the session's DC: \\<DC>\SYSVOL\<domain>\Policies\{<GUID>}.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Id)
    $s = Get-NmSession
    $guid = "{$("$Id".Trim('{', '}').ToUpper())}"
    $server = if ($s.Server) { $s.Server } else { $s.Domain }
    return "\\$server\SYSVOL\$($s.Domain)\Policies\$guid"
}

function Get-NmGpoFilePath {
    # A file under the GPO's folder: Machine\Registry.pol, User\Registry.pol, the security template, ...
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('MachinePol', 'UserPol', 'MachinePrefRegistry', 'UserPrefRegistry', 'GptTmpl', 'Audit', 'GptIni')][string]$File
    )
    $rel = switch ($File) {
        'MachinePol'          { 'Machine\Registry.pol' }
        'UserPol'             { 'User\Registry.pol' }
        'MachinePrefRegistry' { 'Machine\Preferences\Registry\Registry.xml' }
        'UserPrefRegistry'    { 'User\Preferences\Registry\Registry.xml' }
        'GptTmpl'             { 'Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf' }
        'Audit'               { 'Machine\Microsoft\Windows NT\Audit\audit.csv' }
        'GptIni'              { 'GPT.INI' }
    }
    $path = Get-NmGpoFolder -Id $Id
    foreach ($part in ($rel -split '\\')) { $path = Join-Path $path $part }
    return $path
}

function Write-NmGpoText {
    # Writes a text file, creating its folder. Unicode = UTF-16 LE with a BOM (GptTmpl.inf).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Text, [ValidateSet('Unicode', 'Ascii')][string]$Encoding = 'Ascii')
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    $enc = if ($Encoding -eq 'Unicode') { New-Object System.Text.UnicodeEncoding($false, $true) } else { New-Object System.Text.ASCIIEncoding }
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Read-NmGpoText {
    # A text file's content ('' when it does not exist); the BOM decides the encoding.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return [System.IO.File]::ReadAllText($Path)
}

# ---------------------------------------------------------------------------
# Registry.pol (Administrative Templates): read only, the cmdlets write it
# ---------------------------------------------------------------------------
function ConvertFrom-NmRegistryPol {
    <#
    .SYNOPSIS
        Parses Registry.pol bytes: "PReg", version 1, then [key;value;type;size;data] entries in UTF-16 LE.
        Returns Key, ValueName, Type (String, DWord, ...), Value (text: DWord in decimal, MultiString joined with ',').
    #>
    [CmdletBinding()]
    param([byte[]]$Bytes)
    $out = New-Object System.Collections.Generic.List[object]
    if (-not $Bytes -or $Bytes.Length -lt 8) { return @() }
    if ([System.Text.Encoding]::ASCII.GetString($Bytes, 0, 4) -ne 'PReg') { throw 'Not a Registry.pol file (no PReg header).' }
    $u = [System.Text.Encoding]::Unicode
    $i = 8
    $readTo = {
        # UTF-16 text up to the next ';' (skipping the terminating NUL), and the index after the ';'.
        param([int]$start)
        $j = $start
        while ($j + 1 -lt $Bytes.Length -and -not ($Bytes[$j] -eq 0x3B -and $Bytes[$j + 1] -eq 0)) { $j += 2 }
        $t = $u.GetString($Bytes, $start, $j - $start).TrimEnd([char]0)
        return @($t, ($j + 2))
    }
    while ($i + 1 -lt $Bytes.Length) {
        if (-not ($Bytes[$i] -eq 0x5B -and $Bytes[$i + 1] -eq 0)) { throw "Registry.pol is damaged at byte $i." }
        $i += 2
        $r = & $readTo $i; $key = $r[0]; $i = $r[1]
        $r = & $readTo $i; $name = $r[0]; $i = $r[1]
        $type = [BitConverter]::ToInt32($Bytes, $i); $i += 6
        $size = [BitConverter]::ToInt32($Bytes, $i); $i += 6
        $data = New-Object byte[] $size
        if ($size -gt 0) { [Array]::Copy($Bytes, $i, $data, 0, $size) }
        $i += $size
        if (-not ($Bytes[$i] -eq 0x5D -and $Bytes[$i + 1] -eq 0)) { throw "Registry.pol is damaged at byte $i." }
        $i += 2
        $typeName = if ($script:NmRegTypeNames.ContainsKey($type)) { $script:NmRegTypeNames[$type] } else { "Type$type" }
        $value = switch ($typeName) {
            'DWord'        { if ($size -ge 4) { "$([BitConverter]::ToUInt32($data, 0))" } else { '' } }
            'QWord'        { if ($size -ge 8) { "$([BitConverter]::ToUInt64($data, 0))" } else { '' } }
            'MultiString'  { (@($u.GetString($data).Split([char]0) | Where-Object { $_ -ne '' })) -join ',' }
            'Binary'       { ($data | ForEach-Object { $_.ToString('x2') }) -join '' }
            default        { $u.GetString($data).TrimEnd([char]0) }
        }
        $out.Add([pscustomobject]@{ Key = $key; ValueName = $name; Type = $typeName; Value = $value })
    }
    return $out.ToArray()
}

function ConvertTo-NmRegistryPol {
    # The reverse, for tests and fixtures: entries (Key, ValueName, Type, Value) as Registry.pol bytes.
    [CmdletBinding()]
    param([object[]]$Entries = @())
    $u = [System.Text.Encoding]::Unicode
    $ms = New-Object System.IO.MemoryStream
    $w = { param([byte[]]$b) $ms.Write($b, 0, $b.Length) }
    & $w ([System.Text.Encoding]::ASCII.GetBytes('PReg'))
    & $w ([BitConverter]::GetBytes([int]1))
    $codes = @{ String = 1; ExpandString = 2; DWord = 4; MultiString = 7; QWord = 11 }
    foreach ($e in $Entries) {
        $data = switch ("$($e.Type)") {
            'DWord'       { [BitConverter]::GetBytes([uint32][int64]"$($e.Value)") }
            'QWord'       { [BitConverter]::GetBytes([uint64]"$($e.Value)") }
            'MultiString' { $u.GetBytes(((@($e.Value) -join "`0") + "`0`0")) }
            default       { $u.GetBytes("$($e.Value)`0") }
        }
        & $w ($u.GetBytes('['))
        & $w ($u.GetBytes("$($e.Key)`0;"))
        & $w ($u.GetBytes("$($e.ValueName)`0;"))
        & $w ([BitConverter]::GetBytes([int]$codes["$($e.Type)"])); & $w ($u.GetBytes(';'))
        & $w ([BitConverter]::GetBytes([int]$data.Length)); & $w ($u.GetBytes(';'))
        & $w $data
        & $w ($u.GetBytes(']'))
    }
    return , $ms.ToArray()
}

function Read-NmGpoRegistryPol {
    # A GPO's Registry.pol for one side (Computer or User), parsed; none when there is no file.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [ValidateSet('Computer', 'User')][string]$Side = 'Computer')
    $path = Get-NmGpoFilePath -Id $Id -File $(if ($Side -eq 'User') { 'UserPol' } else { 'MachinePol' })
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(ConvertFrom-NmRegistryPol -Bytes ([System.IO.File]::ReadAllBytes($path)))
}

# ---------------------------------------------------------------------------
# Registry preferences (Registry.xml): read only, the cmdlet writes it
# ---------------------------------------------------------------------------
function ConvertFrom-NmPrefRegistryXml {
    # Registry items in a Registry.xml: Hive, Key, ValueName, Type, Value (DWord in decimal), Action.
    [CmdletBinding()]
    param([string]$Xml)
    if (-not "$Xml".Trim()) { return @() }
    $doc = New-Object System.Xml.XmlDocument
    $doc.LoadXml($Xml)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($doc.SelectNodes('//Registry/Properties'))) {
        $type = "$($p.GetAttribute('type'))"
        $typeName = if ($script:NmPrefTypeNames.ContainsKey($type)) { $script:NmPrefTypeNames[$type] } else { $type }
        $raw = "$($p.GetAttribute('value'))"
        $value = $raw
        if ($typeName -eq 'DWord' -and $raw -match '^[0-9A-Fa-f]{1,8}$') { $value = "$([Convert]::ToUInt32($raw, 16))" }
        if ($typeName -eq 'QWord' -and $raw -match '^[0-9A-Fa-f]{1,16}$') { $value = "$([Convert]::ToUInt64($raw, 16))" }
        $hive = switch ("$($p.GetAttribute('hive'))") { 'HKEY_LOCAL_MACHINE' { 'HKLM' } 'HKEY_CURRENT_USER' { 'HKCU' } default { "$_" } }
        $act = "$($p.GetAttribute('action'))"
        $out.Add([pscustomobject]@{
            Hive = $hive; Key = "$($p.GetAttribute('key'))"; ValueName = "$($p.GetAttribute('name'))"; Type = $typeName; Value = $value
            Action = $(if ($script:NmPrefActionNames.ContainsKey($act)) { $script:NmPrefActionNames[$act] } else { $act })
        })
    }
    return $out.ToArray()
}

function Read-NmGpoPrefRegistry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [ValidateSet('Computer', 'User')][string]$Side = 'Computer')
    $path = Get-NmGpoFilePath -Id $Id -File $(if ($Side -eq 'User') { 'UserPrefRegistry' } else { 'MachinePrefRegistry' })
    return @(ConvertFrom-NmPrefRegistryXml -Xml (Read-NmGpoText -Path $path))
}

# ---------------------------------------------------------------------------
# GptTmpl.inf (security template)
# ---------------------------------------------------------------------------
function Get-NmInfLineKey {
    # The key a line is merged by: the text before '=', or a service's quoted name.
    param([string]$Line)
    if ($Line -match '^\s*"([^"]+)"\s*,') { return $Matches[1].ToLower() }
    if ($Line -match '^\s*([^=]+?)\s*=') { return $Matches[1].ToLower() }
    return $Line.Trim().ToLower()
}

function ConvertFrom-NmInf {
    <#
    .SYNOPSIS
        An .inf file's text as an ordered dictionary: section name -> ordered dictionary of key -> line.
    #>
    [CmdletBinding()]
    param([string]$Text)
    $doc = [ordered]@{}
    $section = $null
    foreach ($raw in ("$Text" -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if (-not $line.Trim() -or $line.TrimStart().StartsWith(';')) { continue }
        if ($line -match '^\s*\[(.+)\]\s*$') {
            $section = $Matches[1]
            if (-not $doc.Contains($section)) { $doc[$section] = [ordered]@{} }
            continue
        }
        if ($null -eq $section) { continue }
        $doc[$section][(Get-NmInfLineKey -Line $line)] = $line.Trim()
    }
    return $doc
}

function ConvertTo-NmInf {
    # The reverse: sections in GPMC's order (others after), CRLF line ends.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Doc)
    $sb = New-Object System.Text.StringBuilder
    $names = @($script:NmInfSectionOrder | Where-Object { $Doc.Contains($_) }) + @($Doc.Keys | Where-Object { $script:NmInfSectionOrder -notcontains $_ })
    foreach ($n in $names) {
        [void]$sb.Append("[$n]`r`n")
        foreach ($k in @($Doc[$n].Keys)) { [void]$sb.Append("$($Doc[$n][$k])`r`n") }
    }
    return $sb.ToString()
}

function Format-NmInfString {
    # A string for GptTmpl.inf: in double quotes (a quote inside is doubled).
    param([string]$Text)
    return '"' + "$Text".Replace('"', '""') + '"'
}

function ConvertTo-NmGptTmplLine {
    <#
    .SYNOPSIS
        One expanded setting of a security-template kind as Section and Line (what GptTmpl.inf holds).
        Members (user rights, restricted groups) must already be SIDs or names (Resolve-NmAccountSid).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Setting)
    $s = $Setting
    switch ("$($s.Kind)") {
        'SecurityOption' {
            $code = $script:NmSecTypeCodes["$($s.Type)"]
            $data = switch ("$($s.Type)") {
                'String'      { Format-NmInfString -Text "$($s.Value)" }
                'MultiString' { (@($s.Value) | ForEach-Object { "$_".Replace(',', '\,') }) -join ',' }
                default       { "$([int64]"$($s.Value)")" }
            }
            return [pscustomobject]@{ Section = 'Registry Values'; Line = "$($s.Key)=$code,$data" }
        }
        'SystemAccess' {
            $v = "$($s.Value)"
            if ($v -notmatch '^-?\d+$') { $v = Format-NmInfString -Text $v }
            return [pscustomobject]@{ Section = 'System Access'; Line = "$($s.Name) = $v" }
        }
        'UserRight' {
            return [pscustomobject]@{ Section = 'Privilege Rights'; Line = "$($s.Right) = $((@($s.Members) | ForEach-Object { Format-NmInfMember -Member $_ }) -join ',')" }
        }
        'RestrictedGroup' {
            $g = Format-NmInfMember -Member $s.Group
            $lines = @("${g}__Memberof = $((@($s.MemberOf | Where-Object { $_ }) | ForEach-Object { Format-NmInfMember -Member $_ }) -join ',')")
            $lines += "${g}__Members = $((@($s.Members | Where-Object { $_ }) | ForEach-Object { Format-NmInfMember -Member $_ }) -join ',')"
            return @(foreach ($l in $lines) { [pscustomobject]@{ Section = 'Group Membership'; Line = $l } })
        }
        'Service' {
            $sddl = if ($s.Sddl) { "$($s.Sddl)" } else { $script:NmDefaultServiceSddl }
            return [pscustomobject]@{ Section = 'Service General Setting'; Line = "$(Format-NmInfString -Text "$($s.Service)"),$($script:NmStartModeCodes["$($s.StartMode)"]),$(Format-NmInfString -Text $sddl)" }
        }
    }
    throw "Kind '$($s.Kind)' is not part of the security template."
}

function Format-NmInfMember {
    # A SID as *S-1-..., a name as it is.
    param([string]$Member)
    $m = "$Member".Trim()
    if ($m -match '^\*?(S-1-[0-9-]+)$') { return "*$($Matches[1].ToUpper())" }
    return $m
}

function Write-NmGptTmpl {
    <#
    .SYNOPSIS
        Merges lines (Section, Line) into the GPO's GptTmpl.inf and writes it back (UTF-16 LE, as GPMC does).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][object[]]$Lines)
    $path = Get-NmGpoFilePath -Id $Id -File GptTmpl
    $doc = ConvertFrom-NmInf -Text (Read-NmGpoText -Path $path)
    if (-not $doc.Contains('Unicode')) { $doc['Unicode'] = [ordered]@{ 'unicode' = 'Unicode=yes' } }
    foreach ($l in $Lines) {
        if (-not $doc.Contains($l.Section)) { $doc[$l.Section] = [ordered]@{} }
        $doc[$l.Section][(Get-NmInfLineKey -Line $l.Line)] = $l.Line
    }
    $doc['Version'] = [ordered]@{ 'signature' = 'signature="$CHICAGO$"'; 'revision' = 'Revision=1' }
    Write-NmGpoText -Path $path -Text (ConvertTo-NmInf -Doc $doc) -Encoding Unicode
}

function Read-NmGpoGptTmpl {
    # The GPO's GptTmpl.inf as sections (ConvertFrom-NmInf); empty when there is none.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    return (ConvertFrom-NmInf -Text (Read-NmGpoText -Path (Get-NmGpoFilePath -Id $Id -File GptTmpl)))
}

# ---------------------------------------------------------------------------
# audit.csv (advanced audit policy)
# ---------------------------------------------------------------------------
$script:NmAuditCsvHeader = 'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value'
$script:NmAuditInclusionText = @{ 0 = 'No Auditing'; 1 = 'Success'; 2 = 'Failure'; 3 = 'Success and Failure' }

function ConvertFrom-NmAuditCsv {
    # Rows of an audit.csv: Subcategory, Guid (lower case, braces), Value (0-3).
    [CmdletBinding()]
    param([string]$Text)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($line in ("$Text" -split "`r?`n" | Select-Object -Skip 1)) {
        if (-not $line.Trim()) { continue }
        $f = $line.Split(',')
        if ($f.Count -lt 7) { continue }
        $out.Add([pscustomobject]@{ Subcategory = $f[2]; Guid = $f[3].ToLower(); Value = [int]$f[6] })
    }
    return $out.ToArray()
}

function Write-NmGpoAudit {
    <#
    .SYNOPSIS
        Merges audit settings (Subcategory name, Setting) into the GPO's audit.csv, by subcategory GUID.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][object[]]$Settings)
    $path = Get-NmGpoFilePath -Id $Id -File Audit
    $rows = [ordered]@{}
    foreach ($r in @(ConvertFrom-NmAuditCsv -Text (Read-NmGpoText -Path $path))) { $rows[$r.Guid] = $r }
    foreach ($s in $Settings) {
        $guid = Get-NmAuditSubcategoryGuid -Name "$($s.Subcategory)"
        if (-not $guid) { throw "'$($s.Subcategory)' is not an audit subcategory." }
        $name = "Audit $((Get-NmAuditSubcategoryName -Guid $guid))"
        $rows[$guid] = [pscustomobject]@{ Subcategory = $name; Guid = $guid; Value = [int]$script:NmBaselineAuditValues["$($s.Setting)"] }
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$script:NmAuditCsvHeader`r`n")
    foreach ($r in $rows.Values) {
        [void]$sb.Append(",System,$($r.Subcategory),$($r.Guid),$($script:NmAuditInclusionText[[int]$r.Value]),,$($r.Value)`r`n")
    }
    Write-NmGpoText -Path $path -Text $sb.ToString() -Encoding Ascii
}

function Read-NmGpoAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    return @(ConvertFrom-NmAuditCsv -Text (Read-NmGpoText -Path (Get-NmGpoFilePath -Id $Id -File Audit)))
}

# ---------------------------------------------------------------------------
# The GPO's extension list and version, after the files are written
# ---------------------------------------------------------------------------
function Merge-NmGpoExtensionName {
    <#
    .SYNOPSIS
        Adds [CSE][tool] pairs to a gPCMachineExtensionNames value: one bracket per CSE, CSEs and
        their tools sorted by GUID (the order Windows expects), nothing duplicated.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Current, [object[]]$Add = @())
    $map = @{}
    foreach ($m in [regex]::Matches("$Current", '\[([^\]]*)\]')) {
        $guids = @([regex]::Matches($m.Groups[1].Value, '\{[0-9A-Fa-f-]{36}\}') | ForEach-Object { $_.Value.ToUpper() })
        if (-not $guids.Count) { continue }
        if (-not $map.ContainsKey($guids[0])) { $map[$guids[0]] = New-Object System.Collections.Generic.List[string] }
        foreach ($t in ($guids | Select-Object -Skip 1)) { if (-not $map[$guids[0]].Contains($t)) { $map[$guids[0]].Add($t) } }
    }
    foreach ($pair in $Add) {
        $cse = "$($pair[0])".ToUpper(); $tool = "$($pair[1])".ToUpper()
        if (-not $map.ContainsKey($cse)) { $map[$cse] = New-Object System.Collections.Generic.List[string] }
        if (-not $map[$cse].Contains($tool)) { $map[$cse].Add($tool) }
    }
    $sb = New-Object System.Text.StringBuilder
    foreach ($cse in @($map.Keys | Sort-Object)) {
        [void]$sb.Append("[$cse$((@($map[$cse].ToArray() | Sort-Object)) -join '')]")
    }
    return $sb.ToString()
}

function Get-NmGpoAdState {
    # The GPO's AD object: versionNumber and gPCMachineExtensionNames (a wrapper, for the tests).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $adp = Get-NmADParams
    $o = Get-ADObject -Identity $Path -Properties versionNumber, gPCMachineExtensionNames @adp -ErrorAction Stop
    return [pscustomobject]@{ Version = [int]$o.versionNumber; MachineExtensions = "$($o.gPCMachineExtensionNames)" }
}

function Set-NmGpoAdState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [int]$Version, [string]$MachineExtensions)
    $adp = Get-NmADParams
    Set-ADObject -Identity $Path -Replace @{ versionNumber = $Version; gPCMachineExtensionNames = $MachineExtensions } @adp -ErrorAction Stop
}

function Update-NmGpoVersion {
    <#
    .SYNOPSIS
        After GptTmpl.inf or audit.csv is written: adds their extensions to the GPO and raises its
        computer version by one, in AD and GPT.INI, so clients apply the change.
    .PARAMETER Path
        The GPO's AD distinguished name (the Path property of Get-GPO).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Path, [object[]]$Extensions = @())
    $ad = Get-NmGpoAdState -Path $Path
    $iniPath = Get-NmGpoFilePath -Id $Id -File GptIni
    $ini = Read-NmGpoText -Path $iniPath
    $iniVersion = 0
    if ($ini -match '(?m)^\s*Version\s*=\s*(\d+)') { $iniVersion = [int]$Matches[1] }
    # The low 16 bits are the computer side's version, the high 16 the user side's.
    $current = [Math]::Max([int]$ad.Version, $iniVersion)
    $new = $current + 1
    if (($new -band 0xFFFF) -eq 0) { throw 'The GPO computer version would overflow.' }
    if ($ini -match '(?m)^\s*Version\s*=') {
        $ini = [regex]::Replace($ini, '(?m)^\s*Version\s*=\s*\d+', "Version=$new")
    } else {
        $ini = "[General]`r`nVersion=$new`r`n" + ($ini -replace '^\s*\[General\]\s*\r?\n', '')
    }
    Write-NmGpoText -Path $iniPath -Text $ini -Encoding Ascii
    $ext = Merge-NmGpoExtensionName -Current $ad.MachineExtensions -Add $Extensions
    Set-NmGpoAdState -Path $Path -Version $new -MachineExtensions $ext
    return $new
}

# ---------------------------------------------------------------------------
# Accounts as SIDs
# ---------------------------------------------------------------------------
function Resolve-NmAccountSid {
    <#
    .SYNOPSIS
        An account name or SID as a SID (S-1-...): SIDs as they are, well-known names and the domain's
        built-in groups from tables, anything else looked up in AD (a group, then a user). Throws when
        it cannot be found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $n = "$Name".Trim()
    if ($n -match '^\*?(S-1-[0-9-]+)$') { return $Matches[1].ToUpper() }
    $short = if ($n -match '^[^\\]+\\(.+)$') { $Matches[1] } else { $n }
    foreach ($k in $script:NmWellKnownSids.Keys) { if ($k -eq $short) { return $script:NmWellKnownSids[$k] } }
    $s = Get-NmSession
    foreach ($k in $script:NmDomainRids.Keys) {
        if ($k -eq $short -and $s.DomainSid) { return "$($s.DomainSid)-$($script:NmDomainRids[$k])" }
    }
    $adp = Get-NmADParams
    $filter = "sAMAccountName -eq '$($short.Replace("'", "''"))'"
    $g = @(Get-ADGroup -Filter $filter @adp -ErrorAction SilentlyContinue)[0]
    if ($g) { return "$($g.SID)" }
    $u = @(Get-ADUser -Filter $filter @adp -ErrorAction SilentlyContinue)[0]
    if ($u) { return "$($u.SID)" }
    throw "No account named '$n' in $($s.Domain)."
}
