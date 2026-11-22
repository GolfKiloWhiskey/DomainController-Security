# ---------------------------------------------------------------------------
# Gui.ps1 - Start-NmToolkitGui: a WPF window over the same tools
# Ported from the Nutmeg M365 Toolkit's window (copied and adapted, not shared): the tenant
# chooser, cloud switch, sign-in and name lookups are gone; the header shows the domain and the DC.
# ---------------------------------------------------------------------------
# The window does not have its own copy of any tool. It:
#   - lists the registered tools by category, with search;
#   - builds an options form from each tool's entry-function parameters (switches, choices,
#     numbers, lists, text), or walks the tool's own questions ("Guided");
#   - runs the entry function and shows the rows in a sortable, filterable grid, with export,
#     summary and the tool's row screen.
# Everything the console would print or ask while a tool runs (change confirmations, user pickers,
# row actions, the Domain and DC menu) goes through the same Write-Host / Out-Host / Read-NmHost calls.
# While the window is open those are redirected here: text collects in a buffer, and each prompt
# becomes a dialog that shows the text since the last prompt, with buttons for the menu keys.
# Windows only (WPF), and the PowerShell thread must be STA (Windows PowerShell 5.1 is; pwsh 7 too).

$script:NmGui = @{
    Active        = $false
    Buffer        = New-Object System.Text.StringBuilder
    Transcript    = New-Object System.Text.StringBuilder
    Window        = $null
    Controls      = @{}
    InputProvider = $null     # tests: scriptblock(text, prompt) -> answer
    SecretProvider = $null    # tests: scriptblock(prompt) -> SecureString or $null (cancel)
    BuildMode     = $false    # opened with -NewForest: the New Forest Build only, its questions start at once
    Tool          = $null
    Rows          = @()
    Table         = $null
    Spec          = @()
    Inputs        = @{}
    Open          = @{}       # sidebar: area id -> expanded
    Selection     = $null     # sidebar: '<center id>|<section>'
    Quiet         = $false    # true while code (not the user) clears the search box
    ShownTarget   = $null     # 'domain|DC' whose results are on screen (cleared when it changes)
    Captures      = (New-Object System.Collections.Generic.List[object])   # tables the tool printed since the screen was cleared
    LastCaptures  = @()       # the captures that went with LastLeftover
    TableEnd      = 0         # buffer position where the last printed table ended
    Marks         = @{}       # coloured lines written since the screen was cleared: text -> Red, Yellow, Green or Cyan
    TableText     = $false    # set by Format-Table / Format-List: the next Out-Host is a captured table (kept as a table, not text)
    ConfirmProvider = $null   # tests: scriptblock(model) -> $true / $false
    Progress      = $null     # Write-Progress records by Id while a tool runs
    ProgressClock = $null     # throttles progress repaints
    CardMode      = $true     # results as cards (Settings > Window); the toggle switches to the table
    Facet         = ''        # the tag clicked to filter the cards ('' = all)
    CardLimit     = 100       # cards drawn; Show more adds 100
    Kept          = @{}       # tool id -> the last results (Rows, Title, Target), shown again when the tool is picked
    Selected      = (New-Object 'System.Collections.Generic.HashSet[int]')   # rows ticked for a bulk action (indexes into Rows)
    ShownIndex    = @()       # the rows the cards show now (filter and tag applied), for Select all shown
}

# The New Forest Build's area and tool. The normal window leaves them out (they are for a fresh
# workgroup server); the window opened with -NewForest shows only them.
$script:NmGuiConsoleOnlyAreas = @('build')
$script:NmGuiConsoleOnlyTools = @('new-forest')

# Every named control Start-NmToolkitGui looks up in the main window (the tests check each is in the XAML).
$script:NmGuiMainControls = @('VersionText', 'DomainButton', 'DomainLabel', 'DomainText', 'ServicePanel', 'SettingsButton', 'SettingsGlyph', 'SearchBox', 'HistoryButton',
    'CenterPanel', 'ToolListCenter', 'ToolListTitle', 'ToolList', 'ToolTitle', 'ChangeTag', 'ToolMeta', 'OptionsBorder', 'OptionsPanel', 'ActionRow',
    'RunButton', 'GuidedButton', 'PreviewBox', 'ResultTitle', 'DetailsButton', 'SummaryButton', 'ExportTxtButton', 'ExportCsvButton',
    'AllColumnsBox', 'FilterBox', 'ResultsGrid', 'CardScroll', 'CardHost', 'ViewToggle', 'ClearButton', 'LogBox', 'StatusText', 'ProgressPanel', 'ProgressText', 'ProgressBar',
    'SearchHint', 'FilterHint', 'ResultBar', 'EmptyText', 'OutputExpander', 'SelectionBar', 'SelectionText', 'SelectAllButton', 'SelectNoneButton', 'SelectionActions',
    'StepBorder', 'StepTitle', 'StepSummary', 'StepPanel')

# ---------------------------------------------------------------------------
# Output and prompt redirection (inert unless the window is open)
# ---------------------------------------------------------------------------

function Write-Host {
    # Same parameters as the real Write-Host; only diverts while the window is open.
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)][object]$Object,
        [switch]$NoNewline,
        [object]$Separator = ' ',
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor
    )
    process {
        if ($script:NmGui.Active) {
            $text = if ($null -eq $Object) { '' }
                    elseif ($Object -is [string]) { $Object }
                    elseif ($Object -is [System.Collections.IEnumerable]) { (@($Object) | ForEach-Object { "$_" }) -join "$Separator" }
                    else { "$Object" }
            # Coloured lines (errors, warnings, headings) keep their meaning for the dialogs.
            if (-not $NoNewline -and $PSBoundParameters.ContainsKey('ForegroundColor') -and "$text".Trim() -and "$text" -notmatch '^\s*[=\-_]{5,}\s*$' -and @('Red', 'Yellow', 'Green', 'Cyan') -contains "$ForegroundColor") {
                if ($null -eq $script:NmGui.Marks) { $script:NmGui.Marks = @{} }
                $script:NmGui.Marks["$text".Trim()] = "$ForegroundColor"
            }
            Add-NmGuiText -Text $text -NoNewline:$NoNewline
            return
        }
        Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
    }
}

function Out-Host {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)][psobject]$InputObject, [switch]$Paging)
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { $items.Add($InputObject) }
    end {
        if ($script:NmGui.Active) {
            if ($items.Count -and $script:NmGui.TableText -and $items[0].GetType().FullName -like 'Microsoft.PowerShell.Commands.Internal.Format.*') {
                # A table the window already kept (Format-Table / Format-List): it is shown as a
                # table, so its text goes only to the Output panel, never into a dialog.
                $script:NmGui.TableText = $false
                [void]$script:NmGui.Transcript.Append((($items | Out-String -Width 220).TrimEnd()) + "`r`n")
                return
            }
            if ($items.Count) {
                Add-NmGuiText -Text (($items | Out-String -Width 220).TrimEnd())
                # Remember where printed tables end, so the next table is not titled by one of their rows.
                if ($items[0].GetType().FullName -like 'Microsoft.PowerShell.Commands.Internal.Format.*') { $script:NmGui.TableEnd = $script:NmGui.Buffer.Length }
            }
            return
        }
        if ($items.Count) { $items | Microsoft.PowerShell.Core\Out-Host }
    }
}

function Write-Progress {
    # Same parameters as the real Write-Progress; while the window is open, progress goes to the
    # window's status bar instead (every tool reports progress this way, so none of them change).
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Activity,
        [Parameter(Position = 1)][string]$Status,
        [Parameter(Position = 2)][int]$Id = 0,
        [int]$PercentComplete = -1,
        [int]$SecondsRemaining = -1,
        [string]$CurrentOperation,
        [int]$ParentId = -1,
        [switch]$Completed,
        [int]$SourceId
    )
    if ($script:NmGui.Active) {
        $view = Update-NmGuiProgressState -Activity $Activity -Status $Status -Id $Id -PercentComplete $PercentComplete -CurrentOperation $CurrentOperation -Completed:$Completed
        Show-NmGuiProgress -View $view -Force:($Completed -or -not $view.Visible)
        return
    }
    if (-not $PSBoundParameters.ContainsKey('Activity')) { $PSBoundParameters['Activity'] = 'Working' }   # Windows PowerShell 5.1 needs one
    Microsoft.PowerShell.Utility\Write-Progress @PSBoundParameters
}

function Update-NmGuiProgressState {
    <#
    .SYNOPSIS
        Keeps the progress records by Id and returns what the status bar shows: Visible, Text and
        Percent (-1 when the tool gives none). The most recently updated record is shown. No WPF.
    #>
    param([string]$Activity, [string]$Status, [int]$Id = 0, [int]$PercentComplete = -1, [string]$CurrentOperation, [switch]$Completed)
    if ($null -eq $script:NmGui.Progress) { $script:NmGui.Progress = New-Object System.Collections.Specialized.OrderedDictionary }
    $p = $script:NmGui.Progress
    $key = "id$Id"   # string keys: an int would index the ordered dictionary by position
    if ($Completed) {
        if ($p.Contains($key)) { $p.Remove($key) }
    } else {
        $old = if ($p.Contains($key)) { $p[$key] } else { $null }
        $rec = [pscustomobject]@{
            Activity  = $(if ($Activity) { $Activity } elseif ($old) { $old.Activity } else { 'Working' })
            Status    = $(if ($Status) { $Status } else { '' })
            Operation = $CurrentOperation
            Percent   = [Math]::Max(-1, [Math]::Min(100, $PercentComplete))
        }
        if ($p.Contains($key)) { $p.Remove($key) }
        $p.Add($key, $rec)   # last in the list = most recent
    }
    if ($p.Count -eq 0) { return [pscustomobject]@{ Visible = $false; Text = ''; Percent = -1 } }
    $r = @($p.Values)[-1]
    $text = $r.Activity
    if ($r.Status -and $r.Status -ne 'Processing') { $text += ": $($r.Status)" }
    if ($r.Operation) { $text += " ($($r.Operation))" }
    return [pscustomobject]@{ Visible = $true; Text = $text; Percent = $r.Percent }
}

function Show-NmGuiProgress {
    # Draws the progress view in the status bar, at most about 8 times a second unless -Force.
    param([Parameter(Mandatory)]$View, [switch]$Force)
    $c = $script:NmGui.Controls
    if (-not $c.ProgressPanel) { return }
    if (-not $script:NmGui.ProgressClock) { $script:NmGui.ProgressClock = [System.Diagnostics.Stopwatch]::StartNew(); $Force = $true }
    if (-not $Force -and $c.ProgressPanel.Visibility -eq 'Visible' -and $script:NmGui.ProgressClock.ElapsedMilliseconds -lt 120) { return }
    $script:NmGui.ProgressClock.Restart()
    try {
        $c.ProgressPanel.Visibility = $(if ($View.Visible) { 'Visible' } else { 'Collapsed' })
        $c.ProgressText.Text = $View.Text
        $c.ProgressText.ToolTip = $View.Text
        $c.ProgressBar.IsIndeterminate = ($View.Percent -lt 0)
        if ($View.Percent -ge 0) { $c.ProgressBar.Value = $View.Percent }
        $script:NmGui.Window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
    } catch { $null = $_ }
}

function Clear-NmGuiProgress {
    $script:NmGui.Progress = $null
    Show-NmGuiProgress -View ([pscustomobject]@{ Visible = $false; Text = ''; Percent = -1 }) -Force
}

function Format-Table {
    # Same as Format-Table; while the window is open it also keeps the objects, so the window can
    # show them as a real table (sortable, filterable, exportable) instead of text.
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)][psobject]$InputObject,
        [Parameter(Position = 0)][object[]]$Property,
        [object]$GroupBy, [switch]$AutoSize, [switch]$Wrap, [switch]$HideTableHeaders, [string]$View,
        [switch]$Force, [string]$Expand, [switch]$ShowError, [switch]$DisplayError, [switch]$RepeatHeader
    )
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $items.Add($InputObject) } }
    end {
        if ($script:NmGui.Active) { $was = $script:NmGui.Captures.Count; Add-NmGuiCapture -Items $items.ToArray() -Property $Property -Kind 'Table'; $script:NmGui.TableText = ($script:NmGui.Captures.Count -gt $was) }
        $pass = @{}; foreach ($k in $PSBoundParameters.Keys) { if ($k -ne 'InputObject') { $pass[$k] = $PSBoundParameters[$k] } }
        $items | Microsoft.PowerShell.Utility\Format-Table @pass
    }
}

function Format-List {
    # Same as Format-List; while the window is open it also keeps the objects (see Format-Table).
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)][psobject]$InputObject,
        [Parameter(Position = 0)][object[]]$Property,
        [object]$GroupBy, [string]$View, [switch]$Force, [string]$Expand, [switch]$ShowError, [switch]$DisplayError
    )
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $items.Add($InputObject) } }
    end {
        if ($script:NmGui.Active) { $was = $script:NmGui.Captures.Count; Add-NmGuiCapture -Items $items.ToArray() -Property $Property -Kind 'List'; $script:NmGui.TableText = ($script:NmGui.Captures.Count -gt $was) }
        $pass = @{}; foreach ($k in $PSBoundParameters.Keys) { if ($k -ne 'InputObject') { $pass[$k] = $PSBoundParameters[$k] } }
        $items | Microsoft.PowerShell.Utility\Format-List @pass
    }
}

function ConvertTo-NmGuiCapture {
    <#
    .SYNOPSIS
        Objects plus a Format-Table/Format-List property list as plain rows and column names, the
        way they were printed (calculated columns included). No WPF; $null for nothing to show.
    #>
    param([object[]]$Items, [object[]]$Property, [string]$Kind = 'Table', [string]$Title = '')
    $items = @($Items | Where-Object { $null -ne $_ -and $_.GetType().FullName -notlike 'Microsoft.PowerShell.Commands.Internal.Format.*' })
    if (-not $items.Count) { return $null }
    $first = $items[0]
    if ($first -is [string] -or $first -is [ValueType]) {
        return [pscustomobject]@{ Kind = $Kind; Title = $Title; Columns = @('Value'); Rows = @($items | ForEach-Object { [pscustomobject]@{ Value = "$_" } }) }
    }
    $select = New-Object System.Collections.Generic.List[object]
    $cols = New-Object System.Collections.Generic.List[string]
    if ($Property -and -not @($Property | Where-Object { $_ -is [string] -and $_ -match '\*' }).Count) {
        foreach ($p in $Property) {
            if ($p -is [hashtable] -or $p -is [System.Collections.IDictionary]) {
                $name = foreach ($k in 'Label', 'Name', 'L', 'N') { if ($p.Contains($k)) { "$($p[$k])"; break } }
                $expr = foreach ($k in 'Expression', 'E') { if ($p.Contains($k)) { $p[$k]; break } }
                if (-not $name) { $name = "$expr" }
                $select.Add(@{ Name = "$name"; Expression = $expr }); $cols.Add("$name")
            } else { $select.Add("$p"); $cols.Add("$p") }
        }
    } else {
        $default = $first.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
        $names = if ($default) { @($default) } else { @($first.PSObject.Properties | Where-Object { $_.MemberType -match 'Property' } | ForEach-Object Name) }
        foreach ($n in $names) { $select.Add($n); $cols.Add($n) }
    }
    if (-not $cols.Count) { return $null }
    $rows = @($items | Select-Object -Property $select.ToArray())
    return [pscustomobject]@{ Kind = $Kind; Title = $Title; Columns = $cols.ToArray(); Rows = $rows }
}

function Get-NmGuiCaptureTitle {
    <#
    .SYNOPSIS
        A title for a table, from the screen text written before it: the screen's own title (the first
        line of the last header block), and the menu option just picked if the table came from one
        ("Group: Sales > Show members"). Skips the domain status line, Author/Email/Version, borders,
        echoed answers and "Select an option". No WPF.
    #>
    param([string]$Text, [int]$TableEnd = 0)
    $lines = @("$Text" -split "`r?`n")
    # Lines written after the last printed table: only these can name the next one.
    $since = if ($TableEnd -gt 0 -and $TableEnd -le "$Text".Length) { @("$Text".Substring($TableEnd) -split "`r?`n").Count } else { $lines.Count }
    $border = '^\s*[=\-_]{5,}\s*$'
    $menuLine = '^\s*\[([0-9A-Za-z]{1,3})\]\s+(.+?)\s*$'
    $noise = '^\s*(Domain:\s.*\|.*|Author:.*|Email:.*|Version:.*|Select an option\s*|.*is not an option\.?\s*)$'

    # The screen title: first line after a border that starts a header block (Author on a following line).
    $screen = ''
    for ($i = 0; $i -lt $lines.Count - 2; $i++) {
        if ($lines[$i] -match $border -and "$($lines[$i + 1])".Trim() -and $lines[$i + 1] -notmatch $border -and "$($lines[$i + 2])" -match '^\s*Author:') { $screen = "$($lines[$i + 1])".Trim() }
    }

    # The option picked last, if the table follows an answer to a menu.
    $picked = ''
    $floor = [Math]::Max(0, $lines.Count - $since)
    for ($i = $lines.Count - 1; $i -ge $floor; $i--) {
        $l = "$($lines[$i])"
        if (-not $l.Trim() -or $l -match $border -or $l -match $noise) { continue }
        if ($l -match '^> (.*)$') {
            $key = $Matches[1].Trim().ToUpper()
            for ($j = $i - 1; $j -ge 0; $j--) {
                if ("$($lines[$j])" -match '^> ') { break }
                if ("$($lines[$j])" -match $menuLine -and $Matches[1].ToUpper() -eq $key) {
                    $picked = ($Matches[2] -split '\s{2,}')[0] -replace '\s*\[CHANGE\]\s*$', ''
                    break
                }
            }
            break
        }
        if ($l -match $menuLine) { continue }
        # A plain line just before the table (for example "Members of Sales (143)") names it best.
        $near = $l.Trim().TrimEnd(':')
        if ($near -ne $screen) { return $(if ($screen) { "$screen > $near" } else { $near }) }
        break
    }
    if ($picked -and $screen) { return "$screen > $picked" }
    if ($picked) { return $picked }
    return $screen
}

function Add-NmGuiCapture {
    # Keeps what Format-Table / Format-List printed, titled by the last line written before it.
    param([object[]]$Items, [object[]]$Property, [string]$Kind)
    try {
        $title = Get-NmGuiCaptureTitle -Text $script:NmGui.Buffer.ToString() -TableEnd ([int]$script:NmGui.TableEnd)
        $cap = ConvertTo-NmGuiCapture -Items $Items -Property $Property -Kind $Kind -Title $title
        if ($cap) { $script:NmGui.Captures.Add($cap) }
    } catch { Write-NmLog "Could not keep a table for the window: $($_.Exception.Message)" -Level WARN -NoConsole }
}

function Get-NmGuiTableSummary {
    <#
    .SYNOPSIS
        "143 rows | 120 UserMailbox | 23 SharedMailbox": the count, broken down by the first column
        (after the first) with 2 to 6 different values that repeat. No WPF.
    #>
    param([object[]]$Rows, [string[]]$Columns, [string]$Noun = 'row')
    $n = @($Rows).Count
    $text = "$n $Noun$(if ($n -ne 1) { 's' })"
    foreach ($c in @($Columns | Select-Object -Skip 1)) {
        $vals = @($Rows | ForEach-Object { "$($_.$c)" } | Where-Object { $_ -and $_.Length -le 40 })
        if ($vals.Count -lt [Math]::Max(2, $n / 2)) { continue }
        $groups = @($vals | Group-Object | Sort-Object Count -Descending)
        if ($groups.Count -ge 2 -and $groups.Count -le 6 -and $groups.Count -lt $vals.Count) {
            return "$text  $([char]0x00B7)  " + ((@($groups | ForEach-Object { "$($_.Count) $($_.Name)" })) -join "  $([char]0x00B7)  ")
        }
    }
    return $text
}

