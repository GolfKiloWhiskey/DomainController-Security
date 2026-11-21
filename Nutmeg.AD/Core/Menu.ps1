# ---------------------------------------------------------------------------
# Menu.ps1 - header block, menus, prompts, result display and the Result Action Menu
# ---------------------------------------------------------------------------

$script:NmBorder = '============================================='

# Where the user is (shown under the title as "Main Menu > Mail Flow > Message Trace"),
# the version to show while inside a tool, and notes shown once on a tool's first screen.
$script:NmNav          = New-Object System.Collections.Generic.List[string]
$script:NmScreenVersion = $null
$script:NmScreenNotes   = @()

# [M] Main menu: set when the user picks M two or more levels down. Every menu and loop on the
# way back up sees it and returns, until the main menu clears it.
$script:NmGoMain = $false

function Test-NmShowMainKey { return ($script:NmNav.Count -ge 2) }

function Push-NmNav { param([string]$Name) $script:NmNav.Add($Name) }
function Pop-NmNav  { if ($script:NmNav.Count -gt 0) { $script:NmNav.RemoveAt($script:NmNav.Count - 1) } }

function Read-NmHost {
    # Single wrapper around Read-Host so tests can mock every prompt in one place.
    # Callers print their own coloured prompt text; this adds ": " right after it.
    [CmdletBinding()]
    param([string]$Prompt)
    # In the window (Start-NmToolkitGui) every prompt becomes a dialog showing what was written since.
    if ($script:NmGui -and $script:NmGui.Active) { return (Read-NmGuiHost -Prompt $Prompt) }
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        Write-Host ': ' -ForegroundColor Yellow -NoNewline
        return (Read-Host)
    }
    return (Read-Host -Prompt $Prompt)
}

function Read-NmSecret {
    <#
    .SYNOPSIS
        Asks for a password without showing it, and returns it as a SecureString. Never logged or saved.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param([Parameter(Mandatory)][string]$Prompt)
    Write-Host $Prompt -ForegroundColor Yellow -NoNewline
    return (Read-Host -Prompt ' ' -AsSecureString)
}

function Wait-NmKey {
    Write-Host 'Press Enter to continue' -ForegroundColor DarkGray -NoNewline
    $null = Read-NmHost -Prompt ' '
}

function Read-NmInput {
    <#
    .SYNOPSIS
        Prompts with a default shown: "Export folder (Press Enter for default: C:\Temp)".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default
    )

    $text = if ($Default) { "$Prompt (Press Enter for default: $Default)" } else { $Prompt }
    Write-Host $text -ForegroundColor Yellow -NoNewline
    $answer = Read-NmHost -Prompt ' '
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Read-NmYesNo {
    <#
    .SYNOPSIS
        Y/N prompt with a default. Returns $true for yes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [ValidateSet('Y', 'N')][string]$Default = 'N'
    )

    $hint = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Write-Host "$Prompt $hint" -ForegroundColor Yellow -NoNewline
        $answer = Read-NmHost -Prompt ' '
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        switch -Regex ($answer.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Host 'Please answer Y or N.' -ForegroundColor Red }
        }
    }
}

function Clear-NmScreen {
    <#
    .SYNOPSIS
        Clears the screen and puts the cursor at the top.
    .DESCRIPTION
        In Windows Terminal, Windows PowerShell 5.1's Clear-Host can leave the cursor at the bottom
        of the window, so every menu after the first draws at the bottom. Where the console
        understands escape codes, clear and move the cursor home with them instead.
    #>
    if ($script:NmGui -and $script:NmGui.Active) { Clear-NmGuiBuffer; return }   # the window: start a fresh dialog page
    $vt = $false
    try { $vt = [bool]$Host.UI.SupportsVirtualTerminal } catch { $vt = $false }
    if ($env:WT_SESSION) { $vt = $true }
    if ($vt -and -not [Console]::IsOutputRedirected) {
        $esc = [char]27
        [Console]::Write("$esc[2J$esc[3J$esc[H")
    } else {
        Clear-Host
    }
}

