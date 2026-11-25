# ---------------------------------------------------------------------------
# Baseline.ps1 - the baseline files: format, loader, checks, parameters
# ---------------------------------------------------------------------------
# A baseline is one GPO's settings, nothing else (CLAUDE.md). Each one is a .psd1 file in
# Nutmeg.AD\Baselines, read with Import-PowerShellDataFile (no code runs). Agreed with Cliff,
# Nov 2026: psd1, control tags as "Framework:Control" strings, Restricted Groups in step 2,
# and the GPO's comment stamped "Nutmeg baseline: <Id> <Version>" so gpo-compare finds it.
#
# A file:
#   Id, Name, Version, Description          required
#   Source, Requires, Notes                 optional
#   Parameters = @( @{ Name; Prompt; Type; Default; Min; Max; Choices; Optional } )
#   Settings   = @( @{ Id; Kind; Side; Title; Tags; Note; <the kind's own fields> } )
#
# {Name} in a setting's text is a parameter; {{ and }} are literal braces. A parameter's Default
# can be a toolkit setting ({Setting:Key}) or a fact about the session ({Session:Pdc},
# {Session:Domain}, {Session:NetBIOS}).

$script:NmBaselineCache = $null

# Every kind: its own fields (required, then optional) and the sides it may use.
$script:NmBaselineKinds = [ordered]@{
    Policy          = @{ Required = @('Values'); Optional = @(); Sides = @('Computer', 'User'); Label = 'Administrative Templates' }
    PrefRegistry    = @{ Required = @('Hive', 'Key', 'ValueName', 'Type', 'Value'); Optional = @('Action'); Sides = @('Computer', 'User'); Label = 'Preferences: Registry' }
    SecurityOption  = @{ Required = @('Key', 'Type', 'Value'); Optional = @(); Sides = @('Computer'); Label = 'Security Options' }
    SystemAccess    = @{ Required = @('Name', 'Value'); Optional = @(); Sides = @('Computer'); Label = 'Account policies and accounts' }
    UserRight       = @{ Required = @('Right', 'Members'); Optional = @(); Sides = @('Computer'); Label = 'User Rights Assignment' }
    RestrictedGroup = @{ Required = @('Group', 'Members'); Optional = @('MemberOf'); Sides = @('Computer'); Label = 'Restricted Groups' }
    Audit           = @{ Required = @('Subcategory', 'Setting'); Optional = @(); Sides = @('Computer'); Label = 'Advanced Audit Policy' }
    Service         = @{ Required = @('Service', 'StartMode'); Optional = @('Sddl'); Sides = @('Computer'); Label = 'System Services' }
}
$script:NmBaselineCommonFields = @('Id', 'Kind', 'Side', 'Title', 'Tags', 'Note')
$script:NmBaselineTopFields    = @('Id', 'Name', 'Version', 'Description', 'Source', 'Requires', 'Notes', 'Parameters', 'Settings')
$script:NmBaselineParamFields  = @('Name', 'Prompt', 'Type', 'Default', 'Min', 'Max', 'Choices', 'ValueMap', 'Optional', 'Help')
$script:NmBaselineParamTypes   = @('String', 'Int', 'Choice', 'Fqdn', 'IpRange', 'Group', 'Account')
$script:NmBaselineValueTypes   = @('String', 'ExpandString', 'DWord', 'QWord', 'MultiString')
$script:NmBaselineSecTypes     = @('String', 'DWord', 'MultiString')
$script:NmBaselinePrefActions  = @('Create', 'Replace', 'Update', 'Delete')
$script:NmBaselineStartModes   = @('Automatic', 'Manual', 'Disabled')
$script:NmBaselineAuditValues  = [ordered]@{ NoAuditing = 0; Success = 1; Failure = 2; SuccessAndFailure = 3 }
$script:NmBaselineRequires     = @('Duo', 'PowerShellCore')
# Control tags: a framework from this list, a colon, the control. CIS: section numbers only.
$script:NmBaselineTagFrameworks = @('HIPAA', 'NIST800-53', 'NIST800-171', 'CMMC', 'FFIEC', 'STIG', 'MSBaseline', 'CIS')
$script:NmBaselineSystemAccess = @('MinimumPasswordAge', 'MaximumPasswordAge', 'MinimumPasswordLength', 'PasswordComplexity',
    'PasswordHistorySize', 'LockoutBadCount', 'ResetLockoutCount', 'LockoutDuration', 'RequireLogonToChangePassword',
    'ForceLogoffWhenHourExpire', 'NewAdministratorName', 'NewGuestName', 'ClearTextPassword', 'LSAAnonymousNameLookup',
    'EnableAdminAccount', 'EnableGuestAccount')