function Select-NmGuiTextLine {
    # Lines of text containing the filter (any case); all lines when the filter is empty.
    param([string]$Text, [string]$Filter)
    $lines = @("$Text" -split "`r?`n")
    if (-not "$Filter".Trim()) { return $lines }
    $f = "$Filter".Trim()
    return @($lines | Where-Object { $_.IndexOf($f, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
}

function Test-NmGuiFurniture {
    # True for console header lines: borders, Author, Email, Version, the domain status line, the nav path.
    param([string]$Text)
    return ("$Text" -match '^\s*[=\-_]{5,}\s*$' -or "$Text" -match '^\s*(Author|Email|Version):' -or "$Text" -match '^\s*Domain: .*\|' -or "$Text" -match '^\s*Main Menu > ')
}

function Add-NmGuiText {
    param([AllowEmptyString()][string]$Text, [switch]$NoNewline)
    $line = if ($NoNewline) { $Text } else { "$Text`r`n" }
    [void]$script:NmGui.Buffer.Append($line)
    # The Output panel leaves out the screen furniture (borders, author, version, the status line);
    # the dialogs still get it, to find their titles.
    if (-not (Test-NmGuiFurniture -Text $Text)) {
        [void]$script:NmGui.Transcript.Append($line)
        # The Output panel follows along while a tool runs (at most about 4 times a second).
        try {
            $lb = $script:NmGui.Controls.LogBox
            if ($lb) {
                if (-not $script:NmGui.LogClock) { $script:NmGui.LogClock = [System.Diagnostics.Stopwatch]::StartNew() }
                if ($script:NmGui.LogClock.ElapsedMilliseconds -ge 250 -or $Text -match '^\[[\d\- :]+\] \[') {
                    $script:NmGui.LogClock.Restart()
                    $lb.Text = $script:NmGui.Transcript.ToString(); $lb.ScrollToEnd()
                }
            }
        } catch { $null = $_ }
    }
    # Log lines also go to the status bar, and the window repaints so long runs show progress.
    if ($Text -match '^\[\d{4}-\d{2}-\d{2} [\d:]{8}\] \[(\w+)\] (.*)$' -and $script:NmGui.Controls.StatusText) {
        try {
            $script:NmGui.Controls.StatusText.Text = $Matches[2]
            $script:NmGui.Window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
        } catch { $null = $_ }
    }
}

function Clear-NmGuiBuffer { [void]$script:NmGui.Buffer.Clear(); $script:NmGui.TableEnd = 0; if ($script:NmGui.Captures) { $script:NmGui.Captures.Clear() }; $script:NmGui.Marks = @{} }

function Get-NmGuiChoice {
    <#
    .SYNOPSIS
        Quick-answer buttons for the question being asked: Yes/No for [Y/n], or menu keys from
        "[1] Label" lines. Only text after the last answer ("> ...") counts, unless that part has
        no menu (a menu asked again after a wrong key), then the menu above it is used.
    #>
    param([string]$Text, [string]$Prompt)
    $choices = New-Object System.Collections.Generic.List[object]
    $lines = @("$Text" -split "`r?`n")
    $start = 0
    for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '^> ') { $start = $i + 1; break } }
    $tail = if ($start -lt $lines.Count) { @($lines[$start..($lines.Count - 1)]) } else { @() }
    if ((($tail -join "`n") + " $Prompt") -match '\[Y/n\]|\[y/N\]') {
        $choices.Add([pscustomobject]@{ Key = 'Y'; Label = 'Yes'; Kind = 'YesNo'; Name = 'Yes'; Detail = ''; Tag = ''; Icon = [string][char]0xE73E; Initials = '' })
        $choices.Add([pscustomobject]@{ Key = 'N'; Label = 'No'; Kind = 'YesNo'; Name = 'No'; Detail = ''; Tag = ''; Icon = [string][char]0xE711; Initials = '' })
        return $choices
    }
    $menuLine = '^\s*\[([0-9A-Za-z]{1,3})\]\s+(.+?)\s*$'
    $reask = $false
    $source = if (@($tail | Where-Object { $_ -match $menuLine }).Count) { $tail }
              elseif (@($tail | Where-Object { $_ -match 'is not an option' }).Count) { $reask = $true; @() }
              else { @() }
    $block = New-Object System.Collections.Generic.List[object]
    foreach ($l in $source) {
        if ($l -match '^> ') { $block.Clear(); continue }   # a newer menu starts after each answer
        if ($l -match $menuLine) {
            $k = $Matches[1].ToUpper()
            if (-not @($block | Where-Object Key -eq $k).Count) { $block.Add((New-NmGuiChoiceItem -Key $k -Text $Matches[2])) }
        }
    }
    if ($reask) {
        # Asked again: take the last menu on the screen, whatever came after it.
        foreach ($l in $lines) {
            if ($l -match $menuLine) {
                $k = $Matches[1].ToUpper()
                if (-not @($block | Where-Object Key -eq $k).Count) { $block.Add((New-NmGuiChoiceItem -Key $k -Text $Matches[2])) }
            }
        }
    }
    foreach ($c in $block) { $choices.Add($c) }
    return $choices
}

# Icons for choice rows: Segoe Fluent Icons (Windows 11) / Segoe MDL2 Assets (Windows 10) share
# these code points. First match on the option's words wins; no match gets a neutral dot.
$script:NmGuiIconMap = @(
    @('^\s*windows server\b', 0xE91F),   # levels, versions: the plain dot, alike for every choice
    @('\b(back)\b', 0xE72B), @('\bmain menu\b', 0xE80F), @('\b(quit|exit)\b', 0xE7E8),
    @('\b(remove|delete|purge|clear|strip)\b', 0xE74D), @('\b(grant|add|create|new|assign|enable litigation)\b', 0xE710),
    @('\b(turn (it )?off|off|disable|block)\b', 0xE711), @('\b(turn (it )?on|on|enable|unblock|restore)\b', 0xE73E),
    @('\bsearch|find|look ?up\b', 0xE721), @('\b(refresh|update)\b', 0xE72C), @('\b(test)\b', 0xE9D5),
    @('\b(export|download|report job|csv)\b', 0xE896), @('\b(encrypt|lock|password)\b', 0xE72E),
    @('\b(hold|retention|litigation)\b', 0xE8B7), @('\b(access|permission|delegat|send as|full access)\b', 0xE8D7),
    @('\b(calendar|room|equipment|booking)\b', 0xE787), @('\b(shared|group|members|teams?|distribution)\b', 0xE716),
    @('\b(guest)\b', 0xE8FA), @('\b(device|laptop|bitlocker)\b', 0xE7F8), @('\b(forward)\b', 0xE72A),
    @('\b(rule|filter|transport)\b', 0xE71C), @('\b(security|mfa|sign-?in|protect|phish|spam|quarantine)\b', 0xEA18),
    @('\b(licen[cs]e|subscription)\b', 0xE8C7), @('\b(setting|config|branding)\b', 0xE713),
    @('\b(days?|date|history|recent|inactive|stale|expir)\b', 0xE823), @('\b(several|list|every|all)\b', 0xE8FD),
    @('\b(one mailbox|mailbox|mail|address|alias|message|trace)\b', 0xE715), @('\b(user|person|manager|owner|account)\b', 0xE77B),
    @('\b(view|show|status|summary|who|report)\b', 0xE7B3), @('\b(change|edit|set)\b', 0xE70F), @('\b(domain|forest|organi[sz]ation)\b', 0xE80F)
)

function Get-NmGuiChoiceIcon {
    # The icon glyph for an option, from its words.
    param([string]$Text)
    $t = "$Text".ToLower()
    foreach ($m in $script:NmGuiIconMap) { if ($t -match $m[0]) { return [string][char]$m[1] } }
    return [string][char]0xE91F   # small dot
}

function New-NmGuiChoiceItem {
    <#
    .SYNOPSIS
        One menu line ("Label [CHANGE]  detail", or "Name  <address>  type" in a pick list) as a choice:
        Key, Label (as before), Name, Detail, Tag, Icon, and Initials for people in pick lists.
    #>
    param([string]$Key, [string]$Text)
    $parts = @("$Text" -split '\s{2,}' | Where-Object { $_ })
    $name = "$($parts[0])".Trim()
    $tag = ''
    if ($name -match '^(.*?)\s*\[CHANGE\]\s*$') { $name = $Matches[1]; $tag = 'Can change' }
    $detail = ((@($parts | Select-Object -Skip 1) | ForEach-Object { "$_".Trim().Trim('<', '>') }) -join ' | ') -replace '\s*\|\s*', " $([char]0x00B7) "
    $initials = ''
    if ("$Text" -match '<[^<>@\s]+@[^<>\s]+>' -and $name -match '[A-Za-z]') {
        $initials = (@($name -split '\s+' | Where-Object { $_ -match '^[A-Za-z]' } | Select-Object -First 2) | ForEach-Object { $_.Substring(0, 1).ToUpper() }) -join ''
    }
    [pscustomobject]@{
        Key = $Key; Label = "$Key  $($parts[0])"; Kind = 'Menu'
        Name = $name; Detail = $detail; Tag = $tag; Initials = $initials
        Icon = $(if ((Get-NmGuiChoiceIcon -Text $name) -ne [string][char]0xE91F) { Get-NmGuiChoiceIcon -Text $name } else { Get-NmGuiChoiceIcon -Text $detail })
    }
}

function Get-NmGuiDialogModel {
    <#
    .SYNOPSIS
        What a question dialog shows, from the screen text: Kind (Menu, YesNo, Text, Continue),
        Title, Context (other plain text on the screen), Rows (choices to click), Footer (Back, Main
        menu, Quit as buttons), Default (the key highlighted first). No WPF here, so it can be tested.
    .DESCRIPTION
        No console text reaches the dialog:
        - Section: the last heading written in Cyan since the last answer ("The new forest").
        - Notes: warnings, errors and successes since the last answer, from log lines
          ("[time] [WARN] ...") and from lines written in Red, Yellow or Green (-Marks), as
          Level + Text. INFO log lines are left out (they go to the status bar and Output).
        - DefaultValue: from Read-NmInput's "(Press Enter for default: X)", for the answer box;
          the title loses that part.
    #>
    param([string]$Text, [string]$Prompt, [hashtable]$Marks = $script:NmGui.Marks)
    if ($null -eq $Marks) { $Marks = @{} }
    $lines = @("$Text" -split "`r?`n")
    $start = 0
    for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '^> ') { $start = $i + 1; break } }
    $tail = @(if ($start -lt $lines.Count) { $lines[$start..($lines.Count - 1)] })
    $border = '^\s*[=\-_]{5,}\s*$'
    $menuLine = '^\s*\[([0-9A-Za-z]{1,3})\]\s+(.+?)\s*$'

    $kind = 'Text'
    $choices = @()
    if (Test-NmGuiContinue -Text $Text -Prompt $Prompt) { $kind = 'Continue' }
    else {
        $choices = @(Get-NmGuiChoice -Text $Text -Prompt $Prompt)
        if (@($choices | Where-Object Kind -eq 'YesNo').Count) { $kind = 'YesNo' } elseif ($choices.Count) { $kind = 'Menu' }
    }

    # Header: from the first border line to the last border line before the first option (menus) or
    # before the question. Its first line is the title; the rest (author, version, domain status) is left out.
    $firstMenu = -1
    for ($i = 0; $i -lt $tail.Count; $i++) { if ($tail[$i] -match $menuLine) { $firstMenu = $i; break } }
    $limit = if ($firstMenu -ge 0) { $firstMenu } else { $tail.Count }
    $hStart = -1; $hEnd = -1
    for ($i = 0; $i -lt $limit; $i++) { if ($tail[$i] -match $border) { if ($hStart -lt 0) { $hStart = $i }; $hEnd = $i } }
    $title = ''; $titleIdx = -1
    if ($hStart -ge 0 -and $hEnd -gt $hStart) {
        for ($i = $hStart + 1; $i -lt $hEnd; $i++) { if ("$($tail[$i])".Trim() -and $tail[$i] -notmatch $border) { $title = "$($tail[$i])".Trim(); $titleIdx = $i; break } }
    }
    $questionIdx = -1
    if ($kind -in 'YesNo', 'Text') {
        for ($i = $tail.Count - 1; $i -ge 0; $i--) { if ("$($tail[$i])".Trim() -and $tail[$i] -notmatch $border) { $questionIdx = $i; break } }
        if ($questionIdx -ge 0) {
            $q = ("$($tail[$questionIdx])" -replace '\[(Y/n|y/N)\]', '').Trim().TrimEnd(':').Trim()
            if ($q) { $title = $q; $titleIdx = -1 }
        }
    }
    if ($kind -eq 'Menu' -and -not $title) {
        for ($i = 0; $i -lt $tail.Count; $i++) {
            if ($tail[$i] -match $menuLine) {
                for ($j = $i - 1; $j -ge 0; $j--) { if ("$($tail[$j])".Trim() -and $tail[$j] -notmatch $border) { $title = "$($tail[$j])".Trim().TrimEnd(':'); $titleIdx = $j; break } }
                break
            }
        }
    }
    if (-not $title) { $title = switch ($kind) { 'Menu' { 'Choose an option' } 'Continue' { 'Results' } default { 'Answer' } } }
    $defaultValue = ''
    if ($title -match '^(.*?)\s*\(Press Enter for default: (.*)\)$') { $title = $Matches[1].Trim(); $defaultValue = $Matches[2].Trim() }

    $context = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[object]
    $section = ''
    $logLine = '^\[\d{4}-\d{2}-\d{2} [\d:]{8}\] \[(\w+)\] (.*)$'
    $levelOf = @{ Red = 'Error'; Yellow = 'Warning'; Green = 'Success' }
    for ($i = 0; $i -lt $tail.Count; $i++) {
        $l = "$($tail[$i])"
        if ($i -eq $titleIdx -or $i -eq $questionIdx) { continue }
        if ($hStart -ge 0 -and $i -ge $hStart -and $i -le $hEnd) { continue }
        if ($l -match $border -or $l -match $menuLine -or $l -match '^\s*Select an option\s*$' -or $l -match "is not an option\.?\s*$" -or $l -match '^\s*(Author|Version):' -or $l -match 'Press Enter to continue\s*$') { continue }
        if ($l -match $logLine) {
            $lv = switch ($Matches[1]) { 'WARN' { 'Warning' } 'ERROR' { 'Error' } 'SUCCESS' { 'Success' } default { '' } }
            if ($lv) { $notes.Add([pscustomobject]@{ Level = $lv; Text = $Matches[2].Trim() }) }
            continue
        }
        $color = "$($Marks[$l.Trim()])"
        if ($color -eq 'Cyan') { continue }   # headings: see the section below
        if ($levelOf.ContainsKey($color)) { $notes.Add([pscustomobject]@{ Level = $levelOf[$color]; Text = $l.Trim() }); continue }
        $context.Add($l.TrimEnd())
    }
    while ($context.Count -and -not $context[0].Trim()) { $context.RemoveAt(0) }
    while ($context.Count -and -not $context[$context.Count - 1].Trim()) { $context.RemoveAt($context.Count - 1) }

    $footerNames = @{ B = 'Back'; M = 'Main menu'; Q = 'Quit' }
    $rows = New-Object System.Collections.Generic.List[object]
    $footer = New-Object System.Collections.Generic.List[object]
    foreach ($c in $choices) {
        if ($footerNames.ContainsKey($c.Key) -and $c.Name -eq $footerNames[$c.Key]) { $footer.Add($c) } else { $rows.Add($c) }
    }
    # The section: the last heading written on this screen, before or after the last answer
    # (questions under "The new forest" keep that label until the next heading).
    $qLine = if ($questionIdx -ge 0) { $start + $questionIdx } else { $lines.Count }
    for ($i = [Math]::Min($qLine, $lines.Count) - 1; $i -ge 0; $i--) {
        $t = "$($lines[$i])".Trim()
        if ($t -and $t -notmatch $border -and $t -notmatch $menuLine -and "$($Marks[$t])" -eq 'Cyan') { $section = $t; break }
    }
    $default = if ($kind -eq 'YesNo') { if ("$($tail -join ' ') $Prompt" -cmatch '\[Y/n\]') { 'Y' } else { 'N' } } elseif ($rows.Count) { $rows[0].Key } else { '' }
    [pscustomobject]@{ Kind = $kind; Title = $title; Context = ($context -join "`r`n"); Rows = $rows.ToArray(); Footer = $footer.ToArray(); Default = $default
        Section = $section; Notes = $notes.ToArray(); DefaultValue = $defaultValue }
}

function Test-NmGuiContinue {
    # True for "Press Enter to continue" (Wait-NmKey): the window shows only a Continue button.
    param([string]$Text, [string]$Prompt)
    return ("$Text".TrimEnd() -match 'Press Enter to continue$')
}

function Test-NmGuiCheckPage {
    # True when a "Press Enter to continue" screen is a check list (a table with Result or Status):
    # it opens as the modern dialog with badges, not the results viewer.
    param([object[]]$Captures = @())
    return [bool](@($Captures | Where-Object { $_ -and @(Get-NmGuiCheckRowModel -Capture $_).Count }).Count)
}

function Get-NmGuiContinueText {
    # The text for a "Press Enter to continue" pop-up: its warnings and errors (which the pop-up shows
    # as notes above the tables), then the plain text, successes included. No console borders or log stamps.
    param([Parameter(Mandatory)]$Model)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($n in @($Model.Notes)) {
        if ($n.Level -eq 'Error') { $lines.Add("[note] [ERROR] $($n.Text)") }
        elseif ($n.Level -eq 'Warning') { $lines.Add("[note] [WARN] $($n.Text)") }
        else { $lines.Add("$($n.Text)") }
    }
    if ($Model.Section) { $lines.Insert(0, "$($Model.Section)") }
    if ("$($Model.Context)".Trim()) { $lines.Add("$($Model.Context)".Trim()) }
    return ($lines -join "`r`n")
}

function Get-NmGuiQuestionStatus {
    # The status bar while a question waits: "Question: The new forest > NetBIOS name".
    param([Parameter(Mandatory)]$Model)
    $t = "$($Model.Title)"
    if ($Model.Section) { return "Question: $($Model.Section) > $t" }
    return "Question: $t"
}

function Set-NmGuiStatus {
    param([string]$Text)
    try { if ($script:NmGui.Controls.StatusText) { $script:NmGui.Controls.StatusText.Text = $Text } } catch { $null = $_ }
}

function Read-NmGuiHost {
    <#
    .SYNOPSIS
        Every Read-NmHost while the window is open: a dialog showing the current screen.
    .DESCRIPTION
        The screen is everything written since the last Clear-NmScreen, with earlier answers echoed
        as "> answer", like the console. So when a menu asks again ("'x' is not an option") the
        menu and its buttons are still there. "Press Enter to continue" gets a Continue button only.
    #>
    param([string]$Prompt)
    $text = $script:NmGui.Buffer.ToString()
    $continue = Test-NmGuiContinue -Text $text -Prompt $Prompt
    if ($script:NmGui.InputProvider) {
        $answer = & $script:NmGui.InputProvider $text $Prompt
    } elseif ($continue) {
        $model = Get-NmGuiDialogModel -Text $text -Prompt $Prompt
        $caps = @($script:NmGui.Captures.ToArray())
        $heading = if ($model.Title -ne 'Results' -or -not $caps.Count) { $model.Title } elseif ($caps[0].Title) { Get-NmGuiShortTitle -Title $caps[0].Title } else { 'Results' }
        if (-not $caps.Count) {
            # Only words to read (a notice such as "The server restarts in 60 seconds"): the modern
            # dialog, titled by its heading, with Continue.
            $model.Title = $(if ($model.Section) { $model.Section } elseif ($model.Title -and $model.Title -ne 'Results') { $model.Title } else { 'Note' })
            $model.Section = ''
            $model.Kind = 'Continue'
            Set-NmGuiStatus -Text $model.Title
            $answer = Show-NmGuiQuestion -Model $model
            if ($null -eq $answer) { $answer = '' }   # closing a notice counts as Continue
        } elseif (Test-NmGuiCheckPage -Captures $caps) {
            # A check list (the server check): the modern dialog, its badges, Continue or Cancel,
            # titled by the check ("Server check").
            $first = @($caps | Where-Object { $_ -and @(Get-NmGuiCheckRowModel -Capture $_).Count })[0]
            $short = Get-NmGuiShortTitle -Title "$($first.Title)"
            if ($short) { $heading = $short }
            $model.Title = $heading
            if ($model.Section -eq $heading) { $model.Section = '' }
            $model.Kind = 'Continue'
            Set-NmGuiStatus -Text "Review: $heading"
            $answer = Show-NmGuiQuestion -Model $model -Captures $caps
            if ($null -eq $answer) {
                [void]$script:NmGui.Transcript.Append("> (cancelled)`r`n")
                Clear-NmGuiBuffer
                throw (New-Object System.OperationCanceledException 'Cancelled in the window.')
            }
        } else {
            $null = Show-NmGuiDialog -Text (Get-NmGuiContinueText -Model $model) -Heading $heading -NoInput -OkLabel 'Continue' -Captures $caps
        }
        $answer = ''   # closing the window counts as Continue too
    } else {
        $model = Get-NmGuiDialogModel -Text $text -Prompt $Prompt
        Set-NmGuiStatus -Text (Get-NmGuiQuestionStatus -Model $model)
        $answer = Show-NmGuiQuestion -Model $model -Captures @($script:NmGui.Captures.ToArray())
    }
    if ($null -eq $answer) {
        # The Output panel: the question ends its line and says it was cancelled.
        if ($script:NmGui.Transcript.Length -and $script:NmGui.Transcript[$script:NmGui.Transcript.Length - 1] -ne "`n") { [void]$script:NmGui.Transcript.Append("`r`n") }
        [void]$script:NmGui.Transcript.Append("> (cancelled)`r`n")
        Clear-NmGuiBuffer
        throw (New-Object System.OperationCanceledException 'Cancelled in the window.')
    }
    # Prompts are written without a line break: the echoed answer always starts its own line.
    foreach ($sb in @($script:NmGui.Transcript, $script:NmGui.Buffer)) {
        if ($sb.Length -and $sb[$sb.Length - 1] -ne "`n") { [void]$sb.Append("`r`n") }
    }
    [void]$script:NmGui.Transcript.Append("> $answer`r`n")
    if ($continue) { Clear-NmGuiBuffer } else {
        [void]$script:NmGui.Buffer.Append("> $answer`r`n")
        # Tables printed before this answer belonged to the screen just answered; the next window shows only new ones.
        $script:NmGui.Captures.Clear()
    }
    return "$answer"
}

# ---------------------------------------------------------------------------
# Options form model (no WPF: testable anywhere)
# ---------------------------------------------------------------------------

function ConvertTo-NmGuiLabel {
    param([string]$Name)
    $s = ($Name -creplace '([a-z0-9])([A-Z])', '$1 $2') -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
    if ($s.Length -le 1) { return $s }
    $words = @($s -split ' ' | ForEach-Object { if ($_ -cmatch '^[A-Z]{2,}$') { $_ } else { $_.ToLower() } })
    $out = $words -join ' '
    return $out.Substring(0, 1).ToUpper() + $out.Substring(1)
}

function Get-NmGuiChoiceItem {
    # The drop-down's lines for a ValidateSet parameter: its values, after an empty line only when
    # the parameter has no default (so leaving it empty still means "not set").
    param($Field)
    $hasDefault = $Field.Default -and @($Field.Choices) -contains $Field.Default
    @(if (-not $hasDefault) { '' }) + @($Field.Choices | ForEach-Object { "$_" })
}

function Get-NmGuiParamSpec {
    <#
    .SYNOPSIS
        The entry function's parameters as form fields: Name, Label, Kind (Switch, Choice, Number,
        List, Date, Text), Choices and Default. Hashtables and objects are left to Guided mode.
    #>
    param([Parameter(Mandatory)]$Tool)
    $cmd = Get-Command -Name $Tool.Entry -CommandType Function
    $skip = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters) + @('WhatIf', 'Confirm')
    $defaults = @{}
    $order = New-Object System.Collections.Generic.List[string]
    $pb = $cmd.ScriptBlock.Ast.Body.ParamBlock
    if ($pb) {
        foreach ($p in $pb.Parameters) {
            $n = $p.Name.VariablePath.UserPath
            $order.Add($n)
            # Only plain values make a form default; expressions such as @(), $true or [datetime]::MinValue do not.
            if ($p.DefaultValue -and $p.DefaultValue.Extent.Text -notmatch '^[@$\[(]') { $defaults[$n] = ($p.DefaultValue.Extent.Text -replace "^['""]|['""]$", '') }
        }
    }
    foreach ($n in $order) {
        if ($skip -contains $n -or -not $cmd.Parameters.ContainsKey($n)) { continue }
        $p = $cmd.Parameters[$n]
        $t = $p.ParameterType
        $set = @($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object { $_.ValidValues })
        $kind = if ($t -eq [switch]) { 'Switch' }
                elseif ($set.Count) { 'Choice' }
                elseif ($t -in @([int], [long], [double])) { 'Number' }
                elseif ($t -eq [string[]]) { 'List' }
                elseif ($t -eq [datetime]) { 'Date' }
                elseif ($t -eq [string]) { 'Text' }
                else { $null }
        if (-not $kind) { continue }
        # Required: mandatory in every parameter set it belongs to.
        $pa = @($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        $required = $pa.Count -gt 0 -and @($pa | Where-Object { -not $_.Mandatory }).Count -eq 0
        [pscustomobject]@{ Name = $n; Label = ConvertTo-NmGuiLabel $n; Kind = $kind; Choices = $set; Default = $defaults[$n]; Required = $required }
    }
}

function ConvertFrom-NmGuiForm {
    <#
    .SYNOPSIS
        Form values (Name -> string or bool) to the entry function's arguments. Empty fields are
        left out, so the tool's own defaults apply.
    #>
    param([object[]]$Spec, [hashtable]$Values)
    $a = @{}
    foreach ($f in $Spec) {
        if (-not $Values.ContainsKey($f.Name)) { continue }
        $v = $Values[$f.Name]
        switch ($f.Kind) {
            'Switch' { if ($v -eq $true) { $a[$f.Name] = $true } }
            'Choice' { if ("$v") { $a[$f.Name] = "$v" } }
            'Number' { if ("$v".Trim()) { $n = 0.0; if (-not [double]::TryParse("$v".Trim(), [ref]$n)) { throw "$($f.Label): '$v' is not a number." }; $a[$f.Name] = [int][Math]::Round($n) } }
            'List'   { $items = @("$v" -split '[,;\s]+' | Where-Object { $_ }); if ($items.Count) { $a[$f.Name] = [string[]]$items } }
            'Date'   { if ("$v".Trim()) { $d = [datetime]::MinValue; if (-not [datetime]::TryParse("$v".Trim(), [ref]$d)) { throw "$($f.Label): '$v' is not a date." }; $a[$f.Name] = $d } }
            'Text'   { if ("$v".Trim()) { $a[$f.Name] = "$v".Trim() } }
        }
        if ($f.Required -and $f.Kind -ne 'Switch' -and -not $a.ContainsKey($f.Name)) {
            throw "$($f.Label) is required."
        }
    }
    return $a
}

function Get-NmGuiTarget {
    # 'domain|DC' the session works against now ('' before the domain is read).
    $s = $script:NmSession
    if (-not $s -or -not $s.Domain) { return '' }
    return "$($s.Domain)|$($s.Server)"
}

function Test-NmGuiTargetChanged {
    # True when the session's domain or DC differs from the one whose results are on screen. Records the new one.
    param([string]$Target)
    $was = $script:NmGui.ShownTarget
    $script:NmGui.ShownTarget = $(if ($Target) { $Target } else { $null })
    return [bool]($was -and $Target -and $was -ne $Target)
}

function ConvertTo-NmGuiValue {
    # A tool's answer value back to form text (Guided mode fills the form).
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm') }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return (@($Value) -join ', ') }
    return "$Value"
}

# ---------------------------------------------------------------------------
# Results table (no WPF: testable anywhere)
# ---------------------------------------------------------------------------

function Get-NmGuiColumn {
    # The tool's display columns that exist in the rows, or every property with -All.
    param([object[]]$Rows, $Tool, [switch]$All)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Rows | Select-Object -First 200)) { foreach ($p in $r.PSObject.Properties.Name) { if ($p -ne '#' -and -not $names.Contains($p)) { $names.Add($p) } } }
    if (-not $All -and $Tool -and @($Tool.Columns).Count) {
        $pick = @($Tool.Columns | Where-Object { $names.Contains($_) })
        if ($pick.Count) { return $pick }
    }
    return @($names | Where-Object { $_ -notin @('RowType', 'AuditData') })
}

function ConvertTo-NmGuiTable {
    <#
    .SYNOPSIS
        Rows as a DataTable of text columns plus '#', the row's position in the results. Column names
        are made safe for WPF binding (dots and brackets become underscores).
    #>
    param([object[]]$Rows, [string[]]$Columns)
    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add('#', [int])
    $map = [ordered]@{}
    foreach ($c in $Columns) {
        $safe = ($c -replace '[^A-Za-z0-9_]', '_')
        while ($dt.Columns.Contains($safe)) { $safe += '_' }
        [void]$dt.Columns.Add($safe, [string])
        $map[$c] = $safe
    }
    $i = 0
    foreach ($r in $Rows) {
        $i++
        $dr = $dt.NewRow()
        $dr['#'] = $i
        foreach ($c in $Columns) {
            $v = $r.$c
            $dr[$map[$c]] = if ($null -eq $v) { '' }
                            elseif ($v -is [datetime]) { $v.ToString('yyyy-MM-dd HH:mm:ss') }
                            elseif ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) { (@($v) | ForEach-Object { "$_" }) -join '; ' }
                            else { "$v" }
        }
        $dt.Rows.Add($dr)
    }
    return , $dt
}

function Get-NmGuiRowFilter {
    # A DataView RowFilter matching the text anywhere in the text columns.
    param([string]$Text, [System.Data.DataTable]$Table)
    if (-not "$Text".Trim()) { return '' }
    $t = "$Text".Trim() -replace "'", "''" -replace '\[', '[[]' -replace '(?<!\[)\]', '[]]' -replace '\*', '[*]' -replace '%', '[%]'
    $parts = foreach ($c in $Table.Columns) { if ($c.DataType -eq [string]) { "[$($c.ColumnName)] LIKE '%$t%'" } }
    return (@($parts) -join ' OR ')
}

# ---------------------------------------------------------------------------
# WPF
# ---------------------------------------------------------------------------

function New-NmGuiXaml {
    param([string]$Xaml)
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$Xaml)
    return [Windows.Markup.XamlReader]::Load($reader)
}

# ---------------------------------------------------------------------------
# Theme: one look for every window (main and dialogs). Implicit styles, so plain
# controls pick it up; colours set on a control (a teal Run button) still win.
# ---------------------------------------------------------------------------
$script:NmGuiTheme = @'
    <Style TargetType="Button">
      <Setter Property="MinHeight" Value="36"/><Setter Property="Padding" Value="14,4"/><Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Background" Value="#FFFFFF"/><Setter Property="BorderBrush" Value="#D5D9E0"/><Setter Property="Foreground" Value="#2B313B"/>
      <Setter Property="BorderThickness" Value="1"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/><Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8"/>
              <Border x:Name="Shade" Background="#000000" Opacity="0" CornerRadius="8"/>
              <Border x:Name="Ring" BorderBrush="#0E6B66" BorderThickness="2" CornerRadius="8" Opacity="0"/>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" RecognizesAccessKey="True"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Shade" Property="Opacity" Value="0.05"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Shade" Property="Opacity" Value="0.11"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Ring" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#0E6B66"/><Setter Property="BorderBrush" Value="#0E6B66"/><Setter Property="Foreground" Value="#FFFFFF"/><Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="MinHeight" Value="36"/><Setter Property="Padding" Value="8,4"/><Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Background" Value="#FFFFFF"/><Setter Property="BorderBrush" Value="#C9CED6"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Foreground" Value="#16191F"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#8A919C"/></Trigger>
              <Trigger Property="IsKeyboardFocusWithin" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#0E6B66"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Foreground" Value="#2B313B"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="18" Height="18" CornerRadius="5" BorderBrush="#9AA1AC" BorderThickness="1.5" Background="#FFFFFF" VerticalAlignment="Center">
                <Path x:Name="Tick" Data="M3.5,9 L7.5,13 L14.5,5" Stroke="#FFFFFF" StrokeThickness="2" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="#0E6B66"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="#0E6B66"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="#0E6B66"/><Setter TargetName="Box" Property="BorderBrush" Value="#0E6B66"/><Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="6" Padding="10,7">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="#F1F3F6"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#E3F1EF"/><Setter Property="Foreground" Value="#0A4F4B"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="MinHeight" Value="36"/><Setter Property="Padding" Value="10,4,30,4"/><Setter Property="Foreground" Value="#16191F"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="#FFFFFF" BorderBrush="#C9CED6" BorderThickness="1" CornerRadius="8">
                      <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0" Data="M0,0 L5,5 L10,0" Stroke="#5B6370" StrokeThickness="1.6"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#8A919C"/></Trigger>
                      <Trigger Property="IsChecked" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#0E6B66"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"
                                Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
              <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                <Border Background="#FFFFFF" BorderBrush="#D5D9E0" BorderThickness="1" CornerRadius="8" Margin="0,4,8,8" Padding="4"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <Border.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="3" Opacity="0.14"/></Border.Effect>
                  <ScrollViewer><ItemsPresenter/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#1F252E"/><Setter Property="Foreground" Value="#FFFFFF"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="8,5"/>
    </Style>
    <Style x:Key="ChoiceRow" TargetType="Button">
      <Setter Property="Background" Value="#FFFFFF"/><Setter Property="BorderBrush" Value="#E2E5EA"/><Setter Property="Margin" Value="0,0,0,6"/><Setter Property="Padding" Value="10,8"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#F6F7F9"/><Setter TargetName="Bd" Property="BorderBrush" Value="#B9C0CA"/></Trigger>
              <Trigger Property="Tag" Value="on"><Setter TargetName="Bd" Property="Background" Value="#E3F1EF"/><Setter TargetName="Bd" Property="BorderBrush" Value="#0E6B66"/><Setter TargetName="Bd" Property="BorderThickness" Value="1.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
'@

$script:NmGuiDialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Nutmeg AD Toolkit" Width="640" WindowStartupLocation="CenterOwner" Background="#FFFFFF" FontFamily="Segoe UI" FontSize="13"
        Foreground="#16191F" ShowInTaskbar="False" ResizeMode="CanResizeWithGrip">
  <Window.Resources>
    <!--NMSTYLES-->
  </Window.Resources>
  <Grid Margin="22,18,22,16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition x:Name="ContextRow" Height="Auto"/><RowDefinition x:Name="ChoiceRow" Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,12">
      <TextBlock x:Name="SectionText" FontSize="11" FontWeight="SemiBold" Foreground="#0E6B66" Margin="0,0,0,4" Visibility="Collapsed"/>
      <TextBlock x:Name="HeadingText" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
      <TextBlock x:Name="SubText" FontSize="12" Foreground="#5B6370" Margin="0,3,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
      <StackPanel x:Name="NotePanel" Margin="0,10,0,0" Visibility="Collapsed"/>
      <TextBlock x:Name="ContextText" FontSize="13" Foreground="#3D4450" Margin="0,10,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
      <StackPanel x:Name="TablePanel" Margin="0,10,0,0" Visibility="Collapsed"/>
    </StackPanel>
    <TextBox x:Name="OutputBox" Grid.Row="1" IsReadOnly="True" FontFamily="Consolas" FontSize="12" Background="#F6F7F9" BorderBrush="#E2E5EA" Padding="10,8"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" VerticalContentAlignment="Stretch" Margin="0,0,0,12" Visibility="Collapsed"/>
    <ScrollViewer x:Name="ChoiceScroll" Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Visibility="Collapsed" Focusable="False">
      <StackPanel x:Name="ChoicePanel"/>
    </ScrollViewer>
    <StackPanel x:Name="InputArea" Grid.Row="3" Visibility="Collapsed">
      <TextBlock x:Name="PromptText" FontWeight="SemiBold" Foreground="#3D4450" Margin="0,0,0,6"/>
      <TextBox x:Name="InputBox"/>
    </StackPanel>
    <DockPanel Grid.Row="4" Margin="0,14,0,0" LastChildFill="False">
      <TextBlock x:Name="HintText" DockPanel.Dock="Left" VerticalAlignment="Center" FontSize="12" Foreground="#8A919C"/>
      <Button x:Name="OkButton" DockPanel.Dock="Right" Content="OK" MinWidth="104" Margin="0" IsDefault="True" Style="{StaticResource PrimaryButton}"/>
      <Button x:Name="CancelButton" DockPanel.Dock="Right" Content="Cancel" MinWidth="96"/>
      <StackPanel x:Name="FooterPanel" DockPanel.Dock="Right" Orientation="Horizontal"/>
    </DockPanel>
  </Grid>
