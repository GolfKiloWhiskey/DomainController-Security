# ---------------------------------------------------------------------------
# Steps.ps1 - a live list of a long run's steps (the New Forest Build, later the baselines)
# ---------------------------------------------------------------------------
# A tool that runs several steps starts a list (Start-NmStepList), marks each step Running, Done or
# Failed (Set-NmStepStatus), and passes on what a long step reports (Write-NmStepProgress).
# - The window draws the list above the results and redraws it as it changes (Gui.ps1).
# - The console prints a line when a step finishes; progress goes to the log, once per change.
# Everything here is plain data (no WPF), so it is tested anywhere.

$script:NmSteps = $null

function Start-NmStepList {
    <#
    .SYNOPSIS
        Starts the step list for a run. -Steps: hashtables or objects with Name, Label, and optionally
        Group (a heading, such as the phase), Status ('Done' for a step finished earlier) and Detail.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Title, [Parameter(Mandatory)][object[]]$Steps)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($s in $Steps) {
        $st = "$($s.Status)"
        $items.Add([pscustomobject]@{
            Name = "$($s.Name)"; Label = "$($s.Label)"; Group = "$($s.Group)"
            Status = $(if ($st) { $st } else { 'Waiting' }); Detail = "$($s.Detail)"
            Progress = ''; Percent = -1; Started = $null; Finished = $null; Earlier = ($st -eq 'Done')
        })
    }
    $script:NmSteps = [pscustomobject]@{ Title = $Title; Started = (Get-NmNow); Items = $items; LastLogged = @{} }
    Update-NmStepView
}

function Get-NmStepItem {
    param([string]$Name)
    if (-not $script:NmSteps) { return $null }
    return @($script:NmSteps.Items | Where-Object { $_.Name -eq $Name })[0]
}

function Format-NmStepTime {
    # "48 s", "6 min 15 s", "1 h 2 min".
    param([timespan]$Span)
    if ($Span.TotalSeconds -lt 60) { return "$([int][Math]::Floor($Span.TotalSeconds)) s" }
    if ($Span.TotalMinutes -lt 60) { return "$([int][Math]::Floor($Span.TotalMinutes)) min $($Span.Seconds) s" }
    return "$([int][Math]::Floor($Span.TotalHours)) h $($Span.Minutes) min"
}

function Set-NmStepStatus {
    <#
    .SYNOPSIS
        Marks a step Running, Done, Failed or Skipped. Done and Failed print a line in the console
        (the window shows the list instead). Nothing happens when no list is running.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [ValidateSet('Waiting', 'Running', 'Done', 'Failed', 'Skipped')][string]$Status, [string]$Detail)
    $it = Get-NmStepItem -Name $Name
    if (-not $it) { return }
    $now = Get-NmNow
    if ($Status -eq 'Running') { $it.Started = $now; $it.Finished = $null; $it.Progress = ''; $it.Percent = -1; $it.Earlier = $false }
    if ($Status -in 'Done', 'Failed', 'Skipped') { $it.Finished = $now; $it.Progress = ''; $it.Percent = -1 }
    $it.Status = $Status
    if ($PSBoundParameters.ContainsKey('Detail')) { $it.Detail = $Detail }
    $inWindow = [bool]($script:NmGui -and $script:NmGui.Active)
    if (-not $inWindow -and $Status -in 'Done', 'Failed') {
        $took = if ($it.Started) { " ($(Format-NmStepTime -Span ($now - $it.Started)))" } else { '' }
        $mark = if ($Status -eq 'Done') { '[done]' } else { '[FAILED]' }
        Write-Host "  $mark $($it.Label)$(if ($it.Detail) { ": $($it.Detail)" })$took" -ForegroundColor $(if ($Status -eq 'Done') { 'Green' } else { 'Red' })
    }
    Update-NmStepView
}

function Get-NmRunningStep {
    # The step running now, or $null.
    if (-not $script:NmSteps) { return $null }
    return @($script:NmSteps.Items | Where-Object { $_.Status -eq 'Running' })[-1]
}

