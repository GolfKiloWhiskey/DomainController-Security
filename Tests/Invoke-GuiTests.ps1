<#
.NOTES
    Author:  Cliff Waite
    Date:    11/21/2026
    Email:   cliff.ps@nutmegtech.com
    Version: 0.3.0

.SYNOPSIS
    Tests for the window's logic that does not need WPF: option forms built from tool parameters,
    form values to arguments, the results table, cards and filter, quick-answer buttons, and console
    output and prompts redirected to dialogs while the window is open.

.DESCRIPTION
    - Ported from the Nutmeg M365 Toolkit's window tests, without the tenant and name-lookup ones.
    - The WPF window itself is not tested here (Windows only); its XAML is checked to be well-formed
      and to hold every control the code looks up.
    - A stand-in tool (gui-sample) gives the form tests every kind of parameter.
    - Exits with code 1 if any test fails.

.EXAMPLE
    pwsh -File .\Tests\Invoke-GuiTests.ps1

.VERSIONING
    0.3.0 - Initial window tests.
#>

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path (Join-Path $repoRoot 'Nutmeg.AD') 'Nutmeg.AD.psd1') -Force
$mod = Get-Module Nutmeg.AD
# Tests never read or write your own settings: an empty settings file of their own.
& $mod { $script:NmSettingsTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ("NmSettings_" + [guid]::NewGuid().ToString('N') + '.json'); $script:NmSettingsData = $null; Update-NmConfigFromSetting }

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("NmGuiTests_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
& $mod {
    param($root)
    $script:NmConfig.ExportRoot = Join-Path $root 'Exports'
    $script:NmConfig.DataRoot   = Join-Path $root 'Data'
    $script:NmLogPath = $null
    $script:NmSession = New-NmSessionObject
    $script:NmSession.Domain = 'clientx.local'; $script:NmSession.NetBIOS = 'CLIENTX'; $script:NmSession.Server = 'DC01.clientx.local'

    # A stand-in tool with every kind of parameter the form builds, and its own questions.
    function script:Invoke-NmGuiSampleTool {
        param(
            [ValidateSet('All', 'Enabled', 'Disabled')][string]$Scope = 'Enabled',
            [int]$InactiveDays = 90,
            [string[]]$Identity,
            [Parameter(Mandatory)][string]$SearchBase,
            [datetime]$Since,
            [string[]]$Exclude = @(),
            [switch]$IncludeServiceAccounts,
            [hashtable]$Extra,
            [switch]$WhatIf
        )
        [pscustomobject]@{ Name = 'Jane'; Result = $(if ($WhatIf) { 'WhatIf: not changed' } else { 'Created' }) }
    }
    function script:Read-NmGuiSampleOption {
        $scope = Show-NmMenu -Title 'GUI Sample' -Back -Options @(
            [pscustomobject]@{ Key = '1'; Label = 'Every account' }
            [pscustomobject]@{ Key = '2'; Label = 'Enabled accounts only' }
        )
        if ($scope -eq 'B') { return $null }
        $days = Read-NmInput -Prompt 'Inactive for how many days' -Default '90'
        $base = Read-NmInput -Prompt 'Search base OU'
        return @{ Scope = $(if ($scope -eq '1') { 'All' } else { 'Enabled' }); InactiveDays = [int]$days; SearchBase = $base }
    }
    Register-NmTool -Path 'gui-sample' -Definition @{
        Name = 'GUI Sample'; Id = 'gui-sample'; Category = 'Directory'; Area = 'ad/Users'; Synopsis = 'Stand-in for the window tests'
        Version = '1.0'; Kind = 'Change'; Services = @(); Roles = @(); Entry = 'Invoke-NmGuiSampleTool'; Prompt = 'Read-NmGuiSampleOption'
    }
} $testRoot

$script:Passed = 0
$script:Failed = New-Object System.Collections.Generic.List[string]
function Test-That {
    param([string]$Name, [scriptblock]$Body)
    & $mod { $script:NmGui.Active = $false; $script:NmGui.InputProvider = $null; [void]$script:NmGui.Buffer.Clear(); [void]$script:NmGui.Transcript.Clear() }
    try {
        $result = & $mod $Body
        if ($result -eq $false) { throw 'returned false' }
        $script:Passed++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } catch {
        $script:Failed.Add("$Name - $($_.Exception.Message)")
        Write-Host "  [FAIL] $Name - $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        & $mod { $script:NmGui.Active = $false; $script:NmGui.InputProvider = $null }
    }
}

Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '   Nutmeg.AD window (logic) tests' -ForegroundColor Yellow
Write-Host '=============================================' -ForegroundColor Cyan

$ns = 'http://schemas.microsoft.com/winfx/2006/xaml'

Test-That 'No block given to Invoke-NmGuiAction uses its own names ($Action, $Busy, $left): the block would see Invoke-NmGuiAction''s (call depth overflow on card buttons, 0.7.18-0.7.20)' {
    $own = @('Action', 'Busy', 'left')
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -Path (Join-Path $script:NmModuleRoot 'Core'), (Join-Path $script:NmModuleRoot 'Tools') -Filter *.ps1 -Recurse -File)) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
        foreach ($cmd in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-NmGuiAction' }, $true)) {
            foreach ($sb in $cmd.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }) {
                foreach ($v in $sb.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
                    if ($own -contains $v.VariablePath.UserPath) { $bad.Add("$($f.Name):$($v.Extent.StartLineNumber) `$$($v.VariablePath.UserPath)") }
                }
            }
        }
    }
    if ($bad.Count) { throw "uses Invoke-NmGuiAction's own names: $($bad -join ', ')" }
    $true
}

Test-That 'No closure calls a module function (GetNewClosure leaves the module: 0.7.15 broke every dialog with rows this way)' {
    $files = @(Get-ChildItem -Path (Join-Path $script:NmModuleRoot 'Core'), (Join-Path $script:NmModuleRoot 'Tools') -Filter *.ps1 -Recurse -File)
    $asts = @(foreach ($f in $files) { [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null) })
    $ours = @{}
    foreach ($a in $asts) { foreach ($fd in $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $ours[$fd.Name] = $true } }
    $bad = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $asts.Count; $i++) {
        foreach ($cl in $asts[$i].FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'GetNewClosure' }, $true)) {
            $inside = @{}
            foreach ($fd in $cl.Expression.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $inside[$fd.Name] = $true }
            foreach ($cmd in $cl.Expression.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $name = $cmd.GetCommandName()
                if ($name -and $ours.ContainsKey($name) -and -not $inside.ContainsKey($name)) { $bad.Add("$($files[$i].Name):$($cmd.Extent.StartLineNumber) $name") }
            }
        }
    }
    if ($bad.Count) { throw "module functions called inside a closure: $($bad -join ', ')" }
    $true
}

Test-That 'Start-NmToolkitGui is exported; the redirect helpers are not' {
    $names = @((Get-Module Nutmeg.AD).ExportedFunctions.Keys)
    ($names -contains 'Start-NmToolkitGui') -and ($names -notcontains 'Write-Host') -and ($names -notcontains 'Out-Host') -and ($names -notcontains 'Format-Table')
}