</Window>
'@

$script:NmGuiViewerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Nutmeg AD Toolkit" Width="1000" Height="680" MinWidth="560" MinHeight="360" WindowStartupLocation="CenterOwner" Background="#FFFFFF"
        FontFamily="Segoe UI" FontSize="13" Foreground="#16191F" ShowInTaskbar="False" ResizeMode="CanResizeWithGrip">
  <Window.Resources>
    <!--NMSTYLES-->
  </Window.Resources>
  <Grid Margin="22,18,22,16">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,12">
      <TextBlock x:Name="HeadingText" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
      <TextBlock x:Name="SummaryText" FontSize="12" Foreground="#5B6370" Margin="0,3,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <DockPanel Grid.Row="1" Margin="0,0,0,10" LastChildFill="False">
      <Grid DockPanel.Dock="Left" Width="300">
        <TextBox x:Name="FilterBox" ToolTip="Show only rows containing this text (Ctrl+F)"/>
        <TextBlock x:Name="FilterHint" Text="Filter" Foreground="#8A919C" Margin="10,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
      </Grid>
      <TextBlock x:Name="CountText" DockPanel.Dock="Left" Margin="12,0,0,0" VerticalAlignment="Center" FontSize="12" Foreground="#5B6370"/>
      <Button x:Name="ExcelButton" DockPanel.Dock="Right" Content="Open in Excel" Margin="0" ToolTip="Save as CSV and open it"/>
      <Button x:Name="CsvButton" DockPanel.Dock="Right" Content="Export CSV" ToolTip="Save what is shown as CSV"/>
    </DockPanel>
    <ContentControl x:Name="Body" Grid.Row="2" Focusable="False"/>
    <DockPanel Grid.Row="3" Margin="0,14,0,0" LastChildFill="False">
      <TextBlock x:Name="HintText" DockPanel.Dock="Left" VerticalAlignment="Center" FontSize="12" Foreground="#8A919C"
                 Text="Select rows and press Ctrl+C (or right-click) to copy them with headers"/>
      <Button x:Name="CloseButton" DockPanel.Dock="Right" Content="Close" MinWidth="104" Margin="0" IsDefault="True" IsCancel="True" Style="{StaticResource PrimaryButton}"/>
    </DockPanel>
  </Grid>
</Window>
'@

# ---------------------------------------------------------------------------
# Cards: details and findings shown as readable cards instead of one-row tables
# (the model functions use no WPF, so the tests can check them)
# ---------------------------------------------------------------------------
$script:NmGuiSeverityColors = @{
    'High'          = @('#B42318', '#FEE4E2')
    'Medium'        = @('#B54708', '#FEF0C7')
    'Low'           = @('#1D4ED8', '#E0EAFF')
    'Info'          = @('#475467', '#EEF0F3')
    'OK'            = @('#067647', '#DCFAE6')
    'Not collected' = @('#6B4E16', '#F4EBD0')
}
$script:NmGuiWrapStyle = $null

function Get-NmGuiSeverityColor {
    # Text and background colours for a severity (or a verdict level); grey for anything else.
    param([string]$Severity)
    $c = $script:NmGuiSeverityColors["$Severity"]
    if (-not $c) { $c = $script:NmGuiSeverityColors['Info'] }
    return [pscustomobject]@{ Fore = $c[0]; Back = $c[1] }
}

function ConvertTo-NmGuiFieldText {
    # One value as display text: lists joined with "; ", dates as yyyy-MM-dd HH:mm, True/False as
    # Yes/No, nothing as ''.
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) { if ($Value) { return 'Yes' } else { return 'No' } }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm') }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return ((@($Value) | ForEach-Object { ConvertTo-NmGuiFieldText $_ }) -join '; ') }
    return "$Value"
}

function Get-NmGuiDetailField {
    <#
    .SYNOPSIS
        A row as Name/Value pairs for a details card, in column order; empty values are left out
        unless -KeepEmpty.
    #>
    param($Row, [string[]]$Columns = @(), [switch]$KeepEmpty)
    if ($null -eq $Row) { return }
    $names = if (@($Columns).Count) { @($Columns) } else { @($Row.PSObject.Properties | Where-Object { $_.MemberType -match 'Property' } | ForEach-Object Name) }
    foreach ($n in $names) {
        $p = $Row.PSObject.Properties[$n]
        if (-not $p) { continue }
        $v = ConvertTo-NmGuiFieldText $p.Value
        if (-not $KeepEmpty -and -not "$v".Trim()) { continue }
        [pscustomobject]@{ Name = $n; Value = $v }
    }
}

function Test-NmGuiRowMatch {
    # True when any value in the row contains the text (case ignored); always true for no text.
    param($Row, [string]$Text)
    $t = "$Text".Trim()
    if (-not $t) { return $true }
    foreach ($p in @($Row.PSObject.Properties)) { if ((ConvertTo-NmGuiFieldText $p.Value) -like "*$t*") { return $true } }
    return $false
}

function Get-NmGuiCardTitle {
    # The best title for a details card: a name-like field if the row has one, else the first value.
    param($Row, [string[]]$Columns = @())
    foreach ($n in 'Finding', 'DisplayName', 'Name', 'Title', 'UserPrincipalName', 'PrimarySmtpAddress', 'Identity', 'Item', 'What') {
        $p = $Row.PSObject.Properties[$n]
        if ($p -and "$($p.Value)".Trim()) { return [pscustomobject]@{ Field = $n; Text = (ConvertTo-NmGuiFieldText $p.Value) } }
    }
    $f = @(Get-NmGuiDetailField -Row $Row -Columns $Columns | Select-Object -First 1)
    if ($f.Count) { return [pscustomobject]@{ Field = $f[0].Name; Text = $f[0].Value } }
    return [pscustomobject]@{ Field = ''; Text = '' }
}

function Get-NmGuiFindingDetailColumn {
    # Every field of a finding for its Details, as the table has them: evidence, why and
    # indicators first, then all the rest in their own order. Only what the card already shows
    # (severity, the finding, the next step) is left out.
    param($Row)
    $first = @('Evidence', 'Why', 'Indicators')
    $shown = @('Severity', 'Finding', 'ManualStep', '#')
    $rest = @($Row.PSObject.Properties | Where-Object { $_.MemberType -match 'Property' -and $first -notcontains $_.Name -and $shown -notcontains $_.Name } | ForEach-Object Name)
    return @($first + $rest)
}

function Get-NmGuiFindingModel {
    <#
    .SYNOPSIS
        What the findings view shows: the verdict and its level, the count per severity, the case,
        and the findings grouped by severity (High first), each with its title, a meta line, the
        manual step and the rest as detail fields.
    #>
    param([AllowEmptyCollection()][object[]]$Rows = @(), [string]$Filter = '', [string]$Facet = '')
    $all = @($Rows | Where-Object { $_ })
    $shown = @($all | Where-Object { (-not $Facet -or "$($_.Severity)" -eq $Facet) -and (Test-NmGuiRowMatch -Row $_ -Text $Filter) })
    $order = if ($script:NmIrSeverities) { @($script:NmIrSeverities) } else { @('High', 'Medium', 'Low', 'Info', 'OK', 'Not collected') }
    $verdict = if (Get-Command -Name Get-NmCaseVerdict -ErrorAction SilentlyContinue) { Get-NmCaseVerdict -Findings $all } else { '' }
    $level = if ($verdict -like 'Likely*') { 'High' } elseif ($verdict -like 'Suspicious*') { 'Medium' } else { 'OK' }
    $caseId = @($all | ForEach-Object { "$($_.CaseId)" } | Where-Object { $_ } | Select-Object -First 1)
    $folder = ''
    if ($caseId.Count -and (Get-Command -Name Get-NmCase -ErrorAction SilentlyContinue)) { $c = Get-NmCase; if ($c -and $c.Id -eq $caseId[0]) { $folder = "$($c.Folder)" } }
    $users = @($all | ForEach-Object { "$($_.User)" } | Where-Object { $_ } | Sort-Object -Unique)
    $dot = ' ' + [char]0x00B7 + ' '
    $groups = foreach ($s in $order) {
        $items = @($shown | Where-Object { "$($_.Severity)" -eq $s })
        if (-not $items.Count) { continue }
        [pscustomobject]@{
            Severity = $s
            Items    = @(foreach ($r in $items) {
                $meta = @("$($r.Check)", $(if ($r.When) { ConvertTo-NmGuiFieldText $r.When }), $(if ($r.AttackType -and $r.AttackType -ne 'Context') { "$($r.AttackType)" }), $(if ("$($r.Scope)" -eq 'Tenant') { 'tenant setting' })) | Where-Object { $_ }
                [pscustomobject]@{
                    Severity = $s
                    Title    = "$($r.Finding)"
                    Meta     = ($meta -join $dot)
                    Step     = "$($r.ManualStep)"
                    Details  = @(Get-NmGuiDetailField -Row $r -Columns (Get-NmGuiFindingDetailColumn -Row $r))
                    Row      = $r
                }
            })
        }
    }
    [pscustomobject]@{
        Verdict = $verdict
        Level   = $level
        Counts  = @(foreach ($s in $order) { $n = @($all | Where-Object { "$($_.Severity)" -eq $s }).Count; if ($n) { [pscustomobject]@{ Severity = $s; Count = $n } } })
        CaseId  = $(if ($caseId.Count) { $caseId[0] } else { '' })
        Folder  = $folder
        Users   = $users
        Shown   = $shown.Count
        Total   = $all.Count
        Facet   = $Facet
        Groups  = @($groups)
    }
}

function Get-NmGuiStatusLevel {
    # How a status value reads: a severity as itself; Failed red, warnings amber, done green, the rest grey.
    param([string]$Column, [string]$Value)
    $v = "$Value".Trim()
    if ($Column -eq 'Severity' -and $script:NmGuiSeverityColors.ContainsKey($v)) { return $v }
    if ($v -match '^(?i)(failed|failure|error|denied|blocked|refused|not found|missing|not ready)') { return 'High' }
    if ($v -match '^(?i)(whatif|cancel|skipped|not changed|already|unchanged|none|n/a)') { return 'Info' }
    if ($v -match '^(?i)(warn|partial|suspicious|expir|interrupt|pending|disabled)') { return 'Medium' }
    if ($v -match '^(?i)(granted|added|removed|set\b|success|succeeded|ok\b|done|created|updated|enabled|deleted|changed|sent|saved|yes\b|active|works|connected|complete|passed)') { return 'OK' }
    return 'Info'
}

function Get-NmGuiFacetValue {
    # The value a row is grouped by under the tags: a Result's first word ("Failed: reason" -> Failed).
    param([string]$Column, $Value)
    $v = (ConvertTo-NmGuiFieldText $Value).Trim()
    if ($Column -eq 'Result' -and $v -match '^([^:]+):') { $v = $Matches[1].Trim() }
    if (-not $v) { return '(blank)' }
    return $v
}

function Get-NmGuiFacetColumn {
    <#
    .SYNOPSIS
        The column whose values become the clickable tags: Severity, Result, Status or State when the
        rows have them, else the first shown column with 2 to 8 values that repeat. '' for none.
    #>
    param([object[]]$Rows, [string[]]$Columns)
    $rows = @($Rows | Where-Object { $_ })
    if ($rows.Count -lt 2) { return '' }
    $have = @($rows[0].PSObject.Properties.Name)
    foreach ($c in 'Severity', 'Result', 'Status', 'State') {
        if ($have -contains $c -and @($rows | Where-Object { "$($_.$c)".Trim() }).Count) { return $c }
    }
    foreach ($c in @($Columns | Select-Object -Skip 1)) {
        $vals = @($rows | ForEach-Object { Get-NmGuiFacetValue -Column $c -Value $_.$c } | Where-Object { $_.Length -le 40 })
        if ($vals.Count -lt $rows.Count) { continue }
        $n = @($vals | Sort-Object -Unique).Count
        if ($n -ge 2 -and $n -le 8 -and $n -lt $rows.Count) { return $c }
    }
    return ''
}

function Get-NmGuiCardModel {
    <#
    .SYNOPSIS
        What the card view shows for any tool's rows: the tags (values of the tag column with their
        counts), the rows that match the filter text and the picked tag, and for the first -Limit of
        them a card: title, status label, the shown columns, and the other fields for More.
        -GroupBy (the tool's CardGroup) makes one card per value of its first column instead, with the
        rows listed inside under the values of its second column ("Safe (3)", "Blocked (1)").
    #>
    param([AllowEmptyCollection()][object[]]$Rows = @(), [string[]]$Columns = @(), [string]$Filter = '', [string]$Facet = '', [int]$Limit = 100, [string[]]$GroupBy = @())
    $all = @($Rows | Where-Object { $_ })
    $cols = if (@($Columns).Count) { @($Columns) } elseif ($all.Count) { @($all[0].PSObject.Properties.Name | Where-Object { $_ -ne '#' }) } else { @() }
    $fc = Get-NmGuiFacetColumn -Rows $all -Columns $cols
    $facets = @()
    if ($fc) {
        $groups = @($all | Group-Object { Get-NmGuiFacetValue -Column $fc -Value $_.$fc })
        if ($fc -eq 'Severity' -and $script:NmIrSeverities) { $groups = @($groups | Sort-Object { $i = [array]::IndexOf($script:NmIrSeverities, $_.Name); if ($i -lt 0) { 99 } else { $i } }) }
        else { $groups = @($groups | Sort-Object Count -Descending) }
        $facets = @($groups | ForEach-Object { [pscustomobject]@{ Value = $_.Name; Count = $_.Count; Level = (Get-NmGuiStatusLevel -Column $fc -Value $_.Name) } })
    }
    $shownIdx = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $all.Count; $i++) {
        $r = $all[$i]
        if ($Facet -and $fc -and (Get-NmGuiFacetValue -Column $fc -Value $r.$fc) -ne $Facet) { continue }
        if (-not (Test-NmGuiRowMatch -Row $r -Text $Filter)) { continue }
        $shownIdx.Add($i)
    }
    $groupCol = "$(@($GroupBy)[0])"
    if ($groupCol -and $all.Count -and @($all[0].PSObject.Properties.Name) -contains $groupCol) {
        return (Get-NmGuiGroupedCardModel -All $all -ShownIdx @($shownIdx) -Columns $cols -FacetColumn $fc -Facets $facets -Facet $Facet -Limit $Limit -GroupBy $GroupBy)
    }
    $items = foreach ($i in @($shownIdx | Select-Object -First ([Math]::Max(1, $Limit)))) {
        $r = $all[$i]
        $title = Get-NmGuiCardTitle -Row $r -Columns $cols
        $status = if ($fc) { ConvertTo-NmGuiFieldText $r.$fc } else { '' }
        $skip = @($title.Field, $fc) | Where-Object { $_ }
        $fields = @(Get-NmGuiDetailField -Row $r -Columns $cols | Where-Object { $skip -notcontains $_.Name })
        $rest = @($r.PSObject.Properties.Name | Where-Object { $cols -notcontains $_ -and $skip -notcontains $_ -and $_ -notin '#', 'RowType', 'AuditData' })
        [pscustomobject]@{
            Index  = $i
            Title  = $title.Text
            Status = $status
            Level  = $(if ($status) { Get-NmGuiStatusLevel -Column $fc -Value $status } else { '' })
            Fields = $fields
            More   = @(if ($rest.Count) { Get-NmGuiDetailField -Row $r -Columns $rest })
        }
    }
    [pscustomobject]@{
        FacetColumn = $fc
        Facets      = $facets
        Facet       = $Facet
        Shown       = $shownIdx.Count
        Total       = $all.Count
        Items       = @($items)
        Remaining   = [Math]::Max(0, $shownIdx.Count - [Math]::Max(1, $Limit))
        ShownIndex  = $shownIdx.ToArray()
        GroupBy     = ''
        Cards       = $shownIdx.Count
    }
}

function Get-NmGuiGroupedCardModel {
    <#
    .SYNOPSIS
        The grouped card view (tools with CardGroup): one card per value of the group column, in the
        order rows came. Inside, a field per value of the split column (or one field when there is no
        split column), listing every row's other shown values, one row per line, never cut short.
        The card's status is the tag column's value when the card's rows share one, else the worst.
    #>
    param([object[]]$All, [int[]]$ShownIdx = @(), [string[]]$Columns, [string]$FacetColumn, [object[]]$Facets = @(), [string]$Facet, [int]$Limit, [string[]]$GroupBy)
    $groupCol = "$(@($GroupBy)[0])"
    $splitCol = "$(@($GroupBy)[1])"
    if ($splitCol -and @($All[0].PSObject.Properties.Name) -notcontains $splitCol) { $splitCol = '' }
    $order = New-Object System.Collections.Generic.List[string]
    $byKey = @{}
    foreach ($i in @($ShownIdx)) {
        $k = ConvertTo-NmGuiFieldText $All[$i].$groupCol
        if (-not $byKey.ContainsKey($k)) { $byKey[$k] = New-Object System.Collections.Generic.List[int]; $order.Add($k) }
        $byKey[$k].Add($i)
    }
    $itemCols = @($Columns | Where-Object { $_ -ne $groupCol -and $_ -ne $splitCol -and $_ -ne $FacetColumn })
    if (-not $itemCols.Count) { $itemCols = @($Columns | Where-Object { $_ -ne $groupCol -and $_ -ne $splitCol }) }
    $rank = @{ 'High' = 0; 'Medium' = 1; 'OK' = 2; 'Info' = 3 }
    $keep = [Math]::Max(1, $Limit)
    $items = foreach ($k in @($order | Select-Object -First $keep)) {
        $idx = @($byKey[$k])
        # Each line carries its own status only when the card's rows differ (a Done card lists its
        # steps without "- Done" on every line).
        $mixed = $false
        if ($FacetColumn) { $mixed = @($idx | ForEach-Object { Get-NmGuiFacetValue -Column $FacetColumn -Value $All[$_].$FacetColumn } | Sort-Object -Unique).Count -gt 1 }
        $parts = New-Object System.Collections.Generic.List[string]
        $lines = @{}
        foreach ($i in $idx) {
            $r = $All[$i]
            $part = if ($splitCol) { ConvertTo-NmGuiFieldText $r.$splitCol } else { '' }
            if (-not $part) { $part = if ($splitCol) { '(blank)' } else { '' } }
            if (-not $lines.ContainsKey($part)) { $lines[$part] = New-Object System.Collections.Generic.List[string]; $parts.Add($part) }
            $vals = @(foreach ($c in $itemCols) { $v = ConvertTo-NmGuiFieldText $r.$c; if ("$v".Trim()) { $v } })
            if ($mixed -and $FacetColumn -and $FacetColumn -ne $splitCol -and $itemCols -notcontains $FacetColumn) {
                $fv = ConvertTo-NmGuiFieldText $r.$FacetColumn
                if ("$fv".Trim()) { $vals += $fv }
            }
            $lines[$part].Add($(if ($vals.Count) { $vals -join ' - ' } else { '(blank)' }))
        }
        $fields = @(foreach ($p in $parts) {
            $label = if ($p) { $p } elseif ($itemCols.Count -eq 1) { $itemCols[0] } else { 'Rows' }
            [pscustomobject]@{ Name = $(if ($lines[$p].Count -gt 1) { "$label ($($lines[$p].Count))" } else { $label }); Value = ($lines[$p] -join "`n") }
        })
        $status = ''; $level = ''
        if ($FacetColumn -and $FacetColumn -ne $splitCol) {
            $vals = @($idx | ForEach-Object { Get-NmGuiFacetValue -Column $FacetColumn -Value $All[$_].$FacetColumn } | Sort-Object -Unique)
            $levels = @($vals | ForEach-Object { Get-NmGuiStatusLevel -Column $FacetColumn -Value $_ })
            if ($vals.Count -eq 1) { $status = $vals[0]; $level = $levels[0] }
            else {
                $status = 'Mixed'
                $level = @($levels | Sort-Object { if ($rank.ContainsKey($_)) { $rank[$_] } else { 9 } })[0]
            }
        }
        [pscustomobject]@{
            Index  = $idx[0]
            Title  = $(if ($k) { $k } else { '(blank)' })
            Status = $status
            Level  = $level
            Fields = $fields
            More   = @()
        }
    }
    [pscustomobject]@{
        FacetColumn = $FacetColumn
        Facets      = @($Facets)
        Facet       = $Facet
        Shown       = @($ShownIdx).Count
        Total       = @($All).Count
        Items       = @($items)
        Remaining   = [Math]::Max(0, $order.Count - $keep)
        ShownIndex  = @($ShownIdx)
        GroupBy     = $groupCol
        Cards       = $order.Count
    }
}

function Get-NmGuiSectionName {
    # A table's own name inside a pop-up: its title without the screen title in front
    # ("Mailbox: Jane > Holds" -> "Holds"); '' when it is the screen itself.
    param([string]$Title, [string]$Heading)
    $t = "$Title".Trim(); $h = "$Heading".Trim()
    if (-not $t -or $t -eq $h) { return '' }
    if ($h -and $t.StartsWith("$h > ")) { return $t.Substring($h.Length + 3) }
    return $t
}

function Get-NmGuiViewerMode {
    <#
    .SYNOPSIS
        How a pop-up lays out its tables: Single (one), Sections (2 to 8 small ones on one page,
        each with a heading) or Tabs (anything with a big table, where flipping between them helps).
    #>
    param([int[]]$RowCounts = @())
    $n = @($RowCounts).Count
    if ($n -le 1) { return 'Single' }
    if ($n -le 8 -and -not @($RowCounts | Where-Object { $_ -gt 25 }).Count) { return 'Sections' }
    return 'Tabs'
}

function Get-NmGuiSectionText {
    # A pop-up's sections as plain text for Copy all: the heading, then each section's name and
    # its fields ("Name: value"), records separated by a blank line.
    param([object[]]$Sections, [string]$Heading)
    $out = New-Object System.Collections.Generic.List[string]
    if ($Heading) { $out.Add($Heading); $out.Add('') }
    foreach ($sec in @($Sections)) {
        $out.Add("$($sec.Name)")
        foreach ($r in @($sec.Capture.Rows)) {
            foreach ($f in @(Get-NmGuiDetailField -Row $r -Columns $sec.Capture.Columns)) { $out.Add("  $(ConvertTo-NmGuiLabel $f.Name): $($f.Value)") }
            $out.Add('')
        }
    }
    return (($out -join "`r`n").TrimEnd())
}

function Get-NmGuiNoteLine {
    # The warnings and errors a tool wrote ("[WARN] Inbox rules not read: ..."), to show above the sections.
    param([string]$Text)
    foreach ($l in @("$Text" -split "`r?`n")) {
        if ($l -match '^\[[^\]]+\] \[(WARN|ERROR)\] (.+)$') { [pscustomobject]@{ Level = $Matches[1]; Text = $Matches[2].Trim() } }
    }
}

# --- WPF builders (Windows only) ---------------------------------------------
function Get-NmGuiBrush { param([string]$Hex) return (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex) }

function Get-NmGuiWrapStyle {
    # Grid cells that wrap long text instead of cutting it off.
    if (-not $script:NmGuiWrapStyle) {
        $st = New-Object System.Windows.Style ([System.Windows.Controls.TextBlock])
        $st.Setters.Add((New-Object System.Windows.Setter ([System.Windows.Controls.TextBlock]::TextWrappingProperty), ([System.Windows.TextWrapping]::Wrap)))
        $st.Setters.Add((New-Object System.Windows.Setter ([System.Windows.FrameworkElement]::MarginProperty), (New-Object System.Windows.Thickness 4, 3, 4, 3)))
        $st.Setters.Add((New-Object System.Windows.Setter ([System.Windows.FrameworkElement]::VerticalAlignmentProperty), ([System.Windows.VerticalAlignment]::Center)))
        $script:NmGuiWrapStyle = $st
    }
    return $script:NmGuiWrapStyle
}

function Set-NmGuiWrapColumn {
    # AutoGeneratingColumn: text columns wrap, and none grows wider than 560 pixels.
    param($Column)
    if ($Column -is [System.Windows.Controls.DataGridTextColumn]) {
        $Column.MaxWidth = 560
        $Column.ElementStyle = Get-NmGuiWrapStyle
    }
}

function New-NmGuiText {
    param([string]$Text, [double]$Size = 13, [string]$Color = '#16191F', [string]$Weight = 'Normal', [switch]$Wrap, [string]$Margin = '0')
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = $Size; $t.Foreground = Get-NmGuiBrush $Color; $t.FontWeight = $Weight; $t.Margin = $Margin
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    return $t
}

function New-NmGuiPill {
    # A small coloured label: a severity, a verdict, or a count.
    param([string]$Text, [string]$Severity, [string]$Margin = '0,0,8,0')
    $c = Get-NmGuiSeverityColor -Severity $Severity
    $b = New-Object System.Windows.Controls.Border
    $b.Background = Get-NmGuiBrush $c.Back; $b.CornerRadius = 10; $b.Padding = '9,2'; $b.Margin = $Margin; $b.VerticalAlignment = 'Center'
    $b.Child = New-NmGuiText -Text $Text -Size 11.5 -Color $c.Fore -Weight 'SemiBold'
    return $b
}

function New-NmGuiValueBox {
    # A value that wraps, long words included. A TextBlock rather than a read-only TextBox: a
    # TextBox takes the mouse wheel, so the card list would stop scrolling under the pointer.
    # Each card has a Copy button for the text.
    param([string]$Text, [string]$Color = '#16191F', [double]$Size = 13)
    $v = New-Object System.Windows.Controls.TextBlock
    $v.Text = $Text; $v.TextWrapping = 'Wrap'; $v.FontSize = $Size; $v.Foreground = Get-NmGuiBrush $Color
    if ($Text -match '^\S{40,}$') { $v.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas' }
    return $v
}

function New-NmGuiFieldGrid {
    # Name / value pairs as two columns: names in grey on the left, values wrapping on the right.
    param([object[]]$Fields, [int]$NameWidth = 170)
    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength $NameWidth
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2)
    $i = 0
    foreach ($f in @($Fields)) {
        $g.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $n = New-NmGuiText -Text (ConvertTo-NmGuiLabel $f.Name) -Size 12 -Color '#5B6370' -Wrap -Margin '0,5,12,5'
        [System.Windows.Controls.Grid]::SetRow($n, $i); [void]$g.Children.Add($n)
        $v = New-NmGuiValueBox -Text "$($f.Value)"; $v.Margin = '0,5,0,5'
        [System.Windows.Controls.Grid]::SetRow($v, $i); [System.Windows.Controls.Grid]::SetColumn($v, 1); [void]$g.Children.Add($v)
        $i++
    }
    return $g
}

function New-NmGuiCopyButton {
    # "Copy": puts the text in its Tag on the clipboard. The handler uses only the button, so it
    # works long after the function that made it has returned.
    param([string]$Text, [string]$Label = 'Copy')
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Label; $b.Tag = $Text; $b.MinHeight = 28; $b.Padding = '10,2'; $b.Margin = '8,0,0,0'; $b.FontSize = 12
    $b.Add_Click({ param($s, $e) [System.Windows.Clipboard]::SetText("$($s.Tag)") })
    return $b
}