function Write-NmStepProgress {
    <#
    .SYNOPSIS
        What a long step reports while it runs ("Configuring the DNS Server service", 40 %): shown
        under the running step, and written to the log once each time it changes (the percent in
        tens), so the log has no gap and no flood.
    #>
    [CmdletBinding()]
    param([string]$Text, [int]$Percent = -1)
    $it = Get-NmRunningStep
    $Text = "$Text".Trim()
    if ($it) { $it.Progress = $Text; $it.Percent = $Percent }
    $bucket = if ($Percent -ge 0) { [int]([Math]::Floor($Percent / 10) * 10) } else { -1 }
    $key = "$Text|$bucket"
    $name = if ($it) { $it.Name } else { '' }
    $logged = if ($script:NmSteps) { $script:NmSteps.LastLogged } else { @{} }
    if (($Text -or $Percent -ge 0) -and "$($logged[$name])" -ne $key) {
        $logged[$name] = $key
        $label = if ($it) { "$($it.Label): " } else { '' }
        Write-NmLog "$label$Text$(if ($Percent -ge 0) { " ($Percent %)" })" -Level INFO -NoConsole
    }
    Update-NmStepView
}

function Get-NmStepListModel {
    <#
    .SYNOPSIS
        What the step list shows (no WPF): Title, a Summary ("3 of 10 done", the running time), and
        Rows: group headings and steps, each with Mark (Done, Running, Failed, Waiting, Skipped),
        Label, Detail, Progress and Time ("6 min 15 s" when done, "0:48" while running).
    #>
    [CmdletBinding()]
    param([datetime]$Now = (Get-NmNow))
    $l = $script:NmSteps
    if (-not $l) { return $null }
    $rows = New-Object System.Collections.Generic.List[object]
    $group = $null
    foreach ($it in $l.Items) {
        if ($it.Group -and $it.Group -ne $group) {
            $group = $it.Group
            $rows.Add([pscustomobject]@{ Kind = 'Group'; Label = $group; Mark = ''; Detail = ''; Progress = ''; Time = '' })
        }
        $time = ''
        if ($it.Status -eq 'Running' -and $it.Started) { $sp = $Now - $it.Started; $time = '{0}:{1:00}' -f [int][Math]::Floor($sp.TotalMinutes), $sp.Seconds }
        elseif ($it.Started -and $it.Finished) { $time = Format-NmStepTime -Span ($it.Finished - $it.Started) }
        elseif ($it.Earlier) { $time = 'earlier' }
        $prog = $it.Progress
        if ($it.Percent -ge 0) { $prog = "$(if ($prog) { "$prog  " })$($it.Percent) %" }
        $rows.Add([pscustomobject]@{ Kind = 'Step'; Label = $it.Label; Mark = $it.Status; Detail = $it.Detail; Progress = $prog; Time = $time })
    }
    $done = @($l.Items | Where-Object Status -eq 'Done').Count
    $failed = @($l.Items | Where-Object Status -eq 'Failed').Count
    $running = Get-NmRunningStep
    $state = if ($failed) { 'stopped' } elseif ($running) { 'running' } elseif ($done -eq $l.Items.Count) { 'finished' } else { 'waiting' }
    [pscustomobject]@{
        Title   = $l.Title
        State   = $state
        Summary = "$done of $($l.Items.Count) done"
        Rows    = $rows.ToArray()
    }
}

function Update-NmStepView {
    # Redraws the list in the window, when it is open (Update-NmGuiSteps is in Gui.ps1).
    if ($script:NmGui -and $script:NmGui.Active -and (Get-Command -Name Update-NmGuiSteps -ErrorAction SilentlyContinue)) {
        try { Update-NmGuiSteps } catch { $null = $_ }
    }
}

function Stop-NmStepList {
    # Ends the list (the window keeps showing it until another tool is picked).
    $script:NmSteps = $null
}