# Advanced audit subcategories (auditpol /list /subcategory:* /v). GUIDs share the tail -69ae-11d9-bed3-505054503030.
$script:NmAuditSubcategories = [ordered]@{
    'Security State Change' = '0cce9210'; 'Security System Extension' = '0cce9211'; 'System Integrity' = '0cce9212'
    'IPsec Driver' = '0cce9213'; 'Other System Events' = '0cce9214'
    'Logon' = '0cce9215'; 'Logoff' = '0cce9216'; 'Account Lockout' = '0cce9217'; 'IPsec Main Mode' = '0cce9218'
    'IPsec Quick Mode' = '0cce9219'; 'IPsec Extended Mode' = '0cce921a'; 'Special Logon' = '0cce921b'
    'Other Logon/Logoff Events' = '0cce921c'; 'Network Policy Server' = '0cce9243'; 'User / Device Claims' = '0cce9247'
    'Group Membership' = '0cce9249'
    'File System' = '0cce921d'; 'Registry' = '0cce921e'; 'Kernel Object' = '0cce921f'; 'SAM' = '0cce9220'
    'Certification Services' = '0cce9221'; 'Application Generated' = '0cce9222'; 'Handle Manipulation' = '0cce9223'
    'File Share' = '0cce9224'; 'Filtering Platform Packet Drop' = '0cce9225'; 'Filtering Platform Connection' = '0cce9226'
    'Other Object Access Events' = '0cce9227'; 'Detailed File Share' = '0cce9244'; 'Removable Storage' = '0cce9245'
    'Central Policy Staging' = '0cce9246'
    'Sensitive Privilege Use' = '0cce9228'; 'Non Sensitive Privilege Use' = '0cce9229'; 'Other Privilege Use Events' = '0cce922a'
    'Process Creation' = '0cce922b'; 'Process Termination' = '0cce922c'; 'DPAPI Activity' = '0cce922d'; 'RPC Events' = '0cce922e'
    'Plug and Play Events' = '0cce9248'; 'Token Right Adjusted Events' = '0cce924a'
    'Audit Policy Change' = '0cce922f'; 'Authentication Policy Change' = '0cce9230'; 'Authorization Policy Change' = '0cce9231'
    'MPSSVC Rule-Level Policy Change' = '0cce9232'; 'Filtering Platform Policy Change' = '0cce9233'; 'Other Policy Change Events' = '0cce9234'
    'User Account Management' = '0cce9235'; 'Computer Account Management' = '0cce9236'; 'Security Group Management' = '0cce9237'
    'Distribution Group Management' = '0cce9238'; 'Application Group Management' = '0cce9239'; 'Other Account Management Events' = '0cce923a'
    'Directory Service Access' = '0cce923b'; 'Directory Service Changes' = '0cce923c'; 'Directory Service Replication' = '0cce923d'
    'Detailed Directory Service Replication' = '0cce923e'
    'Credential Validation' = '0cce923f'; 'Kerberos Service Ticket Operations' = '0cce9240'; 'Other Account Logon Events' = '0cce9241'
    'Kerberos Authentication Service' = '0cce9242'
}

