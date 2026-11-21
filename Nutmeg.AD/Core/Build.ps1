# ---------------------------------------------------------------------------
# Build.ps1 - the New Forest Build's state file and step runner
# ---------------------------------------------------------------------------
# The build runs across restarts, so what it has asked and done lives in one state file:
#   <DataRoot>\NewForest\State.json
# - Answers: what the technician typed (domain, names, IP...). Never a password.
# - Steps: each step's Status (Done / Failed), time and detail.
# - LogPath: the build's one log; every session until the build finishes writes to it.
# A step that is Done is skipped on the next run, so a build can be re-run after a failure or a
# restart and picks up where it stopped.
#
# One confirmation: the technician approves the whole plan once (the domain's short name typed);
# from then on Confirm-NmChange shows each change and goes ahead without asking (Set-NmPlanApproved).

$script:NmPlanApproved = $null   # the plan's name while a confirmed plan is running

function Get-NmBuildStatePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return (Join-Path (Join-Path $script:NmConfig.DataRoot 'NewForest') 'State.json')
}

function New-NmBuildState {
    [pscustomobject]@{
        Version  = $script:ModuleVersion
        Started  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Answers  = $null
        Steps    = [pscustomobject]@{}
        Finished = $null
        LogPath  = (Get-NmLogPath)   # the sessions after each restart carry on in this log
    }
}

function Get-NmBuildState {
    # The saved state, or $null when no build has started on this server.
    [CmdletBinding()]
    param()
    $p = Get-NmBuildStatePath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $raw = Get-Content -LiteralPath $p -Raw -ErrorAction Stop
    $s = ConvertFrom-Json -InputObject $raw
    if (-not $s.PSObject.Properties['Steps'] -or $null -eq $s.Steps) { $s | Add-Member -NotePropertyName Steps -NotePropertyValue ([pscustomobject]@{}) -Force }
    return $s
}

function Save-NmBuildState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $p = Get-NmBuildStatePath
    $dir = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $p -Encoding UTF8 -ErrorAction Stop
}

function Test-NmBuildStepDone {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Name)
    $p = $State.Steps.PSObject.Properties[$Name]
    return [bool]($p -and "$($p.Value.Status)" -eq 'Done')
}

function Set-NmBuildStep {
    # Records one step's outcome in the state and saves it.
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Name, [ValidateSet('Done', 'Failed')][string]$Status, [string]$Detail = '')
    $State.Steps | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{ Status = $Status; At = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Detail = $Detail }) -Force
    Save-NmBuildState -State $State
}

function Invoke-NmBuildStep {
    <#
    .SYNOPSIS
        Runs one build step unless it is already Done, records the outcome, and returns a row
        (Phase, Step, Result, Detail). A step that throws is recorded as Failed and stops the build.
    .PARAMETER Action
        Returns a short detail text on success. Throw to fail.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if (Test-NmBuildStepDone -State $State -Name $Name) {
        return [pscustomobject]@{ Phase = $Phase; Step = $Label; Result = 'Already done'; Detail = "$($State.Steps.$Name.Detail)" }
    }
    Write-NmLog "Build step: $Label" -Level INFO
    try {
        $detail = "$(& $Action)"
        Set-NmBuildStep -State $State -Name $Name -Status Done -Detail $detail
        Write-NmLog "Build step done: $Label - $detail" -Level SUCCESS -NoConsole
        Write-NmRunHistory -ToolId 'new-forest' -Kind Change -ItemCount 1 -Notes "$Label ($detail)"
        return [pscustomobject]@{ Phase = $Phase; Step = $Label; Result = 'Done'; Detail = $detail }
    } catch {
        $why = "$($_.Exception.Message)"
        Set-NmBuildStep -State $State -Name $Name -Status Failed -Detail $why
        Write-NmRunHistory -ToolId 'new-forest' -Kind Change -Result Failed -Notes "$Label ($why)"
        Write-NmLog "Build step failed: $Label - $why" -Level ERROR
        throw (New-Object System.InvalidOperationException("$Label failed: $why"))
    }
}

function Set-NmPlanApproved {
    # Turns the one-confirmation mode on (a plan name) or off ($null) for Confirm-NmChange.
    [CmdletBinding()]
    param([AllowNull()][string]$Plan)
    $script:NmPlanApproved = $Plan
}