function Show-NmHeader {
    <#
    .SYNOPSIS
        The standard Nutmeg header block, with where-you-are path and the connection banner.
    .DESCRIPTION
        Inside a tool, the version shown is the tool's, and the tool's notes (what it needs,
        whether it changes things) are shown once, on its first screen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Version,
        [switch]$Clear,
        [switch]$NoBanner
    )

    if (-not $Version) { $Version = if ($script:NmScreenVersion) { $script:NmScreenVersion } else { $script:ModuleVersion } }
    if ($Clear) { Clear-NmScreen }
    Write-Host $script:NmBorder -ForegroundColor Cyan
    Write-Host "   $Title" -ForegroundColor Yellow
    Write-Host '   Author: Cliff Waite' -ForegroundColor DarkGray
    Write-Host '   Email: cliff.ps@nutmegtech.com' -ForegroundColor DarkGray
    Write-Host "   Version: $Version" -ForegroundColor DarkGray
    Write-Host $script:NmBorder -ForegroundColor Cyan
    if ($script:NmNav.Count -gt 0) {
        Write-Host "   Main Menu > $($script:NmNav -join ' > ')" -ForegroundColor DarkGray
    }
    if (-not $NoBanner) {
        Write-Host "   $(Get-NmBannerText)" -ForegroundColor DarkGray
    }
    if ($script:NmNav.Count -gt 0 -or -not $NoBanner) {
        Write-Host $script:NmBorder -ForegroundColor Cyan
    }
    if ($script:NmScreenNotes.Count -gt 0) {
        foreach ($note in $script:NmScreenNotes) { Write-Host "   $($note.Text)" -ForegroundColor $note.Color }
        Write-Host $script:NmBorder -ForegroundColor Cyan
        $script:NmScreenNotes = @()
    }
}

function ConvertFrom-NmPickList {
    # "1,3, 5-7" or "A" as zero-based indexes below Count.
    param([string]$Text, [int]$Count)
    if ("$Text".Trim() -match '^(?i)a(ll)?$') { return @(0..($Count - 1)) }
    $out = New-Object System.Collections.Generic.List[int]
    foreach ($part in @("$Text" -split '[,;\s]+' | Where-Object { $_ })) {
        if ($part -match '^(\d+)-(\d+)$') { foreach ($n in [int]$Matches[1]..[int]$Matches[2]) { if ($n -ge 1 -and $n -le $Count -and -not $out.Contains($n - 1)) { $out.Add($n - 1) } } }
        elseif ($part -match '^\d+$') { $n = [int]$part; if ($n -ge 1 -and $n -le $Count -and -not $out.Contains($n - 1)) { $out.Add($n - 1) } }
    }
    return $out.ToArray()
}

function Read-NmMultiChoice {
    <#
    .SYNOPSIS
        Pick any number of items from a list. Returns the zero-based indexes picked (none for Enter or
        Cancel).
    .DESCRIPTION
        - Console: a numbered list, then "1,3", "2-4", A for all, or Enter for none.
        - Window: a dialog with a tick box per item, Select all / Select none, and OK.
        Use this instead of Show-NmMenu whenever more than one answer is allowed: the window turns
        a numbered list into a single-choice dialog.
    .PARAMETER Items
        Objects with Label and optionally Detail (a second, grey line).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [string]$Note = '',
        [string]$OkLabel = 'OK',
        [switch]$AllChecked
    )
    $list = @($Items | Where-Object { $_ })
    if (-not $list.Count) { return @() }
    if ($script:NmGui -and $script:NmGui.Active) {
        return @(Show-NmGuiCheckList -Heading $Title -Note $Note -Items $list -OkLabel $OkLabel -AllChecked:$AllChecked)
    }
    Write-Host ''
    Write-Host $Title -ForegroundColor Yellow
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host ('   {0,3}. {1}' -f ($i + 1), $list[$i].Label) -ForegroundColor Cyan
        if ($list[$i].Detail) { Write-Host "        $($list[$i].Detail)" -ForegroundColor DarkGray }
    }
    if ($Note) { Write-Host $Note -ForegroundColor DarkGray }
    $pick = "$(Read-NmInput -Prompt 'Which? (numbers like 1,3 or 1-4, A for all, Enter for none)' -Default '')".Trim()
    if (-not $pick) { return @() }
    return @(ConvertFrom-NmPickList -Text $pick -Count $list.Count)
}