function Get-NmAuditSubcategoryGuid {
    # '{0cce923f-69ae-11d9-bed3-505054503030}' for 'Credential Validation' (or 'Audit Credential Validation'); '' if unknown.
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Name)
    $n = "$Name".Trim()
    # The exact name first: 'Audit Policy Change' is itself a subcategory.
    $tries = @($n)
    if ($n -like 'Audit *') { $tries += $n.Substring(6) }
    foreach ($t in $tries) {
        foreach ($k in $script:NmAuditSubcategories.Keys) {
            if ($k -eq $t) { return "{$($script:NmAuditSubcategories[$k])-69ae-11d9-bed3-505054503030}" }
        }
    }
    return ''
}

function Get-NmAuditSubcategoryName {
    # The subcategory name for a GUID (with or without braces); '' if unknown.
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Guid)
    $g = "$Guid".Trim('{', '}', ' ').ToLower()
    foreach ($k in $script:NmAuditSubcategories.Keys) {
        if ("$($script:NmAuditSubcategories[$k])-69ae-11d9-bed3-505054503030" -eq $g) { return $k }
    }
    return ''
}

# ---------------------------------------------------------------------------
# Placeholders
# ---------------------------------------------------------------------------
function Get-NmBaselinePlaceholder {
    # The {Name} placeholders used anywhere in a value (string, array or hashtable, nested).
    [CmdletBinding()]
    param($Value)
    $found = New-Object System.Collections.Generic.List[string]
    $walk = $null
    $walk = {
        param($v)
        if ($null -eq $v) { return }
        if ($v -is [string]) {
            $clean = $v.Replace('{{', '').Replace('}}', '')
            foreach ($m in [regex]::Matches($clean, '\{([A-Za-z][A-Za-z0-9]*)\}')) {
                if (-not $found.Contains($m.Groups[1].Value)) { $found.Add($m.Groups[1].Value) }
            }
        } elseif ($v -is [System.Collections.IDictionary]) {
            foreach ($k in @($v.Keys)) { & $walk $v[$k] }
        } elseif ($v -is [System.Collections.IEnumerable]) {
            foreach ($x in $v) { & $walk $x }
        }
    }
    & $walk $Value
    return $found.ToArray()
}

function Expand-NmBaselineText {
    # Fills {Name} from -Values; {{ and }} become { and }. A name not in -Values is left as {Name}.
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Text, [hashtable]$Values = @{})
    $vals = $Values
    return [regex]::Replace("$Text", '\{\{|\}\}|\{([A-Za-z][A-Za-z0-9]*)\}', {
        param($m)
        if ($m.Value -eq '{{') { return '{' }
        if ($m.Value -eq '}}') { return '}' }
        $n = $m.Groups[1].Value
        if ($vals.ContainsKey($n)) { return "$($vals[$n])" }
        return $m.Value
    })
}

function Expand-NmBaselineValue {
    # A copy of a value (string, number, array, hashtable) with its placeholders filled in.
    [CmdletBinding()]
    param($Value, [hashtable]$Values = @{})
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (Expand-NmBaselineText -Text $Value -Values $Values) }
    if ($Value -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in @($Value.Keys)) { $h[$k] = Expand-NmBaselineValue -Value $Value[$k] -Values $Values }
        return $h
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($x in $Value) { $list.Add((Expand-NmBaselineValue -Value $x -Values $Values)) }
        return , $list.ToArray()
    }
    return $Value
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
function Test-NmBaselineTag {
    # True for "Framework:Control" with a known framework.
    [CmdletBinding()]
    [OutputType([bool])]
    param([string]$Tag)
    if ("$Tag" -notmatch '^([A-Za-z0-9-]+):(\S.*)$') { return $false }
    return ($script:NmBaselineTagFrameworks -ccontains $Matches[1])
}