function New-NmGuiDetailCard {
    <#
    .SYNOPSIS
        One record as a card: a title (with a severity label when the row has one), then every field
        as name and value, wrapping, selectable, with a Copy button for the whole card.
    #>
    # -NoCopy: no Copy button (a section of a pop-up, which has one Copy all).
    param($Row, [string[]]$Columns = @(), [switch]$NoTitle, [switch]$NoCopy)
    $title = if ($NoTitle) { [pscustomobject]@{ Field = ''; Text = '' } } else { Get-NmGuiCardTitle -Row $Row -Columns $Columns }
    $fields = @(Get-NmGuiDetailField -Row $Row -Columns $Columns | Where-Object { $_.Name -ne $title.Field -and $_.Name -ne 'Severity' })
    $card = New-Object System.Windows.Controls.Border
    $card.Background = Get-NmGuiBrush '#FFFFFF'; $card.BorderBrush = Get-NmGuiBrush '#E2E5EA'; $card.BorderThickness = 1; $card.CornerRadius = 10
    $card.Padding = '18,14'; $card.Margin = '0,0,0,12'
    $sp = New-Object System.Windows.Controls.StackPanel
    $sevProp = $Row.PSObject.Properties['Severity']
    $hasSev = [bool]($sevProp -and "$($sevProp.Value)")
    # The heading line only when it has something in it (no empty band above the fields).
    if ($title.Text -or $hasSev -or -not $NoCopy) {
        $head = New-Object System.Windows.Controls.DockPanel
        $head.LastChildFill = $true; $head.Margin = '0,0,0,8'
        if (-not $NoCopy) {
            $copyText = ((@($(if ($title.Field) { "$($title.Field): $($title.Text)" })) + @($fields | ForEach-Object { "$($_.Name): $($_.Value)" })) | Where-Object { $_ }) -join "`r`n"
            $copy = New-NmGuiCopyButton -Text $copyText
            [System.Windows.Controls.DockPanel]::SetDock($copy, 'Right'); [void]$head.Children.Add($copy)
        }
        if ($hasSev) {
            $pill = New-NmGuiPill -Text "$($sevProp.Value)" -Severity "$($sevProp.Value)"
            [System.Windows.Controls.DockPanel]::SetDock($pill, 'Left'); [void]$head.Children.Add($pill)
        }
        if ($title.Text) { $t = New-NmGuiValueBox -Text $title.Text -Size 15; $t.FontWeight = 'SemiBold'; [void]$head.Children.Add($t) }
        else { [void]$head.Children.Add((New-Object System.Windows.Controls.TextBlock)) }
        [void]$sp.Children.Add($head)
    }
    if ($fields.Count) { [void]$sp.Children.Add((New-NmGuiFieldGrid -Fields $fields)) }
    $card.Child = $sp
    return $card
}

function New-NmGuiCardList {
    # The rows of a Format-List capture as cards, filtered by text.
    # -NoScroll: just the cards, for a section of a page that scrolls as a whole. A one-record
    # section has no card title: the section heading names it.
    param($Capture, [string]$Filter = '', [switch]$NoScroll)
    $sp = New-Object System.Windows.Controls.StackPanel
    $rows = @($Capture.Rows | Where-Object { Test-NmGuiRowMatch -Row $_ -Text $Filter })
    $one = $NoScroll -and @($Capture.Rows).Count -eq 1
    foreach ($r in $rows) { [void]$sp.Children.Add((New-NmGuiDetailCard -Row $r -Columns $Capture.Columns -NoTitle:$one -NoCopy:$NoScroll)) }
    if (-not $rows.Count) { [void]$sp.Children.Add((New-NmGuiText -Text $(if ("$Filter".Trim()) { 'Nothing matches the filter.' } else { 'Nothing to show.' }) -Color '#5B6370' -Margin '6')) }
    if ($NoScroll) { return $sp }
    $sv = New-Object System.Windows.Controls.ScrollViewer
    $sv.VerticalScrollBarVisibility = 'Auto'; $sv.HorizontalScrollBarVisibility = 'Disabled'; $sv.Background = Get-NmGuiBrush '#F6F7F9'; $sv.Padding = '12'
    $sv.Content = $sp
    return $sv
}

function New-NmGuiFindingCard {
    # One finding: a coloured edge, severity and meta line, the finding in full, the next step,
    # and "Details" opening the evidence, why and indicators in place.
    param($Item)
    $c = Get-NmGuiSeverityColor -Severity $Item.Severity
    $outer = New-Object System.Windows.Controls.Border
    $outer.Background = Get-NmGuiBrush '#FFFFFF'; $outer.BorderBrush = Get-NmGuiBrush '#E2E5EA'; $outer.BorderThickness = 1; $outer.CornerRadius = 10; $outer.Margin = '0,0,0,10'
    $grid = New-Object System.Windows.Controls.Grid
    $g1 = New-Object System.Windows.Controls.ColumnDefinition; $g1.Width = New-Object System.Windows.GridLength 5
    $g2 = New-Object System.Windows.Controls.ColumnDefinition; $g2.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($g1); $grid.ColumnDefinitions.Add($g2)
    $edge = New-Object System.Windows.Controls.Border
    $edge.Background = Get-NmGuiBrush $c.Fore; $edge.CornerRadius = '10,0,0,10'
    [void]$grid.Children.Add($edge)
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '16,12,16,12'
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)

    $top = New-Object System.Windows.Controls.DockPanel
    $top.LastChildFill = $true
    $more = New-Object System.Windows.Controls.Button
    $more.Content = 'Details'; $more.MinHeight = 28; $more.Padding = '10,2'; $more.Margin = '8,0,0,0'; $more.FontSize = 12
    [System.Windows.Controls.DockPanel]::SetDock($more, 'Right'); [void]$top.Children.Add($more)
    $pill = New-NmGuiPill -Text $Item.Severity -Severity $Item.Severity
    [System.Windows.Controls.DockPanel]::SetDock($pill, 'Left'); [void]$top.Children.Add($pill)
    [void]$top.Children.Add((New-NmGuiText -Text $Item.Meta -Size 12 -Color '#5B6370'))
    [void]$sp.Children.Add($top)

    $title = New-NmGuiValueBox -Text $Item.Title -Size 14.5; $title.FontWeight = 'SemiBold'; $title.Margin = '0,8,0,0'
    [void]$sp.Children.Add($title)
    if ($Item.Step) {
        $step = New-Object System.Windows.Controls.DockPanel
        $step.Margin = '0,8,0,0'
        $lab = New-NmGuiText -Text 'Next step' -Size 12 -Color '#0A4F4B' -Weight 'SemiBold' -Margin '0,0,10,0'
        [System.Windows.Controls.DockPanel]::SetDock($lab, 'Left'); [void]$step.Children.Add($lab)
        [void]$step.Children.Add((New-NmGuiValueBox -Text $Item.Step -Color '#2B313B'))
        [void]$sp.Children.Add($step)
    }
    $details = New-Object System.Windows.Controls.Border
    $details.Background = Get-NmGuiBrush '#F6F7F9'; $details.CornerRadius = 8; $details.Padding = '12,8'; $details.Margin = '0,10,0,0'; $details.Visibility = 'Collapsed'
    $copyText = ((@("$($Item.Severity): $($Item.Title)", $(if ($Item.Meta) { $Item.Meta }), $(if ($Item.Step) { "Next step: $($Item.Step)" })) + @($Item.Details | ForEach-Object { "$($_.Name): $($_.Value)" })) | Where-Object { $_ }) -join "`r`n"
    $dsp = New-Object System.Windows.Controls.StackPanel
    if (@($Item.Details).Count) { [void]$dsp.Children.Add((New-NmGuiFieldGrid -Fields $Item.Details -NameWidth 120)) }
    $copy = New-NmGuiCopyButton -Text $copyText -Label 'Copy finding'; $copy.HorizontalAlignment = 'Right'; $copy.Margin = '0,6,0,0'
    [void]$dsp.Children.Add($copy)
    $details.Child = $dsp
    [void]$sp.Children.Add($details)
    # The handler only touches the button and its Tag (the details panel), so it needs nothing else.
    $more.Tag = $details
    $more.Add_Click({ param($s, $e) $p = $s.Tag; if ($p.Visibility -eq 'Visible') { $p.Visibility = 'Collapsed'; $s.Content = 'Details' } else { $p.Visibility = 'Visible'; $s.Content = 'Hide details' } })

    [void]$grid.Children.Add($sp)
    $outer.Child = $grid
    return $outer
}

function New-NmGuiFacetChip {
    # A tag that filters when clicked: "9 High". Picked, it gets a ring; clicked again, it clears.
    # The handler reads only the button's Tag, and calls Set-NmGuiFacet (a module function: plain
    # handler, no closure).
    param([string]$Text, [string]$Level, [string]$Value, [switch]$Picked)
    $c = Get-NmGuiSeverityColor -Severity $Level
    $b = New-Object System.Windows.Controls.Button
    $b.Tag = $Value; $b.MinHeight = 0; $b.Padding = '0'; $b.Margin = '0,0,8,6'; $b.Background = Get-NmGuiBrush '#00FFFFFF'; $b.BorderThickness = 0
    $b.ToolTip = $(if ($Picked) { 'Showing only these. Click again to show all.' } else { "Show only $Value" })
    $pill = New-NmGuiPill -Text $Text -Severity $Level -Margin '0'
    $pill.Padding = '11,4'
    if ($Picked) { $pill.BorderBrush = Get-NmGuiBrush $c.Fore; $pill.BorderThickness = 2 } else { $pill.BorderBrush = Get-NmGuiBrush '#00FFFFFF'; $pill.BorderThickness = 2 }
    $b.Content = $pill
    $b.Add_Click({ param($s, $e) Set-NmGuiFacet -Value "$($s.Tag)" })
    return $b
}

function Set-NmGuiFacet {
    # Click a tag: show only that value; click it again: show everything.
    param([string]$Value)
    $script:NmGui.Facet = $(if ($script:NmGui.Facet -eq $Value) { '' } else { $Value })
    $script:NmGui.CardLimit = 100
    Update-NmGuiCardView
}

function New-NmGuiResultCard {
    # One result row as a card: status label, title, the shown columns, More for the other fields,
    # and Open for the tool's own row screen when it has one.
    param($Item, [switch]$CanOpen, [switch]$Selectable)
    $outer = New-Object System.Windows.Controls.Border
    $outer.Background = Get-NmGuiBrush '#FFFFFF'; $outer.BorderBrush = Get-NmGuiBrush '#E2E5EA'; $outer.BorderThickness = 1; $outer.CornerRadius = 10; $outer.Margin = '0,0,0,10'
    $grid = New-Object System.Windows.Controls.Grid
    $g1 = New-Object System.Windows.Controls.ColumnDefinition; $g1.Width = New-Object System.Windows.GridLength 5
    $g2 = New-Object System.Windows.Controls.ColumnDefinition; $g2.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($g1); $grid.ColumnDefinitions.Add($g2)
    if ($Item.Level) {
        $edge = New-Object System.Windows.Controls.Border
        $edge.Background = Get-NmGuiBrush (Get-NmGuiSeverityColor -Severity $Item.Level).Fore; $edge.CornerRadius = '10,0,0,10'
        [void]$grid.Children.Add($edge)
    }
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = '16,12,16,12'
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    $top = New-Object System.Windows.Controls.DockPanel
    $top.LastChildFill = $true
    $copyText = ((@($Item.Title, $(if ($Item.Status) { $Item.Status })) + @(@($Item.Fields) + @($Item.More) | ForEach-Object { "$($_.Name): $($_.Value)" })) | Where-Object { $_ }) -join "`r`n"
    $copy = New-NmGuiCopyButton -Text $copyText
    [System.Windows.Controls.DockPanel]::SetDock($copy, 'Right'); [void]$top.Children.Add($copy)
    if ($CanOpen) {
        $open = New-Object System.Windows.Controls.Button
        $open.Content = 'Open'; $open.Tag = $Item.Index; $open.MinHeight = 28; $open.Padding = '10,2'; $open.Margin = '8,0,0,0'; $open.FontSize = 12
        $open.ToolTip = 'The tool''s own screen for this row'
        $open.Add_Click({ param($s, $e) Show-NmGuiRowDetail -Index ([int]$s.Tag) })
        [System.Windows.Controls.DockPanel]::SetDock($open, 'Right'); [void]$top.Children.Add($open)
    }
    $more = $null
    if (@($Item.More).Count) {
        $more = New-Object System.Windows.Controls.Button
        $more.Content = 'More'; $more.MinHeight = 28; $more.Padding = '10,2'; $more.Margin = '8,0,0,0'; $more.FontSize = 12
        [System.Windows.Controls.DockPanel]::SetDock($more, 'Right'); [void]$top.Children.Add($more)
    }
    if ($Selectable) {
        # Tick to act on several rows at once (the tool's bulk actions, in the bar above the results).
        $tick = New-Object System.Windows.Controls.CheckBox
        $tick.Tag = $Item.Index; $tick.VerticalAlignment = 'Center'; $tick.Margin = '0,0,10,0'
        $tick.ToolTip = 'Select this row for an action on several rows'
        $tick.IsChecked = $script:NmGui.Selected.Contains([int]$Item.Index)
        $tick.Add_Click({ param($s, $e) Set-NmGuiRowSelected -Index ([int]$s.Tag) -Selected ([bool]$s.IsChecked) })
        [System.Windows.Controls.DockPanel]::SetDock($tick, 'Left'); [void]$top.Children.Add($tick)
    }
    if ($Item.Status) {
        $pill = New-NmGuiPill -Text $Item.Status -Severity $Item.Level
        [System.Windows.Controls.DockPanel]::SetDock($pill, 'Left'); [void]$top.Children.Add($pill)
    }
    $t = New-NmGuiValueBox -Text $Item.Title -Size 14.5; $t.FontWeight = 'SemiBold'; $t.VerticalAlignment = 'Center'
    [void]$top.Children.Add($t)
    [void]$sp.Children.Add($top)
    if (@($Item.Fields).Count) { $fg = New-NmGuiFieldGrid -Fields $Item.Fields -NameWidth 150; $fg.Margin = '0,8,0,0'; [void]$sp.Children.Add($fg) }
    if ($more) {
        $extra = New-Object System.Windows.Controls.Border
        $extra.Background = Get-NmGuiBrush '#F6F7F9'; $extra.CornerRadius = 8; $extra.Padding = '12,8'; $extra.Margin = '0,8,0,0'; $extra.Visibility = 'Collapsed'
        $extra.Child = New-NmGuiFieldGrid -Fields $Item.More -NameWidth 150
        [void]$sp.Children.Add($extra)
        $more.Tag = $extra
        $more.Add_Click({ param($s, $e) $p = $s.Tag; if ($p.Visibility -eq 'Visible') { $p.Visibility = 'Collapsed'; $s.Content = 'More' } else { $p.Visibility = 'Visible'; $s.Content = 'Less' } })
    }
    [void]$grid.Children.Add($sp)
    $outer.Child = $grid
    return $outer
}

function Get-NmGuiCardCountText {
    # The line above the cards: "Showing 12 of 40." when filtered; for grouped cards also how many
    # rows the cards hold ("127 rows in 40 cards, one per Mailbox.").
    param($Model)
    $m = $Model
    if ($m.GroupBy) {
        $t = "$($m.Shown) row$(if ($m.Shown -ne 1) { 's' }) in $($m.Cards) card$(if ($m.Cards -ne 1) { 's' }), one per $($m.GroupBy)."
        if ($m.Shown -ne $m.Total) { $t = "Showing $($m.Shown) of $($m.Total) rows, in $($m.Cards) card$(if ($m.Cards -ne 1) { 's' }), one per $($m.GroupBy)." }
        return $t
    }
    if ($m.Shown -ne $m.Total) { return "Showing $($m.Shown) of $($m.Total)." }
    return ''
}

function New-NmGuiCardView {
    <#
    .SYNOPSIS
        Any tool's results as cards: the tags to filter by (Result, Status and so on), a card per
        row (the first 100, with Show more), and a line saying how many are shown.
    #>
    param([object[]]$Rows, [string[]]$Columns, [string]$Filter = '', [string]$Facet = '', [int]$Limit = 100, [switch]$CanOpen, [string[]]$GroupBy = @(), [switch]$Selectable)
    $m = Get-NmGuiCardModel -Rows $Rows -Columns $Columns -Filter $Filter -Facet $Facet -Limit $Limit -GroupBy $GroupBy
    $script:NmGui.ShownIndex = @($m.ShownIndex)
    $root = New-Object System.Windows.Controls.StackPanel
    $root.Margin = '0,0,8,0'
    if (@($m.Facets).Count -gt 1 -or $m.Facet) {
        $chips = New-Object System.Windows.Controls.WrapPanel
        $chips.Margin = '0,0,0,8'
        [void]$chips.Children.Add((New-NmGuiText -Text "$($m.FacetColumn):" -Size 12 -Color '#5B6370' -Margin '0,5,10,0'))
        foreach ($f in $m.Facets) { [void]$chips.Children.Add((New-NmGuiFacetChip -Text "$($f.Count) $($f.Value)" -Level $f.Level -Value $f.Value -Picked:($m.Facet -eq $f.Value))) }
        [void]$root.Children.Add($chips)
    }
    $countText = Get-NmGuiCardCountText -Model $m
    if ($countText) { [void]$root.Children.Add((New-NmGuiText -Text $countText -Size 12 -Color '#5B6370' -Margin '2,0,0,10')) }
    $tickable = $Selectable -and -not $m.GroupBy
    foreach ($it in $m.Items) { [void]$root.Children.Add((New-NmGuiResultCard -Item $it -CanOpen:$CanOpen -Selectable:$tickable)) }
    if (-not @($m.Items).Count) { [void]$root.Children.Add((New-NmGuiText -Text 'Nothing matches.' -Color '#5B6370' -Margin '4')) }
    if ($m.Remaining -gt 0) {
        $b = New-Object System.Windows.Controls.Button
        $noun = if ($m.GroupBy) { ' cards' } else { '' }
        $b.Content = "Show $([Math]::Min(100, $m.Remaining)) more ($($m.Remaining)$noun not shown)"; $b.HorizontalAlignment = 'Left'; $b.Margin = '0,4,0,12'
        $b.Add_Click({ $script:NmGui.CardLimit = [int]$script:NmGui.CardLimit + 100; Update-NmGuiCardView })
        [void]$root.Children.Add($b)
    }
    return $root
}