function Show-NmMenu {
    <#
    .SYNOPSIS
        Shows numbered options plus Q (Quit) or B (Back) on a clean screen and returns the key chosen,
        upper-cased. -NoClear keeps what is already on screen (for a menu under a table).
    .PARAMETER Options
        Objects or hashtables with Key and Label, and optionally Tag (shown in Yellow) and Detail (DarkGray).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Options,
        [switch]$Back,
        [string[]]$ExtraKeys = @(),
        [switch]$NoClear,
        [switch]$Clear   # kept for older callers; every menu clears now unless -NoClear
    )

    # On the way back to the main menu: leave without drawing.
    if ($Back -and $script:NmGoMain) { return 'B' }

    $exitKey   = if ($Back) { 'B' } else { 'Q' }
    $exitLabel = if ($Back) { 'Back' } else { 'Quit' }
    $mainKey   = $Back -and (Test-NmShowMainKey) -and (@($Options | Where-Object { "$($_.Key)".ToUpper() -eq 'M' }).Count -eq 0)
    $valid = @($Options | ForEach-Object { "$($_.Key)".ToUpper() }) + $exitKey + ($ExtraKeys | ForEach-Object { $_.ToUpper() })
    if ($mainKey) { $valid += 'M' }

    if ($NoClear) {
        # Under a table: a short divider instead of the full header.
        Write-Host $script:NmBorder -ForegroundColor Cyan
        Write-Host "   $Title" -ForegroundColor Yellow
        Write-Host $script:NmBorder -ForegroundColor Cyan
    } else {
        Show-NmHeader -Title $Title -Clear
    }
    foreach ($opt in $Options) {
        Write-Host ('   [{0}] {1}' -f $opt.Key, $opt.Label) -ForegroundColor Cyan -NoNewline
        if ($opt.Tag)    { Write-Host " $($opt.Tag)" -ForegroundColor Yellow -NoNewline }
        if ($opt.Detail) { Write-Host "  $($opt.Detail)" -ForegroundColor DarkGray -NoNewline }
        Write-Host ''
    }
    if ($mainKey) { Write-Host '   [M] Main menu' -ForegroundColor Red }
    Write-Host ('   [{0}] {1}' -f $exitKey, $exitLabel) -ForegroundColor Red
    Write-Host $script:NmBorder -ForegroundColor Cyan

    # Wrong keys re-ask on the same screen, so the message stays visible.
    while ($true) {
        Write-Host 'Select an option' -ForegroundColor Yellow -NoNewline
        $choice = "$(Read-NmHost -Prompt ' ')".Trim().ToUpper()
        if ($mainKey -and $choice -eq 'M') { $script:NmGoMain = $true; return 'B' }
        if ($valid -contains $choice) { return $choice }
        Write-Host "'$choice' is not an option." -ForegroundColor Red
    }
}

function Add-NmIndex {
    <#
    .SYNOPSIS
        Returns copies of the objects with a [#] column first, numbered from 1.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InputObject)

    $i = 0
    foreach ($item in $InputObject) {
        $i++
        $ordered = [ordered]@{ '#' = $i }
        foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Name -ne '#') { $ordered[$prop.Name] = $prop.Value }
        }
        [pscustomobject]$ordered
    }
}

function Show-NmResult {
    <#
    .SYNOPSIS
        Formatted table in the console (top N rows) and, optionally, Out-GridView beside it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [int]$Top = 50,
        [string[]]$Property,
        [switch]$GridView,
        [string]$Title = 'Results'
    )

    if (-not $Results -or $Results.Count -eq 0) {
        Write-NmLog 'No results.' -Level WARN
        return
    }

    $shown = $Results | Select-Object -First $Top
    $Property = @($Property | Where-Object { $_ })
    if ($Property.Count -gt 0) { $shown = $shown | Select-Object -Property (@('#') + $Property) }
    $shown | Format-Table -AutoSize -Wrap | Out-Host

    if ($Results.Count -gt $Top) {
        Write-Host "Showing top $Top of $($Results.Count). Export or open the grid view for all rows." -ForegroundColor DarkGray
    }

    if ($GridView) {
        if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
            $Results | Out-GridView -Title $Title
        } else {
            Write-NmLog 'Out-GridView is not available in this session.' -Level WARN
        }
    }
}

function Invoke-NmBulkRowAction {
    # [A] in the results menu: pick rows by number ("1,3,5-8" or A), then one of the tool's actions.
    param([object[]]$Results, [scriptblock]$BulkAction, [string[]]$BulkActions)
    $text = Read-NmInput -Prompt "Rows to act on (for example 1,3,5-8, or A for all $($Results.Count))"
    $idx = @(ConvertFrom-NmPickList -Text $text -Count $Results.Count)
    if (-not $idx.Count) { Write-Host 'No rows picked.' -ForegroundColor Red; Wait-NmKey; return }
    $i = 0
    $opts = @($BulkActions | ForEach-Object { $i++; [pscustomobject]@{ Key = "$i"; Label = $_; Tag = '[CHANGE]' } })
    $pick = Show-NmMenu -Title "$($idx.Count) row(s): what to do?" -Back -NoClear -Options $opts
    if ($pick -eq 'B') { return }
    $rows = @($idx | ForEach-Object { $Results[$_] })
    try { $null = & $BulkAction $BulkActions[[int]$pick - 1] $rows $Results } catch { Write-NmLog "Action failed: $($_.Exception.Message)" -Level ERROR }
    Wait-NmKey
}