function Test-NmBaseline {
    <#
    .SYNOPSIS
        Checks one baseline's data. Returns the problems found (none: it is valid).
    .DESCRIPTION
        - Top fields: Id (lower-case-hyphenated), Name, Version (0.7.1), Description; no unknown fields.
        - Parameters: Name, Prompt, a known Type, Choices for a Choice; every declared parameter used,
          every placeholder declared.
        - Settings: unique Ids, a known Kind with its own fields and nothing else, a Side the kind
          allows, a Title, Tags as "Framework:Control" strings, and each kind's values checked
          (registry hive and types, audit subcategory names, service start modes, ...).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data)
    $p = New-Object System.Collections.Generic.List[string]
    foreach ($k in @($Data.Keys)) { if ($script:NmBaselineTopFields -notcontains $k) { $p.Add("unknown field '$k'") } }
    if ("$($Data.Id)" -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $p.Add("Id '$($Data.Id)' must be lower-case-hyphenated") }
    if (-not "$($Data.Name)".Trim()) { $p.Add('Name is missing') }
    if ("$($Data.Version)" -notmatch '^\d+\.\d+(\.\d+)?$') { $p.Add("Version '$($Data.Version)' must look like 0.7.1") }
    if (-not "$($Data.Description)".Trim()) { $p.Add('Description is missing') }
    foreach ($r in @($Data.Requires | Where-Object { $_ })) { if ($script:NmBaselineRequires -notcontains $r) { $p.Add("Requires '$r' is not one of: $($script:NmBaselineRequires -join ', ')") } }

    # Parameters
    $declared = New-Object System.Collections.Generic.List[string]
    foreach ($par in @($Data.Parameters | Where-Object { $null -ne $_ })) {
        if ($par -isnot [System.Collections.IDictionary]) { $p.Add('a parameter is not a hashtable'); continue }
        $n = "$($par.Name)"
        foreach ($k in @($par.Keys)) { if ($script:NmBaselineParamFields -notcontains $k) { $p.Add("parameter ${n}: unknown field '$k'") } }
        if ($n -cnotmatch '^[A-Za-z][A-Za-z0-9]*$') { $p.Add("parameter name '$n' must be letters and digits"); continue }
        if ($declared.Contains($n)) { $p.Add("parameter $n is declared twice") }
        $declared.Add($n)
        if (-not "$($par.Prompt)".Trim()) { $p.Add("parameter ${n}: Prompt is missing") }
        if ($script:NmBaselineParamTypes -notcontains "$($par.Type)") { $p.Add("parameter ${n}: Type '$($par.Type)' is not one of: $($script:NmBaselineParamTypes -join ', ')") }
        if ("$($par.Type)" -eq 'Choice' -and -not @($par.Choices).Count) { $p.Add("parameter ${n}: a Choice needs Choices") }
        if ($par.Contains('ValueMap')) {
            if ("$($par.Type)" -ne 'Choice') { $p.Add("parameter ${n}: ValueMap is only for Choice parameters") }
            elseif ($par.ValueMap -isnot [System.Collections.IDictionary]) { $p.Add("parameter ${n}: ValueMap must be a hashtable") }
            else {
                foreach ($ch in @($par.Choices)) {
                    if (-not $par.ValueMap.Contains("$ch")) { $p.Add("parameter ${n}: ValueMap is missing '$ch'") }
                }
            }
        }
        if (-not $par.Contains('Default')) { $p.Add("parameter ${n}: Default is missing (use '' for none)") }
    }

    # Settings
    $settings = @($Data.Settings | Where-Object { $null -ne $_ })
    if (-not $settings.Count) { $p.Add('Settings is empty') }
    $ids = New-Object System.Collections.Generic.List[string]
    $used = New-Object System.Collections.Generic.List[string]
    foreach ($s in $settings) {
        if ($s -isnot [System.Collections.IDictionary]) { $p.Add('a setting is not a hashtable'); continue }
        $sid = "$($s.Id)"
        $where = "setting '$sid'"
        if ($sid -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $p.Add("$where`: Id must be lower-case-hyphenated") }
        elseif ($ids.Contains($sid)) { $p.Add("$where`: Id is used twice") }
        $ids.Add($sid)
        $kind = "$($s.Kind)"
        if (-not $script:NmBaselineKinds.Contains($kind)) { $p.Add("$where`: Kind '$kind' is not one of: $(@($script:NmBaselineKinds.Keys) -join ', ')"); continue }
        $def = $script:NmBaselineKinds[$kind]
        $allowed = @($script:NmBaselineCommonFields) + @($def.Required) + @($def.Optional)
        foreach ($k in @($s.Keys)) { if ($allowed -notcontains $k) { $p.Add("$where`: unknown field '$k' for $kind") } }
        foreach ($k in $def.Required) { if (-not $s.Contains($k)) { $p.Add("$where`: $k is missing") } }
        if ($def.Sides -notcontains "$($s.Side)") { $p.Add("$where`: Side '$($s.Side)' must be $($def.Sides -join ' or ')") }
        if (-not "$($s.Title)".Trim()) { $p.Add("$where`: Title is missing") }
        if (-not $s.Contains('Tags')) { $p.Add("$where`: Tags is missing (use @() for none)") }
        foreach ($t in @($s.Tags | Where-Object { $null -ne $_ })) {
            if (-not (Test-NmBaselineTag -Tag "$t")) { $p.Add("$where`: tag '$t' must be Framework:Control, with a framework from: $($script:NmBaselineTagFrameworks -join ', ')") }
        }
        $hive = if ("$($s.Side)" -eq 'User') { 'HKCU' } else { 'HKLM' }
        switch ($kind) {
            'Policy' {
                $vals = @($s.Values | Where-Object { $null -ne $_ })
                if (-not $vals.Count) { $p.Add("$where`: Values is empty") }
                foreach ($v in $vals) {
                    if ($v -isnot [System.Collections.IDictionary]) { $p.Add("$where`: a value is not a hashtable"); continue }
                    foreach ($k in @($v.Keys)) { if (@('Key', 'ValueName', 'Type', 'Value') -notcontains $k) { $p.Add("$where`: unknown value field '$k'") } }
                    if ("$($v.Key)" -notmatch "^$hive\\.+") { $p.Add("$where`: Key '$($v.Key)' must start with $hive\ for the $($s.Side) side") }
                    if (-not $v.Contains('ValueName')) { $p.Add("$where`: ValueName is missing") }
                    if ($script:NmBaselineValueTypes -notcontains "$($v.Type)") { $p.Add("$where`: Type '$($v.Type)' is not one of: $($script:NmBaselineValueTypes -join ', ')") }
                    if (-not $v.Contains('Value')) { $p.Add("$where`: Value is missing") }
                }
            }
            'PrefRegistry' {
                if ("$($s.Hive)" -ne $hive) { $p.Add("$where`: Hive must be $hive for the $($s.Side) side") }
                if (-not "$($s.Key)".Trim() -or "$($s.Key)" -match '^HK') { $p.Add("$where`: Key is the path under the hive, without HKLM\ or HKCU\") }
                if ($script:NmBaselineValueTypes -notcontains "$($s.Type)") { $p.Add("$where`: Type '$($s.Type)' is not one of: $($script:NmBaselineValueTypes -join ', ')") }
                if ($s.Contains('Action') -and $script:NmBaselinePrefActions -notcontains "$($s.Action)") { $p.Add("$where`: Action must be one of: $($script:NmBaselinePrefActions -join ', ')") }
            }
            'SecurityOption' {
                if ("$($s.Key)" -notmatch '^MACHINE\\.+\\[^\\]+$') { $p.Add("$where`: Key must be MACHINE\<path>\<value name>") }
                if ($script:NmBaselineSecTypes -notcontains "$($s.Type)") { $p.Add("$where`: Type '$($s.Type)' is not one of: $($script:NmBaselineSecTypes -join ', ')") }
            }
            'SystemAccess' {
                if ($script:NmBaselineSystemAccess -notcontains "$($s.Name)") { $p.Add("$where`: Name '$($s.Name)' is not a [System Access] setting") }
            }
            'UserRight' {
                if ("$($s.Right)" -cnotmatch '^Se[A-Za-z]+(Right|Privilege)$') { $p.Add("$where`: Right '$($s.Right)' must be a user right constant (SeRemoteInteractiveLogonRight)") }
            }
            'RestrictedGroup' {
                if (-not "$($s.Group)".Trim()) { $p.Add("$where`: Group is missing") }
            }
            'Audit' {
                if (-not (Get-NmAuditSubcategoryGuid -Name "$($s.Subcategory)")) { $p.Add("$where`: '$($s.Subcategory)' is not an audit subcategory") }
                if (-not $script:NmBaselineAuditValues.Contains("$($s.Setting)")) { $p.Add("$where`: Setting must be one of: $(@($script:NmBaselineAuditValues.Keys) -join ', ')") }
            }
            'Service' {
                if (-not "$($s.Service)".Trim()) { $p.Add("$where`: Service is missing") }
                if ($script:NmBaselineStartModes -notcontains "$($s.StartMode)") { $p.Add("$where`: StartMode must be one of: $($script:NmBaselineStartModes -join ', ')") }
                if ($s.Contains('Sddl') -and "$($s.Sddl)" -notmatch '^D:') { $p.Add("$where`: Sddl must start with D:") }
            }
        }
        # Placeholders go in values only: what a setting sets (its key, name, right, group) is fixed,
        # so gpo-compare can find it in any GPO.
        $identity = @{}
        foreach ($k in 'Hive', 'Key', 'ValueName', 'Type', 'Name', 'Right', 'Group', 'Subcategory', 'Service', 'StartMode', 'Setting', 'Action') { if ($s.Contains($k)) { $identity[$k] = $s[$k] } }
        if ($kind -eq 'Policy') { $identity['Values'] = @(foreach ($v in @($s.Values)) { if ($v -is [System.Collections.IDictionary]) { "$($v.Key)"; "$($v.ValueName)"; "$($v.Type)" } }) }
        foreach ($ph in (Get-NmBaselinePlaceholder -Value $identity)) { $p.Add("$where`: {$ph} can only be used in a value, not in what the setting sets") }
        $fields = @{}
        foreach ($k in @($s.Keys)) { if (@('Id', 'Kind', 'Side', 'Title', 'Tags', 'Note') -notcontains $k) { $fields[$k] = $s[$k] } }
        foreach ($ph in (Get-NmBaselinePlaceholder -Value $fields)) { if (-not $used.Contains($ph)) { $used.Add($ph) } }
    }
    foreach ($u in $used) { if (-not $declared.Contains($u)) { $p.Add("{$u} is used but not declared in Parameters") } }
    foreach ($d in $declared) { if (-not $used.Contains($d)) { $p.Add("parameter $d is declared but not used") } }
    return $p.ToArray()
}

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------
function Get-NmBaselineFolder {
    # Nutmeg.AD\Baselines (tests point $script:NmBaselineTestFolder elsewhere).
    if ($script:NmBaselineTestFolder) { return $script:NmBaselineTestFolder }
    return (Join-Path $script:NmModuleRoot 'Baselines')
}

function Get-NmBaseline {
    <#
    .SYNOPSIS
        The baselines in Nutmeg.AD\Baselines, sorted by name, or the one with -Id.
    .DESCRIPTION
        Each: Id, Name, Version, Description, Source, Requires, Notes, Parameters, Settings, Path,
        Problems (from Test-NmBaseline, plus a file that would not read or a duplicate Id) and Valid.
        Read once and kept; -Reload reads the folder again. -IncludeInvalid returns the ones with
        problems too (for the checks and the "not loaded" list).
    #>
    [CmdletBinding()]
    param([string]$Id, [switch]$Reload, [switch]$IncludeInvalid)
    if (-not $script:NmBaselineCache -or $Reload) {
        $list = New-Object System.Collections.Generic.List[object]
        $folder = Get-NmBaselineFolder
        $files = @(if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -Filter '*.psd1' -File | Sort-Object Name })
        foreach ($f in $files) {
            $problems = @()
            $data = $null
            try { $data = Import-PowerShellDataFile -LiteralPath $f.FullName -ErrorAction Stop }
            catch { $problems = @("could not be read: $($_.Exception.Message)") }
            if ($data) { $problems = @(Test-NmBaseline -Data $data) }
            $list.Add([pscustomobject]@{
                Id          = $(if ($data) { "$($data.Id)" } else { [System.IO.Path]::GetFileNameWithoutExtension($f.Name) })
                Name        = $(if ($data) { "$($data.Name)" } else { $f.Name })
                Version     = $(if ($data) { "$($data.Version)" } else { '' })
                Description = $(if ($data) { "$($data.Description)" } else { '' })
                Source      = $(if ($data) { "$($data.Source)" } else { '' })
                Requires    = @(if ($data) { $data.Requires | Where-Object { $_ } })
                Notes       = @(if ($data) { $data.Notes | Where-Object { $_ } })
                Parameters  = @(if ($data) { $data.Parameters | Where-Object { $null -ne $_ } })
                Settings    = @(if ($data) { $data.Settings | Where-Object { $null -ne $_ } })
                Path        = $f.FullName
                Problems    = $problems
                Valid       = ($problems.Count -eq 0)
            })
        }
        # The same Id in two files: both are invalid.
        foreach ($g in @($list | Group-Object Id | Where-Object { $_.Count -gt 1 })) {
            foreach ($b in $g.Group) { $b.Problems = @($b.Problems) + "Id '$($b.Id)' is also used by another file"; $b.Valid = $false }
        }
        $script:NmBaselineCache = @($list.ToArray() | Sort-Object Name)
    }
    $out = @($script:NmBaselineCache | Where-Object { $IncludeInvalid -or $_.Valid })
    if ($Id) { $out = @($out | Where-Object { $_.Id -eq $Id }) }
    return $out
}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
function Get-NmBaselineDefault {
    # A parameter's default, with {Setting:Key} and {Session:Pdc|Domain|NetBIOS} filled in.
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Parameter)
    $d = $Parameter.Default
    if ($d -isnot [string]) { return $d }
    return [regex]::Replace($d, '\{(Setting|Session):([A-Za-z0-9]+)\}', {
        param($m)
        $what = $m.Groups[2].Value
        if ($m.Groups[1].Value -eq 'Setting') {
            try { return "$(Get-NmSetting -Key $what)" } catch { return '' }
        }
        $s = Get-NmSession
        switch ($what) {
            'Pdc'     { return "$($s.PdcEmulator)" }
            'Domain'  { return "$($s.Domain)" }
            'NetBIOS' { return "$($s.NetBIOS)" }
            default   { return '' }
        }
    })
}