Test-That 'Main, dialog and results layouts are well-formed XML; every control the code looks up is in the main layout' {
    $ns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $main = [xml]($script:NmGuiMainXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $dlg = [xml]($script:NmGuiDialogXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $null = [xml]($script:NmGuiViewerXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $names = @($main.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', $ns) })
    $missing = @($script:NmGuiMainControls | Where-Object { $names -notcontains $_ })
    $styles = @($main.Window.'Window.Resources'.Style | ForEach-Object { $_.GetAttribute('Key', $ns) })
    # Start-NmToolkitGui looks the controls up from that list, not from a copy of its own.
    $code = (Get-Command Start-NmToolkitGui).ScriptBlock.ToString()
    ($script:NmGuiMainControls.Count -ge 40) -and ($missing.Count -eq 0) -and ($code -match 'foreach \(\$n in \$script:NmGuiMainControls\)') -and
    ($styles -contains 'SideButton') -and ($styles -contains 'ToolItem') -and ($dlg.Window.Title -eq 'Nutmeg AD Toolkit') -and ($main.Window.Title -eq 'Nutmeg AD Toolkit')
}

Test-That 'Every StaticResource the layouts use is defined (the M365 tenant styles are gone)' {
    $all = $script:NmGuiMainXaml + $script:NmGuiDialogXaml + $script:NmGuiViewerXaml
    $used = @([regex]::Matches($all, '\{StaticResource ([A-Za-z]+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $defined = @([regex]::Matches($script:NmGuiTheme + $script:NmGuiMainXaml, 'x:Key="([A-Za-z]+)"') | ForEach-Object { $_.Groups[1].Value })
    (@($used | Where-Object { $defined -notcontains $_ }).Count -eq 0) -and ($all -notmatch 'Tenant') -and ($all -notmatch 'Disconnect')
}

Test-That 'Every Style= in the code points at a style the theme defines' {
    $code = (Get-Content -Raw -Path (Join-Path $script:NmModuleRoot 'Core\Gui.ps1'))
    $asked = @([regex]::Matches($code, "FindResource\('([A-Za-z]+)'\)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $defined = @([regex]::Matches($script:NmGuiTheme + $script:NmGuiMainXaml + $script:NmGuiDialogXaml + $script:NmGuiViewerXaml, 'x:Key="([A-Za-z]+)"') | ForEach-Object { $_.Groups[1].Value })
    @($asked | Where-Object { $defined -notcontains $_ }).Count -eq 0
}

Test-That 'No M365 pieces are left in the window code (tenants, clouds, sign-in, name lookups)' {
    $code = (Get-Content -Raw -Path (Join-Path $script:NmModuleRoot 'Core\Gui.ps1'))
    $bad = @('Get-NmTenantProfile', 'Use-NmTenantProfile', 'Select-NmEnvironment', 'Disconnect-NmService', 'Resolve-NmRecipient', 'Resolve-NmGraphUser',
             'Remove-NmTempApp', 'Initialize-NmModuleOrder', 'Resume-NmOpenSession', 'GraphScopes', 'IppsSearchOnly', 'Show-NmConnectionMenu', 'Session.Tenant')
    @($bad | Where-Object { $code -match [regex]::Escape($_) }).Count -eq 0
}

Test-That 'Option form: every tool gets a form; choices, switches, numbers, lists, dates and defaults come from its parameters' {
    $bad = @(Get-NmTool | Where-Object { $null -eq @(Get-NmGuiParamSpec -Tool $_) })
    $s = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id 'gui-sample'))
    $f = @{}; foreach ($x in $s) { $f[$x.Name] = $x }
    ($bad.Count -eq 0) -and ((($s | ForEach-Object Name) -join ',') -eq 'Scope,InactiveDays,Identity,SearchBase,Since,Exclude,IncludeServiceAccounts') -and
    ($f.Scope.Kind -eq 'Choice') -and (@($f.Scope.Choices).Count -eq 3) -and ($f.Scope.Default -eq 'Enabled') -and
    ($f.InactiveDays.Kind -eq 'Number') -and ($f.InactiveDays.Default -eq '90') -and ($f.InactiveDays.Label -eq 'Inactive days') -and
    ($f.Identity.Kind -eq 'List') -and ($f.Since.Kind -eq 'Date') -and ($f.IncludeServiceAccounts.Kind -eq 'Switch') -and
    $f.SearchBase.Required -and (-not $f.Identity.Required) -and ($null -eq $f.Exclude.Default) -and (-not $f.ContainsKey('Extra')) -and (-not $f.ContainsKey('WhatIf'))
}

Test-That 'Form values to arguments: blanks left out, lists split, numbers and dates checked, required boxes enforced' {
    $spec = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id 'gui-sample'))
    $a = ConvertFrom-NmGuiForm -Spec $spec -Values @{ Scope = 'All'; InactiveDays = '30'; Identity = 'jane, bob;carl'; SearchBase = 'OU=Users,OU=ClientX,DC=clientx,DC=local'; Since = ''; IncludeServiceAccounts = $true }
    $threw = $false; try { $null = ConvertFrom-NmGuiForm -Spec $spec -Values @{ InactiveDays = 'ten'; SearchBase = 'x' } } catch { $threw = $_.Exception.Message -like 'Inactive days*not a number*' }
    $req = $null; try { $null = ConvertFrom-NmGuiForm -Spec $spec -Values @{ SearchBase = '  ' } } catch { $req = $_.Exception.Message }
    $d = ConvertFrom-NmGuiForm -Spec $spec -Values @{ Since = '2026-11-01 08:00'; SearchBase = 'x' }
    ($a.Scope -eq 'All') -and ($a.InactiveDays -eq 30) -and (@($a.Identity).Count -eq 3) -and ($a.IncludeServiceAccounts -eq $true) -and (-not $a.ContainsKey('Since')) -and
    $threw -and ($req -eq 'Search base is required.') -and ($d.Since -is [datetime]) -and ($d.Since.Day -eq 1)
}

Test-That 'Drop-downs: no empty line when the parameter has a default; one when it has none' {
    $scope = @(Get-NmGuiParamSpec -Tool (Get-NmTool -Id 'gui-sample')) | Where-Object Name -eq 'Scope'
    $items = @(Get-NmGuiChoiceItem -Field $scope)
    $none = @(Get-NmGuiChoiceItem -Field ([pscustomobject]@{ Choices = @('A', 'B'); Default = $null }))
    (($items -join ',') -eq 'All,Enabled,Disabled') -and ($items -notcontains '') -and ($none.Count -eq 3) -and ($none[0] -eq '')
}

Test-That 'Window open: Write-Host collects text; each prompt sees only what was written since the last one (a tool''s own questions)' {
    $script:Seen = New-Object System.Collections.Generic.List[string]
    $script:NmGui.InputProvider = {
        param($text, $prompt)
        $script:Seen.Add($text)
        if ($script:Seen.Count -gt 20) { throw 'Too many prompts (scripted answers out of step).' }
        $now = @($text -split '(?m)^> .*$')[-1]   # only the question being asked now
        if ($now -match '\[1\] Every account') { '1' } elseif ($now -match 'how many days') { '45' } elseif ($now -match 'Search base') { 'OU=ClientX,DC=clientx,DC=local' } else { 'N' }
    }
    $script:NmGui.Active = $true
    $a = Read-NmGuiSampleOption
    $script:NmGui.Active = $false
    ($a.Scope -eq 'All') -and ($a.InactiveDays -eq 45) -and ($a.SearchBase -eq 'OU=ClientX,DC=clientx,DC=local') -and ($script:Seen.Count -eq 3) -and
    ($script:Seen[0] -match '\[1\] Every account') -and ($script:Seen[0] -match 'GUI Sample') -and ($script:Seen[1] -match '> 1') -and
    ($script:NmGui.Transcript.ToString() -match '> 1')
}


Test-That 'A menu asked again after an empty answer still shows the menu and its buttons (the Domain and DC loop)' {
    $script:Seen = New-Object System.Collections.Generic.List[string]
    $script:NmGui.InputProvider = { param($text, $prompt) $script:Seen.Add($text); if ($script:Seen.Count -eq 1) { '' } else { '2' } }
    $script:NmGui.Active = $true
    $pick = Show-NmMenu -Title 'Domain and DC' -Back -Options @([pscustomobject]@{ Key = '1'; Label = 'Status' }, [pscustomobject]@{ Key = '2'; Label = 'Work against another DC' })
    $script:NmGui.Active = $false
    $second = $script:Seen[1]
    $buttons = @(Get-NmGuiChoice -Text $second -Prompt ' ')
    ($pick -eq '2') -and ($second -match 'is not an option') -and ($second -match '\[2\] Work against another DC') -and (($buttons.Key -join ',') -eq '1,2,B')
}

Test-That 'Domain and DC header: the domain, its short name and the DC; a note before the domain is read' {
    $saved = $script:NmSession
    try {
        $a = Get-NmGuiDomainText
        $script:NmSession = New-NmSessionObject
        $b = Get-NmGuiDomainText
        $t = Get-NmGuiTarget
    } finally { $script:NmSession = $saved }
    ($a -eq 'clientx.local (CLIENTX)  |  DC: DC01.clientx.local') -and ($b -like 'Not read yet*') -and ($t -eq '') -and ((Get-NmGuiTarget) -eq 'clientx.local|DC01.clientx.local') -and
    ((Get-NmGuiServiceLabel 'AD') -eq 'ActiveDirectory') -and ((Get-NmGuiServiceLabel 'GPO') -eq 'GroupPolicy')
}

Test-That 'Another DC or domain clears what is on screen; the first one and the same one keep it' {
    $script:NmGui.ShownTarget = $null
    $a = Test-NmGuiTargetChanged -Target 'clientx.local|DC01.clientx.local'
    $b = Test-NmGuiTargetChanged -Target 'clientx.local|DC01.clientx.local'
    $c = Test-NmGuiTargetChanged -Target 'clientx.local|DC02.clientx.local'
    $d = Test-NmGuiTargetChanged -Target ''
    (-not $a) -and (-not $b) -and $c -and (-not $d) -and ($null -eq $script:NmGui.ShownTarget)
}

Test-That 'Sidebar: areas only (the New Forest Build stays in the console); an open area lists its sections; the selection is marked' {
    $script:NmGui.Open = @{ ad = $true }
    $script:NmGui.Selection = 'ad|Users'
    $rows = @(Get-NmGuiSidebarModel)
    $centers = @($rows | Where-Object Kind -eq 'Center' | ForEach-Object Center)
    $sel = @($rows | Where-Object Selected)
    ($centers -notcontains 'build') -and ($centers -contains 'kit') -and ($centers -contains 'ad') -and (@(Get-NmAdminCenter | Where-Object Id -eq 'build').Count -eq 1) -and
    (@($rows | Where-Object { $_.Center -eq 'kit' }).Count -eq 1) -and ($sel.Count -eq 1) -and ($sel[0].Section -eq 'Users')
}

Test-That 'Sidebar: the module dot is full, partial or empty from the area''s modules' {
    $saved = $script:NmSession.Services.Clone()
    try {
        $script:NmSession.Services.AD = $true; $script:NmSession.Services.GPO = $false
        $two = [pscustomobject]@{ Services = @('AD', 'GPO') }
        $gpo = [pscustomobject]@{ Services = @('GPO') }
        $s1 = Get-NmGuiCenterState -Center $two; $s2 = Get-NmGuiCenterState -Center $gpo
        $script:NmSession.Services.GPO = $true
        $s3 = Get-NmGuiCenterState -Center $two
        $script:NmGui.Open = @{}
        $kit = @(Get-NmGuiSidebarModel | Where-Object Center -eq 'kit')[0]
        ($s1 -eq 'Some') -and ($s2 -eq 'None') -and ($s3 -eq 'All') -and ((Get-NmGuiCenterState -Center ([pscustomobject]@{ Services = @() })) -eq 'NotNeeded') -and ($kit.Tip -eq 'No module needed')
    } finally { $script:NmSession.Services = $saved }
}

Test-That 'Tool list: a section shows its tools; search finds tools but never the New Forest Build' {
    $m = Get-NmGuiToolListModel -Center 'ad' -Section 'Users'
    $s = Get-NmGuiToolListModel -Search 'session'
    $f = Get-NmGuiToolListModel -Search 'forest'
    $b = Get-NmGuiToolListModel -Center 'build' -Section 'First DC'
    ($m.CenterText -eq 'Active Directory') -and ($m.Title -eq 'Users') -and (@($m.Items | Where-Object { $_.Tool.Id -eq 'gui-sample' }).Count -eq 1) -and
    ($s.CenterText -eq 'Search') -and (@($s.Items | Where-Object { $_.Tool.Id -eq 'session-info' })[0].Note -eq 'Toolkit > Diagnostics') -and
    (@($f.Items | Where-Object { $_.Tool.Id -eq 'new-forest' }).Count -eq 0) -and (@($b.Items).Count -eq 0)
}

Test-That 'Ready text: not elevated says so first; otherwise the domain and DC' {
    $real = ${function:script:Test-NmElevated}
    try {
        ${function:script:Test-NmElevated} = { $false }
        $a = Get-NmGuiReadyText
        ${function:script:Test-NmElevated} = { $true }
        $b = Get-NmGuiReadyText
    } finally { Set-Item -Path function:script:Test-NmElevated -Value $real }
    ($a -like 'Not running as administrator*') -and ($b -eq 'Ready. Domain clientx.local, working against DC01.clientx.local.')
}

Test-That 'Capture titles: the domain status line is never a title; the screen title and the option picked are' {
    Clear-NmGuiBuffer
    $script:NmGui.Active = $true
    $script:NmGui.InputProvider = { param($text, $prompt) '1' }
    try {
        Show-NmHeader -Title 'OU: Users'
        [pscustomobject]@{ Name = 'Users'; Path = 'OU=Users,OU=ClientX,DC=clientx,DC=local' } | Format-List | Out-Host
        $first = $script:NmGui.Captures[0].Title
        $choice = Show-NmMenu -Title 'Actions' -Back -NoClear -Options @([pscustomobject]@{ Key = '1'; Label = 'Show members' }, [pscustomobject]@{ Key = '2'; Label = 'Move objects'; Tag = '[CHANGE]' })
        @([pscustomobject]@{ Member = 'Jane' }) | Format-Table -AutoSize | Out-Host
        $second = $script:NmGui.Captures[0].Title
    } finally { $script:NmGui.InputProvider = $null; $script:NmGui.Active = $false; Clear-NmGuiBuffer }
    ($choice -eq '1') -and ($first -eq 'OU: Users') -and ($second -eq 'OU: Users > Show members')
}

Test-That 'Findings view: counts by severity and groups High first (no incident case here, so no verdict)' {
    $f = { param($sev, $check, $finding) [pscustomobject]@{ Severity = $sev; Check = $check; Finding = $finding; Evidence = ''; Why = ''; ManualStep = '' } }
    $rows = @((& $f 'Medium' 'dns' 'No reverse zone'), (& $f 'High' 'krbtgt' 'Password 900 days old'), (& $f 'Info' 'levels' 'Domain level 2016'))
    $m = Get-NmGuiFindingModel -Rows $rows
    ((($m.Counts | ForEach-Object { "$($_.Count) $($_.Severity)" }) -join ',') -eq '1 High,1 Medium,1 Info') -and ((($m.Groups | ForEach-Object Severity) -join ',') -eq 'High,Medium,Info') -and
    ($m.Level -eq 'OK') -and ($m.Total -eq 3)
}

Test-That 'The window has the card view, its toggle, the selection bar, the Clear button and wrapping grids' {
    $x = [xml]($script:NmGuiMainXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $ns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $names = @($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', $ns) })
    $grid = @($x.SelectNodes('//*[local-name()="DataGrid"]') | Where-Object { $_.GetAttribute('Name', $ns) -eq 'ResultsGrid' })[0]
    (@('CardScroll', 'CardHost', 'ViewToggle', 'SelectionBar', 'SelectionText', 'SelectAllButton', 'SelectNoneButton', 'SelectionActions', 'ResultBar', 'ClearButton', 'DomainButton', 'DomainText') | Where-Object { $names -notcontains $_ }).Count -eq 0 -and
    $grid.GetAttribute('MinRowHeight') -and -not $grid.GetAttribute('RowHeight') -and ($script:NmGui.Kept -is [hashtable])
}

Test-That 'Launcher: the window by default and -Console for the console, carried through elevation, PowerShell 7 and the build' {
    $text = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:NmModuleRoot) 'Start-NutmegAD.ps1') -Raw
    $paramLine = ([regex]::Match($text, '(?m)^param\(.*\)$')).Value
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("NmProbe_" + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -Path $probe -Value ($paramLine + "`n" + '[pscustomobject]@{ Console = [bool]$Console; Gui = [bool]$Gui; Stay = [bool]$Stay; NewForest = [bool]$NewForest; LogPath = $LogPath }')
    try { $p = & $probe -Stay -Console -NewForest -LogPath 'C:\Temp\NutmegAD\Logs\x.txt'; $old = & $probe -Gui } finally { Remove-Item $probe -ErrorAction SilentlyContinue }
    $p.Console -and $p.Stay -and $p.NewForest -and ($p.LogPath -eq 'C:\Temp\NutmegAD\Logs\x.txt') -and $old.Gui -and
    $text.Contains('$useWindow = $onWindows -and -not $Console') -and $text.Contains("if (-not `$useWindow) { `$modeArgs = @('-Console') }") -and
    $text.Contains('$relaunch += $modeArgs') -and $text.Contains('& $pwsh -NoLogo -STA -File $PSCommandPath -Stay @modeArgs @logArgs') -and
    $text.Contains('& powershell.exe -NoLogo -NoProfile -File $PSCommandPath -NewForest @modeArgs @logArgs') -and
    $text.Contains('Start-NmToolkitGui -NewForest') -and $text.Contains("if (`$useWindow) {")
}

Test-That 'Start check: a build in progress or a workgroup server opens the build; a DC, a domain member or a finished build opens the toolkit' {
    $wg = [pscustomobject]@{ Name = 'WIN-1'; PartOfDomain = $false }
    $dc = [pscustomobject]@{ Name = 'DC01'; PartOfDomain = $true }
    $going = [pscustomobject]@{ Answers = [pscustomobject]@{ Domain = 'clientx.local' }; Finished = $null }
    $done = [pscustomobject]@{ Answers = [pscustomobject]@{ Domain = 'clientx.local' }; Finished = '2026-11-21 10:00:00' }
    $a = Get-NmStartMode -Computer $wg -NoState
    $b = Get-NmStartMode -Computer $dc -NoState
    $c = Get-NmStartMode -Computer $dc -BuildState $going
    $d = Get-NmStartMode -Computer $dc -BuildState $done
    ($a.Mode -eq 'NewForest') -and ($a.Reason -like 'WIN-1 is in a workgroup*') -and ($b.Mode -eq 'Toolkit') -and
    ($c.Mode -eq 'NewForest') -and ($c.Reason -like '*of clientx.local is in progress*') -and ($d.Mode -eq 'Toolkit') -and
    (@((Get-Module Nutmeg.AD).ExportedFunctions.Keys) -contains 'Get-NmStartMode')
}

Test-That 'Launcher: the start check runs before the hand-over to Windows PowerShell; -Toolkit and -NewForest skip it' {
    $text = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:NmModuleRoot) 'Start-NutmegAD.ps1') -Raw
    $check = $text.IndexOf('$start = Get-NmStartMode'); $hop = $text.IndexOf('& powershell.exe -NoLogo -NoProfile -File $PSCommandPath -NewForest')
    $import = $text.IndexOf('Import-Module $modulePath')
    ($import -gt 0) -and ($import -lt $check) -and ($check -lt $hop) -and $text.Contains('if (-not $NewForest -and -not $Toolkit -and $onWindows) {') -and
    $text.Contains("if (`$Toolkit) { `$modeArgs += '-Toolkit' }")
}

Test-That 'Launcher: PowerShell 7 is used without asking whenever it is installed (never for the build)' {
    $text = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $script:NmModuleRoot) 'Start-NutmegAD.ps1') -Raw
    (-not $text.Contains('Start the toolkit in PowerShell 7?')) -and $text.Contains("if (`$pwsh) {`n            Write-Host ""Starting the toolkit in PowerShell 7") -and
    $text.Contains('if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $NewForest) {')
}

Test-That 'Build mode: the window lists only the New Forest Build, search finds only it, and Guided starts it' {
    $script:NmGui.BuildMode = $true
    try {
        $areas = @(Get-NmGuiArea | ForEach-Object Id)
        $s = Get-NmGuiToolListModel -Search 'forest'
        $o = Get-NmGuiToolListModel -Search 'session'
        $ready = Get-NmGuiReadyText
    } finally { $script:NmGui.BuildMode = $false }
    $normal = @(Get-NmGuiArea | ForEach-Object Id)
    $code = (Get-Command Start-NmToolkitGui).ScriptBlock.ToString()
    (($areas -join ',') -eq 'build') -and (@($s.Items | Where-Object { $_.Tool.Id -eq 'new-forest' }).Count -eq 1) -and (@($o.Items).Count -eq 0) -and
    ($normal -notcontains 'build') -and ($code -match 'if \(\$script:NmGui\.BuildMode -and \$script:NmGui\.Tool\) \{ Invoke-NmGuiGuided \}') -and
    ($code -match "Select-NmGuiTool -Id 'new-forest'") -and (($ready -like 'New Forest Build:*') -or ($ready -like 'Not running as administrator*'))
}

Test-That 'Password in the window: a SecureString from the dialog, only "(hidden)" in the output, Cancel stops' {
    $script:NmGui.Active = $true
    try {
        Write-Host 'Microsoft''s pre-checks run next.'
        $script:NmGui.SecretProvider = { param($prompt) $script:AskedFor = $prompt; ConvertTo-SecureString 'Not-A-Real-Pw1' -AsPlainText -Force }
        $p = Read-NmSecret -Prompt 'Directory Services Restore Mode (DSRM) password'
        $script:NmGui.SecretProvider = { param($prompt) $null }
        $cancelled = $false
        try { $null = Read-NmSecret -Prompt 'Type it again' } catch [System.OperationCanceledException] { $cancelled = $true }
        $log = $script:NmGui.Transcript.ToString()
    } finally { $script:NmGui.SecretProvider = $null; $script:NmGui.Active = $false }
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))
    ($p -is [securestring]) -and ($plain -eq 'Not-A-Real-Pw1') -and $cancelled -and ($script:AskedFor -like 'Directory Services*') -and
    ($log -match '> \(hidden\)') -and ($log -notmatch 'Not-A-Real-Pw1')
}