function New-NmGuiFindingView {
    <#
    .SYNOPSIS
        The findings view (tools with View = 'Findings', such as ir-triage): a verdict banner with the
        count per severity and the case folder, then a card per finding grouped by severity.
    #>
    param([object[]]$Rows, [string]$Filter = '', [string]$Facet = '')
    $m = Get-NmGuiFindingModel -Rows $Rows -Filter $Filter -Facet $Facet
    $root = New-Object System.Windows.Controls.StackPanel
    $root.Margin = '0,0,8,0'
    if ($m.Verdict) {
        $c = Get-NmGuiSeverityColor -Severity $m.Level
        $banner = New-Object System.Windows.Controls.Border
        $banner.Background = Get-NmGuiBrush $c.Back; $banner.BorderBrush = Get-NmGuiBrush $c.Fore; $banner.BorderThickness = '0,0,0,0'; $banner.CornerRadius = 12
        $banner.Padding = '20,16'; $banner.Margin = '0,0,0,16'
        $bsp = New-Object System.Windows.Controls.StackPanel
        $line1 = New-Object System.Windows.Controls.DockPanel
        $line1.LastChildFill = $true
        if ($m.Folder) {
            $open = New-Object System.Windows.Controls.Button
            $open.Content = 'Open case folder'; $open.Tag = $m.Folder; $open.Margin = '8,0,0,0'
            $open.Add_Click({ param($s, $e) Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$($s.Tag)`"" })
            [System.Windows.Controls.DockPanel]::SetDock($open, 'Right'); [void]$line1.Children.Add($open)
        }
        [void]$line1.Children.Add((New-NmGuiText -Text $m.Verdict.ToUpper() -Size 20 -Color $c.Fore -Weight 'Bold' -Wrap))
        [void]$bsp.Children.Add($line1)
        $who = @(@($m.Users) -join ', ', $(if ($m.CaseId) { "case $($m.CaseId)" })) | Where-Object { $_ }
        if ($who) { [void]$bsp.Children.Add((New-NmGuiText -Text ($who -join ('   ' + [char]0x00B7 + '   ')) -Size 12.5 -Color '#2B313B' -Margin '0,4,0,10' -Wrap)) }
        $chips = New-Object System.Windows.Controls.WrapPanel
        foreach ($n in $m.Counts) { [void]$chips.Children.Add((New-NmGuiFacetChip -Text "$($n.Count) $($n.Severity)" -Level $n.Severity -Value $n.Severity -Picked:($m.Facet -eq $n.Severity))) }
        [void]$bsp.Children.Add($chips)
        $banner.Child = $bsp
        [void]$root.Children.Add($banner)
    }
    if ($m.Shown -ne $m.Total) {
        $why = @($(if ($Facet) { $Facet }), $(if ($Filter.Trim()) { "'$($Filter.Trim())'" })) | Where-Object { $_ }
        [void]$root.Children.Add((New-NmGuiText -Text "Showing $($m.Shown) of $($m.Total) findings ($($why -join ', ')). Click the tag again to show all." -Size 12 -Color '#5B6370' -Margin '2,0,0,10'))
    }
    foreach ($g in $m.Groups) {
        $c = Get-NmGuiSeverityColor -Severity $g.Severity
        [void]$root.Children.Add((New-NmGuiText -Text "$($g.Severity.ToUpper())  ($(@($g.Items).Count))" -Size 12 -Color $c.Fore -Weight 'Bold' -Margin '2,6,0,8'))
        foreach ($it in $g.Items) { [void]$root.Children.Add((New-NmGuiFindingCard -Item $it)) }
    }
    if (-not @($m.Groups).Count) { [void]$root.Children.Add((New-NmGuiText -Text 'No findings match the filter.' -Color '#5B6370' -Margin '4')) }
    return $root
}

function New-NmGuiViewGrid {
    # A read-only table for one capture: sortable, several rows selectable, Ctrl+C / right-click copies with headers.
    param([Parameter(Mandatory)]$Capture)
    $dg = New-Object System.Windows.Controls.DataGrid
    $dg.IsReadOnly = $true; $dg.AutoGenerateColumns = $true; $dg.CanUserAddRows = $false; $dg.SelectionMode = 'Extended'; $dg.SelectionUnit = 'FullRow'
    $dg.ClipboardCopyMode = 'IncludeHeader'; $dg.HeadersVisibility = 'Column'; $dg.GridLinesVisibility = 'Horizontal'
    $conv = New-Object System.Windows.Media.BrushConverter
    $dg.Background = $conv.ConvertFromString('#FFFFFF'); $dg.BorderBrush = $conv.ConvertFromString('#E2E5EA'); $dg.RowBackground = $conv.ConvertFromString('#FFFFFF')
    $dg.AlternatingRowBackground = $conv.ConvertFromString('#FAFBFC'); $dg.HorizontalGridLinesBrush = $conv.ConvertFromString('#EEF0F3')
    $dg.ColumnHeaderHeight = 32; $dg.MinRowHeight = 28
    $dg.Add_AutoGeneratingColumn({ param($s, $e) Set-NmGuiWrapColumn -Column $e.Column })
    $table = ConvertTo-NmGuiTable -Rows $Capture.Rows -Columns $Capture.Columns
    $dg.ItemsSource = $table.DefaultView
    $menu = New-Object System.Windows.Controls.ContextMenu
    foreach ($m in @(@('Copy selected rows', [System.Windows.Input.ApplicationCommands]::Copy), @('Select all', [System.Windows.Input.ApplicationCommands]::SelectAll))) {
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $m[0]; $mi.Command = $m[1]; $mi.CommandTarget = $dg
        [void]$menu.Items.Add($mi)
    }
    $dg.ContextMenu = $menu
    return [pscustomobject]@{ Grid = $dg; Table = $table; Capture = $Capture }
}

function Show-NmGuiViewer {
    <#
    .SYNOPSIS
        Results in their own window: real tables for whatever the tool printed as a table (one tab
        each, plus the text), a filter, a count and breakdown, Export CSV and Open in Excel, and copy.
    #>
    param([string]$Text, [object[]]$Captures = @(), [string]$Heading, [string]$Title = 'Nutmeg AD Toolkit', [string]$CloseLabel = 'Close')
    $d = New-NmGuiXaml -Xaml ($script:NmGuiViewerXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $d.Title = $Title
    if ($script:NmGui.Window -and $script:NmGui.Window.IsLoaded) { $d.Owner = $script:NmGui.Window } else { $d.WindowStartupLocation = 'CenterScreen' }
    $ui = @{}
    foreach ($n in 'HeadingText', 'SummaryText', 'FilterBox', 'FilterHint', 'CountText', 'ExcelButton', 'CsvButton', 'Body', 'CloseButton', 'HintText') { $ui[$n] = $d.FindName($n) }
    $ui.HeadingText.Text = $(if ($Heading) { $Heading } elseif (@($Captures).Count -and $Captures[0].Title) { $Captures[0].Title } else { $Title })
    $ui.CloseButton.Content = $CloseLabel

    # One view per table, plus the text when there is any.
    $views = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($Captures | Where-Object { $_ -and @($_.Rows).Count })) {
        if ($c.Kind -eq 'List' -and @($c.Rows).Count -le 200) {
            # Format-List output is records: one card each, every field readable.
            $holder = New-Object System.Windows.Controls.ContentControl
            $holder.Focusable = $false
            $holder.Content = New-NmGuiCardList -Capture $c
            $views.Add([pscustomobject]@{ Kind = 'Cards'; Header = $(if ($c.Title) { $c.Title } else { 'Details' }); Grid = $holder; Table = $null; Capture = $c; Text = $null })
            continue
        }
        $v = New-NmGuiViewGrid -Capture $c
        $views.Add([pscustomobject]@{ Kind = 'Table'; Header = $(if ($c.Title) { $c.Title } else { 'Table' }); Grid = $v.Grid; Table = $v.Table; Capture = $c; Text = $null })
    }
    if ("$Text".Trim()) {
        $tb = New-Object System.Windows.Controls.TextBox
        $tb.IsReadOnly = $true; $tb.FontFamily = New-Object System.Windows.Media.FontFamily 'Consolas'; $tb.FontSize = 12; $tb.Padding = '10,8'
        $tb.VerticalContentAlignment = 'Stretch'; $tb.VerticalScrollBarVisibility = 'Auto'; $tb.HorizontalScrollBarVisibility = 'Auto'; $tb.TextWrapping = 'NoWrap'
        $tb.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString('#F6F7F9')
        $tb.Text = "$Text".TrimEnd()
        $views.Add([pscustomobject]@{ Kind = 'Text'; Header = $(if ($views.Count) { 'Text' } else { 'Output' }); Grid = $tb; Table = $null; Capture = $null; Text = "$Text".TrimEnd() })
    }
    $state = @{ Index = 0; Sections = $false }
    # Each table's own name, without the screen title in front of it.
    $base = "$($ui.HeadingText.Text)"
    if (-not $Heading) { $base = ($base -split ' > ', 2)[0]; $ui.HeadingText.Text = $base }
    foreach ($v in $views) { if ($v.Kind -ne 'Text') { $sec = Get-NmGuiSectionName -Title $v.Header -Heading $base; $v.Header = $(if ($sec) { $sec } else { 'Details' }) } }
    $dataViews = @($views | Where-Object { $_.Kind -ne 'Text' })
    $mode = Get-NmGuiViewerMode -RowCounts @($dataViews | ForEach-Object { @($_.Capture.Rows).Count })
    if ($mode -eq 'Sections') {
        # A few small parts (one mailbox's overview, a row's screens): one page that scrolls, a
        # heading per part, warnings on top, the raw text folded away at the bottom.
        $state.Sections = $true
        $page = New-Object System.Windows.Controls.StackPanel
        $page.Margin = '4,0,12,8'
        foreach ($n in @(Get-NmGuiNoteLine -Text $Text)) {
            $nb = New-Object System.Windows.Controls.Border
            $nc = Get-NmGuiSeverityColor -Severity $(if ($n.Level -eq 'ERROR') { 'High' } else { 'Medium' })
            $nb.Background = Get-NmGuiBrush $nc.Back; $nb.CornerRadius = 8; $nb.Padding = '12,8'; $nb.Margin = '0,0,0,8'
            $nb.Child = New-NmGuiText -Text $n.Text -Color $nc.Fore -Wrap
            [void]$page.Children.Add($nb)
        }
        for ($k = 0; $k -lt $views.Count; $k++) {
            $v = $views[$k]
            if ($v.Kind -eq 'Text') { continue }
            # Small tables become cards here too: a table inside a scrolling page takes the mouse wheel.
            $v.Kind = 'Cards'
            $holder = New-Object System.Windows.Controls.ContentControl
            $holder.Focusable = $false
            $holder.Content = New-NmGuiCardList -Capture $v.Capture -NoScroll
            $v.Grid = $holder
            $hd = New-Object System.Windows.Controls.DockPanel
            $hd.LastChildFill = $true; $hd.Margin = '0,14,0,8'
            $cnt = @($v.Capture.Rows).Count
            [void]$hd.Children.Add((New-NmGuiText -Text "$($v.Header)$(if ($cnt -gt 1) { "  ($cnt)" })" -Size 15 -Weight 'SemiBold' -Color '#0A4F4B'))
            [void]$page.Children.Add($hd)
            [void]$page.Children.Add($holder)
        }
        $txt = @($views | Where-Object { $_.Kind -eq 'Text' })
        if ($txt.Count) {
            $ex = New-Object System.Windows.Controls.Expander
            $ex.Header = 'Messages (everything the tool wrote)'; $ex.Margin = '0,14,0,0'; $ex.IsExpanded = $false
            $txt[0].Grid.Height = 220
            $ex.Content = $txt[0].Grid
            [void]$page.Children.Add($ex)
        }
        $sv = New-Object System.Windows.Controls.ScrollViewer
        $sv.VerticalScrollBarVisibility = 'Auto'; $sv.HorizontalScrollBarVisibility = 'Disabled'; $sv.Background = Get-NmGuiBrush '#F6F7F9'; $sv.Padding = '12'
        $sv.Content = $page
        $ui.Body.Content = $sv
        # One Copy all for the whole page instead of a Copy and an Export on every part.
        $ui.ExcelButton.Visibility = 'Collapsed'
        $ui.CsvButton.Content = 'Copy all'; $ui.CsvButton.ToolTip = 'Copy every section as text'
    } elseif ($views.Count -gt 1) {
        $tabs = New-Object System.Windows.Controls.TabControl
        foreach ($v in $views) {
            $ti = New-Object System.Windows.Controls.TabItem
            $count = if ($v.Kind -ne 'Text' -and @($v.Capture.Rows).Count -gt 1) { " ($(@($v.Capture.Rows).Count))" } else { '' }
            $h = "$($v.Header)"; if ($h.Length -gt 60) { $h = $h.Substring(0, 60) + '...' }
            $ti.Header = "$h$count"; $ti.Content = $v.Grid
            [void]$tabs.Items.Add($ti)
        }
        $ui.Body.Content = $tabs
    } elseif ($views.Count -eq 1) { $ui.Body.Content = $views[0].Grid }

    $refresh = {
        if (-not $views.Count) { $ui.CountText.Text = ''; $ui.SummaryText.Text = ''; return }
        if ($state.Sections) {
            # Every section follows the filter.
            $f = "$($ui.FilterBox.Text)"
            $shown = 0; $all = 0
            foreach ($v in @($views | Where-Object { $_.Kind -eq 'Cards' })) {
                $v.Grid.Content = New-NmGuiCardList -Capture $v.Capture -Filter $f -NoScroll
                $all += @($v.Capture.Rows).Count
                $shown += @($v.Capture.Rows | Where-Object { Test-NmGuiRowMatch -Row $_ -Text $f }).Count
            }
            $ui.CountText.Text = $(if ($f.Trim()) { "$shown of $all" } else { '' })
            $ui.SummaryText.Text = "$(@($views | Where-Object { $_.Kind -eq 'Cards' }).Count) sections"
            $ui.HintText.Visibility = 'Collapsed'
            return
        }
        $v = $views[$state.Index]
        $f = "$($ui.FilterBox.Text)"
        if ($v.Kind -eq 'Table') {
            $v.Table.DefaultView.RowFilter = Get-NmGuiRowFilter -Text $f -Table $v.Table
            $shown = $v.Table.DefaultView.Count; $all = $v.Table.Rows.Count
            $ui.CountText.Text = $(if ($f.Trim()) { "$shown of $all rows" } else { '' })
            $ui.SummaryText.Text = Get-NmGuiTableSummary -Rows $v.Capture.Rows -Columns $v.Capture.Columns
            $ui.HintText.Visibility = 'Visible'
        } elseif ($v.Kind -eq 'Cards') {
            $v.Grid.Content = New-NmGuiCardList -Capture $v.Capture -Filter $f
            $all = @($v.Capture.Rows).Count
            $shown = @($v.Capture.Rows | Where-Object { Test-NmGuiRowMatch -Row $_ -Text $f }).Count
            $ui.CountText.Text = $(if ($f.Trim()) { "$shown of $all" } else { '' })
            $ui.SummaryText.Text = $(if ($all -eq 1) { '' } else { "$all records" })
            $ui.HintText.Visibility = 'Collapsed'
        } else {
            $lines = @(Select-NmGuiTextLine -Text $v.Text -Filter $f)
            $v.Grid.Text = ($lines -join "`r`n")
            $total = @("$($v.Text)" -split "`r?`n").Count
            $ui.CountText.Text = $(if ($f.Trim()) { "$($lines.Count) of $total lines" } else { '' })
            $ui.SummaryText.Text = "$total lines"
            $ui.HintText.Visibility = 'Collapsed'
        }
    }
    if ($ui.Body.Content -is [System.Windows.Controls.TabControl]) {
        $ui.Body.Content.Add_SelectionChanged({ param($sender2, $e) if ($e.OriginalSource -is [System.Windows.Controls.TabControl]) { $state.Index = $ui.Body.Content.SelectedIndex; & $refresh } })
    }
    $ui.FilterBox.Add_TextChanged({ $ui.FilterHint.Visibility = $(if ($ui.FilterBox.Text) { 'Collapsed' } else { 'Visible' }); & $refresh })

    $export = {
        param([bool]$Open)
        if (-not $views.Count) { return }
        if ($state.Sections) {
            [System.Windows.Clipboard]::SetText((Get-NmGuiSectionText -Sections @($views | Where-Object { $_.Kind -eq 'Cards' } | ForEach-Object { [pscustomobject]@{ Name = $_.Header; Capture = $_.Capture } }) -Heading $ui.HeadingText.Text))
            $ui.CountText.Text = 'Copied every section.'
            return
        }
        $v = $views[$state.Index]
        $data = if ($v.Kind -eq 'Table') {
            # What is shown: the filtered rows, in the order shown.
            @(foreach ($drv in $v.Table.DefaultView) { $v.Capture.Rows[[int]$drv.Row['#'] - 1] })
        } elseif ($v.Kind -eq 'Cards') {
            @($v.Capture.Rows | Where-Object { Test-NmGuiRowMatch -Row $_ -Text $ui.FilterBox.Text })
        } else {
            @(Select-NmGuiTextLine -Text $v.Text -Filter $ui.FilterBox.Text | ForEach-Object { [pscustomobject]@{ Line = $_ } })
        }
        $id = if ($script:NmGui.Tool) { $script:NmGui.Tool.Id } else { 'results' }
        try {
            $path = Export-NmResult -Data $data -ToolId "$id-detail" -Format Csv -NoPrompt
            if (-not $path) { return }
            if ($Open) { Start-Process -FilePath $path; $ui.CountText.Text = "Opened $(Split-Path $path -Leaf)" }
            else { $ui.CountText.Text = "Saved $(Split-Path $path -Leaf)"; Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$path`"" }
        } catch {
            [void][System.Windows.MessageBox]::Show($d, "Could not export: $($_.Exception.Message)", 'Nutmeg AD Toolkit', 'OK', 'Warning')
        }
    }
    $ui.CsvButton.Add_Click({ & $export $false })
    $ui.ExcelButton.Add_Click({ & $export $true })
    $ui.CloseButton.Add_Click({ $d.Close() })
    $d.Add_PreviewKeyDown({
        param($w, $e)
        if ($e.Key -eq 'F' -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) { $ui.FilterBox.Focus() | Out-Null; $e.Handled = $true }
    })
    $ui.CsvButton.IsEnabled = ($views.Count -gt 0); $ui.ExcelButton.IsEnabled = ($views.Count -gt 0)
    & $refresh
    [void]$d.ShowDialog()
    return ''
}

function Get-NmGuiConfirmModel {
    <#
    .SYNOPSIS
        What the approval dialog shows (no WPF): Title, Action, Facts (Domain, DC, Scope), every
        target, and whether a word must be typed (Expected) or Approve / Cancel is enough.
    #>
    param([Parameter(Mandatory)][string]$Action, [string]$Domain, [string]$Server, [switch]$DomainWide,
          [object[]]$Targets = @(), [string]$Expected, [string]$Kind, [string[]]$Facts = @())
    $chips = New-Object System.Collections.Generic.List[object]
    foreach ($f in $Facts) {
        $parts = "$f" -split ':\s*', 2
        $chips.Add([pscustomobject]@{ Name = $parts[0]; Value = $(if ($parts.Count -gt 1) { $parts[1] } else { '' }) })
    }
    if ($Domain -or -not $Facts.Count) { $chips.Add([pscustomobject]@{ Name = 'Domain'; Value = $(if ($Domain) { $Domain } else { 'no domain' }) }) }
    if ($Server) { $chips.Add([pscustomobject]@{ Name = 'DC'; Value = $Server }) }
    $count = @($Targets).Count
    $chips.Add([pscustomobject]@{ Name = 'Scope'; Value = $(if ($DomainWide) { 'domain-wide' } else { "$count object(s)" }) })
    [pscustomobject]@{
        Title    = 'Approve this change'
        Action   = $Action
        Facts    = $chips.ToArray()
        Targets  = @($Targets | ForEach-Object { "$_" })
        Expected = $Expected
        Typed    = [bool]$Expected
        Hint     = $(if ($Expected) { "$Kind. Type '$Expected' to approve." } else { 'Nothing changes until you approve.' })
    }
}

function Read-NmGuiConfirm {
    # Confirm-NmChange in the window: the approval dialog. $true only for Approve with the right word.
    param([Parameter(Mandatory)][string]$Action, [string]$Domain, [string]$Server, [switch]$DomainWide,
          [object[]]$Targets = @(), [string]$Expected, [string]$Kind, [string[]]$Facts = @())
    $model = Get-NmGuiConfirmModel -Action $Action -Domain $Domain -Server $Server -DomainWide:$DomainWide -Targets $Targets -Expected $Expected -Kind $Kind -Facts $Facts
    $ok = if ($script:NmGui.ConfirmProvider) { [bool](& $script:NmGui.ConfirmProvider $model) } else { [bool](Show-NmGuiConfirm -Model $model) }
    [void]$script:NmGui.Transcript.Append("CHANGE: $Action ($((@($model.Facts | ForEach-Object { "$($_.Name): $($_.Value)" })) -join ', '))`r`n> $(if ($ok) { 'approved' } else { 'not approved' })`r`n")
    Clear-NmGuiBuffer
    return $ok
}

$script:NmGuiConfirmXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Nutmeg AD Toolkit" Width="680" SizeToContent="Height" WindowStartupLocation="CenterOwner" Background="#FFFFFF" FontFamily="Segoe UI" FontSize="13"
        Foreground="#16191F" ShowInTaskbar="False" ResizeMode="NoResize">
  <Window.Resources>
    <!--NMSTYLES-->
  </Window.Resources>
  <StackPanel Margin="22,18,22,16">
    <Border Background="#FFF1DC" CornerRadius="6" Padding="8,2" HorizontalAlignment="Left">
      <TextBlock x:Name="TitleText" Foreground="#8A4B00" FontSize="11" FontWeight="SemiBold"/>
    </Border>
    <TextBlock x:Name="ActionText" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,8,0,0"/>
    <WrapPanel x:Name="FactPanel" Margin="0,10,0,0"/>
    <ScrollViewer MaxHeight="340" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="0,12,0,0">
      <StackPanel x:Name="TargetPanel"/>
    </ScrollViewer>
    <TextBlock x:Name="HintText" FontSize="13" Foreground="#3D4450" TextWrapping="Wrap" Margin="0,14,0,0"/>
    <TextBox x:Name="WordBox" Margin="0,8,0,0" MinHeight="32" Padding="6,4" VerticalContentAlignment="Center" Visibility="Collapsed"/>
    <DockPanel Margin="0,16,0,0" LastChildFill="False">
      <Button x:Name="OkButton" DockPanel.Dock="Right" Content="Approve" MinWidth="110" Margin="0" Style="{StaticResource PrimaryButton}"/>
      <Button x:Name="CancelButton" DockPanel.Dock="Right" Content="Cancel" MinWidth="96" IsCancel="True"/>
    </DockPanel>
  </StackPanel>
</Window>
'@
$script:NmGuiConfirmControls = @('TitleText', 'ActionText', 'FactPanel', 'TargetPanel', 'HintText', 'WordBox', 'OkButton', 'CancelButton')

function Show-NmGuiConfirm {
    # The approval dialog. Approve is enabled only once the word is typed (when one is needed).
    param([Parameter(Mandatory)]$Model)
    $d = New-NmGuiXaml -Xaml ($script:NmGuiConfirmXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    if ($script:NmGui.Window -and $script:NmGui.Window.IsLoaded) { $d.Owner = $script:NmGui.Window } else { $d.WindowStartupLocation = 'CenterScreen' }
    Set-NmGuiDialogFit -Dialog $d -Want 720
    $ui = @{}; foreach ($n in $script:NmGuiConfirmControls) { $ui[$n] = $d.FindName($n) }
    # The plan scrolls inside the dialog, which stays inside the window.
    try { $ui.TargetPanel.Parent.MaxHeight = [Math]::Max(160, $d.MaxHeight - 330) } catch { $null = $_ }
    $ui.TitleText.Text = $Model.Title.ToUpper()
    $ui.ActionText.Text = $Model.Action
    foreach ($f in $Model.Facts) {
        $chip = New-Object System.Windows.Controls.Border
        $chip.Background = Get-NmGuiBrush '#F1F3F6'; $chip.CornerRadius = 12; $chip.Padding = '10,3'; $chip.Margin = '0,0,6,6'
        $chip.Child = New-NmGuiTextBlock -Text "$($f.Name): $($f.Value)" -Size 12 -Color '#3D4450'
        [void]$ui.FactPanel.Children.Add($chip)
    }
    $n = 0
    foreach ($t in $Model.Targets) {
        $n++
        $row = New-Object System.Windows.Controls.Border
        $row.BorderBrush = Get-NmGuiBrush '#EEF0F3'; $row.BorderThickness = '0,0,0,1'; $row.Padding = '2,7'
        $dp = New-Object System.Windows.Controls.DockPanel
        # Numbered: these are what will happen, not what has happened.
        $g = New-NmGuiTextBlock -Text "$n" -Size 12 -Weight 'SemiBold' -Color '#0E6B66'
        $g.MinWidth = 22; $g.Margin = '0,1,8,0'; $g.VerticalAlignment = 'Top'
        [System.Windows.Controls.DockPanel]::SetDock($g, 'Left'); [void]$dp.Children.Add($g)
        [void]$dp.Children.Add((New-NmGuiTextBlock -Text $t -Size 13 -Wrap))
        $row.Child = $dp
        [void]$ui.TargetPanel.Children.Add($row)
    }
    $ui.HintText.Text = $Model.Hint
    $state = @{ Ok = $false }
    $box = $ui.WordBox; $okb = $ui.OkButton; $want = "$($Model.Expected)"
    if ($Model.Typed) {
        $box.Visibility = 'Visible'; $okb.IsEnabled = $false
        $box.Add_TextChanged({ $okb.IsEnabled = ($box.Text.Trim() -eq $want) }.GetNewClosure())
        $d.Add_ContentRendered({ $box.Focus() | Out-Null }.GetNewClosure())
    } else {
        $okb.IsDefault = $true
    }
    $okb.Add_Click({ $state.Ok = $true; $d.Close() }.GetNewClosure())
    $ui.CancelButton.Add_Click({ $state.Ok = $false; $d.Close() }.GetNewClosure())
    [void]$d.ShowDialog()
    return $state.Ok
}

function Get-NmGuiProgressText {
    # A progress record as one line and a percent: its status, else its activity ("Installing" over
    # "Install-WindowsFeature"); -1 when it gives no percent.
    param($Record)
    $t = "$($Record.StatusDescription)".Trim()
    # A status that is only a number ("6%", Install-WindowsFeature's way): the activity says more,
    # and the percent is shown on its own.
    if (-not $t -or $t -match '^(?i)(processing|working)$' -or $t -match '^\d+\s*%$') { $t = "$($Record.Activity)".Trim() }
    if ("$($Record.CurrentOperation)".Trim()) { $t = "${t}: $("$($Record.CurrentOperation)".Trim())" }
    $pc = -1
    try { $pc = [int]$Record.PercentComplete } catch { $pc = -1 }
    if ($pc -gt 100) { $pc = 100 }
    [pscustomobject]@{ Text = $t; Percent = $pc }
}

function Update-NmGuiSteps {
    # Draws the step list (Get-NmStepListModel) above the results; hides it when there is none.
    $c = $script:NmGui.Controls
    if (-not $c -or -not $c.StepBorder) { return }
    $m = Get-NmStepListModel
    if (-not $m) { $c.StepBorder.Visibility = 'Collapsed'; return }
    $c.StepBorder.Visibility = 'Visible'
    $c.StepTitle.Text = $m.Title
    $c.StepSummary.Text = "$($m.Summary)  |  $($m.State)"
    $c.StepPanel.Children.Clear()
    $glyph = @{ Done = 0xE73E; Failed = 0xE711; Running = 0xE895; Waiting = 0xE91F; Skipped = 0xE738 }
    $color = @{ Done = '#1F6B35'; Failed = '#A0281C'; Running = '#0E6B66'; Waiting = '#8A919C'; Skipped = '#8A919C' }
    foreach ($r in $m.Rows) {
        if ($r.Kind -eq 'Group') {
            $h = New-NmGuiTextBlock -Text "$($r.Label)".ToUpper() -Size 11 -Weight 'SemiBold' -Color '#0E6B66'
            $h.Margin = '0,8,0,4'
            [void]$c.StepPanel.Children.Add($h)
            continue
        }
        $g = New-Object System.Windows.Controls.Grid
        $g.Margin = '0,3'
        foreach ($w in @(26, 0, 90)) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = $(if ($w -gt 0) { New-Object System.Windows.GridLength $w } else { New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star) })
            [void]$g.ColumnDefinitions.Add($cd)
        }
        $mk = New-NmGuiTextBlock -Text ([string][char]$glyph["$($r.Mark)"]) -Size 14 -Color $color["$($r.Mark)"]
        $mk.FontFamily = 'Segoe MDL2 Assets'; $mk.VerticalAlignment = 'Top'; $mk.Margin = '0,2,0,0'
        $sp = New-Object System.Windows.Controls.StackPanel
        [System.Windows.Controls.Grid]::SetColumn($sp, 1)
        $weight = if ($r.Mark -eq 'Running') { 'SemiBold' } else { 'Normal' }
        [void]$sp.Children.Add((New-NmGuiTextBlock -Text $r.Label -Size 13 -Weight $weight -Color $(if ($r.Mark -eq 'Waiting') { '#5B6370' } else { '#16191F' }) -Wrap))
        $sub = if ($r.Mark -eq 'Running' -and $r.Progress) { $r.Progress } else { $r.Detail }
        if ($sub) { $t = New-NmGuiTextBlock -Text $sub -Size 12 -Color $(if ($r.Mark -eq 'Failed') { '#A0281C' } else { '#5B6370' }) -Wrap; [void]$sp.Children.Add($t) }
        $tm = New-NmGuiTextBlock -Text $r.Time -Size 12 -Color '#5B6370'
        $tm.HorizontalAlignment = 'Right'; $tm.VerticalAlignment = 'Top'; $tm.Margin = '0,2,0,0'
        [System.Windows.Controls.Grid]::SetColumn($tm, 2)
        [void]$g.Children.Add($mk); [void]$g.Children.Add($sp); [void]$g.Children.Add($tm)
        [void]$c.StepPanel.Children.Add($g)
    }
    try { $script:NmGui.Window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { $null = $_ }
}

function Invoke-NmGuiBackground {
    <#
    .SYNOPSIS
        Runs one long call (a role install, the forest promotion) so the window stays responsive:
        in its own runspace while the window is open, with the elapsed time in the status bar.
        Outside the window it simply runs here.
    .DESCRIPTION
        The script block must stand alone (it runs without the module): pass what it needs with
        -Parameters. Its output is returned; its first error is thrown here.
    #>
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock, [hashtable]$Parameters = @{}, [string]$Status = 'Working')
    if (-not ($script:NmGui -and $script:NmGui.Active)) { return (& $ScriptBlock @Parameters) }
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript($ScriptBlock.ToString())
        foreach ($k in $Parameters.Keys) { [void]$ps.AddParameter($k, $Parameters[$k]) }
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $handle = $ps.BeginInvoke()
        $seen = 0; $tick = [System.Diagnostics.Stopwatch]::StartNew()
        $said = ''   # the last thing the call reported: stays in the status bar until it says something new
        while (-not $handle.IsCompleted) {
            # What the call reports (Install-WindowsFeature's percent, the forest's stages): under the
            # running step, in the status bar, and in the log once per change.
            $n = $ps.Streams.Progress.Count
            if ($n -gt $seen) {
                $rec = $ps.Streams.Progress[$n - 1]; $seen = $n
                $p = Get-NmGuiProgressText -Record $rec
                if ($p.Text -or $p.Percent -ge 0) {
                    Write-NmStepProgress -Text $p.Text -Percent $p.Percent
                    $said = (@($p.Text, $(if ($p.Percent -ge 0) { "$($p.Percent) %" })) | Where-Object { $_ }) -join ' '
                }
            }
            $view = Update-NmGuiProgressState -Id 7 -Activity $Status -Status ('{0}{1:m\:ss} elapsed' -f $(if ($said) { "$said  |  " } else { '' }), $clock.Elapsed)
            if ($script:NmGui.Window) { Show-NmGuiProgress -View $view -Force }
            # The running step's timer, once a second.
            if ($tick.ElapsedMilliseconds -ge 1000) { $tick.Restart(); Update-NmStepView }
            [void]$handle.AsyncWaitHandle.WaitOne(150)
        }
        $out = @($ps.EndInvoke($handle))
        $view = Update-NmGuiProgressState -Id 7 -Completed
        if ($script:NmGui.Window) { Show-NmGuiProgress -View $view -Force }
        if ($ps.Streams.Error.Count) { throw $ps.Streams.Error[0].Exception }
        return $out
    } finally { $ps.Dispose() }
}

function Read-NmGuiSecret {
    <#
    .SYNOPSIS
        Read-NmSecret while the window is open: a dialog with a password box (the characters are
        never shown), returning a SecureString. Cancel stops the action. Nothing but "(hidden)"
        reaches the window's output.
    #>
    param([Parameter(Mandatory)][string]$Prompt)
    $context = $script:NmGui.Buffer.ToString()
    $secret = if ($script:NmGui.SecretProvider) { & $script:NmGui.SecretProvider $Prompt } else { Show-NmGuiSecret -Prompt $Prompt -Context $context }
    if ($null -eq $secret) { Clear-NmGuiBuffer; throw (New-Object System.OperationCanceledException 'Cancelled in the window.') }
    foreach ($sb in @($script:NmGui.Transcript, $script:NmGui.Buffer)) {
        if ($sb.Length -and $sb[$sb.Length - 1] -ne "`n") { [void]$sb.Append("`r`n") }
    }
    [void]$script:NmGui.Transcript.Append("$Prompt`r`n> (hidden)`r`n")
    Clear-NmGuiBuffer
    return $secret
}

$script:NmGuiSecretXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Nutmeg AD Toolkit" Width="520" SizeToContent="Height" WindowStartupLocation="CenterOwner" Background="#FFFFFF" FontFamily="Segoe UI" FontSize="13"
        Foreground="#16191F" ShowInTaskbar="False" ResizeMode="NoResize">
  <Window.Resources>
    <!--NMSTYLES-->
  </Window.Resources>
  <StackPanel Margin="22,18,22,16">
    <TextBlock x:Name="HeadingText" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
    <TextBlock x:Name="ContextText" FontSize="12" Foreground="#5B6370" Margin="0,6,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
    <PasswordBox x:Name="SecretBox" Margin="0,14,0,0" MinHeight="32" Padding="6,4" VerticalContentAlignment="Center"/>
    <TextBlock Text="Not shown, saved or logged." FontSize="12" Foreground="#8A919C" Margin="0,6,0,0"/>
    <DockPanel Margin="0,16,0,0" LastChildFill="False">
      <Button x:Name="OkButton" DockPanel.Dock="Right" Content="OK" MinWidth="104" Margin="0" IsDefault="True" Style="{StaticResource PrimaryButton}"/>
      <Button x:Name="CancelButton" DockPanel.Dock="Right" Content="Cancel" MinWidth="96" IsCancel="True"/>
    </DockPanel>
  </StackPanel>
</Window>
'@
$script:NmGuiSecretControls = @('HeadingText', 'ContextText', 'SecretBox', 'OkButton', 'CancelButton')

function Get-NmGuiSecretContext {
    # The note above the password box: only the problems written just before it ("The two did not
    # match."), from lines written in Red or ERROR / WARN log lines. Never console text.
    param([string]$Text, [hashtable]$Marks = $script:NmGui.Marks)
    if ($null -eq $Marks) { $Marks = @{} }
    $out = foreach ($l in @("$Text" -split "`r?`n" | Select-Object -Last 6)) {
        $t = "$l".Trim()
        if (-not $t) { continue }
        if ($t -match '^\[\d{4}-\d{2}-\d{2} [\d:]{8}\] \[(WARN|ERROR)\] (.*)$') { $Matches[2].Trim(); continue }
        if ("$($Marks[$t])" -eq 'Red') { $t }
    }
    return (@($out) -join "`n")
}

