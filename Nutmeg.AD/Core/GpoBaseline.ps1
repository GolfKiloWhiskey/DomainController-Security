# ---------------------------------------------------------------------------
# GpoBaseline.ps1 - a baseline written into a GPO, and a GPO compared with its baseline
# ---------------------------------------------------------------------------
# gpo-build and gpo-compare are thin tools on top of this, so the New Forest Build (phase 4) can
# call the same code without prompts.
#
# Writing: Administrative Templates with Set-GPRegistryValue, registry preferences with
# Set-GPPrefRegistryValue, the security-template kinds into GptTmpl.inf, audit into audit.csv
# (Core\GpoFiles.ps1), then the GPO's extensions and version once.
#
# Comparing: the GPO's files are read (never the cmdlets), each value becomes an "item" with an
# identity (what it sets) and a value, and the baseline's settings become items the same way.

$script:NmSecurityKinds = @('SecurityOption', 'SystemAccess', 'UserRight', 'RestrictedGroup', 'Service')

# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------
function ConvertTo-NmRegData {
    # A baseline value as what Set-GPRegistryValue / Set-GPPrefRegistryValue take for the type.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Type, $Value)
    switch ($Type) {
        'DWord' {
            $n = [int64]"$Value"
            if ($n -gt [int]::MaxValue) { $n = $n - 4294967296 }   # 0x80000000 and up, as the signed int the cmdlet takes
            return [int]$n
        }
        'QWord'       { return [int64]"$Value" }
        'MultiString' { return [string[]]@($Value | ForEach-Object { "$_" }) }
        default       { return "$Value" }
    }
}

function Get-NmBaselineSettingText {
    # One line about a setting for confirmations and logs: "Title (Kind)".
    param([System.Collections.IDictionary]$Setting)
    return "$($Setting.Title) ($($Setting.Kind))"
}

function Invoke-NmBaselineWrite {
    <#
    .SYNOPSIS
        Writes a baseline's settings, with the parameters filled in, into an existing GPO.
    .DESCRIPTION
        - Returns one row per setting: Setting, Kind, Result (Written, Failed: reason).
        - A setting that fails does not stop the rest; accounts that cannot be found fail their setting.
    .PARAMETER Gpo
        The GPO from New-GPO / Get-GPO (its Id and Path are used).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Gpo, [Parameter(Mandatory)]$Baseline, [hashtable]$Values = @{})
    $gp = Get-NmGPParams
    $id = "$($Gpo.Id)"
    $rows = New-Object System.Collections.Generic.List[object]
    $infLines = New-Object System.Collections.Generic.List[object]
    $infSettings = New-Object System.Collections.Generic.List[object]
    $audit = New-Object System.Collections.Generic.List[object]
    $auditSettings = New-Object System.Collections.Generic.List[object]
    $settings = @($Baseline.Settings)
    $i = 0
    foreach ($raw in $settings) {
        $i++
        Write-Progress -Activity "Writing $($Baseline.Name)" -Status "[$i/$($settings.Count)] $($raw.Title)" -PercentComplete ([int](100 * $i / [Math]::Max(1, $settings.Count)))
        $s = Expand-NmBaselineValue -Value $raw -Values $Values
        $row = [pscustomobject]@{ Setting = "$($raw.Title)"; SettingId = "$($raw.Id)"; Kind = "$($raw.Kind)"; Result = 'Written' }
        try {
            switch ("$($s.Kind)") {
                'Policy' {
                    foreach ($v in @($s.Values)) {
                        Set-GPRegistryValue -Guid $id -Key "$($v.Key)" -ValueName "$($v.ValueName)" -Type "$($v.Type)" -Value (ConvertTo-NmRegData -Type "$($v.Type)" -Value $v.Value) @gp -ErrorAction Stop | Out-Null
                    }
                }
                'PrefRegistry' {
                    $action = if ($s.Action) { "$($s.Action)" } else { 'Update' }
                    $context = if ("$($s.Side)" -eq 'User') { 'User' } else { 'Computer' }
                    Set-GPPrefRegistryValue -Guid $id -Context $context -Action $action -Key "$($s.Hive)\$($s.Key)" -ValueName "$($s.ValueName)" -Type "$($s.Type)" -Value (ConvertTo-NmRegData -Type "$($s.Type)" -Value $s.Value) @gp -ErrorAction Stop | Out-Null
                }
                'Audit' {
                    $audit.Add($s); $auditSettings.Add($row)
                }
                default {
                    if ($script:NmSecurityKinds -notcontains "$($s.Kind)") { throw "Kind '$($s.Kind)' cannot be written yet." }
                    if ("$($s.Kind)" -eq 'UserRight' -or "$($s.Kind)" -eq 'RestrictedGroup') {
                        $s.Members = @(foreach ($m in @($s.Members | Where-Object { "$_".Trim() })) { Resolve-NmAccountSid -Name "$m" })
                    }
                    if ("$($s.Kind)" -eq 'RestrictedGroup') {
                        $s.Group = Resolve-NmAccountSid -Name "$($s.Group)"
                        $s.MemberOf = @(foreach ($m in @($s.MemberOf | Where-Object { "$_".Trim() })) { Resolve-NmAccountSid -Name "$m" })
                    }
                    foreach ($l in @(ConvertTo-NmGptTmplLine -Setting $s)) { $infLines.Add($l) }
                    $infSettings.Add($row)
                }
            }
        } catch {
            $row.Result = "Failed: $($_.Exception.Message)"
            Write-NmLog "$($Baseline.Name): '$($raw.Title)' was not written: $($_.Exception.Message)" -Level ERROR
        }
        $rows.Add($row)
    }
    Write-Progress -Activity "Writing $($Baseline.Name)" -Completed

    # The files with no cmdlet, then the GPO's extensions and version once.
    $ext = New-Object System.Collections.Generic.List[object]
    if ($infLines.Count) {
        try { Write-NmGptTmpl -Id $id -Lines $infLines.ToArray(); $ext.Add($script:NmCseSecurity) }
        catch { foreach ($r in $infSettings) { $r.Result = "Failed: security template not written: $($_.Exception.Message)" } }
    }
    if ($audit.Count) {
        try { Write-NmGpoAudit -Id $id -Settings $audit.ToArray(); $ext.Add($script:NmCseAudit) }
        catch { foreach ($r in $auditSettings) { $r.Result = "Failed: audit.csv not written: $($_.Exception.Message)" } }
    }
    if ($ext.Count) {
        try {
            $v = Update-NmGpoVersion -Id $id -Path "$($Gpo.Path)" -Extensions $ext.ToArray()
            Write-NmLog "$($Gpo.DisplayName): extensions added, computer version now $v." -Level INFO -NoConsole
        } catch {
            foreach ($r in @($infSettings) + @($auditSettings)) {
                if ($r.Result -eq 'Written') { $r.Result = "Failed: written to SYSVOL but the GPO's version was not raised: $($_.Exception.Message)" }
            }
        }
    }
    return $rows.ToArray()
}