Test-That 'Password dialog: well-formed, a PasswordBox (never a TextBox), every control there; its note drops log stamps' {
    $ns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $x = [xml]($script:NmGuiSecretXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $names = @($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', $ns) })
    $box = @($x.SelectNodes('//*[local-name()="PasswordBox"]'))
    $note = Get-NmGuiSecretContext -Text "=====`r`n[2026-11-21 10:00:00] [INFO] Running Microsoft's pre-checks...`r`nThe two did not match.`r`nSome plain line`r`n" -Marks @{ 'The two did not match.' = 'Red' }
    $none = Get-NmGuiSecretContext -Text "[2026-11-21 10:00:00] [INFO] Creating the forest" -Marks @{}
    (@($script:NmGuiSecretControls | Where-Object { $names -notcontains $_ }).Count -eq 0) -and ($box.Count -eq 1) -and (@($x.SelectNodes('//*[local-name()="TextBox"]')).Count -eq 0) -and
    ($note -eq 'The two did not match.') -and ($none -eq '')
}

Test-That 'Build mode controls: Run, options and WhatIf hidden; Guided is the way in' {
    $mk = { [pscustomobject]@{ Visibility = 'Visible'; Content = 'x'; ToolTip = '' } }
    $c = @{ RunButton = (& $mk); OptionsBorder = (& $mk); PreviewBox = (& $mk); GuidedButton = (& $mk) }
    Set-NmGuiBuildModeControl -Controls $c
    ($c.RunButton.Visibility -eq 'Collapsed') -and ($c.OptionsBorder.Visibility -eq 'Collapsed') -and ($c.PreviewBox.Visibility -eq 'Collapsed') -and
    ($c.GuidedButton.Content -eq 'Start or continue the build') -and ($c.GuidedButton.Visibility -eq 'Visible')
}

Test-That 'Sign-in task: reopens the window when the build ran in it, the console otherwise' {
    $l = 'C:\Tools\DomainController-Security\Start-NutmegAD.ps1'
    $con = Get-NmResumeTaskArgument -LauncherPath $l
    $win = Get-NmResumeTaskArgument -LauncherPath $l -Gui
    ($con -eq "-NoExit -NoProfile -File `"$l`" -NewForest -Console") -and ($win -eq "-NoExit -NoProfile -File `"$l`" -NewForest")
}

Test-That 'Dialogs carry no console text: a kept table goes to the Output panel only; plain values still show' {
    Clear-NmGuiBuffer
    $script:NmGui.Active = $true
    try {
        [pscustomobject]@{ Col = 'value-123' } | Format-Table | Out-Host
        $buf = $script:NmGui.Buffer.ToString()
        $caps = $script:NmGui.Captures.Count
        'plain value' | Out-Host
        $buf2 = $script:NmGui.Buffer.ToString()
        $log = $script:NmGui.Transcript.ToString()
    } finally { $script:NmGui.Active = $false; Clear-NmGuiBuffer }
    ($buf -notmatch 'value-123') -and ($caps -eq 1) -and ($log -match 'value-123') -and ($buf2 -match 'plain value') -and (-not $script:NmGui.TableText)
}

Test-That 'Dialog model: the Cyan heading is the section, warnings and errors are notes, INFO lines and console text are left out, the default fills the box' {
    Clear-NmGuiBuffer
    $script:NmGui.Active = $true
    try {
        Write-Host '[2026-11-21 07:11:33] [INFO] Checking this server before anything changes...'
        Write-Host '[2026-11-21 07:11:34] [WARN] Windows is waiting for a restart'
        Write-Host ''
        Write-Host 'The new forest' -ForegroundColor Cyan
        Write-Host 'Use a DNS name with at least two parts, such as clientx.local.' -ForegroundColor Red
        Write-Host 'Domain name (DNS, for example clientx.local) (Press Enter for default: clientx.local)' -ForegroundColor Yellow -NoNewline
        $m = Get-NmGuiDialogModel -Text $script:NmGui.Buffer.ToString() -Prompt ' '
    } finally { $script:NmGui.Active = $false; Clear-NmGuiBuffer }
    ($m.Kind -eq 'Text') -and ($m.Title -eq 'Domain name (DNS, for example clientx.local)') -and ($m.DefaultValue -eq 'clientx.local') -and ($m.Section -eq 'The new forest') -and
    (@($m.Notes).Count -eq 2) -and ($m.Notes[0].Level -eq 'Warning') -and ($m.Notes[0].Text -eq 'Windows is waiting for a restart') -and
    ($m.Notes[1].Level -eq 'Error') -and ($m.Notes[1].Text -like 'Use a DNS name*') -and (-not "$($m.Context)".Trim()) -and (@($script:NmGui.Marks.Keys).Count -eq 0)
}

Test-That 'Dialog model: only what came after the last answer counts (an earlier warning is not repeated)' {
    $text = "[2026-11-21 07:11:34] [WARN] Old warning`r`nComputer name`r`n> DC01`r`nTime zone (Windows ID)"
    $m = Get-NmGuiDialogModel -Text $text -Prompt ' ' -Marks @{}
    ($m.Title -eq 'Time zone (Windows ID)') -and (@($m.Notes).Count -eq 0)
}

Test-That 'Approval in the window: the change, domain, DC, scope and every target; the typed word must match; a plain change is Approve or Cancel' {
    $script:Seen = $null
    $script:NmGui.ConfirmProvider = { param($m) $script:Seen = $m; $true }
    $script:NmGui.Active = $true
    try {
        $targets = @(1..12 | ForEach-Object { "Step $_" })
        $ok = Confirm-NmChange -Action 'New Forest Build: clientx.local' -Targets $targets -DomainWide -ConfirmWord 'clientx'
        $typed = $script:Seen
        $script:NmGui.ConfirmProvider = { param($m) $script:Seen = $m; $false }
        $no = Confirm-NmChange -Action 'Create 2 OUs' -Targets @('OU=A', 'OU=B')
        $plain = $script:Seen
        $buf = $script:NmGui.Buffer.ToString(); $log = $script:NmGui.Transcript.ToString()
    } finally { $script:NmGui.ConfirmProvider = $null; $script:NmGui.Active = $false }
    $ok -and (-not $no) -and ($typed.Typed) -and ($typed.Expected -eq 'clientx') -and (@($typed.Targets).Count -eq 12) -and
    ((($typed.Facts | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';') -eq 'Domain=clientx.local;DC=DC01.clientx.local;Scope=domain-wide') -and
    ($typed.Hint -eq "This changes the whole domain. Type 'clientx' to approve.") -and (-not $plain.Typed) -and ($plain.Hint -eq 'Nothing changes until you approve.') -and
    ($buf -notmatch 'CHANGE:') -and ($log -match 'CHANGE: New Forest Build: clientx.local') -and ($log -match '> not approved')
}

Test-That 'Approval dialog: well-formed, every control there, Approve is the primary button' {
    $ns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $x = [xml]($script:NmGuiConfirmXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $names = @($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', $ns) })
    $ok = @($x.SelectNodes('//*[local-name()="Button"]') | Where-Object { $_.GetAttribute('Name', $ns) -eq 'OkButton' })[0]
    $sec = @($x.SelectNodes('//*[local-name()="Button"]') | Where-Object { $_.GetAttribute('Name', $ns) -eq 'SecondaryButton' })[0]
    (@($script:NmGuiConfirmControls | Where-Object { $names -notcontains $_ }).Count -eq 0) -and ($ok.Content -eq 'Approve') -and ($ok.Style -match 'PrimaryButton') -and ($null -ne $sec) -and ($sec.Visibility -eq 'Collapsed')
}

Test-That 'Approval in the window with SecondaryLabel: Approve all, Review each, Cancel, and clean valueless fact chips' {
    $script:Seen = $null
    $script:NmGui.Active = $true
    try {
        $script:NmGui.ConfirmProvider = { param($m) $script:Seen = $m; 'Approve' }
        $c1 = Confirm-NmChange -Action 'Create 3 GPOs from baselines' -Targets @('GPO A', 'GPO B', 'GPO C') -Facts @('All GPOs are created unlinked.') -ApproveLabel 'Approve all' -SecondaryLabel 'Review each'
        $m = $script:Seen
        $script:NmGui.ConfirmProvider = { param($m) 'Secondary' }
        $c2 = Confirm-NmChange -Action 'Create 3 GPOs from baselines' -Targets @('GPO A', 'GPO B', 'GPO C') -ApproveLabel 'Approve all' -SecondaryLabel 'Review each'
        $script:NmGui.ConfirmProvider = { param($m) 'Cancel' }
        $c3 = Confirm-NmChange -Action 'Create 3 GPOs from baselines' -Targets @('GPO A', 'GPO B', 'GPO C') -ApproveLabel 'Approve all' -SecondaryLabel 'Review each'
        $log = $script:NmGui.Transcript.ToString()
    } finally { $script:NmGui.ConfirmProvider = $null; $script:NmGui.Active = $false }
    ($c1 -eq 'Approve') -and ($c2 -eq 'Secondary') -and ($c3 -eq 'Cancel') -and
    ($m.ApproveLabel -eq 'Approve all') -and ($m.SecondaryLabel -eq 'Review each') -and
    ($log -match 'All GPOs are created unlinked\., Domain:') -and ($log -notmatch 'All GPOs are created unlinked\.:') -and
    ($log -match '> Review each')
}

Test-That 'Question dialog layout: section, notes, plain text and tables have their places; no console box is used for questions' {
    $ns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $x = [xml]($script:NmGuiDialogXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $names = @($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', $ns) })
    $code = (Get-Command Show-NmGuiQuestion).ScriptBlock.ToString()
    (@('SectionText', 'NotePanel', 'ContextText', 'TablePanel' | Where-Object { $names -notcontains $_ }).Count -eq 0) -and ($code -notmatch 'OutputBox') -and ($code -match 'Set-NmGuiDialogBody')
}

Test-That 'Background runs: outside the window directly; in the window in its own runspace, with parameters, output and errors' {
    $direct = Invoke-NmGuiBackground -ScriptBlock { 'here' }
    $script:NmGui.Active = $true
    try {
        $out = @(Invoke-NmGuiBackground -Status 'Testing' -Parameters @{ A = 2; B = 3 } -ScriptBlock { param($A, $B) Start-Sleep -Milliseconds 300; [pscustomobject]@{ Sum = $A + $B; Rs = [runspace]::DefaultRunspace.InstanceId } })
        $err = $null
        try { $null = Invoke-NmGuiBackground -ScriptBlock { Write-Error 'role install failed' } } catch { $err = $_.Exception.Message }
        $left = @($script:NmGui.Progress.Keys)
    } finally { $script:NmGui.Active = $false }
    ($direct -eq 'here') -and ($out[-1].Sum -eq 5) -and ($out[-1].Rs -ne [runspace]::DefaultRunspace.InstanceId) -and ($err -eq 'role install failed') -and ($left -notcontains 'id7')
}

Test-That 'The long server steps run through the background runner' {
    $code = Get-Content -Raw -Path (Join-Path $script:NmModuleRoot 'Core\Server.ps1')
    foreach ($f in 'Install-NmAddsFeature', 'Test-NmForestInstallation', 'Install-NmForest') {
        $body = (Get-Command $f).ScriptBlock.ToString()
        if ($body -notmatch 'Invoke-NmGuiBackground') { return $false }
    }
    $true
}

Test-That 'Build mode header: the server, workgroup or domain, and its address' {
    $pc = [pscustomobject]@{ Name = 'WIN-1'; PartOfDomain = $false; Domain = '' }
    $a = Get-NmGuiServerText -Computer $pc -Adapters @([pscustomobject]@{ IPv4 = '192.0.2.140'; Dhcp = $true })
    $b = Get-NmGuiServerText -Computer ([pscustomobject]@{ Name = 'DC01'; PartOfDomain = $true; Domain = 'clientx.local' }) -Adapters @([pscustomobject]@{ IPv4 = '192.0.2.50'; Dhcp = $false })
    $c = Get-NmGuiServerText -Computer $pc -Adapters @()
    ($a -eq 'WIN-1 (workgroup)  |  192.0.2.140 (DHCP)') -and ($b -eq 'DC01 (clientx.local)  |  192.0.2.50 (static)') -and ($c -eq 'WIN-1 (workgroup)')
}

Test-That 'Continue pop-ups keep the warnings, errors and successes (as notes and text), without log stamps' {
    $m = [pscustomobject]@{ Section = 'Server check'; Context = 'Nothing was changed.'
        Notes = @([pscustomobject]@{ Level = 'Error'; Text = 'This server is not ready' }, [pscustomobject]@{ Level = 'Success'; Text = 'Build finished.' }) }
    $t = Get-NmGuiContinueText -Model $m
    $n = @(Get-NmGuiNoteLine -Text $t)
    ($t -match '^Server check') -and ($t -match 'Build finished\.') -and ($t -match 'Nothing was changed\.') -and ($n.Count -eq 1) -and ($n[0].Level -eq 'ERROR') -and ($n[0].Text -eq 'This server is not ready')
}

Test-That 'The section label stays until the next heading (NetBIOS is still under "The new forest")' {
    $text = "The new forest`r`nDomain name (DNS, for example clientx.local)`r`n> clientx.local`r`nNetBIOS name (Press Enter for default: CLIENTX)"
    $m = Get-NmGuiDialogModel -Text $text -Prompt ' ' -Marks @{ 'The new forest' = 'Cyan' }
    $text2 = $text + "`r`n> CLIENTX`r`n" + ('=' * 45) + "`r`n   Forest and domain functional level`r`n" + ('=' * 45) + "`r`n   [1] Windows Server 2025`r`n   [B] Back`r`n" + ('=' * 45) + "`r`nSelect an option (Enter for 1)"
    $m2 = Get-NmGuiDialogModel -Text $text2 -Prompt ' ' -Marks @{ 'The new forest' = 'Cyan' }
    ($m.Section -eq 'The new forest') -and ($m.Title -eq 'NetBIOS name') -and ($m2.Section -eq 'The new forest') -and ($m2.Kind -eq 'Menu') -and
    ((Get-NmGuiQuestionStatus -Model $m) -eq 'Question: The new forest > NetBIOS name')
}

Test-That 'Borders written in Cyan are never headings' {
    Clear-NmGuiBuffer
    $script:NmGui.Active = $true
    try { Write-Host ('=' * 45) -ForegroundColor Cyan; Write-Host 'Folders' -ForegroundColor Cyan; $marks = $script:NmGui.Marks.Clone() } finally { $script:NmGui.Active = $false; Clear-NmGuiBuffer }
    (@($marks.Keys).Count -eq 1) -and ($marks['Folders'] -eq 'Cyan')
}

Test-That 'Output panel: no header furniture, and a cancelled question ends its line' {
    Clear-NmGuiBuffer; [void]$script:NmGui.Transcript.Clear()
    $script:NmGui.Active = $true
    try {
        Show-NmHeader -Title 'New Forest Build (first DC)'
        Write-Host 'Domain name' -NoNewline
        $script:NmGui.InputProvider = { param($t, $p) $null }
        try { $null = Read-NmHost -Prompt ' ' } catch [System.OperationCanceledException] { $null = $_ }
        $log = $script:NmGui.Transcript.ToString()
    } finally { $script:NmGui.InputProvider = $null; $script:NmGui.Active = $false }
    ($log -match 'New Forest Build \(first DC\)') -and ($log -notmatch 'Author:') -and ($log -notmatch '=====') -and ($log -match "Domain name\r?\n> \(cancelled\)")
}

Test-That 'Dialogs fit inside the window: same width each time, never wider or taller than it' {
    $a = Get-NmGuiDialogSize -Want 720 -OwnerWidth 1600 -OwnerHeight 800
    $b = Get-NmGuiDialogSize -Want 880 -OwnerWidth 900 -OwnerHeight 600
    $c = Get-NmGuiDialogSize -Want 720 -ScreenWidth 1024 -ScreenHeight 700
    ($a.Width -eq 720) -and ($a.MaxHeight -eq 740) -and ($b.Width -eq 820) -and ($b.MaxHeight -eq 540) -and ($c.Width -eq 720) -and ($c.MaxHeight -eq 640)
}

Test-That 'Check tables become rows with a coloured badge: OK green, Warning amber, Not ready red; titles are short' {
    $cap = [pscustomobject]@{ Title = 'New Forest Build (first DC) > Server check'; Columns = @('Check', 'Result', 'Detail')
        Rows = @([pscustomobject]@{ Check = 'Running as administrator'; Result = 'OK'; Detail = 'yes' },
                 [pscustomobject]@{ Check = 'No restart pending'; Result = 'Warning'; Detail = 'Windows is waiting for a restart' },
                 [pscustomobject]@{ Check = 'Not joined to a domain'; Result = 'Not ready'; Detail = 'joined to clientx.local' }) }
    $r = @(Get-NmGuiCheckRowModel -Capture $cap)
    $none = @(Get-NmGuiCheckRowModel -Capture ([pscustomobject]@{ Columns = @('Name', 'Size'); Rows = @([pscustomobject]@{ Name = 'a'; Size = 1 }) }))
    ($r.Count -eq 3) -and ((($r | ForEach-Object Level) -join ',') -eq 'OK,Medium,High') -and ($r[1].Name -eq 'No restart pending') -and ($r[1].Detail -eq 'Windows is waiting for a restart') -and
    ($none.Count -eq 0) -and ((Get-NmGuiShortTitle -Title $cap.Title) -eq 'Server check')
}

Test-That 'Approval for a new forest: its own facts instead of "no domain"' {
    $m = Get-NmGuiConfirmModel -Action 'New Forest Build: clientx.local' -Domain '' -DomainWide -Targets @('a', 'b') -Expected 'clientx' -Kind 'This changes the whole domain' -Facts @('New forest: clientx.local (CLIENTX)', 'This server: WIN-1 > DC01')
    ((($m.Facts | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';') -eq 'New forest=clientx.local (CLIENTX);This server=WIN-1 > DC01;Scope=domain-wide')
}

Test-That 'Windows Server choices get the same plain icon (no clock for "older")' {
    $a = Get-NmGuiChoiceIcon 'Windows Server 2025 (every DC will run 2025)'
    $b = Get-NmGuiChoiceIcon 'Windows Server 2016 (older DCs can join later)'
    ($a -eq $b) -and ($a -eq [string][char]0xE91F)
}

Test-That 'Build results: one card per phase, a line per step named by the step, worst status on the card' {
    $rows = @(
        [pscustomobject]@{ Phase = 'Phase 0: Prepare the server'; Step = 'Time zone'; Result = 'Done'; Detail = 'Eastern Standard Time (was Pacific Standard Time)' }
        [pscustomobject]@{ Phase = 'Phase 0: Prepare the server'; Step = 'Static IP'; Result = 'Done'; Detail = '192.0.2.50/24 via 192.0.2.1' }
        [pscustomobject]@{ Phase = 'Phase 1: Promote to the first DC'; Step = 'Promote'; Result = 'Failed'; Detail = 'pre-checks failed' }
    )
    $m = Get-NmGuiCardModel -Rows $rows -Columns @('Phase', 'Step', 'Result', 'Detail') -GroupBy @('Phase', 'Step')
    $p0 = $m.Items[0]
    ($m.Cards -eq 2) -and ($p0.Title -eq 'Phase 0: Prepare the server') -and ((($p0.Fields | ForEach-Object Name) -join '|') -eq 'Time zone|Static IP') -and
    ($p0.Fields[0].Value -eq 'Eastern Standard Time (was Pacific Standard Time)') -and ($p0.Status -eq 'Done') -and ($m.Items[1].Level -eq 'High')
}

Test-That 'A check list before "Press Enter to continue" opens as the modern check dialog, not the results viewer' {
    $check = [pscustomobject]@{ Title = 'New Forest Build (first DC) > Server check'; Columns = @('Check', 'Result', 'Detail'); Rows = @([pscustomobject]@{ Check = 'Running as administrator'; Result = 'OK'; Detail = 'yes' }) }
    $plain = [pscustomobject]@{ Title = 'Members'; Columns = @('Name', 'Mail'); Rows = @([pscustomobject]@{ Name = 'Jane'; Mail = 'jane@clientx.com' }) }
    $code = (Get-Command Read-NmGuiHost).ScriptBlock.ToString()
    $q = (Get-Command Show-NmGuiQuestion).ScriptBlock.ToString()
    (Test-NmGuiCheckPage -Captures @($check)) -and (-not (Test-NmGuiCheckPage -Captures @($plain))) -and (-not (Test-NmGuiCheckPage -Captures @())) -and
    ($code -match "\`$model.Kind = 'Continue'") -and ($q -match "if \(\`$Model.Kind -eq 'Continue'\)") -and ($q -match "\`$ok.Content = 'Continue'")
}

Test-That 'A notice with only words opens as the modern dialog with Continue, titled by its heading' {
    $code = (Get-Command Read-NmGuiHost).ScriptBlock.ToString()
    ($code -match 'if \(-not \$caps\.Count\) \{') -and ($code -match '\$model\.Title = \$\(if \(\$model\.Section\)')
}

Test-That 'Step list: groups, marks, times while running and when done, a summary; earlier steps say so' {
    $real = ${function:script:Get-NmNow}
    try {
        $script:T = [datetime]'2026-11-21 17:00:00'
        ${function:script:Get-NmNow} = { $script:T }
        Start-NmStepList -Title 'New Forest Build: clientx.local' -Steps @(
            @{ Name = 'StaticIp'; Label = 'Static IP'; Group = 'Phase 0: Prepare the server'; Status = 'Done'; Detail = '192.0.2.50/24' }
            @{ Name = 'Features'; Label = 'AD DS, DNS and GPMC'; Group = 'Phase 1: Promote to the first DC' }
            @{ Name = 'Promote'; Label = 'New forest clientx.local'; Group = 'Phase 1: Promote to the first DC' }
        )
        Set-NmStepStatus -Name 'Features' -Status Running
        $script:T = $script:T.AddSeconds(48)
        $m1 = Get-NmStepListModel
        $script:T = $script:T.AddMinutes(5).AddSeconds(27)
        $null = & { Set-NmStepStatus -Name 'Features' -Status Done -Detail 'installed' } 6>&1
        $m2 = Get-NmStepListModel
    } finally { Set-Item -Path function:script:Get-NmNow -Value $real; Stop-NmStepList }
    $f1 = @($m1.Rows | Where-Object Label -eq 'AD DS, DNS and GPMC')[0]
    $f2 = @($m2.Rows | Where-Object Label -eq 'AD DS, DNS and GPMC')[0]
    ((($m1.Rows | ForEach-Object Kind) -join ',') -eq 'Group,Step,Group,Step,Step') -and ($m1.Rows[1].Time -eq 'earlier') -and ($m1.Rows[1].Mark -eq 'Done') -and
    ($f1.Mark -eq 'Running') -and ($f1.Time -eq '0:48') -and ($m1.State -eq 'running') -and ($m1.Summary -eq '1 of 3 done') -and
    ($f2.Mark -eq 'Done') -and ($f2.Time -eq '6 min 15 s') -and ($f2.Detail -eq 'installed') -and ($m2.State -eq 'waiting') -and ($m2.Summary -eq '2 of 3 done')
}

Test-That 'Step progress: shown under the running step, logged once per change (percent in tens)' {
    Start-NmStepList -Title 'x' -Steps @(@{ Name = 'Features'; Label = 'AD DS, DNS and GPMC' })
    Set-NmStepStatus -Name 'Features' -Status Running
    $before = @(Get-Content -LiteralPath (Get-NmLogPath)).Count
    Write-NmStepProgress -Text 'Installing' -Percent 41
    Write-NmStepProgress -Text 'Installing' -Percent 45
    Write-NmStepProgress -Text 'Installing' -Percent 52
    $row = @((Get-NmStepListModel).Rows | Where-Object Kind -eq 'Step')[0]
    $new = @(Get-Content -LiteralPath (Get-NmLogPath) | Select-Object -Skip $before)
    Stop-NmStepList
    ($row.Progress -eq 'Installing  52 %') -and ($new.Count -eq 2) -and ($new[0] -match 'AD DS, DNS and GPMC: Installing \(41 %\)') -and ($new[1] -match '\(52 %\)')
}

Test-That 'Step list in the console: a line when a step is done or fails; nothing without a list' {
    Start-NmStepList -Title 'x' -Steps @(@{ Name = 'A'; Label = 'Time zone' }, @{ Name = 'B'; Label = 'Static IP' })
    $o = & { Set-NmStepStatus -Name 'A' -Status Running; Set-NmStepStatus -Name 'A' -Status Done -Detail 'Eastern Standard Time'; Set-NmStepStatus -Name 'B' -Status Failed -Detail 'in use' } 6>&1 | Out-String
    Stop-NmStepList
    $none = & { Set-NmStepStatus -Name 'A' -Status Done } 6>&1 | Out-String
    ($o -match '\[done\] Time zone: Eastern Standard Time') -and ($o -match '\[FAILED\] Static IP: in use') -and (-not $none.Trim())
}

Test-That 'Progress records read as one line and a percent' {
    $a = Get-NmGuiProgressText -Record ([pscustomobject]@{ Activity = 'Install-WindowsFeature'; StatusDescription = 'Installing'; CurrentOperation = ''; PercentComplete = 40 })
    $b = Get-NmGuiProgressText -Record ([pscustomobject]@{ Activity = 'Configuring the DNS Server service'; StatusDescription = 'Processing'; CurrentOperation = ''; PercentComplete = -1 })
    # Install-WindowsFeature puts only the number in its status: the activity is used, the percent once.
    $c = Get-NmGuiProgressText -Record ([pscustomobject]@{ Activity = 'Installing'; StatusDescription = '6%'; CurrentOperation = ''; PercentComplete = 6 })
    ($a.Text -eq 'Installing') -and ($a.Percent -eq 40) -and ($b.Text -eq 'Configuring the DNS Server service') -and ($b.Percent -eq -1) -and
    ($c.Text -eq 'Installing') -and ($c.Percent -eq 6)
}

Test-That 'The status bar keeps the last progress between records' {
    $code = (Get-Command Invoke-NmGuiBackground).ScriptBlock.ToString()
    $loop = $code.Substring($code.IndexOf('while (-not $handle.IsCompleted)'))
    ($code.IndexOf("`$said = ''") -lt $code.IndexOf('while (-not $handle.IsCompleted)')) -and ($loop -notmatch "`$said = ''")
}

Test-That 'A background call''s progress reaches the running step and the log while it runs' {
    Start-NmStepList -Title 'x' -Steps @(@{ Name = 'Features'; Label = 'AD DS, DNS and GPMC' })
    Set-NmStepStatus -Name 'Features' -Status Running
    $before = @(Get-Content -LiteralPath (Get-NmLogPath)).Count
    $script:NmGui.Active = $true
    try {
        $null = Invoke-NmGuiBackground -Status 'Installing' -ScriptBlock { Write-Progress -Activity 'Install-WindowsFeature' -Status 'Installing' -PercentComplete 40; Start-Sleep -Milliseconds 600; 'ok' }
    } finally { $script:NmGui.Active = $false }
    $new = @(Get-Content -LiteralPath (Get-NmLogPath) | Select-Object -Skip $before) -join "`n"
    $it = Get-NmStepItem -Name 'Features'
    Stop-NmStepList
    ($it.Progress -eq 'Installing') -and ($it.Percent -eq 40) -and ($new -match 'AD DS, DNS and GPMC: Installing \(40 %\)')
}

Test-That 'The main window fits the usable screen with a margin: never against the top edge, maximised on a small screen' {
    $vm = Get-NmGuiWindowPlacement -WorkWidth 1920 -WorkHeight 1032          # 1080p less the taskbar
    $big = Get-NmGuiWindowPlacement -WorkWidth 2560 -WorkHeight 1392
    $small = Get-NmGuiWindowPlacement -WorkWidth 1024 -WorkHeight 728
    ($vm.Width -eq 1440) -and ($vm.Height -eq 900) -and ($vm.Top -eq 66) -and ($vm.Left -eq 240) -and (-not $vm.Maximize) -and
    ($big.Top -eq 246) -and (-not $big.Maximize) -and $small.Maximize -and
    ((Get-NmGuiWindowPlacement -WorkWidth 1366 -WorkHeight 728).Height -eq 648) -and
    # 1920 x 1080 at 125 % scaling: 1536 x 826 in the window's units. The 900-high window no longer fits; it shrinks to 746 with the margin.
    ((Get-NmGuiWindowPlacement -WorkWidth 1536 -WorkHeight 826).Height -eq 746) -and ((Get-NmGuiWindowPlacement -WorkWidth 1536 -WorkHeight 826).Top -eq 40)
}

Test-That 'Settings: the window''s results view is a setting (cards by default)' {
    ((Get-NmSetting -Key ResultsView) -eq 'Cards') -and (@($script:NmSettingSections) -contains 'Window')
}

Test-That 'Results table: tool columns first, safe column names, dates and lists as text, # maps back to the row' {
    $rows = @(
        [pscustomobject]@{ User = 'a@x.com'; 'Audit.Operation' = 'SendAs'; Date = [datetime]'2026-11-16 15:04:05'; Groups = @('A', 'B'); RowType = 'x' }
        [pscustomobject]@{ User = 'b@x.com'; 'Audit.Operation' = $null; Date = $null; Groups = @(); RowType = 'x' }
    )
    $tool = [pscustomobject]@{ Columns = @('User', 'Date', 'Missing') }
    $cols = @(Get-NmGuiColumn -Rows $rows -Tool $tool)
    $all = @(Get-NmGuiColumn -Rows $rows -Tool $tool -All)
    $dt = ConvertTo-NmGuiTable -Rows $rows -Columns $all
    (($cols -join ',') -eq 'User,Date') -and ($all -notcontains 'RowType') -and ($dt.Columns.Contains('Audit_Operation')) -and ($dt.Rows[0]['Date'] -eq '2026-11-16 15:04:05') -and
    ($dt.Rows[0]['Groups'] -eq 'A; B') -and ($dt.Rows[1]['Audit_Operation'] -eq '') -and ($dt.Rows[1]['#'] -eq 2)
}
Test-That 'Filter matches text in any column, and odd characters do not break it' {
    $rows = @([pscustomobject]@{ User = 'ann@clientx.com'; Note = "it's 50% [done]*" }, [pscustomobject]@{ User = 'bob@clientx.com'; Note = 'other' })
    $dt = ConvertTo-NmGuiTable -Rows $rows -Columns @('User', 'Note')
    $dt.DefaultView.RowFilter = Get-NmGuiRowFilter -Text 'ANN' -Table $dt
    $c1 = $dt.DefaultView.Count
    $dt.DefaultView.RowFilter = Get-NmGuiRowFilter -Text "it's 50% [done]*" -Table $dt
    $c2 = $dt.DefaultView.Count
    $dt.DefaultView.RowFilter = Get-NmGuiRowFilter -Text '  ' -Table $dt
    ($c1 -eq 1) -and ($c2 -eq 1) -and ($dt.DefaultView.Count -eq 2)
}
Test-That 'Quick answers: menu keys from [1] lines (not [1-3] ranges), Yes/No for [Y/n]' {
    $menu = "   [1] One user`r`n   [2] Several users  20 per call`r`n   [M] Main menu`r`n   [B] Back`r`n   [1-3] Deep-dive into a row"
    $m = @(Get-NmGuiChoice -Text $menu -Prompt ' ')
    $y = @(Get-NmGuiChoice -Text 'Licensed users only? [y/N]' -Prompt ' ')
    $n = @(Get-NmGuiChoice -Text "Type 'clientx' to continue" -Prompt ' ')
    $again = @(Get-NmGuiChoice -Text ($menu + "`r`n> `r`n'' is not an option.`r`nSelect an option") -Prompt ' ')
    $after = @(Get-NmGuiChoice -Text ($menu + "`r`n> 2`r`nRemove ann from Sales? [y/N]") -Prompt ' ')
    $done = @(Get-NmGuiChoice -Text ($menu + "`r`n> 2`r`nUser (UPN)") -Prompt ' ')
    (($m.Key -join ',') -eq '1,2,M,B') -and ($m[1].Label -eq '2  Several users') -and ($m[0].Kind -eq 'Menu') -and (($y.Key -join ',') -eq 'Y,N') -and ($y[0].Kind -eq 'YesNo') -and ($n.Count -eq 0) -and
    (($again.Key -join ',') -eq '1,2,M,B') -and (($after.Key -join ',') -eq 'Y,N') -and ($done.Count -eq 0)
}
Test-That '"Press Enter to continue" is recognised and starts a fresh page after it' {
    $script:NmGui.InputProvider = { param($text, $prompt) '' }
    $script:NmGui.Active = $true
    Write-Host '[2026-11-17 08:56:30] [SUCCESS] ActiveDirectory module loaded.'
    $isCont = Test-NmGuiContinue -Text ($script:NmGui.Buffer.ToString() + 'Press Enter to continue ') -Prompt ' '
    Wait-NmKey
    $after = $script:NmGui.Buffer.ToString()
    Write-Host 'Select an option'
    $notCont = Test-NmGuiContinue -Text $script:NmGui.Buffer.ToString() -Prompt ' '
    $script:NmGui.Active = $false
    $isCont -and (-not $notCont) -and ($after -eq '')
}
Test-That 'Cancel in a dialog stops the action' {
    $script:NmGui.Active = $true
    $script:NmGui.InputProvider = { param($t, $p) $null }
    $cancelled = $false
    try { $null = Read-NmYesNo -Prompt 'Go?' } catch [System.OperationCanceledException] { $cancelled = $true }
    $script:NmGui.Active = $false
    $cancelled -and ($script:NmGui.Buffer.Length -eq 0)
}
Test-That 'Clear-NmScreen starts a fresh dialog page in the window; with the window closed, Write-Host is normal' {
    $script:NmGui.Active = $true
    Write-Host 'old text'
    Show-NmHeader -Title 'Fresh' -Clear
    $page = $script:NmGui.Buffer.ToString()
    $script:NmGui.Active = $false
    $out = & { Write-Host 'console again' } 6>&1 | Out-String
    ($page -notmatch 'old text') -and ($page -match 'Fresh') -and ($out -match 'console again') -and ($script:NmGui.Buffer.ToString() -notmatch 'console again')
}
Test-That 'Question model: a menu becomes a title, rows with icons and tags, and Back as a footer button' {
    $script:NmGui.Active = $true
    $script:Seen = $null
    $script:NmGui.InputProvider = { param($text, $prompt) $script:Seen = Get-NmGuiDialogModel -Text $text -Prompt $prompt; 'B' }
    try {
        $null = Show-NmMenu -Title 'Which mailboxes?' -Back -Options @(
            [pscustomobject]@{ Key = '1'; Label = 'All mailboxes'; Detail = 'user, shared, room, equipment' }
            [pscustomobject]@{ Key = '2'; Label = 'Shared mailboxes' }
            [pscustomobject]@{ Key = '3'; Label = 'Remove access'; Tag = '[CHANGE]' }
        )
    } finally { $script:NmGui.InputProvider = $null; $script:NmGui.Active = $false; Clear-NmGuiBuffer }
    $m = $script:Seen
    ($m.Kind -eq 'Menu') -and ($m.Title -eq 'Which mailboxes?') -and ($m.Rows.Count -eq 3) -and (@($m.Footer).Count -eq 1) -and ($m.Footer[0].Name -eq 'Back') -and
    ($m.Rows[0].Detail -eq 'user, shared, room, equipment') -and ($m.Rows[2].Tag -eq 'Can change') -and ($m.Rows[2].Name -eq 'Remove access') -and
    ($m.Rows[0].Icon -eq [string][char]0xE8FD) -and ($m.Rows[1].Icon -eq [string][char]0xE716) -and ($m.Rows[2].Icon -eq [string][char]0xE74D) -and ($m.Default -eq '1') -and (-not $m.Context)
}
Test-That 'Question model: yes/no takes the question as the title and highlights the default; typed questions keep a box' {
    $y = Get-NmGuiDialogModel -Text "Include archive sizes? [Y/n]" -Prompt ' '
    $n = Get-NmGuiDialogModel -Text "Some notes`r`nRemove ann from Sales? [y/N]" -Prompt ' '
    $t = Get-NmGuiDialogModel -Text "Mailbox (email, or part of a name): " -Prompt ' '
    ($y.Kind -eq 'YesNo') -and ($y.Title -eq 'Include archive sizes?') -and ($y.Default -eq 'Y') -and ($n.Default -eq 'N') -and ($n.Context -eq 'Some notes') -and
    ($n.Title -eq 'Remove ann from Sales?') -and ($t.Kind -eq 'Text') -and ($t.Title -eq 'Mailbox (email, or part of a name)') -and (@($y.Rows).Count -eq 2)
}
Test-That 'Icons: words pick the icon; nothing matching gets the neutral dot' {
    ((Get-NmGuiChoiceIcon 'Grant access') -eq [string][char]0xE710) -and ((Get-NmGuiChoiceIcon 'User mailboxes') -eq [string][char]0xE77B) -and ((Get-NmGuiChoiceIcon 'One mailbox') -eq [string][char]0xE715) -and
    ((Get-NmGuiChoiceIcon 'Room and equipment mailboxes') -eq [string][char]0xE787) -and ((Get-NmGuiChoiceIcon 'Zebra') -eq [string][char]0xE91F)
}
Test-That 'Capture: Format-Table output is kept as a table (calculated columns too) while the window is open' {
    Clear-NmGuiBuffer
    $script:NmGui.Active = $true
    try {
        Write-Host 'Members of Sales (2)'
        $m = @([pscustomobject]@{ DisplayName = 'Jane Smith'; Mail = 'jane@clientx.com'; Type = 'UserMailbox'; Secret = 'x' },
               [pscustomobject]@{ DisplayName = 'Sales'; Mail = 'sales@clientx.com'; Type = 'SharedMailbox'; Secret = 'y' })
        $m | Format-Table DisplayName, @{ Label = 'Address'; Expression = { $_.Mail }; Width = 30 }, Type -AutoSize | Out-Host
        $cap = $script:NmGui.Captures[0]
        $text = $script:NmGui.Buffer.ToString()
    } finally { $script:NmGui.Active = $false }
    ($script:NmGui.Captures.Count -eq 1) -and (($cap.Columns -join ',') -eq 'DisplayName,Address,Type') -and ($cap.Rows[1].Address -eq 'sales@clientx.com') -and
    ($cap.Title -eq 'Members of Sales (2)') -and ($text -notlike '*jane@clientx.com*') -and (-not ($cap.Rows[0].PSObject.Properties.Name -contains 'Secret'))
}
Test-That 'Capture: Format-List and plain values are kept; nothing is kept with the window closed; clearing the screen clears them' {
    Clear-NmGuiBuffer
    $script:NmGui.Active = $true
    try {
        [pscustomobject]@{ Name = 'A'; Size = 3 } | Format-List | Out-Host
        @('one', 'two') | Format-Table | Out-Host
        $kinds = @($script:NmGui.Captures | ForEach-Object Kind) -join ','
        $vals = ($script:NmGui.Captures[1].Rows | ForEach-Object Value) -join ','
    } finally { $script:NmGui.Active = $false }
    $n = $script:NmGui.Captures.Count
    Clear-NmGuiBuffer
    [pscustomobject]@{ Name = 'B' } | Format-Table | Out-String | Out-Null
    ($kinds -eq 'List,Table') -and ($vals -eq 'one,two') -and ($n -eq 2) -and ($script:NmGui.Captures.Count -eq 0)
}
Test-That 'Results window: summary counts and breaks down by a column with a few values' {
    $rows = @(1..5 | ForEach-Object { [pscustomobject]@{ Name = "u$_"; Type = $(if ($_ -le 3) { 'UserMailbox' } else { 'SharedMailbox' }); Mail = "u$_@x.com" } })
    $a = Get-NmGuiTableSummary -Rows $rows -Columns @('Name', 'Mail', 'Type')
    $b = Get-NmGuiTableSummary -Rows @($rows[0]) -Columns @('Name', 'Type')
    $dot = [char]0x00B7
    ($a -eq "5 rows  $dot  3 UserMailbox  $dot  2 SharedMailbox") -and ($b -eq '1 row')
}
Test-That 'Results window: text filter keeps matching lines, any case; empty filter keeps all' {
    $t = "Jane Smith  jane@a.com`r`nBob Jones  bob@clienty.com`r`nSales  sales@CLIENTY.com"
    (@(Select-NmGuiTextLine -Text $t -Filter 'clienty').Count -eq 2) -and (@(Select-NmGuiTextLine -Text $t -Filter ' ').Count -eq 3)
}
Test-That 'Results window layout: well-formed, styles resolve, every control the code uses is there' {
    $ns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $x = [xml]($script:NmGuiViewerXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $names = @($x.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $_.GetAttribute('Name', $ns) })
    $code = (Get-Command Show-NmGuiViewer).ScriptBlock.ToString()
    $need = @([regex]::Matches([regex]::Match($code, "foreach \(\`$n in ([^)]*)\)").Groups[1].Value, "'([A-Za-z]+)'") | ForEach-Object { $_.Groups[1].Value })
    ($need.Count -ge 9) -and (@($need | Where-Object { $names -notcontains $_ }).Count -eq 0)
}
Test-That 'CSV exports carry a byte-order mark so Excel reads accented names' {
    $p = Export-NmResult -Data @([pscustomobject]@{ Name = 'Jos' + [char]0x00E9 }) -ToolId 'bomtest' -Format Csv -NoPrompt
    $bytes = [System.IO.File]::ReadAllBytes($p)
    Remove-Item $p -ErrorAction SilentlyContinue
    ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
}
Test-That 'Progress: the status bar shows activity, step and percent; nested bars show the latest; completed hides it' {
    $script:NmGui.Progress = $null
    $v1 = Update-NmGuiProgressState -Activity 'Auditing mailbox delegation' -Status '[6/25] Discovery Search Mailbox' -PercentComplete 24
    $v2 = Update-NmGuiProgressState -Id 1 -Activity 'Reading folders' -Status 'Processing'
    $v3 = Update-NmGuiProgressState -Id 1 -Completed
    $v4 = Update-NmGuiProgressState -Completed
    $v1.Visible -and ($v1.Text -eq 'Auditing mailbox delegation: [6/25] Discovery Search Mailbox') -and ($v1.Percent -eq 24) -and
    ($v2.Text -eq 'Reading folders') -and ($v2.Percent -eq -1) -and ($v3.Text -eq $v1.Text) -and (-not $v4.Visible)
}
Test-That 'Progress: a tool''s Write-Progress goes to the window while it is open, not the console' {
    $script:NmGui.Progress = $null
    $script:NmGui.Active = $true
    Write-Progress -Activity 'Collecting mailboxes' -Status '[2/5] alice' -PercentComplete 40
    $shown = Update-NmGuiProgressState -Id 99 -Completed   # read the current view without changing it
    $script:NmGui.Active = $false
    $shown.Visible -and ($shown.Text -eq 'Collecting mailboxes: [2/5] alice') -and ($shown.Percent -eq 40)
}
Test-That 'Details card fields: column order, lists joined, dates formatted, empty values left out' {
    $row = [pscustomobject]@{ Name = 'Jane'; Groups = @('Sales', 'Staff'); When = [datetime]'2026-11-17T15:24:00'; Note = ''; Count = 3 }
    $f = @(Get-NmGuiDetailField -Row $row -Columns @('When', 'Name', 'Groups', 'Note', 'Count', 'Missing'))
    $all = @(Get-NmGuiDetailField -Row $row -KeepEmpty)
    (($f | ForEach-Object Name) -join ',') -eq 'When,Name,Groups,Count' -and ($f[0].Value -eq '2026-11-17 15:24') -and ($f[2].Value -eq 'Sales; Staff') -and ($all.Count -eq 5)
}
Test-That 'Details card title: a name-like field first, else the first value; filter matches any value' {
    $a = Get-NmGuiCardTitle -Row ([pscustomobject]@{ Id = 7; DisplayName = 'Jane Doe'; Mail = 'jane@clientx.com' })
    $b = Get-NmGuiCardTitle -Row ([pscustomobject]@{ Id = 7; Mail = 'jane@clientx.com' })
    $r = [pscustomobject]@{ A = 'x'; B = @('one', 'Two words') }
    ($a.Text -eq 'Jane Doe') -and ($a.Field -eq 'DisplayName') -and ($b.Text -eq '7') -and (Test-NmGuiRowMatch -Row $r -Text 'two w') -and -not (Test-NmGuiRowMatch -Row $r -Text 'three') -and (Test-NmGuiRowMatch -Row $r -Text '  ')
}
Test-That 'Severity colours: each severity has its own, anything else is grey' {
    $h = Get-NmGuiSeverityColor -Severity 'High'; $m = Get-NmGuiSeverityColor -Severity 'Medium'; $x = Get-NmGuiSeverityColor -Severity 'Whatever'; $i = Get-NmGuiSeverityColor -Severity 'Info'
    ($h.Fore -ne $m.Fore) -and ($x.Fore -eq $i.Fore) -and ($h.Back -match '^#[0-9A-F]{6}$')
}
Test-That 'Status colours: failed red, done green, WhatIf and cancelled grey, a severity as itself' {
    ((Get-NmGuiStatusLevel -Column 'Result' -Value 'Failed: no mailbox') -eq 'High') -and ((Get-NmGuiStatusLevel -Column 'Result' -Value 'Granted') -eq 'OK') -and
        ((Get-NmGuiStatusLevel -Column 'Result' -Value 'WhatIf: not changed') -eq 'Info') -and ((Get-NmGuiStatusLevel -Column 'Result' -Value 'Cancelled') -eq 'Info') -and
        ((Get-NmGuiStatusLevel -Column 'Severity' -Value 'Medium') -eq 'Medium') -and ((Get-NmGuiStatusLevel -Column 'Type' -Value 'UserMailbox') -eq 'Info')
}
Test-That 'Tag column: Result (by its first word) when there is one, else a column with a few repeating values, else none' {
    $a = @([pscustomobject]@{ Mailbox = 'a'; Result = 'Granted' }, [pscustomobject]@{ Mailbox = 'b'; Result = 'Failed: no mailbox' }, [pscustomobject]@{ Mailbox = 'c'; Result = 'Failed: locked' })
    $b = @(1..6 | ForEach-Object { [pscustomobject]@{ Name = "n$_"; Type = $(if ($_ -le 4) { 'UserMailbox' } else { 'SharedMailbox' }); Size = "$_ GB" } })
    $c = @(1..3 | ForEach-Object { [pscustomobject]@{ Name = "n$_"; Size = "$_ GB" } })
    ((Get-NmGuiFacetColumn -Rows $a -Columns @('Mailbox', 'Result')) -eq 'Result') -and ((Get-NmGuiFacetValue -Column 'Result' -Value 'Failed: no mailbox') -eq 'Failed') -and
        ((Get-NmGuiFacetColumn -Rows $b -Columns @('Name', 'Type', 'Size')) -eq 'Type') -and ((Get-NmGuiFacetColumn -Rows $c -Columns @('Name', 'Size')) -eq '')
}
Test-That 'Card model: tags with counts, clicking one keeps only its rows, the title and tag column are not repeated as fields, and the rest goes under More' {
    $rows = @(
        [pscustomobject]@{ Mailbox = 'jane@clientx.com'; Delegate = 'amy@clientx.com'; Result = 'Granted'; Note = 'x'; Extra = 'kept' }
        [pscustomobject]@{ Mailbox = 'bob@clientx.com'; Delegate = 'amy@clientx.com'; Result = 'Failed: no mailbox'; Note = ''; Extra = '' }
        [pscustomobject]@{ Mailbox = 'sam@clientx.com'; Delegate = 'amy@clientx.com'; Result = 'Failed: locked'; Note = ''; Extra = '' }
    )
    $all = Get-NmGuiCardModel -Rows $rows -Columns @('Mailbox', 'Delegate', 'Result', 'Note')
    $fail = Get-NmGuiCardModel -Rows $rows -Columns @('Mailbox', 'Delegate', 'Result', 'Note') -Facet 'Failed'
    $f0 = $all.Items[0]
    ($all.FacetColumn -eq 'Result') -and ((($all.Facets | ForEach-Object { "$($_.Count) $($_.Value) $($_.Level)" }) -join ',') -eq '2 Failed High,1 Granted OK') -and
        ($fail.Shown -eq 2) -and ($fail.Items[0].Index -eq 1) -and ($f0.Title -eq 'jane@clientx.com') -and
        (($f0.Fields | ForEach-Object Name) -notcontains 'Result') -and (($f0.More | ForEach-Object Name) -join ',') -eq 'Extra' -and ($f0.Level -eq 'OK')
}
Test-That 'Card model: only the first cards are drawn, the rest counted for Show more' {
    $rows = @(1..250 | ForEach-Object { [pscustomobject]@{ Name = "user$_"; Size = $_ } })
    $m = Get-NmGuiCardModel -Rows $rows -Columns @('Name', 'Size') -Limit 100
    $f = Get-NmGuiCardModel -Rows $rows -Columns @('Name', 'Size') -Filter 'user24'
    (@($m.Items).Count -eq 100) -and ($m.Remaining -eq 150) -and ($f.Shown -eq 11) -and ($f.Remaining -eq 0)
}
Test-That 'Selection bar: only for tools with bulk actions and results; buttons enabled once something is ticked' {
    $tool = [pscustomobject]@{ BulkAction = 'Invoke-X'; BulkActions = @('Release', 'Block senders') }
    $none = Get-NmGuiSelectionModel -Tool $tool -RowCount 5 -SelectedCount 0
    $two = Get-NmGuiSelectionModel -Tool $tool -RowCount 5 -SelectedCount 2
    $plain = Get-NmGuiSelectionModel -Tool ([pscustomobject]@{ BulkAction = $null }) -RowCount 5 -SelectedCount 0
    $empty = Get-NmGuiSelectionModel -Tool $tool -RowCount 0 -SelectedCount 0
    $none.Visible -and ($none.Text -eq 'None selected') -and (@($none.Actions | Where-Object Enabled).Count -eq 0) -and
        ($two.Text -eq '2 selected') -and (@($two.Actions | Where-Object Enabled).Count -eq 2) -and ((@($two.Actions | ForEach-Object Label) -join ',') -eq 'Release,Block senders') -and
        -not $plain.Visible -and -not $empty.Visible
}
Test-That 'Selection: table rows map to their row numbers; card ticks add and remove; cards know what they show' {
    $rows = @(1..5 | ForEach-Object { [pscustomobject]@{ Name = "user$_"; Result = $(if ($_ % 2) { 'Added' } else { 'Failed: x' }) } })
    $dt = ConvertTo-NmGuiTable -Rows $rows -Columns @('Name', 'Result')
    $view = $dt.DefaultView
    $picked = @(Get-NmGuiGridSelectedIndex -Items @($view[1], $view[3]))
    $script:NmGui.Selected.Clear()
    Set-NmGuiRowSelected -Index 2 -Selected $true; Set-NmGuiRowSelected -Index 4 -Selected $true; Set-NmGuiRowSelected -Index 2 -Selected $false
    $sel = @($script:NmGui.Selected)
    $m = Get-NmGuiCardModel -Rows $rows -Columns @('Name', 'Result') -Facet 'Failed'
    $script:NmGui.Selected.Clear()
    (($picked -join ',') -eq '1,3') -and (($sel -join ',') -eq '4') -and ((@($m.ShownIndex) -join ',') -eq '1,3')
}
Test-That 'Grouped cards: one card per mailbox, entries listed in full under each list, tags still filter the rows' {
    $rows = @(
        [pscustomobject]@{ Mailbox = 'jane@clientx.com'; List = 'Safe'; Entry = 'vendor.com'; Result = '' }
        [pscustomobject]@{ Mailbox = 'jane@clientx.com'; List = 'Safe'; Entry = 'partner.com'; Result = '' }
        [pscustomobject]@{ Mailbox = 'bob@clientx.com'; List = 'Blocked'; Entry = 'spam@bad.com'; Result = '' }
        [pscustomobject]@{ Mailbox = 'jane@clientx.com'; List = 'Blocked'; Entry = 'evil.com'; Result = '' }
    )
    $cols = @('Mailbox', 'List', 'Entry', 'Result')
    $m = Get-NmGuiCardModel -Rows $rows -Columns $cols -GroupBy @('Mailbox', 'List')
    $b = Get-NmGuiCardModel -Rows $rows -Columns $cols -GroupBy @('Mailbox', 'List') -Facet 'Blocked'
    $jane = $m.Items[0]
    ($m.Cards -eq 2) -and ($m.Shown -eq 4) -and ($jane.Title -eq 'jane@clientx.com') -and ($m.FacetColumn -eq 'List') -and
        ((($jane.Fields | ForEach-Object Name) -join '|') -eq 'Safe (2)|Blocked') -and ($jane.Fields[0].Value -eq "vendor.com`npartner.com") -and
        ($b.Cards -eq 2) -and ((@($b.Items[0].Fields) | ForEach-Object Name) -join '|') -eq 'Blocked' -and
        ((Get-NmGuiCardCountText -Model $m) -eq '4 rows in 2 cards, one per Mailbox.')
}
Test-That 'Grouped cards: a change run keeps each row''s result and the card shows the worst' {
    $rows = @(
        [pscustomobject]@{ Mailbox = 'jane@clientx.com'; List = 'Safe'; Entry = 'a.com'; Result = 'Added' }
        [pscustomobject]@{ Mailbox = 'jane@clientx.com'; List = 'Safe'; Entry = 'b.com'; Result = 'Failed: locked' }
        [pscustomobject]@{ Mailbox = 'bob@clientx.com'; List = 'Safe'; Entry = 'a.com'; Result = 'Added' }
    )
    $m = Get-NmGuiCardModel -Rows $rows -Columns @('Mailbox', 'List', 'Entry', 'Result') -GroupBy @('Mailbox', 'List') -Limit 1
    $jane = $m.Items[0]
    ($m.FacetColumn -eq 'Result') -and ($jane.Status -eq 'Mixed') -and ($jane.Level -eq 'High') -and ($jane.Fields[0].Value -eq "a.com - Added`nb.com - Failed: locked") -and
        (@($m.Items).Count -eq 1) -and ($m.Remaining -eq 1)
}
Test-That 'Grouped cards: a group column the rows do not have falls back to a card per row' {
    $rows = @(1..3 | ForEach-Object { [pscustomobject]@{ Name = "user$_"; Size = $_ } })
    $m = Get-NmGuiCardModel -Rows $rows -Columns @('Name', 'Size') -GroupBy @('Mailbox')
    (@($m.Items).Count -eq 3) -and (-not $m.GroupBy)
}
Test-That 'Pop-up section names: the part after the screen title, not cut short' {
    ((Get-NmGuiSectionName -Title 'Mailbox: Admin (admin@clientx.onmicrosoft.com) > Size and activity' -Heading 'Mailbox: Admin (admin@clientx.onmicrosoft.com)') -eq 'Size and activity') -and
        ((Get-NmGuiSectionName -Title 'Mailbox: Admin' -Heading 'Mailbox: Admin') -eq '') -and ((Get-NmGuiSectionName -Title 'Members of Sales' -Heading 'Group') -eq 'Members of Sales')
}
Test-That 'Pop-up layout: one table alone, a few small ones as sections on one page, big ones as tabs' {
    ((Get-NmGuiViewerMode -RowCounts @(1)) -eq 'Single') -and ((Get-NmGuiViewerMode -RowCounts @(1, 1, 3, 1)) -eq 'Sections') -and
        ((Get-NmGuiViewerMode -RowCounts @(1, 120)) -eq 'Tabs') -and ((Get-NmGuiViewerMode -RowCounts @(1, 1, 1, 1, 1, 1, 1, 1, 1)) -eq 'Tabs')
}
Test-That 'Pop-up notes: the warnings and errors the tool wrote, without the timestamps' {
    $t = "[2026-11-18 16:51:13] [INFO] Retrieving mailboxes...`n[2026-11-18 16:51:14] [WARN] Inbox rules not read: Rules unavailable`n[2026-11-18 16:51:15] [ERROR] Holds not read: denied"
    $n = @(Get-NmGuiNoteLine -Text $t)
    ($n.Count -eq 2) -and ($n[0].Level -eq 'WARN') -and ($n[0].Text -eq 'Inbox rules not read: Rules unavailable') -and ($n[1].Level -eq 'ERROR')
}
Test-That 'Copy all: every section as text, with its heading and named fields; True/False read Yes/No' {
    $secs = @(
        [pscustomobject]@{ Name = 'Holds'; Capture = [pscustomobject]@{ Columns = @('LitigationHold', 'RetentionPolicy'); Rows = @([pscustomobject]@{ LitigationHold = $false; RetentionPolicy = 'Default MRM Policy' }) } }
        [pscustomobject]@{ Name = 'Who has access'; Capture = [pscustomobject]@{ Columns = @('Access'); Rows = @([pscustomobject]@{ Access = 'Nobody else has access' }) } }
    )
    $t = Get-NmGuiSectionText -Sections $secs -Heading 'Mailbox: Jane'
    ($t -match '^Mailbox: Jane') -and ($t -match 'Holds\r?\n  Litigation hold: No\r?\n  Retention policy: Default MRM Policy') -and ($t -match 'Who has access\r?\n  Access: Nobody else has access') -and
        ((ConvertTo-NmGuiFieldText $true) -eq 'Yes') -and ((ConvertTo-NmGuiFieldText @($false, 'x')) -eq 'No; x')
}

Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '=============================================' -ForegroundColor Cyan
if ($script:Failed.Count -eq 0) {
    Write-Host "   All $script:Passed tests passed." -ForegroundColor Green
    Write-Host '=============================================' -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "   $($script:Failed.Count) failed, $script:Passed passed:" -ForegroundColor Red
    $script:Failed | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    Write-Host '=============================================' -ForegroundColor Cyan
    exit 1
}