function Show-NmGuiSecret {
    # The password dialog itself. Returns the SecureString, or $null for Cancel.
    param([Parameter(Mandatory)][string]$Prompt, [string]$Context)
    $d = New-NmGuiXaml -Xaml ($script:NmGuiSecretXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    if ($script:NmGui.Window -and $script:NmGui.Window.IsLoaded) { $d.Owner = $script:NmGui.Window } else { $d.WindowStartupLocation = 'CenterScreen' }
    Set-NmGuiDialogFit -Dialog $d -Want 560
    $ui = @{}; foreach ($n in $script:NmGuiSecretControls) { $ui[$n] = $d.FindName($n) }
    $ui.HeadingText.Text = "$Prompt".Trim()
    $note = Get-NmGuiSecretContext -Text $Context
    if ($note) { $ui.ContextText.Text = $note; $ui.ContextText.Visibility = 'Visible' }
    $state = @{ Secret = $null }
    $box = $ui.SecretBox
    $ui.OkButton.Add_Click({ $state.Secret = $box.SecurePassword.Copy(); $d.Close() }.GetNewClosure())
    $ui.CancelButton.Add_Click({ $state.Secret = $null; $d.Close() }.GetNewClosure())
    $d.Add_ContentRendered({ $box.Focus() | Out-Null }.GetNewClosure())
    [void]$d.ShowDialog()
    $box.Clear()
    return $state.Secret
}

function Get-NmGuiDialogSize {
    <#
    .SYNOPSIS
        A dialog's width and maximum height: the width asked for, but never wider than the main
        window (or the screen) less a margin, and never taller. No WPF here.
    #>
    param([double]$Want = 720, [double]$OwnerWidth = 0, [double]$OwnerHeight = 0, [double]$ScreenWidth = 1280, [double]$ScreenHeight = 800)
    $w = if ($OwnerWidth -gt 0) { $OwnerWidth } else { $ScreenWidth }
    $h = if ($OwnerHeight -gt 0) { $OwnerHeight } else { $ScreenHeight }
    [pscustomobject]@{ Width = [Math]::Max(420, [Math]::Min($Want, $w - 80)); MaxHeight = [Math]::Max(320, $h - 60) }
}

function Set-NmGuiDialogFit {
    # Sizes a dialog to fit inside the main window (or the screen), centred on it: same width for
    # every question, so they do not jump about.
    param([Parameter(Mandatory)]$Dialog, [double]$Want = 720)
    $ow = 0; $oh = 0
    try { if ($Dialog.Owner) { $ow = $Dialog.Owner.ActualWidth; $oh = $Dialog.Owner.ActualHeight } } catch { $null = $_ }
    $wa = [System.Windows.SystemParameters]::WorkArea
    $size = Get-NmGuiDialogSize -Want $Want -OwnerWidth $ow -OwnerHeight $oh -ScreenWidth $wa.Width -ScreenHeight $wa.Height
    $Dialog.Width = $size.Width
    $Dialog.MaxHeight = $size.MaxHeight
}

function New-NmGuiDialogShell {
    # The dialog window with the theme, owned by the main window when it is open.
    param([string]$Title)
    $d = New-NmGuiXaml -Xaml ($script:NmGuiDialogXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
    $d.Title = $(if ($Title) { $Title } else { 'Nutmeg AD Toolkit' })
    if ($script:NmGui.Window -and $script:NmGui.Window.IsLoaded) { $d.Owner = $script:NmGui.Window } else { $d.WindowStartupLocation = 'CenterScreen' }
    Set-NmGuiDialogFit -Dialog $d
    return $d
}

function Show-NmGuiDialog {
    <#
    .SYNOPSIS
        A text viewer (results, row details) with one button, or a typed-answer box with -Prompt.
        Returns the answer, '' for the viewer, or $null for Cancel.
    #>
    param([string]$Text, [string]$Prompt, [string]$Heading, [string]$Title = 'Nutmeg AD Toolkit', [switch]$NoInput, [string]$OkLabel = 'Close', [object[]]$Captures = @())
    if ($NoInput) { return (Show-NmGuiViewer -Text $Text -Captures $Captures -Heading $Heading -Title $Title -CloseLabel $OkLabel) }
    $d = New-NmGuiDialogShell -Title $Title
    $d.Width = 860; $d.Height = 600
    $d.FindName('HeadingText').Text = $(if ($Heading) { $Heading } else { $Title })
    $out = $d.FindName('OutputBox'); $in = $d.FindName('InputBox'); $ok = $d.FindName('OkButton'); $cancel = $d.FindName('CancelButton')
    $d.FindName('ContextRow').Height = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    if ("$Text".Trim()) { $out.Text = "$Text".TrimEnd(); $out.Visibility = 'Visible'; $out.ScrollToEnd() }
    $state = @{ Answer = $null }
    if ($NoInput) {
        $cancel.Visibility = 'Collapsed'; $ok.Content = $OkLabel
        $ok.Add_Click({ $state.Answer = ''; $d.Close() }.GetNewClosure())
    } else {
        $d.FindName('InputArea').Visibility = 'Visible'
        $d.FindName('PromptText').Text = $(if ("$Prompt".Trim()) { "$Prompt".Trim() } else { 'Answer' })
        $ok.Add_Click({ $state.Answer = $in.Text; $d.Close() }.GetNewClosure())
        $cancel.Add_Click({ $state.Answer = $null; $d.Close() }.GetNewClosure())
        $d.Add_ContentRendered({ $in.Focus() | Out-Null }.GetNewClosure())
    }
    [void]$d.ShowDialog()
    return $state.Answer
}

function Show-NmGuiCheckList {
    <#
    .SYNOPSIS
        A dialog with a tick box per item (label, grey detail line), Select all / Select none, and
        OK. Returns the zero-based indexes ticked; none for Cancel. Read-NmMultiChoice calls it.
    #>
    param([string]$Heading, [string]$Note, [object[]]$Items, [string]$OkLabel = 'OK', [switch]$AllChecked)
    $d = New-NmGuiDialogShell -Title 'Nutmeg AD Toolkit'
    $d.Width = 820; $d.Height = 640
    $d.FindName('HeadingText').Text = $Heading
    if ($Note) { $sub = $d.FindName('SubText'); $sub.Text = $Note; $sub.Visibility = 'Visible' }
    $d.FindName('ChoiceRow').Height = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $d.FindName('ChoiceScroll').Visibility = 'Visible'
    $panel = $d.FindName('ChoicePanel'); $footer = $d.FindName('FooterPanel')
    $ok = $d.FindName('OkButton'); $cancel = $d.FindName('CancelButton'); $hint = $d.FindName('HintText')
    $boxes = New-Object System.Collections.Generic.List[object]
    foreach ($it in @($Items)) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Margin = '4,6,4,6'; $cb.IsChecked = [bool]$AllChecked; $cb.VerticalContentAlignment = 'Top'
        $sp = New-Object System.Windows.Controls.StackPanel
        $t1 = New-Object System.Windows.Controls.TextBlock
        $t1.Text = "$($it.Label)"; $t1.FontWeight = 'SemiBold'; $t1.TextWrapping = 'Wrap'
        [void]$sp.Children.Add($t1)
        if ($it.Detail) {
            $t2 = New-Object System.Windows.Controls.TextBlock
            $t2.Text = "$($it.Detail)"; $t2.FontSize = 12; $t2.Foreground = '#5B6370'; $t2.TextWrapping = 'Wrap'; $t2.Margin = '0,2,0,0'
            [void]$sp.Children.Add($t2)
        }
        $cb.Content = $sp
        [void]$panel.Children.Add($cb)
        $boxes.Add($cb)
    }
    $state = @{ Answer = @() }
    $count = { $n = @($boxes | Where-Object { $_.IsChecked }).Count; $hint.Text = "$n of $($boxes.Count) ticked" }.GetNewClosure()
    foreach ($cb in $boxes) { $cb.Add_Click({ & $count }.GetNewClosure()) }
    foreach ($pair in @(@('Select all', $true), @('Select none', $false))) {
        $fb = New-Object System.Windows.Controls.Button
        $fb.Content = $pair[0]; $fb.MinWidth = 96
        $val = $pair[1]
        $fb.Add_Click({ foreach ($b in $boxes) { $b.IsChecked = $val }; & $count }.GetNewClosure())
        [void]$footer.Children.Add($fb)
    }
    $ok.Content = $OkLabel
    $ok.Add_Click({ $state.Answer = @(for ($i = 0; $i -lt $boxes.Count; $i++) { if ($boxes[$i].IsChecked) { $i } }); $d.Close() }.GetNewClosure())
    $cancel.Add_Click({ $state.Answer = @(); $d.Close() }.GetNewClosure())
    & $count
    [void]$d.ShowDialog()
    return @($state.Answer)
}

function New-NmGuiChoiceRow {
    # One clickable row: icon (or initials), name, detail, "Can change" tag, and the key on the right.
    param([Parameter(Mandatory)]$Choice)
    $conv = New-Object System.Windows.Media.BrushConverter
    $b = New-Object System.Windows.Controls.Button
    $b.Style = $script:NmGuiDialogStyleRow
    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in 'Auto', '*', 'Auto') {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = $(if ($w -eq '*') { New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star) } else { [System.Windows.GridLength]::Auto })
        [void]$g.ColumnDefinitions.Add($cd)
    }
    $box = New-Object System.Windows.Controls.Border
    $box.Width = 34; $box.Height = 34; $box.CornerRadius = 8; $box.Background = $conv.ConvertFromString('#F1F3F6'); $box.Margin = '0,0,12,0'
    $glyph = New-Object System.Windows.Controls.TextBlock
    $glyph.HorizontalAlignment = 'Center'; $glyph.VerticalAlignment = 'Center'; $glyph.Foreground = $conv.ConvertFromString('#5B6370')
    if ($Choice.Initials) { $glyph.Text = $Choice.Initials; $glyph.FontSize = 12; $glyph.FontWeight = 'SemiBold' }
    else { $glyph.Text = $Choice.Icon; $glyph.FontSize = 16; $glyph.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe Fluent Icons, Segoe MDL2 Assets' }
    $box.Child = $glyph
    [void]$g.Children.Add($box)

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    $head = New-Object System.Windows.Controls.StackPanel
    $head.Orientation = 'Horizontal'
    $name = New-NmGuiTextBlock -Text $Choice.Name -Size 14 -Weight 'SemiBold' -Wrap
    [void]$head.Children.Add($name)
    if ($Choice.Tag) {
        $pill = New-Object System.Windows.Controls.Border
        $pill.Background = $conv.ConvertFromString('#FFF1DC'); $pill.CornerRadius = 6; $pill.Padding = '6,1'; $pill.Margin = '8,0,0,0'; $pill.VerticalAlignment = 'Center'
        $pill.Child = (New-NmGuiTextBlock -Text $Choice.Tag -Size 11 -Weight 'SemiBold' -Color '#8A4B00')
        [void]$head.Children.Add($pill)
    }
    [void]$sp.Children.Add($head)
    if ($Choice.Detail) { [void]$sp.Children.Add((New-NmGuiTextBlock -Text $Choice.Detail -Size 12 -Color '#5B6370' -Wrap)) }
    [void]$g.Children.Add($sp)

    $key = New-NmGuiTextBlock -Text $Choice.Key -Size 12 -Color '#8A919C'
    $key.VerticalAlignment = 'Center'; $key.Margin = '12,0,4,0'
    [System.Windows.Controls.Grid]::SetColumn($key, 2)
    [void]$g.Children.Add($key)
    $b.Content = $g
    $b.Uid = $Choice.Key
    [System.Windows.Automation.AutomationProperties]::SetName($b, "$($Choice.Name) $($Choice.Detail)".Trim())
    return [pscustomobject]@{ Button = $b; Box = $box; Glyph = $glyph; Key = $Choice.Key }
}

function Get-NmGuiNoteStyle {
    # Colours and glyph for a note line in a dialog: Error red, Warning amber, Success green.
    param([string]$Level)
    switch ($Level) {
        'Error'   { [pscustomobject]@{ Fore = '#A0281C'; Back = '#FDECEA'; Glyph = [string][char]0xE783 } }
        'Warning' { [pscustomobject]@{ Fore = '#8A4B00'; Back = '#FFF4E0'; Glyph = [string][char]0xE7BA } }
        'Success' { [pscustomobject]@{ Fore = '#1F6B35'; Back = '#E6F4EA'; Glyph = [string][char]0xE73E } }
        default   { [pscustomobject]@{ Fore = '#3D4450'; Back = '#F1F3F6'; Glyph = [string][char]0xE946 } }
    }
}

function Get-NmGuiShortTitle {
    # A table's title in a dialog: the part after the last ' > ' ("New Forest Build (first DC) > Server check" -> "Server check").
    param([string]$Title)
    $parts = @("$Title" -split ' > ')
    return "$($parts[-1])".Trim()
}

function Get-NmGuiCheckRowModel {
    <#
    .SYNOPSIS
        A table with a Result or Status column as check rows (no WPF): Name (the first other column),
        Status, Level (for the badge colour) and Detail (the rest, joined). Nothing for other tables.
    #>
    param([Parameter(Mandatory)]$Capture)
    $cols = @($Capture.Columns)
    $statusCol = @($cols | Where-Object { $_ -in 'Result', 'Status' })[0]
    if (-not $statusCol) { return }
    $nameCol = @($cols | Where-Object { $_ -ne $statusCol -and $_ -ne '#' })[0]
    $rest = @($cols | Where-Object { $_ -ne $statusCol -and $_ -ne $nameCol -and $_ -ne '#' })
    foreach ($r in @($Capture.Rows)) {
        $st = "$($r.$statusCol)"
        [pscustomobject]@{
            Name   = "$($r.$nameCol)"
            Status = $st
            Level  = (Get-NmGuiStatusLevel -Column $statusCol -Value $st)
            Detail = (@($rest | ForEach-Object { ConvertTo-NmGuiFieldText $r.$_ } | Where-Object { "$_".Trim() }) -join '  |  ')
        }
    }
}

function Set-NmGuiDialogBody {
    # Fills a question dialog's body from its model: section label, notes, plain text, tables.
    param([Parameter(Mandatory)]$Dialog, [Parameter(Mandatory)]$Model, [object[]]$Captures = @())
    if ($Model.Section) { $st = $Dialog.FindName('SectionText'); $st.Text = "$($Model.Section)".ToUpper(); $st.Visibility = 'Visible' }
    $np = $Dialog.FindName('NotePanel')
    foreach ($n in @($Model.Notes)) {
        $style = Get-NmGuiNoteStyle -Level $n.Level
        $b = New-Object System.Windows.Controls.Border
        $b.Background = Get-NmGuiBrush $style.Back; $b.CornerRadius = 8; $b.Padding = '10,7'; $b.Margin = '0,0,0,6'
        $dp = New-Object System.Windows.Controls.DockPanel
        $g = New-NmGuiTextBlock -Text $style.Glyph -Size 14 -Color $style.Fore
        $g.FontFamily = 'Segoe MDL2 Assets'; $g.Margin = '0,1,10,0'; $g.VerticalAlignment = 'Top'
        [System.Windows.Controls.DockPanel]::SetDock($g, 'Left'); [void]$dp.Children.Add($g)
        [void]$dp.Children.Add((New-NmGuiTextBlock -Text $n.Text -Size 13 -Color $style.Fore -Wrap))
        $b.Child = $dp
        [void]$np.Children.Add($b)
    }
    if (@($Model.Notes).Count) { $np.Visibility = 'Visible' }
    if ("$($Model.Context)".Trim()) { $ct = $Dialog.FindName('ContextText'); $ct.Text = "$($Model.Context)".Trim(); $ct.Visibility = 'Visible' }
    $tp = $Dialog.FindName('TablePanel')
    foreach ($cap in @($Captures | Where-Object { $_ })) {
        $short = Get-NmGuiShortTitle -Title "$($cap.Title)"
        if ($short) {
            $h = New-NmGuiTextBlock -Text $short -Size 12 -Weight 'SemiBold' -Color '#5B6370'
            $h.Margin = '0,0,0,4'; [void]$tp.Children.Add($h)
        }
        $checks = @(Get-NmGuiCheckRowModel -Capture $cap)
        if ($checks.Count) {
            # A check list (a Result or Status column): a coloured badge per row, the detail in full.
            $sv = New-Object System.Windows.Controls.ScrollViewer
            $sv.MaxHeight = 320; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.HorizontalScrollBarVisibility = 'Disabled'; $sv.Margin = '0,0,0,10'
            $sp = New-Object System.Windows.Controls.StackPanel
            foreach ($r in $checks) {
                $row = New-Object System.Windows.Controls.Border
                $row.BorderBrush = Get-NmGuiBrush '#EEF0F3'; $row.BorderThickness = '0,0,0,1'; $row.Padding = '2,6'
                $g = New-Object System.Windows.Controls.Grid
                foreach ($wd in @(110, 230)) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = New-Object System.Windows.GridLength $wd; [void]$g.ColumnDefinitions.Add($cd) }
                $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star); [void]$g.ColumnDefinitions.Add($cd)
                $pill = New-NmGuiPill -Text $r.Status -Severity $r.Level
                $pill.HorizontalAlignment = 'Left'; $pill.VerticalAlignment = 'Top'
                $name = New-NmGuiTextBlock -Text $r.Name -Size 13 -Weight 'SemiBold' -Wrap; $name.Margin = '0,1,10,0'
                $det = New-NmGuiTextBlock -Text $r.Detail -Size 13 -Color '#3D4450' -Wrap; $det.Margin = '0,1,0,0'
                [System.Windows.Controls.Grid]::SetColumn($name, 1); [System.Windows.Controls.Grid]::SetColumn($det, 2)
                [void]$g.Children.Add($pill); [void]$g.Children.Add($name); [void]$g.Children.Add($det)
                $row.Child = $g
                [void]$sp.Children.Add($row)
            }
            $sv.Content = $sp
            [void]$tp.Children.Add($sv)
            continue
        }
        $v = New-NmGuiViewGrid -Capture $cap
        $v.Grid.MaxHeight = 300; $v.Grid.Margin = '0,0,0,10'
        [void]$tp.Children.Add($v.Grid)
    }
    if ($tp.Children.Count) { $tp.Visibility = 'Visible'; Set-NmGuiDialogFit -Dialog $Dialog -Want 880 }
}

function Show-NmGuiQuestion {
    <#
    .SYNOPSIS
        A question in the window: rows to click for menus, yes/no and pick lists (no answer box), or
        a box to type in when the question needs typing. Returns the key or text, or $null for Cancel.
    .DESCRIPTION
        Rows: click to pick; arrow keys and Enter; or press the option's key (1-9, letters; two-digit
        keys are typed in full). Back / Main menu / Quit are buttons at the bottom.
    #>
    param([Parameter(Mandatory)]$Model, [object[]]$Captures = @())
    $d = New-NmGuiDialogShell
    $script:NmGuiDialogStyleRow = $d.FindResource('ChoiceRow')
    $d.FindName('HeadingText').Text = $Model.Title
    $panel = $d.FindName('ChoicePanel'); $ok = $d.FindName('OkButton'); $cancel = $d.FindName('CancelButton')
    $hint = $d.FindName('HintText'); $footer = $d.FindName('FooterPanel'); $in = $d.FindName('InputBox')
    $state = @{ Answer = $null; Rows = @(); Index = -1; Typed = '' }
    $conv = New-Object System.Windows.Media.BrushConverter

    # No console text: a section label, notes as coloured lines, plain text wrapped, tables as tables.
    Set-NmGuiDialogBody -Dialog $d -Model $Model -Captures $Captures
    $d.SizeToContent = 'Height'
    $cancel.Add_Click({ $state.Answer = $null; $d.Close() }.GetNewClosure())

    if ($Model.Kind -eq 'Continue') {
        # Something to read before going on (a check list): Continue, or Cancel to stop.
        $ok.Content = 'Continue'; $ok.IsDefault = $true
        $hint.Text = 'Read it, then Continue'
        $ok.Add_Click({ $state.Answer = ''; $d.Close() }.GetNewClosure())
        $d.Add_ContentRendered({ $ok.Focus() | Out-Null }.GetNewClosure())
        [void]$d.ShowDialog()
        return $state.Answer
    }

    if ($Model.Kind -eq 'Text') {
        $d.FindName('InputArea').Visibility = 'Visible'
        $d.FindName('PromptText').Text = $(if ($Model.DefaultValue) { 'Your answer (the suggested value is filled in)' } else { 'Your answer' })
        if ($Model.DefaultValue) { $in.Text = $Model.DefaultValue }
        $ok.Add_Click({ $state.Answer = $in.Text; $d.Close() }.GetNewClosure())
        $d.Add_ContentRendered({ $in.Focus() | Out-Null; $in.SelectAll() }.GetNewClosure())
        [void]$d.ShowDialog()
        return $state.Answer
    }

    # Rows: no answer box and no OK; a click picks.
    $ok.Visibility = 'Collapsed'
    $d.FindName('ChoiceScroll').Visibility = 'Visible'
    # A star row sizes to its rows until the window reaches its maximum height, then scrolls.
    $d.FindName('ChoiceRow').Height = New-Object System.Windows.GridLength 1, ([System.Windows.GridUnitType]::Star)
    $hint.Text = 'Click an option, or press its key'
    $highlight = {
        param($i)
        for ($n = 0; $n -lt $state.Rows.Count; $n++) {
            $r = $state.Rows[$n]
            $on = $n -eq $i
            $r.Button.Tag = $(if ($on) { 'on' } else { $null })
            $r.Box.Background = $conv.ConvertFromString($(if ($on) { '#CDE9E5' } else { '#F1F3F6' }))
            $r.Glyph.Foreground = $conv.ConvertFromString($(if ($on) { '#0A4F4B' } else { '#5B6370' }))
        }
        $state.Index = $i
        if ($i -ge 0) { $state.Rows[$i].Button.BringIntoView() }
    }.GetNewClosure()
    foreach ($c in $Model.Rows) {
        $row = New-NmGuiChoiceRow -Choice $c
        $row.Button.Add_Click({ param($btn) $state.Answer = "$($btn.Uid)"; $d.Close() }.GetNewClosure())
        [void]$panel.Children.Add($row.Button)
        $state.Rows += $row
    }
    foreach ($f in $Model.Footer) {
        $fb = New-Object System.Windows.Controls.Button
        $fb.Content = $f.Name; $fb.Uid = $f.Key; $fb.MinWidth = 96
        $fb.Add_Click({ param($btn) $state.Answer = "$($btn.Uid)"; $d.Close() }.GetNewClosure())
        [void]$footer.Children.Add($fb)
    }
    $first = 0
    for ($n = 0; $n -lt $state.Rows.Count; $n++) { if ($state.Rows[$n].Key -eq $Model.Default) { $first = $n } }
    & $highlight $first

    $keys = @(@($Model.Rows) + @($Model.Footer) | ForEach-Object { "$($_.Key)".ToUpper() })
    $d.Add_PreviewKeyDown({
        param($w, $e)
        switch ("$($e.Key)") {
            'Down'   { if ($state.Rows.Count) { & $highlight ([Math]::Min($state.Index + 1, $state.Rows.Count - 1)) }; $e.Handled = $true; return }
            'Up'     { if ($state.Rows.Count) { & $highlight ([Math]::Max($state.Index - 1, 0)) }; $e.Handled = $true; return }
            'Return' { if ($state.Index -ge 0) { $state.Answer = $state.Rows[$state.Index].Key; $d.Close() }; $e.Handled = $true; return }
            'Escape' { $state.Answer = $null; $d.Close(); $e.Handled = $true; return }
            'Back'   { $state.Typed = ''; $e.Handled = $true; return }
        }
        $k = "$($e.Key)"
        $ch = if ($k -match '^D(\d)$' -or $k -match '^NumPad(\d)$') { $Matches[1] } elseif ($k -match '^[A-Z]$') { $k } else { '' }
        if (-not $ch) { return }
        $e.Handled = $true
        $typed = "$($state.Typed)$ch"
        if (-not @($keys | Where-Object { $_.StartsWith($typed) }).Count) { $typed = $ch }
        $longer = @($keys | Where-Object { $_.Length -gt $typed.Length -and $_.StartsWith($typed) })
        if ($keys -contains $typed -and -not $longer.Count) { $state.Answer = $typed; $d.Close(); return }
        $state.Typed = $typed
        for ($n = 0; $n -lt $state.Rows.Count; $n++) { if ("$($state.Rows[$n].Key)".ToUpper().StartsWith($typed)) { & $highlight $n; break } }
        $hint.Text = "Typed $typed - press Enter, or keep typing"
    }.GetNewClosure())
    $d.Add_ContentRendered({ $d.Focus() | Out-Null }.GetNewClosure())
    [void]$d.ShowDialog()
    return $state.Answer
}

