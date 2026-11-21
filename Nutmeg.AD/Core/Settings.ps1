# ---------------------------------------------------------------------------
# Settings.ps1 - the technician's own settings (Main menu > Settings)
#
# - One file per Windows user: %APPDATA%\NutmegAD\Settings.json (NUTMEG_AD_SETTINGS_FILE moves it).
#   It is not under C:\Temp, because the folders it sets can move, and C:\Temp is shared by every
#   user of the computer.
# - Secrets (none yet) are encrypted with Windows DPAPI: only this Windows user on this computer
#   can read them back.
# - An environment variable always wins over a saved value, so scripted runs keep working.
# ---------------------------------------------------------------------------

$script:NmSettingsData = $null
$script:NmSettingsTestFile = $null   # the tests' own file

# Every setting: where it shows, its type and limits, and the environment variable that wins over it.
# Type: Secret, Int, Choice, Bool, Folder, List. Config: the $NmConfig property it sets, if any.
$script:NmSettingDefs = @(
    [pscustomobject]@{ Key = 'ExportRoot'; Section = 'Folders'; Label = 'Export folder'; Type = 'Folder'; Default = '{Root}'; EnvVar = ''; Config = 'ExportRoot'; Min = 0; Max = 0; Choices = @()
        Help = 'Where CSV and TXT exports are written.' }
    [pscustomobject]@{ Key = 'LogRetentionDays'; Section = 'Folders'; Label = 'Keep session logs for (days, 0 = keep all)'; Type = 'Int'; Default = 0; EnvVar = ''; Config = ''; Min = 0; Max = 3650; Choices = @()
        Help = 'Session logs older than this are deleted when the toolkit starts. Run history is never deleted.' }
    [pscustomobject]@{ Key = 'BulkConfirmCount'; Section = 'Safety'; Label = 'Targets before the domain name must be typed'; Type = 'Int'; Default = 25; EnvVar = ''; Config = 'BulkConfirmCount'; Min = 1; Max = 10000; Choices = @()
        Help = 'A change to more objects than this needs the domain''s short name typed, not just Y.' }
)
$script:NmSettingSections = @('Folders', 'Safety')

# ---------------------------------------------------------------------------
# The file
# ---------------------------------------------------------------------------
function Get-NmSettingsPath {
    if ($script:NmSettingsTestFile) { return $script:NmSettingsTestFile }
    if ($env:NUTMEG_AD_SETTINGS_FILE) { return $env:NUTMEG_AD_SETTINGS_FILE }
    $base = if ($script:NmOnWindows -and $env:APPDATA) { $env:APPDATA } else { Join-Path $HOME '.config' }
    return (Join-Path (Join-Path $base 'NutmegAD') 'Settings.json')
}

function New-NmSettingsData {
    [pscustomobject]@{ Values = [pscustomobject]@{}; Secrets = [pscustomobject]@{} }
}

function Get-NmSettingsData {
    <#
    .SYNOPSIS
        The saved settings (Values, Secrets encrypted), read once and kept. A damaged file
        is reported and treated as empty; it is only replaced when something is saved.
    #>
    [CmdletBinding()]
    param([switch]$Reload)
    if ($script:NmSettingsData -and -not $Reload) { return $script:NmSettingsData }
    $d = New-NmSettingsData
    $p = Get-NmSettingsPath
    if (Test-Path $p) {
        try {
            $raw = Get-Content -Path $p -Raw -ErrorAction Stop
            if ("$raw".Trim()) {
                $j = ConvertFrom-Json -InputObject $raw
                foreach ($n in 'Values', 'Secrets') {
                    if ($j.PSObject.Properties[$n] -and $j.$n -is [pscustomobject]) { $d.$n = $j.$n }
                }
            }
        } catch { Write-NmLog "Settings could not be read ($p): $($_.Exception.Message). Defaults are used." -Level WARN }
    }
    $script:NmSettingsData = $d
    return $d
}

function Save-NmSettingsData {
    $d = Get-NmSettingsData
    $p = Get-NmSettingsPath
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null }
    $d | ConvertTo-Json -Depth 6 | Set-Content -Path $p -Encoding UTF8 -ErrorAction Stop
}