# ---------------------------------------------------------------------------
# Items: what a GPO sets, and what a baseline expects, in one shape
# ---------------------------------------------------------------------------
function ConvertTo-NmDwordText {
    # A DWord as unsigned decimal text ('-1' -> '4294967295'); anything else (a placeholder) as it is.
    param($Value)
    $n = [int64]0
    if ([int64]::TryParse("$Value", [ref]$n)) {
        if ($n -lt 0) { $n += 4294967296 }
        return "$n"
    }
    return "$Value"
}

function Get-NmRegItemValue {
    # "Type:data", the way both sides are compared.
    param([string]$Type, $Value)
    $data = switch ($Type) {
        'DWord'       { ConvertTo-NmDwordText -Value $Value }
        'MultiString' { (@($Value) | ForEach-Object { "$_" }) -join ',' }
        default       { "$Value" }
    }
    return "${Type}:$data"
}

function Remove-NmHive {
    param([string]$Key)
    return ("$Key" -replace '^(HKLM|HKCU|HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER)\\', '')
}

function Get-NmAccountLabel {
    # A SID shown by name when it is a well-known one or a domain built-in group; otherwise the SID.
    param([string]$Sid)
    foreach ($k in $script:NmWellKnownSids.Keys) { if ($script:NmWellKnownSids[$k] -eq $Sid) { return $k } }
    $s = Get-NmSession
    if ($s.DomainSid -and $Sid -like "$($s.DomainSid)-*") {
        $rid = [int]($Sid.Substring("$($s.DomainSid)".Length + 1))
        foreach ($k in $script:NmDomainRids.Keys) { if ($script:NmDomainRids[$k] -eq $rid) { return $k } }
    }
    return $Sid
}

function ConvertTo-NmMemberKey {
    # A member as compared: a SID upper case without '*', a name lower case.
    param([string]$Member)
    $m = "$Member".Trim()
    if ($m -match '^\*?(S-1-[0-9-]+)$') { return $Matches[1].ToUpper() }
    return $m.ToLower()
}