function Test-NmBaselineParamValue {
    # '' when a value suits the parameter, otherwise why not.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Parameter, $Value)
    $text = "$Value".Trim()
    if (-not $text) {
        if ($Parameter.Optional) { return '' }
        return 'an answer is needed'
    }
    switch ("$($Parameter.Type)") {
        'Int' {
            $n = 0
            if (-not [int]::TryParse($text, [ref]$n)) { return 'a whole number is needed' }
            if ($Parameter.Contains('Min') -and $n -lt [int]$Parameter.Min) { return "at least $($Parameter.Min)" }
            if ($Parameter.Contains('Max') -and $n -gt [int]$Parameter.Max) { return "at most $($Parameter.Max)" }
        }
        'Choice' {
            if (@($Parameter.Choices) -notcontains $text) { return "one of: $(@($Parameter.Choices) -join ', ')" }
        }
        'Fqdn' {
            if ($text -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$') { return 'a full DNS name is needed (server.clientx.local)' }
        }
        'IpRange' {
            if (-not (Test-NmIpRangeText -Text $text)) { return 'an IP address or range is needed (192.0.2.0/24)' }
        }
    }
    return ''
}

function Resolve-NmBaselineValues {
    <#
    .SYNOPSIS
        Every parameter's value: the one given, else its default. Returns Values (hashtable) and
        Problems (a parameter with no usable value).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Baseline, [hashtable]$Given = @{})
    $vals = @{}
    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($par in @($Baseline.Parameters)) {
        $n = "$($par.Name)"
        $v = if ($Given.ContainsKey($n)) { $Given[$n] } else { Get-NmBaselineDefault -Parameter $par }
        $why = Test-NmBaselineParamValue -Parameter $par -Value $v
        if ($why) { $problems.Add("${n}: $why") }
        $vals[$n] = "$v".Trim()
    }
    return [pscustomobject]@{ Values = $vals; Problems = $problems.ToArray() }
}