$script:NmGuiMainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Nutmeg AD Toolkit" Width="1440" Height="900" MinWidth="1000" MinHeight="640" WindowStartupLocation="CenterScreen"
        Background="#F6F7F9" FontFamily="Segoe UI" FontSize="13" Foreground="#16191F">
  <Window.Resources>
    <!--NMSTYLES-->
    <Style x:Key="SideButton" TargetType="Button">
      <Setter Property="Foreground" Value="#E6E8EB"/><Setter Property="Background" Value="Transparent"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Margin" Value="0,1"/><Setter Property="Focusable" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#1F252E"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="Background" Value="#262C36"/></Trigger>
              <Trigger Property="Tag" Value="on"><Setter TargetName="Bd" Property="Background" Value="#0E6B66"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ToolItem" TargetType="ListBoxItem">
      <Setter Property="Margin" Value="0,1"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="1" CornerRadius="8" Padding="8,6">
              <ContentPresenter HorizontalAlignment="Stretch"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#F6F7F9"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#E3F1EF"/><Setter TargetName="Bd" Property="BorderBrush" Value="#B9DCD8"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#FFFFFF" BorderBrush="#E2E5EA" BorderThickness="0,0,0,1" Padding="16,10">
      <DockPanel LastChildFill="False">
        <StackPanel Orientation="Horizontal" DockPanel.Dock="Left" VerticalAlignment="Center" Margin="0,0,16,0">
          <Border Width="32" Height="32" CornerRadius="8" Background="#0E6B66" Margin="0,0,10,0">
            <TextBlock Text="N" Foreground="#FFFFFF" FontWeight="Bold" FontSize="15" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="Nutmeg AD Toolkit" FontWeight="Bold" FontSize="15"/>
            <TextBlock x:Name="VersionText" FontFamily="Consolas" FontSize="11" Foreground="#5B6370"/>
          </StackPanel>
        </StackPanel>
        <Button x:Name="DomainButton" DockPanel.Dock="Left" ToolTip="Domain and DC: status, work against another DC, read the domain again">
          <StackPanel>
            <TextBlock x:Name="DomainLabel" Text="Domain and DC" FontSize="11" Foreground="#5B6370"/>
            <TextBlock x:Name="DomainText" FontWeight="SemiBold" Foreground="#16191F"/>
          </StackPanel>
        </Button>
        <WrapPanel x:Name="ServicePanel" DockPanel.Dock="Left" VerticalAlignment="Center" Margin="4,0,0,0"/>
        <Button x:Name="SettingsButton" DockPanel.Dock="Right" Margin="0" ToolTip="Settings" Padding="10,6">
          <TextBlock x:Name="SettingsGlyph" FontFamily="Segoe MDL2 Assets" FontSize="16" VerticalAlignment="Center"/>
        </Button>
        <Grid DockPanel.Dock="Right" Width="300" Margin="0,0,8,0">
          <TextBox x:Name="SearchBox" MinHeight="34" Padding="8,4" VerticalContentAlignment="Center" BorderBrush="#E2E5EA" ToolTip="Search tools"/>
          <TextBlock x:Name="SearchHint" Text="Search tools: OU, GPO, health..." Foreground="#8A919C" Margin="11,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        </Grid>
      </DockPanel>
    </Border>

    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="340"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>

      <DockPanel Grid.Column="0" Background="#14181F">
        <StackPanel DockPanel.Dock="Bottom" Margin="10">
          <Button x:Name="HistoryButton" Content="Run history" Background="#1F252E" Foreground="#C9CED6" BorderBrush="#262C36" Margin="0,0,0,8" HorizontalContentAlignment="Left"/>
        </StackPanel>
        <TextBlock DockPanel.Dock="Top" Text="AREAS" Foreground="#8A919C" FontSize="11" FontWeight="SemiBold" Margin="18,16,0,8"/>
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
          <StackPanel x:Name="CenterPanel" Margin="8,0"/>
        </ScrollViewer>
      </DockPanel>

      <DockPanel Grid.Column="1" Background="#FFFFFF">
        <TextBlock x:Name="ToolListCenter" DockPanel.Dock="Top" FontSize="12" Foreground="#5B6370" Margin="16,16,16,0"/>
        <TextBlock x:Name="ToolListTitle" DockPanel.Dock="Top" FontSize="16" FontWeight="Bold" Margin="16,2,16,8"/>
        <ListBox x:Name="ToolList" BorderThickness="0" Margin="8,0" ScrollViewer.HorizontalScrollBarVisibility="Disabled" HorizontalContentAlignment="Stretch"
                 ItemContainerStyle="{StaticResource ToolItem}"/>
      </DockPanel>

      <Grid Grid.Column="2" Margin="20,16,20,12">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel Grid.Row="0">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="ToolTitle" FontSize="22" FontWeight="Bold" Text="Pick a tool"/>
            <Border x:Name="ChangeTag" Background="#FFF1DC" CornerRadius="6" Padding="8,2" Margin="10,4,0,0" VerticalAlignment="Center" Visibility="Collapsed">
              <TextBlock Text="Can change" Foreground="#8A4B00" FontSize="11" FontWeight="SemiBold"/>
            </Border>
          </StackPanel>
          <TextBlock x:Name="ToolMeta" Foreground="#5B6370" TextWrapping="Wrap" Margin="0,4,0,0" Text="Choose an area on the left, then a tool."/>
        </StackPanel>
        <Border Grid.Row="1" x:Name="OptionsBorder" Background="#FFFFFF" BorderBrush="#E2E5EA" BorderThickness="1" CornerRadius="10" Padding="14" Margin="0,12,0,0" Visibility="Collapsed">
          <ScrollViewer MaxHeight="230" VerticalScrollBarVisibility="Auto">
            <WrapPanel x:Name="OptionsPanel"/>
          </ScrollViewer>
        </Border>
        <StackPanel Grid.Row="2" x:Name="ActionRow" Orientation="Horizontal" Margin="0,12,0,0" Visibility="Collapsed">
          <Button x:Name="RunButton" Content="Run" MinWidth="110" Style="{StaticResource PrimaryButton}"/>
          <Button x:Name="GuidedButton" Content="Guided..." ToolTip="Answer the tool's own questions, then run"/>
          <CheckBox x:Name="PreviewBox" Content="Preview changes only (WhatIf)" VerticalAlignment="Center" Margin="8,0,0,0"/>
        </StackPanel>
        <StackPanel Grid.Row="3">
        <Border x:Name="StepBorder" Visibility="Collapsed" Background="#FFFFFF" BorderBrush="#E2E5EA" BorderThickness="1" CornerRadius="10" Padding="16,12" Margin="0,16,0,0">
          <StackPanel>
            <DockPanel LastChildFill="True" Margin="0,0,0,8">
              <TextBlock x:Name="StepSummary" DockPanel.Dock="Right" Foreground="#5B6370" VerticalAlignment="Center"/>
              <TextBlock x:Name="StepTitle" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center" TextWrapping="Wrap"/>
            </DockPanel>
            <ScrollViewer MaxHeight="300" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
              <StackPanel x:Name="StepPanel"/>
            </ScrollViewer>
          </StackPanel>
        </Border>
        <DockPanel x:Name="ResultBar" Margin="0,16,0,8" LastChildFill="False" Visibility="Collapsed">
          <TextBlock x:Name="ResultTitle" DockPanel.Dock="Left" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <Button x:Name="DetailsButton" DockPanel.Dock="Right" Content="Row details" Margin="0" IsEnabled="False"/>
          <Button x:Name="ViewToggle" DockPanel.Dock="Right" Content="Table view" Visibility="Collapsed" ToolTip="Switch between cards and the table"/>
          <Button x:Name="ClearButton" DockPanel.Dock="Right" Content="Clear" Visibility="Collapsed" ToolTip="Clear these results (they are kept while you look at other tools)"/>
          <Button x:Name="SummaryButton" DockPanel.Dock="Right" Content="Summary" IsEnabled="False"/>
          <Button x:Name="ExportTxtButton" DockPanel.Dock="Right" Content="Export TXT" IsEnabled="False"/>
          <Button x:Name="ExportCsvButton" DockPanel.Dock="Right" Content="Export CSV" IsEnabled="False"/>
          <CheckBox x:Name="AllColumnsBox" DockPanel.Dock="Right" Content="All columns" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <Grid DockPanel.Dock="Right" Width="220" Margin="0,0,12,0">
            <TextBox x:Name="FilterBox" MinHeight="34" Padding="8,4" VerticalContentAlignment="Center" BorderBrush="#E2E5EA" ToolTip="Filter rows"/>
            <TextBlock x:Name="FilterHint" Text="Filter rows" Foreground="#8A919C" Margin="11,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          </Grid>
        </DockPanel>
        <Border x:Name="SelectionBar" Visibility="Collapsed" Background="#EEF6F4" BorderBrush="#CFE6E0" BorderThickness="1" CornerRadius="8" Padding="12,6" Margin="0,0,0,8">
          <DockPanel LastChildFill="False">
            <TextBlock x:Name="SelectionText" DockPanel.Dock="Left" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="#1F5F55" MinWidth="90"/>
            <Button x:Name="SelectAllButton" DockPanel.Dock="Left" Content="Select all shown" Margin="12,0,0,0" ToolTip="Tick every row the filter and tag show"/>
            <Button x:Name="SelectNoneButton" DockPanel.Dock="Left" Content="Clear selection" Margin="8,0,0,0"/>
            <StackPanel x:Name="SelectionActions" DockPanel.Dock="Right" Orientation="Horizontal"/>
          </DockPanel>
        </Border>
        </StackPanel>
        <TextBlock Grid.Row="4" x:Name="EmptyText" Foreground="#5B6370" FontSize="14" Margin="0,24,0,0" TextWrapping="Wrap" VerticalAlignment="Top"/>
        <DataGrid Grid.Row="4" x:Name="ResultsGrid" Visibility="Collapsed" IsReadOnly="True" AutoGenerateColumns="True" CanUserAddRows="False" SelectionMode="Extended" SelectionUnit="FullRow" ClipboardCopyMode="IncludeHeader"
                  Background="#FFFFFF" BorderBrush="#E2E5EA" RowBackground="#FFFFFF" AlternatingRowBackground="#FAFBFC" GridLinesVisibility="Horizontal"
                  HorizontalGridLinesBrush="#EEF0F3" HeadersVisibility="Column" ColumnHeaderHeight="32" MinRowHeight="28"/>
        <ScrollViewer Grid.Row="4" x:Name="CardScroll" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
          <ContentControl x:Name="CardHost" Focusable="False"/>
        </ScrollViewer>
        <Expander Grid.Row="5" x:Name="OutputExpander" Header="Output" Margin="0,8,0,0">
          <TextBox x:Name="LogBox" Height="160" VerticalContentAlignment="Stretch" IsReadOnly="True" FontFamily="Consolas" FontSize="11" Background="#F6F7F9" BorderBrush="#E2E5EA"
                   VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextWrapping="Wrap"/>
        </Expander>
      </Grid>
    </Grid>

    <Border Grid.Row="2" Background="#FFFFFF" BorderBrush="#E2E5EA" BorderThickness="0,1,0,0" Padding="16,6">
      <DockPanel LastChildFill="True">
        <StackPanel x:Name="ProgressPanel" DockPanel.Dock="Right" Orientation="Horizontal" Visibility="Collapsed" Margin="16,0,0,0">
          <TextBlock x:Name="ProgressText" Foreground="#0A4F4B" FontWeight="SemiBold" MaxWidth="560" TextTrimming="CharacterEllipsis" VerticalAlignment="Center" Margin="0,0,10,0"/>
          <ProgressBar x:Name="ProgressBar" Width="220" Height="8" Minimum="0" Maximum="100" Foreground="#0E6B66" Background="#E3F1EF" BorderThickness="0" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="StatusText" Foreground="#5B6370" Text="Ready." TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>

  </Grid>
</Window>
'@

function New-NmGuiTextBlock {
    param([string]$Text, [double]$Size = 13, [string]$Weight = 'Normal', [string]$Color = '#16191F', [switch]$Wrap)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text; $t.FontSize = $Size; $t.FontWeight = $Weight
    $t.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Color)
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    return $t
}

function Update-NmGuiBanner {
    $c = $script:NmGui.Controls
    $s = Get-NmSession
    # Another domain or DC: nothing read from the previous one stays on screen.
    $target = Get-NmGuiTarget
    if (Test-NmGuiTargetChanged -Target $target) { Reset-NmGuiTargetView -Target $target }
    $c.DomainText.Text = Get-NmGuiDomainText
    $c.ServicePanel.Children.Clear()
    # Building a forest: the server itself, not a domain; no module chips (nothing to load yet).
    if ($script:NmGui.BuildMode) {
        if ($c.DomainLabel) { $c.DomainLabel.Text = 'This server' }
        $c.DomainText.Text = Get-NmGuiServerText
        $c.ServicePanel.Visibility = 'Collapsed'
        return
    }
    foreach ($svc in $script:NmKnownServices) {
        $up = [bool]$s.Services[$svc]
        $b = New-Object System.Windows.Controls.Border
        $b.CornerRadius = 12; $b.Padding = '10,3'; $b.Margin = '0,0,6,0'; $b.BorderThickness = 1
        $conv = New-Object System.Windows.Media.BrushConverter
        $b.Background = $conv.ConvertFromString($(if ($up) { '#E3F1EF' } else { '#FFFFFF' }))
        $b.BorderBrush = $conv.ConvertFromString($(if ($up) { '#B9DCD8' } else { '#E2E5EA' }))
        $b.Child = New-NmGuiTextBlock -Text "$(if ($up) { [char]0x25CF } else { [char]0x25CB }) $(Get-NmGuiServiceLabel $svc)" -Size 12 -Weight $(if ($up) { 'SemiBold' } else { 'Normal' }) -Color $(if ($up) { '#0A4F4B' } else { '#5B6370' })
        $b.ToolTip = "$(Get-NmGuiServiceLabel $svc) module $(if ($up) { 'loaded' } else { 'not loaded yet (loads when a tool needs it)' })"
        [void]$c.ServicePanel.Children.Add($b)
    }
    # The sidebar's dots follow the same state.
    if ($c.CenterPanel) { Update-NmGuiCenters }
}

function Get-NmGuiServiceLabel {
    # The header chip's name for a service: the module it loads.
    param([string]$Service)
    switch ($Service) { 'AD' { 'ActiveDirectory' } 'GPO' { 'GroupPolicy' } default { $Service } }
}

function Get-NmGuiServerText {
    # The header in build mode: "WIN-1 (workgroup)  |  192.0.2.10 (DHCP)", or its domain once joined.
    param($Computer, [object[]]$Adapters)
    try {
        if (-not $Computer) { $Computer = Get-NmLocalComputer }
        if ($null -eq $Adapters) { $Adapters = @(Get-NmNetAdapterInfo) }
    } catch { $null = $_ }
    $who = if ($Computer) { "$($Computer.Name) ($(if ($Computer.PartOfDomain) { $Computer.Domain } else { 'workgroup' }))" } else { 'This server' }
    $nic = @($Adapters | Where-Object { $_ -and $_.IPv4 })[0]
    if ($nic) { return "$who  |  $($nic.IPv4) ($(if ($nic.Dhcp) { 'DHCP' } else { 'static' }))" }
    return $who
}

function Get-NmGuiDomainText {
    # The header's domain line: domain (NETBIOS) | DC, or a note that tools read it when they need it.
    $s = $script:NmSession
    if ($s -and $s.Domain) { return "$($s.Domain) ($($s.NetBIOS))  |  DC: $($s.Server)" }
    return 'Not read yet: tools read it from this DC when they need it'
}

function Get-NmGuiCenterState {
    # Load state of an area from the services its tools use: All, Some, None or NotNeeded.
    param([Parameter(Mandatory)][object]$Center)
    $svc = @($Center.Services)
    if ($svc.Count -eq 0) { return 'NotNeeded' }
    $up = @($svc | Where-Object { $script:NmSession.Services[$_] }).Count
    if ($up -eq $svc.Count) { 'All' } elseif ($up -gt 0) { 'Some' } else { 'None' }
}

function Get-NmGuiSidebarModel {
    <#
    .SYNOPSIS
        The rows the window sidebar draws, in order: one Center row per area and, under an
        open area, one Section row per section. No WPF here, so it can be tested anywhere.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:NmGui.Open) { $script:NmGui.Open = @{} }
    $sel = "$($script:NmGui.Selection)"
    foreach ($c in @(Get-NmGuiArea)) {
        $open = [bool]$script:NmGui.Open[$c.Id]
        $svcState = @($c.Services | ForEach-Object { "$(Get-NmGuiServiceLabel $_) $(if ($script:NmSession.Services[$_]) { 'loaded' } else { 'not loaded yet' })" })
        [pscustomobject]@{
            Kind = 'Center'; Center = $c.Id; Section = $null; Name = $c.Name; Count = $c.Count; Open = $open; Selected = $false
            State = (Get-NmGuiCenterState -Center $c)
            Tip   = $(if ($svcState.Count) { $svcState -join ', ' } else { 'No module needed' })
        }
        if (-not $open) { continue }
        foreach ($sec in $c.Sections) {
            [pscustomobject]@{
                Kind = 'Section'; Center = $c.Id; Section = $sec.Name; Name = $sec.Name; Count = @($sec.Items).Count; Open = $true
                Selected = ($sel -eq "$($c.Id)|$($sec.Name)"); State = $null; Tip = $null
            }
        }
    }
}

function Reset-NmGuiTargetView {
    # Clears results, filter, output and the option form after a move to another domain or DC.
    param([string]$Target)
    $c = $script:NmGui.Controls
    [void]$script:NmGui.Transcript.Clear()
    Clear-NmGuiBuffer
    $script:NmGui.Kept = @{}
    $script:NmGui.LastLeftover = $null
    if ($c.LogBox) { $c.LogBox.Text = '' }
    if ($script:NmGui.Tool) { Build-NmGuiOptionForm }
    if ($c.ResultsGrid) { Set-NmGuiResult -Rows @() -Title '' }
    if ($c.StatusText) { $c.StatusText.Text = "Working against $(($Target -split '\|')[-1]) now. Results from before were cleared." }
}

function Update-NmGuiCenters {
    # Redraws the sidebar from Get-NmGuiSidebarModel (open/closed areas, the selected section, module dots).
    $c = $script:NmGui.Controls
    if (-not $c.CenterPanel) { return }
    $c.CenterPanel.Children.Clear()
    $conv = New-Object System.Windows.Media.BrushConverter
    $style = $script:NmGui.Window.FindResource('SideButton')
    foreach ($row in @(Get-NmGuiSidebarModel)) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $style
        $dp = New-Object System.Windows.Controls.DockPanel
        $dp.LastChildFill = $true
        $n = New-NmGuiTextBlock -Text "$($row.Count)" -Size 12 -Color $(if ($row.Selected) { '#CDE7E4' } else { '#8A919C' })
        $n.Margin = '8,0,0,0'
        [System.Windows.Controls.DockPanel]::SetDock($n, 'Right')
        [void]$dp.Children.Add($n)
        if ($row.Kind -eq 'Center') {
            $b.Padding = '10,9'
            # Module dot: filled when every module the area's tools use is loaded, ringed when some are, hollow when none.
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 8; $dot.Height = 8; $dot.Margin = '8,0,0,0'; $dot.StrokeThickness = 1.5; $dot.VerticalAlignment = 'Center'
            switch ($row.State) {
                'All'       { $dot.Fill = $conv.ConvertFromString('#3FB8AF'); $dot.Stroke = $conv.ConvertFromString('#3FB8AF') }
                'Some'      { $dot.Fill = $conv.ConvertFromString('#1F5F5B'); $dot.Stroke = $conv.ConvertFromString('#3FB8AF') }
                'NotNeeded' { $dot.Fill = $conv.ConvertFromString('#3FB8AF'); $dot.Stroke = $conv.ConvertFromString('#3FB8AF') }
                default     { $dot.Fill = [System.Windows.Media.Brushes]::Transparent; $dot.Stroke = $conv.ConvertFromString('#8A919C') }
            }
            [System.Windows.Controls.DockPanel]::SetDock($dot, 'Right')
            [void]$dp.Children.Add($dot)
            $chev = New-NmGuiTextBlock -Text $(if ($row.Open) { [string][char]0x25BE } else { [string][char]0x25B8 }) -Size 12 -Color '#8A919C'
            $chev.Width = 16
            [System.Windows.Controls.DockPanel]::SetDock($chev, 'Left')
            [void]$dp.Children.Add($chev)
            [void]$dp.Children.Add((New-NmGuiTextBlock -Text $row.Name -Size 14 -Weight 'SemiBold' -Color '#E6E8EB'))
            $b.ToolTip = $row.Tip
            [System.Windows.Automation.AutomationProperties]::SetName($b, "$($row.Name), $($row.Count) tools, $($row.Tip)")
            $b.Uid = "C|$($row.Center)"
        } else {
            $b.Padding = '34,7,10,7'
            if ($row.Selected) { $b.Tag = 'on' }
            [void]$dp.Children.Add((New-NmGuiTextBlock -Text $row.Name -Size 13 -Color $(if ($row.Selected) { '#FFFFFF' } else { '#C9CED6' })))
            $b.Uid = "S|$($row.Center)|$($row.Section)"
        }
        $b.Content = $dp
        $b.Add_Click({
            param($btn)
            $parts = $btn.Uid -split '\|', 3
            if ($parts[0] -eq 'C') {
                $script:NmGui.Open[$parts[1]] = -not [bool]$script:NmGui.Open[$parts[1]]
                Update-NmGuiCenters
            } else {
                Select-NmGuiSection -Center $parts[1] -Section $parts[2]
            }
        })
        [void]$c.CenterPanel.Children.Add($b)
    }
}

function Select-NmGuiSection {
    # Shows one area's section in the tool list and highlights it in the sidebar.
    param([Parameter(Mandatory)][string]$Center, [Parameter(Mandatory)][string]$Section)
    $script:NmGui.Selection = "$Center|$Section"
    $script:NmGui.Open[$Center] = $true
    $c = $script:NmGui.Controls
    if ($c.SearchBox -and $c.SearchBox.Text) { $script:NmGui.Quiet = $true; $c.SearchBox.Text = ''; $script:NmGui.Quiet = $false }
    Update-NmGuiCenters
    Update-NmGuiToolList -Center $Center -Section $Section
}

function Get-NmGuiToolListModel {
    <#
    .SYNOPSIS
        What the tool list shows: a heading, the center line above it, and items (Tool + Note).
        -Search lists every tool that matches, with its home as the note.
    #>
    [CmdletBinding()]
    param([string]$Center, [string]$Section, [string]$Search)
    if ($Search) {
        $areas = @(Get-NmGuiArea | ForEach-Object Id)
        $tools = @(Get-NmTool -Search $Search | Where-Object { $areas -contains $_.AdminCenter -and ($script:NmGui.BuildMode -or $script:NmGuiConsoleOnlyTools -notcontains $_.Id) } | Sort-Object Name)
        $items = foreach ($t in $tools) {
            $cn = ($script:NmAdminCenters | Where-Object { $_.Id -eq $t.AdminCenter } | Select-Object -First 1).Name
            [pscustomobject]@{ Tool = $t; Note = "$cn > $($t.Section)" }
        }
        return [pscustomobject]@{ CenterText = 'Search'; Title = "$Search ($($tools.Count))"; Items = @($items) }
    }
    $centerObj = Get-NmGuiArea | Where-Object { $_.Id -eq $Center } | Select-Object -First 1
    $sec = if ($centerObj) { $centerObj.Sections | Where-Object { $_.Name -eq $Section } | Select-Object -First 1 }
    if (-not $sec) { return [pscustomobject]@{ CenterText = ''; Title = 'Pick an area'; Items = @() } }
    return [pscustomobject]@{ CenterText = $centerObj.Name; Title = $sec.Name; Items = @($sec.Items) }
}

function Update-NmGuiToolList {
    param([string]$Center, [string]$Section, [string]$Search)
    $c = $script:NmGui.Controls
    $c.ToolList.Items.Clear()
    $model = Get-NmGuiToolListModel -Center $Center -Section $Section -Search $Search
    $c.ToolListCenter.Text = $model.CenterText
    $c.ToolListTitle.Text = $model.Title
    foreach ($entry in $model.Items) {
        $t = $entry.Tool
        $item = New-Object System.Windows.Controls.ListBoxItem
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = '4,6'
        $head = New-Object System.Windows.Controls.DockPanel
        if ($t.Kind -ne 'Report') {
            $tag = New-NmGuiTextBlock -Text 'Can change' -Size 11 -Weight 'SemiBold' -Color '#8A4B00'
            [System.Windows.Controls.DockPanel]::SetDock($tag, 'Right')
            [void]$head.Children.Add($tag)
        }
        [void]$head.Children.Add((New-NmGuiTextBlock -Text $t.Name -Size 14 -Weight 'SemiBold' -Wrap))
        [void]$sp.Children.Add($head)
        [void]$sp.Children.Add((New-NmGuiTextBlock -Text $t.Synopsis -Size 12 -Color '#5B6370' -Wrap))
        if ($entry.Note) {
            $note = New-NmGuiTextBlock -Text $entry.Note -Size 11 -Color '#2B4C8C' -Wrap
            $note.Margin = '0,3,0,0'
            [void]$sp.Children.Add($note)
        }
        $item.Content = $sp; $item.Tag = $t.Id
        [void]$c.ToolList.Items.Add($item)
    }
}

function Select-NmGuiTool {
    param([string]$Id)
    $c = $script:NmGui.Controls
    $t = Get-NmTool -Id $Id | Select-Object -First 1
    if (-not $t) { return }
    $script:NmGui.Tool = $t
    $c.ToolTitle.Text = $t.Name
    $c.ChangeTag.Visibility = $(if ($t.Kind -ne 'Report') { 'Visible' } else { 'Collapsed' })
    $centerName = ($script:NmAdminCenters | Where-Object { $_.Id -eq $t.AdminCenter } | Select-Object -First 1).Name
    $meta = "$($t.Synopsis)`nv$($t.Version)  |  $centerName > $($t.Section)  |  $($t.Id)"
    if (@($t.Roles).Count) { $meta += "`nNeeds: $($t.Roles -join ', ')" }
    $c.ToolMeta.Text = $meta
    $c.GuidedButton.IsEnabled = [bool]$t.Prompt
    $entry = Get-Command -Name $t.Entry -CommandType Function
    $c.PreviewBox.Visibility = $(if ($entry.Parameters.ContainsKey('WhatIf')) { 'Visible' } else { 'Collapsed' })
    $c.PreviewBox.IsChecked = $false
    Build-NmGuiOptionForm
    $c.ActionRow.Visibility = 'Visible'
    # Another tool: the last run's step list goes.
    if (-not $script:NmGui.BuildMode) { Stop-NmStepList; Update-NmGuiSteps }
    # Build mode: one way in, the build's own questions (the Resume and WhatIf boxes would only confuse).
    if ($script:NmGui.BuildMode) { Set-NmGuiBuildModeControl -Controls $c }
    # The tool's last results stay until cleared or the domain or DC changes.
    $k = $script:NmGui.Kept[$t.Id]
    if ($k -and $k.Target -eq (Get-NmGuiTarget)) { Set-NmGuiResult -Rows $k.Rows -Title "$($k.Title)" }
    else { Set-NmGuiResult -Rows @() -Title '' }
}

function Build-NmGuiOptionForm {
    $c = $script:NmGui.Controls
    $c.OptionsPanel.Children.Clear()
    $script:NmGui.Inputs = @{}
    $script:NmGui.Spec = @(Get-NmGuiParamSpec -Tool $script:NmGui.Tool)
    $c.OptionsBorder.Visibility = $(if ($script:NmGui.Spec.Count) { 'Visible' } else { 'Collapsed' })
    foreach ($f in $script:NmGui.Spec) {
        $box = New-Object System.Windows.Controls.StackPanel
        $box.Width = 230; $box.Margin = '0,0,16,10'
        switch ($f.Kind) {
            'Switch' {
                $cb = New-Object System.Windows.Controls.CheckBox
                $cb.Content = $f.Label; $cb.Margin = '0,22,0,0'
                [void]$box.Children.Add($cb); $script:NmGui.Inputs[$f.Name] = $cb
            }
            'Choice' {
                [void]$box.Children.Add((New-NmGuiTextBlock -Text "$($f.Label)$(if ($f.Required) { ' *' })" -Size 12 -Weight 'SemiBold' -Color '#3D4450'))
                $cmb = New-Object System.Windows.Controls.ComboBox
                $cmb.MinHeight = 30; $cmb.Margin = '0,4,0,0'
                # An empty choice only when there is nothing to fall back on: a parameter with a
                # default always has a value, so a blank line there only confuses.
                foreach ($v in @(Get-NmGuiChoiceItem -Field $f)) { [void]$cmb.Items.Add("$v") }
                $cmb.SelectedItem = $(if ($f.Default -and $f.Choices -contains $f.Default) { $f.Default } else { '' })
                [void]$box.Children.Add($cmb); $script:NmGui.Inputs[$f.Name] = $cmb
            }
            default {
                $hint = switch ($f.Kind) { 'List' { ' (comma-separated)' } 'Date' { ' (yyyy-MM-dd HH:mm)' } default { '' } }
                $star = if ($f.Required) { ' *' } else { '' }
                [void]$box.Children.Add((New-NmGuiTextBlock -Text "$($f.Label)$hint$star" -Size 12 -Weight 'SemiBold' -Color '#3D4450'))
                $tb = New-Object System.Windows.Controls.TextBox
                $tb.MinHeight = 30; $tb.Margin = '0,4,0,0'; $tb.Padding = '6,3'; $tb.VerticalContentAlignment = 'Center'
                if ($f.Default) { $tb.Text = $f.Default }
                [void]$box.Children.Add($tb); $script:NmGui.Inputs[$f.Name] = $tb
            }
        }
        [void]$c.OptionsPanel.Children.Add($box)
    }
}

function Get-NmGuiFormValue {
    $v = @{}
    foreach ($k in $script:NmGui.Inputs.Keys) {
        $ctl = $script:NmGui.Inputs[$k]
        if ($ctl -is [System.Windows.Controls.CheckBox]) { $v[$k] = [bool]$ctl.IsChecked }
        elseif ($ctl -is [System.Windows.Controls.ComboBox]) { $v[$k] = "$($ctl.SelectedItem)" }
        else { $v[$k] = $ctl.Text }
    }
    return $v
}

function Set-NmGuiFormValue {
    # Guided answers back into the form, so a re-run uses them.
    param([hashtable]$Answers)
    foreach ($k in $Answers.Keys) {
        $ctl = $script:NmGui.Inputs[$k]
        if (-not $ctl) { continue }
        $val = $Answers[$k]
        if ($ctl -is [System.Windows.Controls.CheckBox]) { $ctl.IsChecked = [bool]$val }
        elseif ($ctl -is [System.Windows.Controls.ComboBox]) { if ($ctl.Items.Contains("$val")) { $ctl.SelectedItem = "$val" } }
        else { $ctl.Text = ConvertTo-NmGuiValue $val }
    }
}

function Set-NmGuiResult {
    # -Keep: the same results redrawn (after a row screen), so the clicked tag stays.
    param([object[]]$Rows, [string]$Title, [switch]$Keep)
    $c = $script:NmGui.Controls
    $script:NmGui.Rows = @($Rows)
    if (-not $Keep) { $script:NmGui.Facet = ''; $script:NmGui.CardLimit = 100 }
    $script:NmGui.Selected.Clear()
    $t = $script:NmGui.Tool
    if ($t -and $script:NmGui.Rows.Count) { $script:NmGui.Kept[$t.Id] = @{ Rows = $script:NmGui.Rows; Title = $Title; Target = (Get-NmGuiTarget) } }
    if ($c.ClearButton) { $c.ClearButton.Visibility = $(if ($t -and $script:NmGui.Rows.Count) { 'Visible' } else { 'Collapsed' }) }
    $cols = @(Get-NmGuiColumn -Rows $script:NmGui.Rows -Tool $script:NmGui.Tool -All:([bool]$c.AllColumnsBox.IsChecked))
    $script:NmGui.Table = ConvertTo-NmGuiTable -Rows $script:NmGui.Rows -Columns $cols
    $c.FilterBox.Text = ''
    $c.ResultsGrid.ItemsSource = $script:NmGui.Table.DefaultView
    $c.ResultTitle.Text = $Title
    $has = $script:NmGui.Rows.Count -gt 0
    $c.ResultBar.Visibility = $(if ($has) { 'Visible' } else { 'Collapsed' })
    $c.ResultsGrid.Visibility = $(if ($has) { 'Visible' } else { 'Collapsed' })
    $c.EmptyText.Text = $(if ($has) { '' } elseif ($Title) { "No results. $Title" } elseif ($script:NmGui.BuildMode) { 'The build asks its questions one at a time, as the console does. Nothing changes until you approve the plan.' } elseif ($script:NmGui.Tool) { 'Set the options and press Run, or use Guided... to answer the questions one at a time.' } else { '' })
    $c.ExportCsvButton.IsEnabled = $has; $c.ExportTxtButton.IsEnabled = $has
    $c.SummaryButton.IsEnabled = $has -and $script:NmGui.Tool -and [bool]$script:NmGui.Tool.Summary
    $c.DetailsButton.IsEnabled = $has
    Update-NmGuiCardView
    Update-NmGuiSelectionBar
}

