# ---------------------------------------------------------------------------
# Safety.ps1 - confirmation and dry run for every tool that changes something
# ---------------------------------------------------------------------------

function Get-NmConfirmWord {
    # The word typed to confirm a domain-wide or bulk change: the first label of the domain's DNS
    # name (clientx for clientx.local), or CONFIRM when no domain is known yet.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $domain = "$((Get-NmSession).Domain)"
    if ($domain) { return ($domain -split '\.')[0] }
    return 'CONFIRM'
}

function Confirm-NmChange {
    <#
    .SYNOPSIS
        Shows what a change will do and asks before it happens.
    .DESCRIPTION
        - Lists the action, the domain, the DC it goes to and up to 10 targets.
        - With -WhatIf, prints what would happen, logs it and returns $false.
        - Up to BulkConfirmCount targets: a Y/N prompt.
        - More than that, -DomainWide (a change to the whole domain or forest, a GPO linked at the
          domain root) or -RequireTyped (destructive or hard to undo): the domain's short name must
          be typed (-ConfirmWord sets another word, for a domain that does not exist yet).
        - While a confirmed plan runs (Set-NmPlanApproved), the change is shown and goes ahead
          without asking: the technician approved it with the plan.
        - In the window, the same choice is one approval dialog (Read-NmGuiConfirm): the change, the
          domain and DC, every target, and the box for the word or Approve / Cancel.
    .OUTPUTS
        $true to go ahead, $false to stop.
    .EXAMPLE
        if (Confirm-NmChange -Action 'Create OU' -Targets $paths -WhatIf:$WhatIf) { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [AllowEmptyCollection()][object[]]$Targets = @(),
        [switch]$DomainWide,
        [switch]$RequireTyped,
        [string]$ConfirmWord,
        [switch]$WhatIf
    )

    $session = Get-NmSession
    $count   = @($Targets).Count
    $domain  = if ($session.Domain) { $session.Domain } else { 'no domain' }

    $inWindow = [bool]($script:NmGui -and $script:NmGui.Active)
    if (-not $inWindow) {
        Write-Host $script:NmBorder -ForegroundColor Yellow
        Write-Host "   CHANGE: $Action" -ForegroundColor Yellow
        Write-Host "   Domain: $domain" -ForegroundColor Yellow
        if ($session.Server) { Write-Host "   DC:     $($session.Server)" -ForegroundColor Yellow }
        if ($DomainWide) {
            Write-Host '   Scope:  domain-wide' -ForegroundColor Yellow
        } else {
            Write-Host "   Scope:  $count object(s)" -ForegroundColor Yellow
        }
        foreach ($t in (@($Targets) | Select-Object -First 10)) {
            Write-Host "     - $t" -ForegroundColor DarkGray
        }
        if ($count -gt 10) { Write-Host "     ... and $($count - 10) more" -ForegroundColor DarkGray }
        Write-Host $script:NmBorder -ForegroundColor Yellow
    }

    if ($WhatIf) {
        Write-NmLog "WhatIf: would run '$Action' on $(if ($DomainWide) { 'the whole domain' } else { "$count object(s)" }) in $domain." -Level WARN
        return $false
    }

    if ($script:NmPlanApproved) {
        Write-NmLog "Approved with the plan '$script:NmPlanApproved': $Action ($domain)" -Level INFO -NoConsole
        return $true
    }

    $needsTyped = $DomainWide -or $RequireTyped -or ($count -gt $script:NmConfig.BulkConfirmCount)
    $expected = ''
    $kind = ''
    if ($needsTyped) {
        $expected = if ($ConfirmWord) { $ConfirmWord } else { Get-NmConfirmWord }
        $kind = if ($RequireTyped -and -not $DomainWide -and $count -le $script:NmConfig.BulkConfirmCount) { 'This change is hard to undo' } elseif ($DomainWide) { 'This changes the whole domain' } else { 'This is a bulk change' }
    }
    if ($inWindow) {
        # The window: one approval dialog with the change, every target and the word to type.
        $ok = Read-NmGuiConfirm -Action $Action -Domain $domain -Server "$($session.Server)" -DomainWide:$DomainWide -Targets @($Targets) -Expected $expected -Kind $kind
    } elseif ($needsTyped) {
        Write-Host "$kind. Type '$expected' to continue, or anything else to cancel" -ForegroundColor Yellow -NoNewline
        $typed = "$(Read-NmHost -Prompt ' ')".Trim()
        $ok = ($typed -eq $expected)
    } else {
        $ok = Read-NmYesNo -Prompt 'Proceed with this change?' -Default 'N'
    }

    if ($ok) {
        Write-NmLog "Confirmed: $Action ($domain)" -Level INFO -NoConsole
    } else {
        Write-NmLog "Cancelled: $Action" -Level WARN
    }
    return $ok
}