function Expand-NmBaselineParamValues {
    # Returns a copy of -Values where any Choice parameter with a ValueMap is mapped to its setting value.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Baseline, [hashtable]$Values = @{})
    $out = @{}
    foreach ($k in $Values.Keys) { $out[$k] = $Values[$k] }
    foreach ($par in @($Baseline.Parameters)) {
        if ($par -is [System.Collections.IDictionary] -and $par.Contains('ValueMap') -and $par.ValueMap -is [System.Collections.IDictionary]) {
            $n = "$($par.Name)"
            if ($out.ContainsKey($n) -and $par.ValueMap.Contains("$($out[$n])")) {
                $out[$n] = $par.ValueMap["$($out[$n])"]
            }
        }
    }
    return $out
}

function Read-NmBaselineParameter {
    <#
    .SYNOPSIS
        Asks a baseline's parameters (default offered, re-asked until the answer suits). Returns a hashtable.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Baseline)
    $vals = @{}
    foreach ($par in @($Baseline.Parameters)) {
        $default = "$(Get-NmBaselineDefault -Parameter $par)"
        $prompt = "$($par.Prompt)"
        if ("$($par.Type)" -eq 'Choice') { $prompt += " ($(@($par.Choices) -join ', '))" }
        if ($par.Help) { Write-Host "   $($par.Help)" -ForegroundColor DarkGray }
        while ($true) {
            $ans = Read-NmInput -Prompt $prompt -Default $default
            $why = Test-NmBaselineParamValue -Parameter $par -Value $ans
            if (-not $why) { $vals["$($par.Name)"] = "$ans".Trim(); break }
            Write-Host "That does not fit: $why." -ForegroundColor Red
        }
    }
    return $vals
}