function Get-NmGpoLiveItem {
    <#
    .SYNOPSIS
        Everything a GPO sets that the baselines can describe, from its files: Ident, Kind, Label,
        Value (and Members for user rights and restricted groups).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($side in 'Computer', 'User') {
        $hive = if ($side -eq 'User') { 'HKCU' } else { 'HKLM' }
        foreach ($e in @(Read-NmGpoRegistryPol -Id $Id -Side $side)) {
            $out.Add([pscustomobject]@{ Ident = "policy|$($side.ToLower())|$($e.Key.ToLower())|$($e.ValueName.ToLower())"; Kind = 'Policy'
                Label = "$hive\$($e.Key)\$($e.ValueName)"; Value = (Get-NmRegItemValue -Type $e.Type -Value $e.Value); Members = $null })
        }
        foreach ($e in @(Read-NmGpoPrefRegistry -Id $Id -Side $side)) {
            $out.Add([pscustomobject]@{ Ident = "pref|$($side.ToLower())|$("$($e.Hive)\$($e.Key)".ToLower())|$($e.ValueName.ToLower())"; Kind = 'PrefRegistry'
                Label = "$($e.Hive)\$($e.Key)\$($e.ValueName) ($($e.Action))"; Value = (Get-NmRegItemValue -Type $e.Type -Value $e.Value); Members = $null })
        }
    }
    $inf = Read-NmGpoGptTmpl -Id $Id
    $rhs = { param($line) if ($line -match '^[^=]*=\s*(.*)$') { $Matches[1].Trim() } else { '' } }
    $lhs = { param($line) if ($line -match '^\s*([^=]+?)\s*=') { $Matches[1] } else { $line } }
    if ($inf.Contains('Registry Values')) {
        foreach ($l in $inf['Registry Values'].Values) {
            $out.Add([pscustomobject]@{ Ident = "secopt|$((& $lhs $l).ToLower())"; Kind = 'SecurityOption'; Label = (& $lhs $l); Value = (& $rhs $l); Members = $null })
        }
    }
    if ($inf.Contains('System Access')) {
        foreach ($l in $inf['System Access'].Values) {
            $out.Add([pscustomobject]@{ Ident = "sysaccess|$((& $lhs $l).ToLower())"; Kind = 'SystemAccess'; Label = (& $lhs $l); Value = ((& $rhs $l).Trim('"')); Members = $null })
        }
    }
    if ($inf.Contains('Privilege Rights')) {
        foreach ($l in $inf['Privilege Rights'].Values) {
            $members = @((& $rhs $l) -split ',' | Where-Object { $_.Trim() } | ForEach-Object { ConvertTo-NmMemberKey -Member $_ })
            $out.Add([pscustomobject]@{ Ident = "right|$((& $lhs $l).ToLower())"; Kind = 'UserRight'; Label = (& $lhs $l); Value = ''; Members = $members })
        }
    }
    if ($inf.Contains('Group Membership')) {
        foreach ($l in $inf['Group Membership'].Values) {
            $left = & $lhs $l
            if ($left -notmatch '^(.+)__(Members|Memberof)$') { continue }
            $g = ConvertTo-NmMemberKey -Member $Matches[1]
            $which = $Matches[2].ToLower()
            $members = @((& $rhs $l) -split ',' | Where-Object { $_.Trim() } | ForEach-Object { ConvertTo-NmMemberKey -Member $_ })
            $out.Add([pscustomobject]@{ Ident = "group|$($g.ToLower())|$which"; Kind = 'RestrictedGroup'; Label = "$(Get-NmAccountLabel -Sid $g) ($which)"; Value = ''; Members = $members })
        }
    }
    if ($inf.Contains('Service General Setting')) {
        foreach ($l in $inf['Service General Setting'].Values) {
            if ($l -notmatch '^\s*"([^"]+)"\s*,\s*(\d+)') { continue }
            $mode = switch ([int]$Matches[2]) { 2 { 'Automatic' } 3 { 'Manual' } 4 { 'Disabled' } default { "$_" } }
            $out.Add([pscustomobject]@{ Ident = "service|$($Matches[1].ToLower())"; Kind = 'Service'; Label = $Matches[1]; Value = $mode; Members = $null })
        }
    }
    foreach ($a in @(Read-NmGpoAudit -Id $Id)) {
        $name = @($script:NmBaselineAuditValues.Keys | Where-Object { $script:NmBaselineAuditValues[$_] -eq $a.Value })[0]
        $label = Get-NmAuditSubcategoryName -Guid $a.Guid
        if (-not $label) { $label = $a.Subcategory }
        $out.Add([pscustomobject]@{ Ident = "audit|$($a.Guid)"; Kind = 'Audit'; Label = $label; Value = "$name"; Members = $null })
    }
    return $out.ToArray()
}