function Show-NmResultMenu {
    <#
    .SYNOPSIS
        The Result Action Menu: Re-run, Export CSV/TXT, Grid view, Summary, deep-dive by [#], or Back.
        The deep-dive gets the chosen row and all results; the summary gets all results.
    .OUTPUTS
        'Rerun' or 'Back', so the caller decides what happens next.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$ToolId,
        [scriptblock]$DeepDive,
        [scriptblock]$Summary,
        [string[]]$Columns,
        [string]$Title = 'Results',
        [scriptblock]$BulkAction,
        [string[]]$BulkActions = @()
    )

    $showMain = Test-NmShowMainKey
    $redraw = $false
    while ($true) {
        if ($script:NmGoMain) { return 'Back' }
        if ($redraw) {
            # Back from a deep-dive or summary: one clean results screen again.
            Show-NmHeader -Title $Title -Clear
            Show-NmResult -Results $Results -Property $Columns -Title $Title
            $redraw = $false
        }
        Write-Host $script:NmBorder -ForegroundColor Cyan
        Write-Host "   $($Results.Count) result(s)" -ForegroundColor Cyan
        Write-Host '   [R] Re-run    [E] Export CSV    [T] Export TXT    [G] Grid view' -ForegroundColor Cyan
        if ($Summary -and $Results.Count -gt 0) {
            Write-Host '   [S] Summary' -ForegroundColor Cyan
        }
        if ($DeepDive -and $Results.Count -gt 0) {
            Write-Host "   [1-$($Results.Count)] Deep-dive into a row" -ForegroundColor Cyan
        }
        if ($BulkAction -and $Results.Count -gt 0) {
            Write-Host "   [A] Act on several rows ($($BulkActions -join ', '))" -ForegroundColor Cyan
        }
        if ($showMain) { Write-Host '   [M] Main menu' -ForegroundColor Red }
        Write-Host '   [B] Back' -ForegroundColor Red
        Write-Host $script:NmBorder -ForegroundColor Cyan

        Write-Host 'Select an option' -ForegroundColor Yellow -NoNewline
        $choice = "$(Read-NmHost -Prompt ' ')".Trim().ToUpper()
        if ($showMain -and $choice -eq 'M') { $script:NmGoMain = $true; return 'Back' }

        switch -Regex ($choice) {
            '^R$' { return 'Rerun' }
            '^E$' { $null = Export-NmResult -Data $Results -ToolId $ToolId -Format Csv }
            '^T$' { $null = Export-NmResult -Data $Results -ToolId $ToolId -Format Txt }
            '^G$' {
                if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
                    $Results | Out-GridView -Title $Title
                } else {
                    Write-NmLog 'Out-GridView is not available in this session.' -Level WARN
                }
            }
            '^S$' {
                if (-not $Summary) {
                    Write-Host 'This tool has no summary view.' -ForegroundColor Red
                } else {
                    try { & $Summary $Results } catch { Write-NmLog "Summary failed: $($_.Exception.Message)" -Level ERROR }
                    $redraw = $true
                }
            }
            '^B$' { return 'Back' }
            '^A$' {
                if (-not $BulkAction) { Write-Host 'This tool has no actions on several rows.' -ForegroundColor Red; break }
                Invoke-NmBulkRowAction -Results $Results -BulkAction $BulkAction -BulkActions $BulkActions
                $redraw = $true
            }
            '^\d+$' {
                $n = [int]$choice
                if (-not $DeepDive) {
                    Write-Host 'This tool has no deep-dive view.' -ForegroundColor Red
                } elseif ($n -lt 1 -or $n -gt $Results.Count) {
                    Write-Host "Pick a row from 1 to $($Results.Count)." -ForegroundColor Red
                } else {
                    try {
                        & $DeepDive $Results[$n - 1] $Results
                    } catch {
                        Write-NmLog "Deep-dive failed: $($_.Exception.Message)" -Level ERROR
                        Wait-NmKey
                    }
                    $redraw = $true
                }
            }
            default { Write-Host "'$choice' is not an option." -ForegroundColor Red }
        }
    }
}