function Get-NmGuiSelectionModel {
    <#
    .SYNOPSIS
        What the selection bar shows (no WPF): whether it is there at all (the tool has bulk
        actions and there are results), the "n selected" text, and each action button, enabled
        only when something is selected.
    #>
    param($Tool, [int]$RowCount, [int]$SelectedCount)
    $on = [bool]($Tool -and $Tool.BulkAction -and $RowCount -gt 0)
    [pscustomobject]@{
        Visible = $on
        Text    = $(if ($SelectedCount -eq 0) { 'None selected' } else { "$SelectedCount selected" })
        Actions = @(if ($on) { foreach ($a in @($Tool.BulkActions)) { [pscustomobject]@{ Label = "$a"; Enabled = ($SelectedCount -gt 0) } } })
    }
}

function Get-NmGuiGridSelectedIndex {
    # The table rows selected in the grid, as indexes into Rows (from the '#' column).
    param([object[]]$Items)
    @(foreach ($it in @($Items)) {
        $n = 0
        $v = if ($it -is [System.Data.DataRowView]) { $it.Row['#'] } else { $it.'#' }
        if ([int]::TryParse("$v", [ref]$n) -and $n -ge 1) { $n - 1 }
    })
}

function Set-NmGuiRowSelected {
    # A card's tick box: adds or removes the row, then refreshes the bar.
    param([int]$Index, [bool]$Selected)
    if ($Selected) { [void]$script:NmGui.Selected.Add($Index) } else { [void]$script:NmGui.Selected.Remove($Index) }
    Update-NmGuiSelectionBar
}

function Update-NmGuiSelectionBar {
    # Shows the bar for tools with bulk actions: the count, and a button per action.
    $c = $script:NmGui.Controls
    if (-not $c -or -not $c.SelectionBar) { return }
    $m = Get-NmGuiSelectionModel -Tool $script:NmGui.Tool -RowCount @($script:NmGui.Rows).Count -SelectedCount $script:NmGui.Selected.Count
    $c.SelectionBar.Visibility = $(if ($m.Visible) { 'Visible' } else { 'Collapsed' })
    if (-not $m.Visible) { return }
    $c.SelectionText.Text = $m.Text
    $c.SelectNoneButton.IsEnabled = $script:NmGui.Selected.Count -gt 0
    $c.SelectionActions.Children.Clear()
    foreach ($a in $m.Actions) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $a.Label; $b.Tag = $a.Label; $b.IsEnabled = $a.Enabled; $b.Margin = '8,0,0,0'
        $b.ToolTip = "$($a.Label): the selected rows (asked and confirmed first)"
        $b.Add_Click({ param($s, $e) Invoke-NmGuiBulkAction -Action "$($s.Tag)" })
        [void]$c.SelectionActions.Children.Add($b)
    }
}

function Select-NmGuiShownRow {
    # Select all shown: every card the filter and tag show, or every row in the table.
    param([switch]$None)
    $c = $script:NmGui.Controls
    $script:NmGui.Selected.Clear()
    if ($None) {
        if ($c.ResultsGrid.SelectedItems.Count) { $c.ResultsGrid.UnselectAll() }
    } elseif (Test-NmGuiCardView) {
        foreach ($i in @($script:NmGui.ShownIndex)) { [void]$script:NmGui.Selected.Add([int]$i) }
    } else {
        $c.ResultsGrid.SelectAll()
        foreach ($i in @(Get-NmGuiGridSelectedIndex -Items @($c.ResultsGrid.SelectedItems))) { [void]$script:NmGui.Selected.Add([int]$i) }
    }
    if (Test-NmGuiCardView) { Update-NmGuiCardView }
    Update-NmGuiSelectionBar
}

function Invoke-NmGuiBulkAction {
    # Runs the tool's BulkAction on the selected rows; its questions and results show as dialogs.
    param([Parameter(Mandatory)][string]$Action)
    $t = $script:NmGui.Tool
    if (-not $t -or -not $t.BulkAction) { return }
    $idx = @($script:NmGui.Selected | Sort-Object)
    $rows = @($idx | Where-Object { $_ -lt @($script:NmGui.Rows).Count } | ForEach-Object { $script:NmGui.Rows[$_] })
    if (-not $rows.Count) { $script:NmGui.Controls.StatusText.Text = 'Select one or more rows first.'; return }
    $fn = (Get-Command -Name $t.BulkAction -CommandType Function).ScriptBlock
    Invoke-NmGuiAction -Busy "$Action ($($rows.Count))..." -Action { $null = & $fn $Action $rows $script:NmGui.Rows }
    if ($script:NmGui.LastLeftover) { [void](Show-NmGuiDialog -Title "$Action ($($rows.Count) selected)" -Text $script:NmGui.LastLeftover -NoInput -Captures $script:NmGui.LastCaptures) }
    # The action can change rows (Released): redraw, keeping the filter and tag; the selection clears.
    Set-NmGuiResult -Rows $script:NmGui.Rows -Title $script:NmGui.Controls.ResultTitle.Text -Keep
}

function Test-NmGuiCardView {
    # True when the results show as cards: there are results and the view is on Cards.
    return [bool]($script:NmGui.CardMode -and @($script:NmGui.Rows).Count)
}

function Update-NmGuiCardView {
    # Shows cards (finding cards for View = 'Findings' tools) or the table, as the toggle says,
    # with the filter text and the clicked tag applied.
    $c = $script:NmGui.Controls
    if (-not $c.CardScroll) { return }
    $has = @($script:NmGui.Rows).Count -gt 0
    $c.ViewToggle.Visibility = $(if ($has) { 'Visible' } else { 'Collapsed' })
    if (Test-NmGuiCardView) {
        $t = $script:NmGui.Tool
        $f = "$($c.FilterBox.Text)"
        if ($t -and "$($t.View)" -eq 'Findings') {
            $c.CardHost.Content = New-NmGuiFindingView -Rows $script:NmGui.Rows -Filter $f -Facet $script:NmGui.Facet
        } else {
            $cols = @(Get-NmGuiColumn -Rows $script:NmGui.Rows -Tool $t -All:([bool]$c.AllColumnsBox.IsChecked))
            $grp = @(if ($t -and $t.CardGroup) { $t.CardGroup })
            $c.CardHost.Content = New-NmGuiCardView -Rows $script:NmGui.Rows -Columns $cols -Filter $f -Facet $script:NmGui.Facet -Limit ([int]$script:NmGui.CardLimit) -CanOpen:([bool]($t -and $t.DeepDive)) -GroupBy $grp -Selectable:([bool]($t -and $t.BulkAction))
        }
        $c.CardScroll.Visibility = 'Visible'; $c.ResultsGrid.Visibility = 'Collapsed'
        $c.ViewToggle.Content = 'Table view'; $c.DetailsButton.IsEnabled = $false
    } else {
        $c.CardHost.Content = $null
        $c.CardScroll.Visibility = 'Collapsed'
        if ($has) { $c.ResultsGrid.Visibility = 'Visible' }
        $c.ViewToggle.Content = 'Card view'; $c.DetailsButton.IsEnabled = $has
    }
}

function Set-NmGuiBusy {
    param([bool]$Busy, [string]$Status)
    $c = $script:NmGui.Controls
    foreach ($b in @('RunButton', 'GuidedButton', 'DomainButton', 'SettingsButton')) { if ($c[$b]) { $c[$b].IsEnabled = -not $Busy } }
    if ($Busy -eq $false -and $script:NmGui.Tool) { $c.GuidedButton.IsEnabled = [bool]$script:NmGui.Tool.Prompt }
    $script:NmGui.Window.Cursor = $(if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { $null })
    if ($Status) { $c.StatusText.Text = $Status }
    # While a tool asks its questions, the page behind the dialogs stays quiet.
    if ($c.EmptyText) { $c.EmptyText.Visibility = $(if ($Busy) { 'Collapsed' } else { 'Visible' }) }
    $script:NmGui.Window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Update-NmGuiLog {
    $c = $script:NmGui.Controls
    $c.LogBox.Text = $script:NmGui.Transcript.ToString()
    $c.LogBox.ScrollToEnd()
}

function Invoke-NmGuiAction {
    # Runs console-style code inside the window (prompts become dialogs); reports errors and cancels.
    param([scriptblock]$Action, [string]$Busy = 'Working...')
    Set-NmGuiBusy -Busy $true -Status $Busy
    Clear-NmGuiBuffer
    try {
        & $Action
    } catch [System.OperationCanceledException] {
        $script:NmGui.Controls.StatusText.Text = "Cancelled: $($Busy.TrimEnd('.'))"
    } catch {
        $script:NmGui.Controls.StatusText.Text = "Failed: $($_.Exception.Message)"
        [void][System.Windows.MessageBox]::Show($script:NmGui.Window, $_.Exception.Message, 'Nutmeg AD Toolkit', 'OK', 'Error')
    } finally {
        $left = $script:NmGui.Buffer.ToString().Trim()
        $script:NmGui.LastCaptures = @($script:NmGui.Captures.ToArray())
        Clear-NmGuiBuffer
        Clear-NmGuiProgress
        Set-NmGuiBusy -Busy $false
        Update-NmGuiBanner
        Update-NmGuiLog
        $script:NmGui.LastLeftover = $left
    }
}

function Invoke-NmGuiRun {
    param([hashtable]$EntryArgs)
    $t = $script:NmGui.Tool
    $c = $script:NmGui.Controls
    if ($c.PreviewBox.IsChecked -and $c.PreviewBox.Visibility -eq 'Visible') { $EntryArgs.WhatIf = $true }
    $mode = if ($EntryArgs.WhatIf) { 'WhatIf' } else { 'Run' }
    Invoke-NmGuiAction -Busy "Running $($t.Name)..." -Action {
        if (-not (Assert-NmConnection -Services $t.Services)) { throw "Could not load what $($t.Name) needs (the modules, or the domain from this DC)." }
        Update-NmGuiBanner
        Clear-NmGuiBuffer
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-NmLog "Running $($t.Name) v$($t.Version) (window)." -Level INFO -NoConsole
        try {
            $rows = @(& $t.Entry @EntryArgs)
        } catch {
            Write-NmRunHistory -ToolId $t.Id -ToolVersion $t.Version -Kind $t.Kind -Mode $mode -Result Failed -Notes $_.Exception.Message
            throw
        }
        $sw.Stop()
        Write-NmRunHistory -ToolId $t.Id -ToolVersion $t.Version -Kind $t.Kind -Mode $mode -ItemCount $rows.Count
        Set-NmGuiResult -Rows $rows -Title ("{0} result(s)  |  ran {1:HH:mm}  |  {2:N1} s" -f $rows.Count, (Get-Date), $sw.Elapsed.TotalSeconds)
        $c.StatusText.Text = "$($t.Name): $($rows.Count) result(s)."
    }
    # Messages the tool wrote but never asked about (for example "No results"): show them once.
    if ($script:NmGui.LastLeftover -and $script:NmGui.Rows.Count -eq 0) {
        [void](Show-NmGuiDialog -Title $t.Name -Text $script:NmGui.LastLeftover -NoInput -Captures $script:NmGui.LastCaptures)
    }
}

function Get-NmGuiSelectedRow {
    $c = $script:NmGui.Controls
    $sel = $c.ResultsGrid.SelectedItem
    if (-not $sel) { return $null }
    $i = [int]$sel.Row['#']
    return $script:NmGui.Rows[$i - 1]
}

function Show-NmGuiRowDetail {
    # The selected row in the table, or row -Index (a card's Open button).
    param([int]$Index = -1)
    $row = if ($Index -ge 0 -and $Index -lt @($script:NmGui.Rows).Count) { $script:NmGui.Rows[$Index] } else { Get-NmGuiSelectedRow }
    if (-not $row) { $script:NmGui.Controls.StatusText.Text = 'Select a row first.'; return }
    $t = $script:NmGui.Tool
    if ($t -and $t.DeepDive) {
        $dd = (Get-Command -Name $t.DeepDive -CommandType Function).ScriptBlock
        Invoke-NmGuiAction -Busy 'Row details...' -Action { & $dd $row $script:NmGui.Rows }
        if ($script:NmGui.LastLeftover) { [void](Show-NmGuiDialog -Title 'Row details' -Text $script:NmGui.LastLeftover -NoInput -Captures $script:NmGui.LastCaptures) }
        # Row screens can change the row (Result column): redraw the grid.
        Set-NmGuiResult -Rows $script:NmGui.Rows -Title $script:NmGui.Controls.ResultTitle.Text -Keep
    } else {
        # The row as a details card: every field named, long text wrapped, copyable.
        $cap = [pscustomobject]@{ Kind = 'List'; Title = 'Row details'; Columns = @($row.PSObject.Properties | Where-Object { $_.MemberType -match 'Property' -and $_.Name -ne '#' } | ForEach-Object Name); Rows = @($row) }
        [void](Show-NmGuiDialog -Title 'Row details' -Heading 'Row details' -NoInput -Captures @($cap))
    }
}

function Get-NmGuiWindowPlacement {
    <#
    .SYNOPSIS
        Where the main window opens (no WPF): 1440 x 900 when the usable screen has room for it with
        a margin, smaller otherwise, centred in the usable screen; Maximize on a screen too small for
        the window's minimum (1000 x 640) with that margin.
    #>
    param([double]$WorkLeft = 0, [double]$WorkTop = 0, [Parameter(Mandatory)][double]$WorkWidth, [Parameter(Mandatory)][double]$WorkHeight,
          [double]$Want = 1440, [double]$WantHeight = 900, [double]$Margin = 40)
    $w = [Math]::Min($Want, $WorkWidth - 2 * $Margin)
    $h = [Math]::Min($WantHeight, $WorkHeight - 2 * $Margin)
    $max = ($w -lt 1000 -or $h -lt 640)
    if ($max) { $w = [Math]::Max(1000, $w); $h = [Math]::Max(640, $h) }
    [pscustomobject]@{
        Width    = $w
        Height   = $h
        Left     = $WorkLeft + [Math]::Max(0, [Math]::Floor(($WorkWidth - $w) / 2))
        Top      = $WorkTop + [Math]::Max(0, [Math]::Floor(($WorkHeight - $h) / 2))
        Maximize = $max
    }
}

function Start-NmToolkitGui {
    <#
    .SYNOPSIS
        Opens the toolkit in a window. Same tools, confirmations, logs and run history as the
        console menu.
    .DESCRIPTION
        - The header shows the domain and the DC every tool works against (Domain and DC opens the
          same menu as the console), and which modules are loaded.
        - -NewForest opens the New Forest Build instead (Start-NutmegAD.ps1 -NewForest, in
          Windows PowerShell 5.1): only the build is listed, and its questions start as soon as the
          window is up. The normal window leaves the build out.
    .EXAMPLE
        Import-Module .\Nutmeg.AD\Nutmeg.AD.psd1; Start-NmToolkitGui
    .EXAMPLE
        Start-NmToolkitGui -NewForest
    #>
    [CmdletBinding()]
    param([switch]$NewForest)

    if (-not $script:NmOnWindows) { Write-NmLog 'The window needs Windows (WPF). Use Start-NmToolkit for the console menu.' -Level ERROR; return }
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        Write-NmLog 'The window needs an STA thread. Run it from Windows PowerShell 5.1, or start PowerShell 7 with: pwsh -STA' -Level ERROR
        return
    }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    Write-NmLog "Nutmeg AD Toolkit $script:ModuleVersion window started$(if ($NewForest) { ' (New Forest Build)' }). Log: $(Get-NmLogPath)" -Level INFO -NoConsole
    $script:NmGui.BuildMode = [bool]$NewForest
    $null = Remove-NmOldLog
    $script:NmGui.CardMode = ("$(Get-NmSetting -Key ResultsView)" -ne 'Table')
    $script:NmGui.Kept = @{}
    $script:NmGui.Active = $true
    [void]$script:NmGui.Transcript.Clear()
    Clear-NmGuiBuffer
    try {
        $w = New-NmGuiXaml -Xaml ($script:NmGuiMainXaml.Replace('<!--NMSTYLES-->', $script:NmGuiTheme))
        $script:NmGui.Window = $w
        # Fit the usable screen (the screen less the taskbar), with a margin, so the title bar never
        # sits against the top edge and nothing runs off the side; a small screen opens maximised.
        try {
            $wa = [System.Windows.SystemParameters]::WorkArea
            $fit = Get-NmGuiWindowPlacement -WorkLeft $wa.Left -WorkTop $wa.Top -WorkWidth $wa.Width -WorkHeight $wa.Height
            $w.WindowStartupLocation = 'Manual'
            $w.Width = $fit.Width; $w.Height = $fit.Height; $w.Left = $fit.Left; $w.Top = $fit.Top
            if ($fit.Maximize) { $w.WindowState = 'Maximized' }
        } catch { $null = $_ }
        $c = @{}
        foreach ($n in $script:NmGuiMainControls) { $c[$n] = $w.FindName($n) }
        $script:NmGui.Controls = $c
        $c.VersionText.Text = "v$script:ModuleVersion"

        $c.SearchBox.Add_TextChanged({
            $script:NmGui.Controls.SearchHint.Visibility = $(if ($script:NmGui.Controls.SearchBox.Text) { 'Collapsed' } else { 'Visible' })
            if ($script:NmGui.Quiet) { return }
            $s = $script:NmGui.Controls.SearchBox.Text.Trim()
            if ($s) {
                Update-NmGuiToolList -Search $s
            } elseif ($script:NmGui.Selection) {
                # Search cleared: back to the section that was open.
                $p = "$($script:NmGui.Selection)" -split '\|', 2
                Update-NmGuiToolList -Center $p[0] -Section $p[1]
            }
        })
        $c.ToolList.Add_SelectionChanged({
            $i = $script:NmGui.Controls.ToolList.SelectedItem
            if ($i) { Select-NmGuiTool -Id $i.Tag }
        })
        $c.RunButton.Add_Click({
            try { $a = ConvertFrom-NmGuiForm -Spec $script:NmGui.Spec -Values (Get-NmGuiFormValue) }
            catch { [void][System.Windows.MessageBox]::Show($script:NmGui.Window, $_.Exception.Message, 'Check the options', 'OK', 'Warning'); return }
            Invoke-NmGuiRun -EntryArgs $a
        })
        $c.GuidedButton.Add_Click({ Invoke-NmGuiGuided })
        $c.FilterBox.Add_TextChanged({
            $script:NmGui.Controls.FilterHint.Visibility = $(if ($script:NmGui.Controls.FilterBox.Text) { 'Collapsed' } else { 'Visible' })
            if ($script:NmGui.Table) {
                try { $script:NmGui.Table.DefaultView.RowFilter = Get-NmGuiRowFilter -Text $script:NmGui.Controls.FilterBox.Text -Table $script:NmGui.Table } catch { $null = $_ }
            }
            if (Test-NmGuiCardView) { Update-NmGuiCardView }
        })
        $c.AllColumnsBox.Add_Click({ Set-NmGuiResult -Rows $script:NmGui.Rows -Title $script:NmGui.Controls.ResultTitle.Text -Keep })
        $c.ExportCsvButton.Add_Click({
            $p = Export-NmResult -Data $script:NmGui.Rows -ToolId $(if ($script:NmGui.Tool) { $script:NmGui.Tool.Id } else { 'results' }) -Format Csv -NoPrompt
            if ($p) { $script:NmGui.Controls.StatusText.Text = "Exported to $p"; Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$p`"" }
        })
        $c.ExportTxtButton.Add_Click({
            $p = Export-NmResult -Data $script:NmGui.Rows -ToolId $(if ($script:NmGui.Tool) { $script:NmGui.Tool.Id } else { 'results' }) -Format Txt -NoPrompt
            if ($p) { $script:NmGui.Controls.StatusText.Text = "Exported to $p"; Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$p`"" }
        })
        $c.SummaryButton.Add_Click({
            $t = $script:NmGui.Tool
            $sb = (Get-Command -Name $t.Summary -CommandType Function).ScriptBlock
            Invoke-NmGuiAction -Busy 'Summary...' -Action { & $sb $script:NmGui.Rows }
            [void](Show-NmGuiDialog -Title "$($t.Name): summary" -Text $script:NmGui.LastLeftover -NoInput -Captures $script:NmGui.LastCaptures)
        })
        $c.DetailsButton.Add_Click({ Show-NmGuiRowDetail })
        $c.ResultsGrid.Add_MouseDoubleClick({ Show-NmGuiRowDetail })
        $c.ResultsGrid.Add_AutoGeneratingColumn({ param($s, $e) Set-NmGuiWrapColumn -Column $e.Column })
        $c.ViewToggle.Add_Click({ $script:NmGui.CardMode = -not $script:NmGui.CardMode; $script:NmGui.Selected.Clear(); Update-NmGuiCardView; Update-NmGuiSelectionBar })
        $c.ResultsGrid.Add_SelectionChanged({
            # In the table, the selected rows are the selection for the bar.
            if ((Test-NmGuiCardView) -or -not ($script:NmGui.Tool -and $script:NmGui.Tool.BulkAction)) { return }
            $script:NmGui.Selected.Clear()
            foreach ($i in @(Get-NmGuiGridSelectedIndex -Items @($script:NmGui.Controls.ResultsGrid.SelectedItems))) { [void]$script:NmGui.Selected.Add([int]$i) }
            Update-NmGuiSelectionBar
        })
        $c.SelectAllButton.Add_Click({ Select-NmGuiShownRow })
        $c.SelectNoneButton.Add_Click({ Select-NmGuiShownRow -None })
        $c.ClearButton.Add_Click({
            if ($script:NmGui.Tool) { $script:NmGui.Kept.Remove($script:NmGui.Tool.Id) }
            Set-NmGuiResult -Rows @() -Title ''
            $script:NmGui.Controls.StatusText.Text = 'Results cleared.'
        })
        $c.HistoryButton.Add_Click({
            $script:NmGui.Tool = $null
            $script:NmGui.Controls.ToolTitle.Text = 'Run history'
            $script:NmGui.Controls.ChangeTag.Visibility = 'Collapsed'
            $script:NmGui.Controls.ToolMeta.Text = 'The last 200 tool runs, newest first.'
            $script:NmGui.Controls.OptionsBorder.Visibility = 'Collapsed'
            $script:NmGui.Controls.ActionRow.Visibility = 'Collapsed'
            $rows = @(Get-NmRunHistory -Last 200 | Sort-Object Timestamp -Descending)
            Set-NmGuiResult -Rows $rows -Title "$($rows.Count) run(s)"
        })
        # Domain and DC: the console's menu, its questions as dialogs.
        $c.DomainButton.Add_Click({ Invoke-NmGuiAction -Busy 'Domain and DC...' -Action { Show-NmDomainMenu } })
        # The cog: the same Settings menu as the console, its questions as dialogs. The gear glyph is
        # built at run time (code files are ASCII only).
        $c.SettingsGlyph.Text = [string][char]0xE713
        $c.SettingsButton.Add_Click({ Invoke-NmGuiAction -Busy 'Settings...' -Action { Show-NmSettingsMenu } })

        $w.Add_ContentRendered({
            if ($script:NmGui.Started) { return }
            $script:NmGui.Started = $true
            $script:NmGui.Controls.StatusText.Text = Get-NmGuiReadyText
            # The New Forest Build: its questions (or "Continue it?" after a restart) start at once.
            if ($script:NmGui.BuildMode -and $script:NmGui.Tool) { Invoke-NmGuiGuided }
        })

        $script:NmGui.Started = $false
        $script:NmGui.ShownTarget = $null
        $script:NmGui.Progress = $null
        $script:NmGui.ProgressClock = $null
        Update-NmGuiBanner
        # Start on the first area's first section, opened (the build, with its tool picked, in build mode).
        $script:NmGui.Open = @{}
        $first = @(Get-NmGuiArea) | Select-Object -First 1
        if ($first) { Select-NmGuiSection -Center $first.Id -Section $first.Sections[0].Name } else { Update-NmGuiCenters }
        if ($NewForest) {
            $w.Title = 'Nutmeg AD Toolkit: New Forest Build'
            $c.VersionText.Text = "v$script:ModuleVersion  |  New Forest Build"
            Select-NmGuiTool -Id 'new-forest'
        }
        [void]$w.ShowDialog()
    } finally {
        $script:NmGui.Active = $false
        $script:NmGui.BuildMode = $false
        $script:NmGui.Window = $null
        $script:NmGui.Controls = @{}
        Write-NmLog 'Nutmeg AD Toolkit window closed.' -Level INFO -NoConsole
    }
}

function Set-NmGuiBuildModeControl {
    # Build mode: the Run button, the options form and the WhatIf box go; Guided becomes the one
    # button that starts (or continues) the build.
    param([Parameter(Mandatory)][hashtable]$Controls)
    $Controls.RunButton.Visibility = 'Collapsed'
    $Controls.OptionsBorder.Visibility = 'Collapsed'
    $Controls.PreviewBox.Visibility = 'Collapsed'
    $Controls.GuidedButton.Content = 'Start or continue the build'
    $Controls.GuidedButton.ToolTip = 'Checks the server, asks the questions once and shows the plan; after a restart, carries on where it stopped'
}

function Invoke-NmGuiGuided {
    # Guided...: the tool's own questions as dialogs, then the run with the answers (also how the
    # New Forest Build starts in build mode).
    $t = $script:NmGui.Tool
    if (-not $t -or -not $t.Prompt) { return }
    $state = @{ Answers = $null }
    Invoke-NmGuiAction -Busy "$($t.Name): questions..." -Action {
        if (-not (Assert-NmConnection -Services $t.Services)) { throw "Could not load what $($t.Name) needs (the modules, or the domain from this DC)." }
        $state.Answers = & $t.Prompt
    }
    if ($state.Answers -is [hashtable]) {
        Set-NmGuiFormValue -Answers $state.Answers
        Invoke-NmGuiRun -EntryArgs $state.Answers.Clone()
    }
}

function Get-NmGuiReadyText {
    # The status line once the window is up: elevation first, since every change needs it.
    if (-not (Test-NmElevated)) { return 'Not running as administrator: checks may be incomplete and changes will fail. Start it again elevated.' }
    if ($script:NmGui.BuildMode) { return 'New Forest Build: answer the questions to start, or continue a saved build.' }
    $s = $script:NmSession
    if ($s -and $s.Domain) { return "Ready. Domain $($s.Domain), working against $($s.Server)." }
    return 'Ready. Pick a tool: the domain is read from this DC when a tool needs it.'
}

function Get-NmGuiArea {
    <#
    .SYNOPSIS
        The areas the window shows: every area with tools except the New Forest Build, or, in build
        mode (Start-NmToolkitGui -NewForest), the build only.
    #>
    [CmdletBinding()]
    param()
    if ($script:NmGui.BuildMode) { return @(Get-NmAdminCenter | Where-Object { $script:NmGuiConsoleOnlyAreas -contains $_.Id }) }
    @(Get-NmAdminCenter | Where-Object { $script:NmGuiConsoleOnlyAreas -notcontains $_.Id })
}