function Get-NmBaselineExpectedItem {
    <#
    .SYNOPSIS
        What one baseline setting expects, as items (Ident, Label, Value, Members), placeholders kept.
        Fixed members are resolved to SIDs where they can be; a {Param} member matches any one account.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Setting)
    $s = $Setting
    $side = "$($s.Side)".ToLower()
    $member = {
        param($m)
        if ("$m" -match '^\{[A-Za-z][A-Za-z0-9]*\}$') { return "$m" }
        try { return (ConvertTo-NmMemberKey -Member (Resolve-NmAccountSid -Name "$m")) } catch { return (ConvertTo-NmMemberKey -Member "$m") }
    }
    switch ("$($s.Kind)") {
        'Policy' {
            foreach ($v in @($s.Values)) {
                $key = Remove-NmHive -Key "$($v.Key)"
                [pscustomobject]@{ Ident = "policy|$side|$($key.ToLower())|$("$($v.ValueName)".ToLower())"; Label = "$($v.Key)\$($v.ValueName)"; Value = (Get-NmRegItemValue -Type "$($v.Type)" -Value $v.Value); Members = $null }
            }
        }
        'PrefRegistry' {
            [pscustomobject]@{ Ident = "pref|$side|$("$($s.Hive)\$($s.Key)".ToLower())|$("$($s.ValueName)".ToLower())"; Label = "$($s.Hive)\$($s.Key)\$($s.ValueName)"; Value = (Get-NmRegItemValue -Type "$($s.Type)" -Value $s.Value); Members = $null }
        }
        'SecurityOption' {
            $code = $script:NmSecTypeCodes["$($s.Type)"]
            $data = switch ("$($s.Type)") {
                'String'      { Format-NmInfString -Text "$($s.Value)" }
                'MultiString' { (@($s.Value) | ForEach-Object { "$_".Replace(',', '\,') }) -join ',' }
                default       { ConvertTo-NmDwordText -Value $s.Value }
            }
            [pscustomobject]@{ Ident = "secopt|$("$($s.Key)".ToLower())"; Label = "$($s.Key)"; Value = "$code,$data"; Members = $null }
        }
        'SystemAccess' {
            [pscustomobject]@{ Ident = "sysaccess|$("$($s.Name)".ToLower())"; Label = "$($s.Name)"; Value = "$($s.Value)"; Members = $null }
        }
        'UserRight' {
            [pscustomobject]@{ Ident = "right|$("$($s.Right)".ToLower())"; Label = "$($s.Right)"; Value = ''; Members = @(foreach ($m in @($s.Members | Where-Object { "$_".Trim() })) { & $member $m }) }
        }
        'RestrictedGroup' {
            $g = & $member $s.Group
            [pscustomobject]@{ Ident = "group|$($g.ToLower())|members"; Label = "$($s.Group) (members)"; Value = ''; Members = @(foreach ($m in @($s.Members | Where-Object { "$_".Trim() })) { & $member $m }) }
            [pscustomobject]@{ Ident = "group|$($g.ToLower())|memberof"; Label = "$($s.Group) (memberof)"; Value = ''; Members = @(foreach ($m in @($s.MemberOf | Where-Object { "$_".Trim() })) { & $member $m }) }
        }
        'Audit' {
            $guid = Get-NmAuditSubcategoryGuid -Name "$($s.Subcategory)"
            [pscustomobject]@{ Ident = "audit|$guid"; Label = "$($s.Subcategory)"; Value = "$($s.Setting)"; Members = $null }
        }
        'Service' {
            [pscustomobject]@{ Ident = "service|$("$($s.Service)".ToLower())"; Label = "$($s.Service)"; Value = "$($s.StartMode)"; Members = $null }
        }
    }
}

function Test-NmTemplateMatch {
    <#
    .SYNOPSIS
        Does an actual value match an expected one that may hold {Param} placeholders?
        Returns $null for no, or a hashtable of the parameter values it found (empty: no parameters).
    #>
    [CmdletBinding()]
    param([string]$Template, [string]$Actual)
    $names = New-Object System.Collections.Generic.List[string]
    $pattern = New-Object System.Text.StringBuilder
    [void]$pattern.Append('^')
    $pos = 0
    foreach ($m in [regex]::Matches($Template, '\{\{|\}\}|\{([A-Za-z][A-Za-z0-9]*)\}')) {
        [void]$pattern.Append([regex]::Escape($Template.Substring($pos, $m.Index - $pos)))
        if ($m.Value -eq '{{') { [void]$pattern.Append('\{') }
        elseif ($m.Value -eq '}}') { [void]$pattern.Append('\}') }
        else { [void]$pattern.Append('(.*?)'); $names.Add($m.Groups[1].Value) }
        $pos = $m.Index + $m.Length
    }
    [void]$pattern.Append([regex]::Escape($Template.Substring($pos)))
    [void]$pattern.Append('$')
    $r = [regex]::Match($Actual, $pattern.ToString(), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $r.Success) { return $null }
    $found = @{}
    for ($k = 0; $k -lt $names.Count; $k++) { $found[$names[$k]] = $r.Groups[$k + 1].Value }
    return $found
}

function Format-NmMemberList {
    param([string[]]$Members)
    return ((@($Members) | ForEach-Object { if ($_ -match '^S-1-') { Get-NmAccountLabel -Sid $_ } else { $_ } }) -join ', ')
}