function Get-NmBaselineStamp {
    # The comment gpo-build writes on a GPO: "Nutmeg baseline: <Id> <Version>".
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Baseline)
    return "Nutmeg baseline: $($Baseline.Id) $($Baseline.Version)"
}

function Read-NmBaselineStamp {
    # Id and Version from a GPO's comment, or $null when it has no stamp.
    [CmdletBinding()]
    param([string]$Comment)
    if ("$Comment" -match 'Nutmeg baseline: ([a-z0-9-]+) (\d+\.\d+(?:\.\d+)?)') {
        return [pscustomobject]@{ Id = $Matches[1]; Version = $Matches[2] }
    }
    return $null
}

function Get-NmBaselineDefaultLink {
    # The default links for a baseline name from Data\GpoDefaultLinks.csv: Links (array) and Notes.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $csv = Join-Path (Join-Path $script:NmModuleRoot 'Data') 'GpoDefaultLinks.csv'
    if (-not (Test-Path -LiteralPath $csv)) { return $null }
    $row = @(Import-Csv -LiteralPath $csv | Where-Object { $_.Baseline -eq $Name })[0]
    if (-not $row) { return $null }
    return [pscustomobject]@{ Links = @("$($row.DefaultLinks)" -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }); Notes = "$($row.Notes)" }
}