function Set-NmObjectValue {
    # Adds or replaces one property on a settings object.
    param($Object, [string]$Name, $Value)
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Remove-NmObjectValue {
    param($Object, [string]$Name)
    if ($Object.PSObject.Properties[$Name]) { $Object.PSObject.Properties.Remove($Name) }
}

# ---------------------------------------------------------------------------
# Secrets (Windows DPAPI: this Windows user on this computer only)
# ---------------------------------------------------------------------------
function Protect-NmSecret {
    param([Parameter(Mandatory)][string]$Text)
    if (-not $script:NmOnWindows) { throw 'Saving a key or token needs Windows (it is encrypted for your Windows user).' }
    $sec = New-Object System.Security.SecureString
    foreach ($c in $Text.ToCharArray()) { $sec.AppendChar($c) }
    $sec.MakeReadOnly()
    return (ConvertFrom-SecureString -SecureString $sec)
}

function Unprotect-NmSecret {
    param([Parameter(Mandatory)][string]$Encrypted)
    $sec = ConvertTo-SecureString -String $Encrypted
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# ---------------------------------------------------------------------------
# Reading and changing settings
# ---------------------------------------------------------------------------
function Get-NmSettingDef {
    param([Parameter(Mandatory)][string]$Key)
    $d = @($script:NmSettingDefs | Where-Object { $_.Key -eq $Key })
    if (-not $d.Count) { throw "Unknown setting '$Key'." }
    return $d[0]
}

function Get-NmSettingDefault {
    param([Parameter(Mandatory)]$Def)
    if ($Def.Type -eq 'Folder') {
        $data = if ($script:NmConfig -and $script:NmConfig.DataRoot) { $script:NmConfig.DataRoot } else { Join-Path $script:NmDefaultRoot 'NutmegAD' }
        $v = "$($Def.Default)".Replace('{Root}', $script:NmDefaultRoot).Replace('{Data}', $data)
        if (-not $script:NmOnWindows) { $v = $v.Replace('\', [System.IO.Path]::DirectorySeparatorChar) }
        return $v
    }
    if ($Def.Type -eq 'List') { return @() }
    return $Def.Default
}

function ConvertTo-NmSettingValue {
    <#
    .SYNOPSIS
        Checks a value for a setting and returns it in its type, or throws a plain reason.
    #>
    param([Parameter(Mandatory)]$Def, $Value)
    switch ($Def.Type) {
        'Int' {
            $n = 0
            if (-not [int]::TryParse("$Value".Trim(), [ref]$n)) { throw "$($Def.Label): '$Value' is not a whole number." }
            if ($n -lt $Def.Min -or $n -gt $Def.Max) { throw "$($Def.Label): $n is outside $($Def.Min)-$($Def.Max)." }
            return $n
        }
        'Bool' {
            if ($Value -is [bool]) { return $Value }
            switch -Regex ("$Value".Trim()) { '^(?i)(1|true|yes|y|on)$' { return $true } '^(?i)(0|false|no|n|off)$' { return $false } }
            throw "$($Def.Label): '$Value' is not yes or no."
        }
        'Choice' {
            $m = @($Def.Choices | Where-Object { $_ -eq "$Value".Trim() })
            if (-not $m.Count) { throw "$($Def.Label): '$Value' is not one of $($Def.Choices -join ', ')." }
            return $m[0]
        }
        'Folder' {
            $p = "$Value".Trim().Trim('"')
            if (-not $p -or -not [System.IO.Path]::IsPathRooted($p)) { throw "$($Def.Label): give a full path (C:\Temp, \\server\share)." }
            if ($p.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) { throw "$($Def.Label): the path has characters Windows does not allow." }
            return $p.TrimEnd('\', '/')
        }
        'List' {
            $items = @(@($Value) | ForEach-Object { "$_" -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
            return , $items
        }
        default { return "$Value" }
    }
}

function Get-NmSettingSource {
    # Environment, Saved or Default: where a setting's value comes from.
    param([Parameter(Mandatory)][string]$Key)
    $def = Get-NmSettingDef -Key $Key
    if ($def.EnvVar -and [Environment]::GetEnvironmentVariable($def.EnvVar)) { return 'Environment' }
    $d = Get-NmSettingsData
    $bag = if ($def.Type -eq 'Secret') { $d.Secrets } else { $d.Values }
    if ($bag.PSObject.Properties[$Key]) { return 'Saved' }
    return 'Default'
}

function Get-NmSetting {
    <#
    .SYNOPSIS
        A setting's value: the environment variable if set, else the saved value, else the default.
    .EXAMPLE
        $days = Get-NmSetting -Key LogRetentionDays
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key)
    $def = Get-NmSettingDef -Key $Key
    if ($def.EnvVar) {
        $e = [Environment]::GetEnvironmentVariable($def.EnvVar)
        if ($e) { try { return (ConvertTo-NmSettingValue -Def $def -Value $e) } catch { Write-NmLog "$($def.EnvVar): $($_.Exception.Message)" -Level WARN } }
    }
    $d = Get-NmSettingsData
    if ($def.Type -eq 'Secret') {
        $p = $d.Secrets.PSObject.Properties[$Key]
        if ($p -and "$($p.Value)") {
            try { return (Unprotect-NmSecret -Encrypted "$($p.Value)") }
            catch { Write-NmLog "The saved $($def.Label) could not be read for $env:USERNAME on this computer: $($_.Exception.Message)" -Level WARN }
        }
        return ''
    }
    $p = $d.Values.PSObject.Properties[$Key]
    if ($p) {
        try { return (ConvertTo-NmSettingValue -Def $def -Value $p.Value) }
        catch { Write-NmLog "Saved setting ignored: $($_.Exception.Message)" -Level WARN }
    }
    if ($def.Type -eq 'List') { return @() }
    return (Get-NmSettingDefault -Def $def)
}

function Set-NmSetting {
    <#
    .SYNOPSIS
        Checks and saves a setting, and applies it at once. Secrets are saved encrypted.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key, [AllowEmptyString()][AllowEmptyCollection()]$Value)
    $def = Get-NmSettingDef -Key $Key
    $d = Get-NmSettingsData
    if ($def.Type -eq 'Secret') {
        $t = "$Value".Trim()
        if (-not $t) { throw "$($def.Label): nothing to save (use Clear to remove it)." }
        Set-NmObjectValue -Object $d.Secrets -Name $Key -Value (Protect-NmSecret -Text $t)
    } else {
        Set-NmObjectValue -Object $d.Values -Name $Key -Value (ConvertTo-NmSettingValue -Def $def -Value $Value)
    }
    Save-NmSettingsData
    Update-NmConfigFromSetting
    $shown = if ($def.Type -eq 'Secret') { 'saved (encrypted)' } else { Format-NmSettingValue -Key $Key }
    Write-NmLog "Setting changed: $($def.Label) = $shown." -Level SUCCESS
    if ($def.EnvVar -and [Environment]::GetEnvironmentVariable($def.EnvVar)) {
        Write-NmLog "$($def.EnvVar) is set in this computer's environment, and it wins over the saved value." -Level WARN
    }
}

function Clear-NmSetting {
    # Removes a saved value, so the default (or the environment variable) applies again.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Key)
    $def = Get-NmSettingDef -Key $Key
    $d = Get-NmSettingsData
    Remove-NmObjectValue -Object $d.Values -Name $Key
    Remove-NmObjectValue -Object $d.Secrets -Name $Key
    Save-NmSettingsData
    Update-NmConfigFromSetting
    Write-NmLog "Setting cleared: $($def.Label) (now $(Format-NmSettingValue -Key $Key))." -Level SUCCESS
}

function Format-NmSettingValue {
    # A setting's value for the screen; secrets show only whether they are set.
    param([Parameter(Mandatory)][string]$Key)
    $def = Get-NmSettingDef -Key $Key
    $v = Get-NmSetting -Key $Key
    switch ($def.Type) {
        'Secret' { if ("$v") { return 'set' } else { return 'not set' } }
        'Bool'   { if ($v) { return 'on' } else { return 'off' } }
        'List'   { if (@($v).Count) { return (@($v) -join ', ') } else { return '(none)' } }
        'Choice' { return "$v" }
        default  { return "$v" }
    }
}

function Update-NmConfigFromSetting {
    # Copies the settings that older code reads from $NmConfig into it.
    foreach ($def in @($script:NmSettingDefs | Where-Object { $_.Config })) {
        try { $script:NmConfig.($def.Config) = Get-NmSetting -Key $def.Key }
        catch { Write-NmLog "Setting $($def.Key) not applied: $($_.Exception.Message)" -Level WARN }
    }
}

# ---------------------------------------------------------------------------
# IP addresses and ranges (for baseline parameters such as a management range)
# ---------------------------------------------------------------------------
function Test-NmIpRangeText {
    # True for an IP address or an address/prefix range.
    param([string]$Text)
    $ip = $null
    $parts = "$Text".Trim() -split '/'
    if ($parts.Count -gt 2 -or -not [System.Net.IPAddress]::TryParse($parts[0], [ref]$ip)) { return $false }
    if ($parts.Count -eq 1) { return $true }
    $n = 0
    if (-not [int]::TryParse($parts[1], [ref]$n)) { return $false }
    $max = if ($ip.GetAddressBytes().Length -eq 4) { 32 } else { 128 }
    return ($n -ge 0 -and $n -le $max)
}

function Test-NmIpInRange {
    <#
    .SYNOPSIS
        True when an address is one of the entries: an exact address, or inside an address/prefix range.
    #>
    param([string]$Ip, [AllowEmptyCollection()][string[]]$Range = @())
    $a = $null
    if (-not $Ip -or -not [System.Net.IPAddress]::TryParse("$Ip", [ref]$a)) { return $false }
    if ($a.IsIPv4MappedToIPv6) { $a = $a.MapToIPv4() }
    $ab = $a.GetAddressBytes()
    foreach ($r in @($Range)) {
        $parts = "$r".Trim() -split '/'
        $n = $null
        if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$n)) { continue }
        $nb = $n.GetAddressBytes()
        if ($nb.Length -ne $ab.Length) { continue }
        $bits = if ($parts.Count -gt 1) { [int]$parts[1] } else { $nb.Length * 8 }
        $match = $true
        for ($i = 0; $i -lt $nb.Length -and $bits -gt 0; $i++) {
            $take = [Math]::Min(8, $bits)
            $mask = [byte]((0xFF -shl (8 - $take)) -band 0xFF)
            if (($ab[$i] -band $mask) -ne ($nb[$i] -band $mask)) { $match = $false; break }
            $bits -= $take
        }
        if ($match) { return $true }
    }
    return $false
}

function Remove-NmOldLog {
    <#
    .SYNOPSIS
        Deletes session logs older than the Settings retention (0 keeps them all). Returns the count.
    #>
    [CmdletBinding()]
    param()
    $days = [int](Get-NmSetting -Key LogRetentionDays)
    if ($days -le 0) { return 0 }
    $dir = Join-Path $script:NmConfig.DataRoot 'Logs'
    if (-not (Test-Path $dir)) { return 0 }
    $cut = (Get-Date).AddDays(-$days)
    $old = @(Get-ChildItem -Path $dir -Filter 'NutmegAD_*.txt' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut -and $_.FullName -ne $script:NmLogPath })
    foreach ($f in $old) { try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop } catch { Write-NmLog "Old log not deleted ($($f.Name)): $($_.Exception.Message)" -Level DETAIL -NoConsole } }
    if ($old.Count) { Write-NmLog "Deleted $($old.Count) session log(s) older than $days days." -Level INFO -NoConsole }
    return $old.Count
}

function Get-NmStorageLocation {
    <#
    .SYNOPSIS
        Where everything is kept, one row each (What, Path, Exists).
    #>
    [CmdletBinding()]
    param()
    $data = $script:NmConfig.DataRoot
    $rows = [ordered]@{
        'Settings (this Windows user)' = Get-NmSettingsPath
        'Exports'                      = $script:NmConfig.ExportRoot
        'Data folder'                  = $data
        'Session logs'                 = Join-Path $data 'Logs'
        'This session''s log'          = $script:NmLogPath
        'Run history'                  = Join-Path $data 'History.csv'
    }
    foreach ($k in $rows.Keys) {
        $p = "$($rows[$k])"
        [pscustomobject]@{ What = $k; Path = $p; Exists = $(if ($p) { [bool](Test-Path -LiteralPath $p) } else { $false }) }
    }
}

function Get-NmSettingRow {
    <#
    .SYNOPSIS
        Every setting with its value and where it comes from (Section, Setting, Value, From).
    #>
    [CmdletBinding()]
    param([string]$Section)
    foreach ($def in @($script:NmSettingDefs | Where-Object { -not $Section -or $_.Section -eq $Section })) {
        $from = Get-NmSettingSource -Key $def.Key
        if ($from -eq 'Environment') { $from = "Environment ($($def.EnvVar))" }
        [pscustomobject]@{ Section = $def.Section; Setting = $def.Label; Value = (Format-NmSettingValue -Key $def.Key); From = $from; Key = $def.Key }
    }
}

# ---------------------------------------------------------------------------
# The Settings menu (console, and the window's cog: prompts become dialogs)
# ---------------------------------------------------------------------------
function Show-NmSettingsMenu {
    <#
    .SYNOPSIS
        Main menu > Settings: every setting by section, and where everything is stored.
    #>
    [CmdletBinding()]
    param()
    while ($true) {
        $opts = New-Object System.Collections.Generic.List[object]
        $i = 0
        foreach ($sec in $script:NmSettingSections) {
            $i++
            $opts.Add([pscustomobject]@{ Key = "$i"; Label = $sec; Detail = (Get-NmSettingSectionHint -Section $sec) })
        }
        $opts.Add([pscustomobject]@{ Key = 'A'; Label = 'Show all settings' })
        $opts.Add([pscustomobject]@{ Key = 'W'; Label = 'Where everything is stored' })
        $pick = Show-NmMenu -Title "Settings  ($(Get-NmSettingsPath))" -Back -Options $opts.ToArray()
        switch -Regex ($pick) {
            '^B$' { return }
            '^\d+$' { Show-NmSettingSection -Section $script:NmSettingSections[[int]$pick - 1] }
            '^A$' { Get-NmSettingRow | Format-Table Section, Setting, Value, From -AutoSize | Out-Host; Wait-NmKey }
            '^W$' { Get-NmStorageLocation | Format-Table What, Path, Exists -AutoSize -Wrap | Out-Host; Wait-NmKey }
        }
    }
}

function Get-NmSettingSectionHint {
    param([string]$Section)
    return (@($script:NmSettingDefs | Where-Object { $_.Section -eq $Section } | Select-Object -First 2 | ForEach-Object { $_.Label.ToLower() }) -join ', ')
}

function Show-NmSettingSection {
    param([Parameter(Mandatory)][string]$Section)
    while ($true) {
        $defs = @($script:NmSettingDefs | Where-Object { $_.Section -eq $Section })
        $opts = New-Object System.Collections.Generic.List[object]
        for ($i = 0; $i -lt $defs.Count; $i++) {
            $src = Get-NmSettingSource -Key $defs[$i].Key
            $tag = switch ($src) { 'Environment' { '(environment)' } 'Saved' { '' } default { '(default)' } }
            $opts.Add([pscustomobject]@{ Key = "$($i + 1)"; Label = "$($defs[$i].Label): $(Format-NmSettingValue -Key $defs[$i].Key)"; Tag = $tag })
        }
        $pick = Show-NmMenu -Title "Settings: $Section" -Back -Options $opts.ToArray()
        switch -Regex ($pick) {
            '^B$' { return }
            '^\d+$' { try { Edit-NmSetting -Key $defs[[int]$pick - 1].Key } catch [System.OperationCanceledException] { throw } catch { Write-NmLog $_.Exception.Message -Level ERROR; Wait-NmKey } }
        }
    }
}

function Edit-NmSetting {
    <#
    .SYNOPSIS
        Asks for a new value for one setting (by its type), or clears it back to the default.
    #>
    param([Parameter(Mandatory)][string]$Key)
    $def = Get-NmSettingDef -Key $Key
    Write-Host "$($def.Label): $(Format-NmSettingValue -Key $Key)" -ForegroundColor Cyan
    Write-Host $def.Help -ForegroundColor DarkGray
    if ((Get-NmSettingSource -Key $Key) -eq 'Environment') { Write-Host "$($def.EnvVar) is set in the environment and wins over anything saved here." -ForegroundColor Yellow }
    $saved = (Get-NmSettingsData).Values.PSObject.Properties[$Key] -or (Get-NmSettingsData).Secrets.PSObject.Properties[$Key]
    $opts = @([pscustomobject]@{ Key = '1'; Label = 'Change it' })
    if ($saved) { $opts += [pscustomobject]@{ Key = '2'; Label = $(if ($def.Type -eq 'Secret') { 'Clear it' } else { "Back to the default ($(Get-NmSettingDefault -Def $def))" }) } }
    $pick = Show-NmMenu -Title $def.Label -Back -NoClear -Options $opts
    if ($pick -eq 'B') { return }
    if ($pick -eq '2') { Clear-NmSetting -Key $Key; Wait-NmKey; return }
    $value = $null
    switch ($def.Type) {
        'Secret' { $value = Read-NmInput -Prompt "Paste the $($def.Label)"; if (-not $value) { return } }
        'Bool'   { $value = Read-NmYesNo -Prompt "Turn $($def.Label.ToLower()) on?" -Default $(if (Get-NmSetting -Key $Key) { 'Y' } else { 'N' }) }
        'Choice' {
            $c = @($def.Choices)
            $copts = @(for ($i = 0; $i -lt $c.Count; $i++) { [pscustomobject]@{ Key = "$($i + 1)"; Label = $c[$i] } })
            $p = Show-NmMenu -Title $def.Label -Back -NoClear -Options $copts
            if ($p -eq 'B') { return }
            $value = $c[[int]$p - 1]
        }
        'List' {
            Write-Host 'Type the whole list, comma-separated. Enter keeps it as it is.' -ForegroundColor DarkGray
            $t = Read-NmInput -Prompt $def.Label -Default ''
            if (-not $t) { return }
            $value = @($t -split ',')
        }
        default { $value = Read-NmInput -Prompt $def.Label -Default "$(Get-NmSetting -Key $Key)" }
    }
    Set-NmSetting -Key $Key -Value $value
    Wait-NmKey
}