function Compare-NmGpoWithBaseline {
    <#
    .SYNOPSIS
        One GPO against one baseline: a row per baseline setting, then a row per extra setting.
    .DESCRIPTION
        Result per row:
        - Matches: set as the baseline says (a parameter's value is shown in Detail);
        - Different: set to something else, or only some of its values are set;
        - Missing: not set at all;
        - Not filled: a {Param} placeholder is still in the GPO;
        - Extra: set in the GPO, not in the baseline;
        - Note: about the GPO itself (built from an older version of the baseline).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Gpo, [Parameter(Mandatory)]$Baseline)
    $name = "$($Gpo.DisplayName)"
    $live = @(Get-NmGpoLiveItem -Id "$($Gpo.Id)")
    $byIdent = @{}
    foreach ($l in $live) { $byIdent[$l.Ident] = $l }
    $used = @{}
    $rows = New-Object System.Collections.Generic.List[object]
    $declared = @($Baseline.Parameters | ForEach-Object { "$($_.Name)" })

    $stamp = Read-NmBaselineStamp -Comment "$($Gpo.Description)"
    if ($stamp -and $stamp.Id -eq $Baseline.Id -and $stamp.Version -ne $Baseline.Version) {
        $rows.Add([pscustomobject]@{ Gpo = $name; Baseline = $Baseline.Name; Setting = '(the GPO)'; SettingId = ''; Kind = ''; Expected = "baseline $($Baseline.Version)"
            Actual = "built from $($stamp.Version)"; Result = 'Note'; Detail = "Built from version $($stamp.Version) of the baseline; it is now $($Baseline.Version). The differences below show what changed." })
    }

    foreach ($s in @($Baseline.Settings)) {
        $items = @(Get-NmBaselineExpectedItem -Setting $s)
        $exp = New-Object System.Collections.Generic.List[string]
        $act = New-Object System.Collections.Generic.List[string]
        $params = New-Object System.Collections.Generic.List[string]
        $states = New-Object System.Collections.Generic.List[string]
        foreach ($it in $items) {
            $l = $byIdent[$it.Ident]
            $isList = ($null -ne $it.Members)
            $expText = if ($isList) { Format-NmMemberList -Members $it.Members } else { $it.Value }
            $exp.Add($(if ($items.Count -gt 1) { "$($it.Label) = $expText" } else { $expText }))
            if (-not $l) {
                $act.Add($(if ($items.Count -gt 1) { "$($it.Label) = (not set)" } else { '(not set)' }))
                $states.Add('Missing'); continue
            }
            $used[$it.Ident] = $true
            $actText = if ($isList) { Format-NmMemberList -Members $l.Members } else { $l.Value }
            $act.Add($(if ($items.Count -gt 1) { "$($it.Label) = $actText" } else { $actText }))
            $notFilled = @($declared | Where-Object { "$actText" -like "*{$_}*" })
            if ($notFilled.Count) { $states.Add('Not filled'); continue }
            if ($isList) {
                $wild = @($it.Members | Where-Object { $_ -match '^\{[A-Za-z][A-Za-z0-9]*\}$' })
                $fixed = @($it.Members | Where-Object { $_ -notmatch '^\{[A-Za-z][A-Za-z0-9]*\}$' })
                $liveMembers = @($l.Members)
                $missingFixed = @($fixed | Where-Object { $liveMembers -notcontains $_ })
                $others = @($liveMembers | Where-Object { $fixed -notcontains $_ })
                if ($missingFixed.Count -or $others.Count -ne $wild.Count) { $states.Add('Different'); continue }
                if ($wild.Count) { $params.Add("$($wild -join ', ') = $(Format-NmMemberList -Members $others)") }
                $states.Add('Matches'); continue
            }
            $m = Test-NmTemplateMatch -Template "$($it.Value)" -Actual "$($l.Value)"
            if ($null -eq $m) { $states.Add('Different'); continue }
            foreach ($k in $m.Keys) { $params.Add("$k = $($m[$k])") }
            $states.Add('Matches')
        }
        $result = if ($states -contains 'Not filled') { 'Not filled' }
            elseif (@($states | Where-Object { $_ -eq 'Missing' }).Count -eq $states.Count) { 'Missing' }
            elseif ($states -contains 'Different' -or $states -contains 'Missing') { 'Different' }
            else { 'Matches' }
        $rows.Add([pscustomobject]@{ Gpo = $name; Baseline = $Baseline.Name; Setting = "$($s.Title)"; SettingId = "$($s.Id)"; Kind = "$($s.Kind)"
            Expected = ($exp -join '; '); Actual = ($act -join '; '); Result = $result; Detail = ($params -join '; ') })
    }
    foreach ($l in $live) {
        if ($used.ContainsKey($l.Ident)) { continue }
        $actText = if ($null -ne $l.Members) { Format-NmMemberList -Members $l.Members } else { $l.Value }
        $rows.Add([pscustomobject]@{ Gpo = $name; Baseline = $Baseline.Name; Setting = $l.Label; SettingId = ''; Kind = $l.Kind
            Expected = '(not in the baseline)'; Actual = $actText; Result = 'Extra'; Detail = '' })
    }
    return $rows.ToArray()
}

# ---------------------------------------------------------------------------
# Where a GPO applies (issue #36): its links and status, from its XML report
# ---------------------------------------------------------------------------
function Get-NmGpoReportXml {
    # The GPO's report as XML text (Get-GPOReport; a wrapper so the tests can stand in for it).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    $gp = Get-NmGPParams
    return "$(Get-GPOReport -Guid $Id -ReportType Xml @gp -ErrorAction Stop)"
}

function ConvertFrom-NmGpoReportXml {
    <#
    .SYNOPSIS
        From a GPO's XML report: Links (Path as shown, Enabled, Enforced), ComputerEnabled, UserEnabled.
        A link's path is shown without the domain ("Domain Controllers"; the root as "Domain root").
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Xml, [string]$Domain = (Get-NmSession).Domain)
    $x = [xml]$Xml
    $g = $x.GPO
    $links = @(foreach ($l in @($g.LinksTo | Where-Object { $_ })) {
        $path = "$($l.SOMPath)"
        if ($Domain -and $path -eq $Domain) { $path = 'Domain root' }
        elseif ($Domain -and $path.StartsWith("$Domain/")) { $path = $path.Substring($Domain.Length + 1) }
        [pscustomobject]@{ Path = $path; Enabled = ("$($l.Enabled)" -eq 'true'); Enforced = ("$($l.NoOverride)" -eq 'true') }
    })
    [pscustomobject]@{
        Links           = $links
        ComputerEnabled = ("$($g.Computer.Enabled)" -ne 'false')
        UserEnabled     = ("$($g.User.Enabled)" -ne 'false')
    }
}

function Format-NmGpoLinks {
    # "Domain Controllers; Devices/Member Servers (disabled); Domain root (enforced)", or "(not linked)".
    param([object[]]$Links = @())
    $l = @($Links | Where-Object { $_ })
    if (-not $l.Count) { return '(not linked)' }
    return (($l | ForEach-Object {
        $flags = @($(if (-not $_.Enabled) { 'disabled' }), $(if ($_.Enforced) { 'enforced' })) | Where-Object { $_ }
        "$($_.Path)$(if ($flags) { " ($($flags -join ', '))" })"
    }) -join '; ')
}

function Get-NmGpoApplyState {
    <#
    .SYNOPSIS
        Does a GPO apply anywhere, for the settings its baseline has? Result and Detail:
        - Not applied (red): linked, but the side the baseline uses (computer or user) is disabled;
        - Not linked (amber): linked nowhere, or every link disabled (may be on purpose: just built);
        - Linked (green).
        Linked somewhere other than the suggested links is only noted: links are chosen per client.
    #>
    [CmdletBinding()]
    param($Report, [string[]]$Sides = @('Computer'), [string[]]$Suggested = @())
    $links = @($Report.Links | Where-Object { $_ })
    $on = @($links | Where-Object { $_.Enabled })
    $off = @()
    if ($Sides -contains 'Computer' -and -not $Report.ComputerEnabled) { $off += 'computer' }
    if ($Sides -contains 'User' -and -not $Report.UserEnabled) { $off += 'user' }
    if ($on.Count -and $off.Count) {
        return [pscustomobject]@{ Result = 'Not applied'; Detail = "Its $($off -join ' and ') settings are disabled on the GPO, so the baseline's $($off -join ' and ') settings never apply." }
    }
    if (-not $links.Count) { return [pscustomobject]@{ Result = 'Not linked'; Detail = 'Linked nowhere: it applies to nothing yet.' } }
    if (-not $on.Count) { return [pscustomobject]@{ Result = 'Not linked'; Detail = 'Every link is disabled: it applies to nothing.' } }
    $note = ''
    $sugg = @($Suggested | Where-Object { $_ })
    if ($sugg.Count) {
        $missing = @($sugg | Where-Object { $s = $_; -not @($on | Where-Object { $_.Path -eq $s }).Count })
        if ($missing.Count) { $note = "Suggested links not used: $($missing -join ', ') (links are chosen per client)." }
    }
    return [pscustomobject]@{ Result = 'Linked'; Detail = $note }
}

# ---------------------------------------------------------------------------
# A GPO opened from a card: Microsoft's editor, or GPMC's full report
# ---------------------------------------------------------------------------
function Start-NmGpoEditor {
    # The Group Policy Management Editor on one GPO, on the session's DC (a wrapper for the tests).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $s = Get-NmSession
    $target = if ($s.Server) { "LDAP://$($s.Server)/$Path" } else { "LDAP://$Path" }
    Start-Process -FilePath 'gpme.msc' -ArgumentList "/gpobject:`"$target`""
    return $target
}

function Invoke-NmGpoCardEdit {
    # Card button "Edit GPO": opens the GPO in Microsoft's editor. The toolkit itself changes nothing.
    [CmdletBinding()]
    param($Row)
    if (-not $Row -or -not "$($Row.GpoPath)") { Write-NmLog 'This card has no GPO to open.' -Level WARN; return }
    $t = Start-NmGpoEditor -Path "$($Row.GpoPath)"
    Write-NmLog "Opened $($Row.Gpo) in the Group Policy Management Editor ($t). Compare again after editing." -Level INFO
}

function Save-NmGpoHtmlReport {
    # GPMC's own HTML report of a GPO, saved to a file (a wrapper for the tests).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Path)
    $gp = Get-NmGPParams
    Get-GPOReport -Guid $Id -ReportType Html -Path $Path @gp -ErrorAction Stop | Out-Null
    return $Path
}

function Invoke-NmGpoCardReport {
    # Card button "GPMC report": GPMC's own full HTML report of the GPO, saved in the reports folder and opened.
    [CmdletBinding()]
    param($Row)
    if (-not $Row -or -not "$($Row.GpoId)") { Write-NmLog 'This card has no GPO to show.' -Level WARN; return }
    $safe = ("$($Row.Gpo)" -replace '[^A-Za-z0-9 ._()-]', '_').Trim()
    $folder = Get-NmReportFolder
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
    $file = Join-Path $folder ("GPO_{0}_{1:yyyyMMdd-HHmmss}.html" -f $safe, (Get-Date))
    $p = Save-NmGpoHtmlReport -Id "$($Row.GpoId)" -Path $file
    Write-NmLog "GPO report for $($Row.Gpo): $p" -Level INFO
    Open-NmReport -Path $p
}

# ---------------------------------------------------------------------------
# The GPO in the app (View GPO): its XML report as one table per part (Computer: Security, ...)
# ---------------------------------------------------------------------------
$script:NmGpoViewSkip = @('Explain', 'Supported', 'SecurityDescriptor', 'SubcategoryGuid', 'PolicyTarget', 'GPOSettingOrder', 'Filters', 'Comment')
$script:NmAuditValueText = @{ '0' = 'No Auditing'; '1' = 'Success'; '2' = 'Failure'; '3' = 'Success and Failure' }

function Get-NmXmlChild {
    # The child elements of an XML node with a local name (any namespace).
    param($Node, [string]$Name)
    @($Node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.LocalName -eq $Name })
}

function Get-NmXmlChildText {
    param($Node, [string]$Name)
    $c = @(Get-NmXmlChild -Node $Node -Name $Name)
    if ($c.Count) { return "$($c[0].InnerText)".Trim() }
    return ''
}

function ConvertTo-NmGpoViewRow {
    <#
    .SYNOPSIS
        One setting element of a GPO report as Setting and Value, whatever its extension: security
        options (shown as GPMC words), Administrative Templates (category, state, and their own
        fields), audit, services, user rights (members), registry preferences (key, value, action).
    #>
    param([Parameter(Mandatory)]$Node)
    $ln = $Node.LocalName
    # Registry preferences: every Properties under the item.
    $props = @($Node.SelectNodes('.//*[local-name()="Properties"]') | Where-Object { $_.Attributes['key'] })
    if ($props.Count) {
        foreach ($p in $props) {
            $act = @{ C = 'Create'; R = 'Replace'; U = 'Update'; D = 'Delete' }["$($p.GetAttribute('action'))"]
            [pscustomobject]@{ Setting = "$($p.GetAttribute('hive'))\$($p.GetAttribute('key'))\$($p.GetAttribute('name'))"; Value = "$($p.GetAttribute('type')) = $($p.GetAttribute('value'))$(if ($act) { " ($act)" })" }
        }
        return
    }
    $disp = @(Get-NmXmlChild -Node $Node -Name 'Display')[0]
    $title = ''
    foreach ($n in 'Name', 'SubcategoryName', 'KeyName') {
        if ($n -eq 'Name' -and $disp) { $t = Get-NmXmlChildText -Node $disp -Name 'Name'; if ($t) { $title = $t; break } }
        $t = Get-NmXmlChildText -Node $Node -Name $n
        if ($t) { $title = $t; break }
    }
    if (-not $title) { $title = $ln }
    $cat = Get-NmXmlChildText -Node $Node -Name 'Category'
    if ($cat) { $title = "${cat}: $title" }
    $vals = New-Object System.Collections.Generic.List[string]
    $state = Get-NmXmlChildText -Node $Node -Name 'State'
    if ($state) { $vals.Add($state) }
    if ($disp) {
        foreach ($d in 'DisplayString', 'DisplayBoolean', 'DisplayNumber') { $t = Get-NmXmlChildText -Node $disp -Name $d; if ($t) { $vals.Add($(if ($d -eq 'DisplayBoolean') { if ($t -eq 'true') { 'Enabled' } else { 'Disabled' } } else { $t })) } }
        $f = @(Get-NmXmlChild -Node $disp -Name 'DisplayFields')
        foreach ($x in @(if ($f.Count) { $f[0].ChildNodes })) { if ($x.NodeType -eq 'Element') { $vals.Add("$(Get-NmXmlChildText -Node $x -Name 'Name') = $(Get-NmXmlChildText -Node $x -Name 'Value')") } }
    } else {
        foreach ($n in 'SettingString', 'SettingNumber', 'SettingBoolean') { $t = Get-NmXmlChildText -Node $Node -Name $n; if ($t) { $vals.Add($t) } }
    }
    $mode = Get-NmXmlChildText -Node $Node -Name 'StartupMode'
    if ($mode) { $vals.Add($mode) }
    $audit = Get-NmXmlChildText -Node $Node -Name 'SettingValue'
    if ($audit) { $vals.Add($(if ($script:NmAuditValueText.ContainsKey($audit)) { $script:NmAuditValueText[$audit] } else { $audit })) }
    $members = @(foreach ($m in @(Get-NmXmlChild -Node $Node -Name 'Member')) { Get-NmXmlChildText -Node $m -Name 'Name' })
    if ($members.Count) { $vals.Add(($members | Where-Object { $_ }) -join ', ') }
    # Administrative Templates: the policy's own fields (text, numbers, lists, tick boxes).
    foreach ($k in 'EditText', 'Numeric', 'DropDownList', 'CheckBox', 'ListBox') {
        foreach ($e in @(Get-NmXmlChild -Node $Node -Name $k)) {
            $nm = Get-NmXmlChildText -Node $e -Name 'Name'
            $v = Get-NmXmlChildText -Node $e -Name 'Value'
            if (-not $v) { $v = Get-NmXmlChildText -Node $e -Name 'State' }
            if (-not $v) { $sel = @(Get-NmXmlChild -Node $e -Name 'Value'); $v = "$(if ($sel.Count) { $sel[0].InnerText })".Trim() }
            if ($nm) { $vals.Add("$nm = $v") }
        }
    }
    [pscustomobject]@{ Setting = $title; Value = $(if ($vals.Count) { $vals -join '; ' } else { '(set)' }) }
}

function ConvertTo-NmGpoViewModel {
    <#
    .SYNOPSIS
        A GPO's XML report as what View GPO shows: Heading, Summary (status, links, comment) and
        Sections, one per side and extension ("Computer: Security"), each with Setting/Value rows.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Xml, [string]$Domain = (Get-NmSession).Domain)
    $x = [xml]$Xml
    $g = $x.GPO
    $rep = ConvertFrom-NmGpoReportXml -Xml $Xml -Domain $Domain
    $sections = New-Object System.Collections.Generic.List[object]
    foreach ($side in 'Computer', 'User') {
        $part = @(Get-NmXmlChild -Node $g -Name $side)[0]
        if (-not $part) { continue }
        foreach ($ed in @(Get-NmXmlChild -Node $part -Name 'ExtensionData')) {
            $ename = Get-NmXmlChildText -Node $ed -Name 'Name'
            $ext = @(Get-NmXmlChild -Node $ed -Name 'Extension')[0]
            if (-not $ext) { continue }
            $rows = @(foreach ($n in @($ext.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $script:NmGpoViewSkip -notcontains $_.LocalName })) { ConvertTo-NmGpoViewRow -Node $n })
            if ($rows.Count) { $sections.Add([pscustomobject]@{ Title = "${side}: $ename"; Rows = $rows }) }
        }
    }
    $status = "Computer settings $(if ($rep.ComputerEnabled) { 'enabled' } else { 'DISABLED' }); user settings $(if ($rep.UserEnabled) { 'enabled' } else { 'DISABLED' })"
    $comment = "$($g.Description)".Trim()
    [pscustomobject]@{
        Heading  = "$($g.Name)"
        Summary  = (@("Links: $(Format-NmGpoLinks -Links $rep.Links)", $status, $(if ($comment) { "Comment: $comment" })) | Where-Object { $_ }) -join "`r`n"
        Sections = $sections.ToArray()
    }
}

function Show-NmGpoViewer {
    # The model in the app's viewer: a tab per section, each a table to sort, copy and export.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Model)
    $caps = @(foreach ($s in $Model.Sections) { [pscustomobject]@{ Kind = 'Table'; Title = $s.Title; Columns = @('Setting', 'Value'); Rows = @($s.Rows) } })
    if (-not $caps.Count) { $caps = @([pscustomobject]@{ Kind = 'Table'; Title = 'Settings'; Columns = @('Setting', 'Value'); Rows = @([pscustomobject]@{ Setting = '(none)'; Value = 'This GPO has no settings.' }) }) }
    [void](Show-NmGuiDialog -Title "View GPO: $($Model.Heading)" -Heading $Model.Heading -Text $Model.Summary -NoInput -Captures $caps)
}

function Invoke-NmGpoCardView {
    # Card button "View GPO": the GPO's settings in the app, a tab per part (GPMC report has everything).
    [CmdletBinding()]
    param($Row)
    if (-not $Row -or -not "$($Row.GpoId)") { Write-NmLog 'This card has no GPO to show.' -Level WARN; return }
    $m = ConvertTo-NmGpoViewModel -Xml (Get-NmGpoReportXml -Id "$($Row.GpoId)")
    Show-NmGpoViewer -Model $m
}
