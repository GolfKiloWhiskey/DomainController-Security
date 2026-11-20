<#
.SYNOPSIS
    Interactively adds SCHANNEL protocol deprecation registry preferences
    (TLS 1.0, TLS 1.1, SSL 2.0, SSL 3.0) to a GPO via Registry.xml.

.PARAMETER Domain
    Target domain FQDN. Defaults to the current domain.

.PARAMETER GPOName
    Optional. If provided, skips interactive selection and uses this GPO directly.

.EXAMPLE
    .\Add-SCHANNELRegistryPrefs.ps1
    .\Add-SCHANNELRegistryPrefs.ps1 -GPOName "Security - SCHANNEL Hardening"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Domain   = $env:USERDNSDOMAIN,
    [string]$GPOName  = ""
)

#Requires -Modules GroupPolicy
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ══════════════════════════════════════════════════════════════════════════════
# DISPLAY HELPERS
# ══════════════════════════════════════════════════════════════════════════════

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        SCHANNEL GPO Registry Preference Manager         ║" -ForegroundColor Cyan
    Write-Host "  ║    TLS 1.0 / TLS 1.1 / SSL 2.0 / SSL 3.0 Deprecation   ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  Domain: $Domain" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-SectionHeader([string]$Title) {
    Write-Host ""
    Write-Host "  ── $Title " -ForegroundColor Yellow -NoNewline
    Write-Host ("─" * [Math]::Max(2, 54 - $Title.Length)) -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Success([string]$Msg) { Write-Host "  ✔  $Msg" -ForegroundColor Green  }
function Write-Info   ([string]$Msg) { Write-Host "  ℹ  $Msg" -ForegroundColor Cyan   }
function Write-Warn   ([string]$Msg) { Write-Host "  ⚠  $Msg" -ForegroundColor Yellow }
function Write-Skipped([string]$Msg) { Write-Host "  ↷  $Msg" -ForegroundColor DarkGray }

# ══════════════════════════════════════════════════════════════════════════════
# REGISTRY ENTRY DEFINITIONS
# ══════════════════════════════════════════════════════════════════════════════

$schannel = "SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"

$entries = @(
    @{ Protocol="TLS 1.0"; Role="Client"; Key="$schannel\TLS 1.0\Client"; Name="Enabled";           Value="00000000" }
    @{ Protocol="TLS 1.0"; Role="Client"; Key="$schannel\TLS 1.0\Client"; Name="DisabledByDefault"; Value="00000001" }
    @{ Protocol="TLS 1.0"; Role="Server"; Key="$schannel\TLS 1.0\Server"; Name="Enabled";           Value="00000000" }
    @{ Protocol="TLS 1.0"; Role="Server"; Key="$schannel\TLS 1.0\Server"; Name="DisabledByDefault"; Value="00000001" }

    @{ Protocol="TLS 1.1"; Role="Client"; Key="$schannel\TLS 1.1\Client"; Name="Enabled";           Value="00000000" }
    @{ Protocol="TLS 1.1"; Role="Client"; Key="$schannel\TLS 1.1\Client"; Name="DisabledByDefault"; Value="00000001" }
    @{ Protocol="TLS 1.1"; Role="Server"; Key="$schannel\TLS 1.1\Server"; Name="Enabled";           Value="00000000" }
    @{ Protocol="TLS 1.1"; Role="Server"; Key="$schannel\TLS 1.1\Server"; Name="DisabledByDefault"; Value="00000001" }

    @{ Protocol="SSL 2.0"; Role="Client"; Key="$schannel\SSL 2.0\Client"; Name="Enabled";           Value="00000000" }
    @{ Protocol="SSL 2.0"; Role="Client"; Key="$schannel\SSL 2.0\Client"; Name="DisabledByDefault"; Value="00000001" }
    @{ Protocol="SSL 2.0"; Role="Server"; Key="$schannel\SSL 2.0\Server"; Name="Enabled";           Value="00000000" }
    @{ Protocol="SSL 2.0"; Role="Server"; Key="$schannel\SSL 2.0\Server"; Name="DisabledByDefault"; Value="00000001" }

    @{ Protocol="SSL 3.0"; Role="Client"; Key="$schannel\SSL 3.0\Client"; Name="Enabled";           Value="00000000" }
    @{ Protocol="SSL 3.0"; Role="Client"; Key="$schannel\SSL 3.0\Client"; Name="DisabledByDefault"; Value="00000001" }
    @{ Protocol="SSL 3.0"; Role="Server"; Key="$schannel\SSL 3.0\Server"; Name="Enabled";           Value="00000000" }
    @{ Protocol="SSL 3.0"; Role="Server"; Key="$schannel\SSL 3.0\Server"; Name="DisabledByDefault"; Value="00000001" }
)

# ══════════════════════════════════════════════════════════════════════════════
# HELPER: Build a single <Registry> XML preference node
# ══════════════════════════════════════════════════════════════════════════════

function New-RegistryPrefNode {
    param([string]$Key, [string]$ValueName, [string]$HexValue)

    $uid     = "{$([guid]::NewGuid().ToString().ToUpper())}"
    $changed = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

    return "`t<Registry clsid=""{9CD4B2F4-923D-47f5-A062-E897DD1DAD50}"" name=""$ValueName"" status=""$ValueName"" image=""12"" changed=""$changed"" uid=""$uid""><Properties action=""U"" displayDecimal=""1"" default=""0"" hive=""HKEY_LOCAL_MACHINE"" key=""$Key"" name=""$ValueName"" type=""REG_DWORD"" value=""$HexValue""/></Registry>"
}

# ══════════════════════════════════════════════════════════════════════════════
# HELPER: Prompt user for a numbered menu selection
# ══════════════════════════════════════════════════════════════════════════════

function Invoke-MenuSelection {
    param(
        [string]  $Prompt,
        [string[]]$Options,
        [string[]]$ExtraOptions = @()   # Non-numbered options appended at the bottom
    )

    Write-Host "  $Prompt" -ForegroundColor White
    Write-Host ""

    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host ("  [{0,2}]  {1}" -f ($i + 1), $Options[$i]) -ForegroundColor White
    }

    if ($ExtraOptions.Count -gt 0) {
        Write-Host ""
        foreach ($opt in $ExtraOptions) {
            Write-Host "  $opt" -ForegroundColor DarkCyan
        }
    }

    Write-Host ""
    $max = $Options.Count

    do {
        $raw = Read-Host "  Enter selection"
        if ($raw -match '^\d+$') {
            $sel = [int]$raw
            if ($sel -ge 1 -and $sel -le $max) { return $sel }
        }
        # Check extra option keys (e.g. "N", "S", "Q")
        foreach ($opt in $ExtraOptions) {
            if ($opt -match '^\[([A-Za-z])\]' -and $raw -ieq $Matches[1]) {
                return $raw.ToUpper()
            }
        }
        Write-Warn "Invalid selection — enter a number between 1 and $max$(if ($ExtraOptions) { ' (or a letter option)' })."
    } while ($true)
}

# ══════════════════════════════════════════════════════════════════════════════
# HELPER: Confirm before proceeding
# ══════════════════════════════════════════════════════════════════════════════

function Confirm-Action([string]$Message) {
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor Yellow
    $ans = Read-Host "  Proceed? [Y/N]"
    return ($ans -imatch '^y')
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1 — GPO SELECTION
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner

$selectedGPO = $null

if ($GPOName -ne "") {
    # ── Non-interactive mode: GPOName passed as parameter ──────────────────
    Write-Info "GPO name provided via parameter: '$GPOName'"
    try {
        $selectedGPO = Get-GPO -Name $GPOName -Domain $Domain
        Write-Success "Found GPO: '$($selectedGPO.DisplayName)'"
    } catch {
        Write-Warn "GPO '$GPOName' not found."
        if (Confirm-Action "Would you like to CREATE a new GPO named '$GPOName'?") {
            $selectedGPO = New-GPO -Name $GPOName -Domain $Domain
            Write-Success "Created new GPO: '$GPOName'"
        } else {
            Write-Host "  Aborted." -ForegroundColor Red
            exit 0
        }
    }

} else {
    # ── Interactive mode ────────────────────────────────────────────────────
    Write-SectionHeader "GPO Selection"

    # Sub-menu: how does the user want to find their GPO?
    $modeChoice = Invoke-MenuSelection `
        -Prompt  "How would you like to select the target GPO?" `
        -Options @(
            "Type a GPO name (exact match or partial search)",
            "Browse all GPOs and pick from a list",
            "Create a brand-new GPO"
        )

    switch ($modeChoice) {

        # ── Option 1: Name search ──────────────────────────────────────────
        1 {
            Write-Host ""
            $searchTerm = Read-Host "  Enter GPO name (or partial name to search)"

            Write-Info "Searching for GPOs matching '$searchTerm'..."
            $allGPOs = Get-GPO -All -Domain $Domain | Where-Object { $_.DisplayName -ilike "*$searchTerm*" } | Sort-Object DisplayName

            if ($allGPOs.Count -eq 0) {
                Write-Warn "No GPOs found matching '$searchTerm'."
                Write-Host ""

                $fallback = Invoke-MenuSelection `
                    -Prompt  "What would you like to do?" `
                    -Options @(
                        "Search again with a different name",
                        "Browse all GPOs",
                        "Create a new GPO named '$searchTerm'",
                        "Exit"
                    )

                switch ($fallback) {
                    1 { & $PSCommandPath -Domain $Domain; exit }  # restart
                    2 { $modeChoice = 2 }                         # fall through to browse
                    3 {
                        $newName = $searchTerm
                        if (Confirm-Action "Create new GPO: '$newName'?") {
                            $selectedGPO = New-GPO -Name $newName -Domain $Domain
                            Write-Success "Created GPO: '$newName'"
                        } else { exit 0 }
                    }
                    4 { exit 0 }
                }

            } elseif ($allGPOs.Count -eq 1) {
                $selectedGPO = $allGPOs[0]
                Write-Success "Unique match found: '$($selectedGPO.DisplayName)'"

            } else {
                Write-Host ""
                Write-Info "$($allGPOs.Count) GPOs matched. Select one:"
                $pick = Invoke-MenuSelection `
                    -Prompt  "Matching GPOs:" `
                    -Options ($allGPOs | ForEach-Object { $_.DisplayName }) `
                    -ExtraOptions @("[N]  None — create a new GPO instead")

                if ($pick -eq 'N') { $modeChoice = 3 }
                else { $selectedGPO = $allGPOs[$pick - 1] }
            }
        }

        # ── Option 2: Browse all GPOs ──────────────────────────────────────
        2 {
            Write-Info "Retrieving all GPOs from '$Domain'..."
            $allGPOs = Get-GPO -All -Domain $Domain | Sort-Object DisplayName

            if ($allGPOs.Count -eq 0) {
                Write-Warn "No GPOs found in domain '$Domain'. Switching to create mode."
                $modeChoice = 3
            } else {
                Write-Host ""
                # Paginate if there are many GPOs
                $pageSize  = 20
                $page      = 0
                $totalPages = [Math]::Ceiling($allGPOs.Count / $pageSize)

                do {
                    $start   = $page * $pageSize
                    $end     = [Math]::Min($start + $pageSize, $allGPOs.Count) - 1
                    $pageGPOs = $allGPOs[$start..$end]

                    Write-Host ("  Showing {0}–{1} of {2} GPOs  (Page {3}/{4})" -f
                        ($start+1), ($end+1), $allGPOs.Count, ($page+1), $totalPages) -ForegroundColor DarkGray
                    Write-Host ""

                    $extraOpts = @("[N]  None — create a new GPO instead")
                    if ($page -lt $totalPages - 1) { $extraOpts += "[M]  More (next page)" }
                    if ($page -gt 0)               { $extraOpts += "[B]  Back (previous page)" }

                    $pick = Invoke-MenuSelection `
                        -Prompt  "Select a GPO:" `
                        -Options ($pageGPOs | ForEach-Object { $_.DisplayName }) `
                        -ExtraOptions $extraOpts

                    if     ($pick -eq 'N') { $modeChoice = 3; break }
                    elseif ($pick -eq 'M') { $page++; Clear-Host; Write-Banner }
                    elseif ($pick -eq 'B') { $page--; Clear-Host; Write-Banner }
                    else {
                        $selectedGPO = $pageGPOs[$pick - 1]
                        break
                    }
                } while ($true)
            }
        }
    }

    # ── Option 3: Create new GPO ───────────────────────────────────────────
    if ($modeChoice -eq 3 -and -not $selectedGPO) {
        Write-Host ""
        $newName = Read-Host "  Enter a name for the new GPO"
        if ([string]::IsNullOrWhiteSpace($newName)) {
            Write-Warn "No name entered. Exiting."
            exit 0
        }

        # Check it doesn't already exist
        $existing = Get-GPO -All -Domain $Domain | Where-Object { $_.DisplayName -ieq $newName }
        if ($existing) {
            Write-Warn "A GPO named '$newName' already exists."
            $useExisting = Invoke-MenuSelection `
                -Prompt  "What would you like to do?" `
                -Options @("Use the existing GPO '$newName'", "Exit without making changes")
            if ($useExisting -eq 1) { $selectedGPO = $existing }
            else                    { exit 0 }
        } else {
            if (Confirm-Action "Create new GPO: '$newName' in domain '$Domain'?") {
                $selectedGPO = New-GPO -Name $newName -Domain $Domain
                Write-Success "Created GPO: '$newName'"
            } else { exit 0 }
        }
    }
}

if (-not $selectedGPO) {
    Write-Warn "No GPO selected. Exiting."
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2 — CONFIRM SELECTION & SHOW SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

Write-Banner
Write-SectionHeader "Summary"

$gpoId      = $selectedGPO.Id.ToString().ToUpper()
$sysvolBase = "\\$Domain\SYSVOL\$Domain\Policies\{$gpoId}\Machine\Preferences\Registry"
$xmlPath    = Join-Path $sysvolBase "Registry.xml"
$xmlExists  = Test-Path $xmlPath

Write-Host "  GPO Name  : $($selectedGPO.DisplayName)" -ForegroundColor White
Write-Host "  GPO GUID  : {$gpoId}"                    -ForegroundColor DarkGray
Write-Host "  Domain    : $Domain"                     -ForegroundColor DarkGray
Write-Host "  XML Path  : $xmlPath"                    -ForegroundColor DarkGray
Write-Host "  XML Status: $(if ($xmlExists) { 'Exists — will merge' } else { 'Not found — will create' })" -ForegroundColor $(if ($xmlExists) { 'Yellow' } else { 'Cyan' })
Write-Host ""
Write-Host "  Entries to add:" -ForegroundColor White
Write-Host ""

$groups = $entries | Group-Object Protocol
foreach ($g in $groups) {
    Write-Host ("  {0,-10}  Client/Server  Enabled=0, DisabledByDefault=1" -f $g.Name) -ForegroundColor Gray
}
Write-Host ""

if (-not (Confirm-Action "Apply these $($entries.Count) registry preferences to '$($selectedGPO.DisplayName)'?")) {
    Write-Host "  Aborted — no changes made." -ForegroundColor Red
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3 — WRITE REGISTRY.XML
# ══════════════════════════════════════════════════════════════════════════════

Write-SectionHeader "Applying Changes"

if ($PSCmdlet.ShouldProcess($xmlPath, "Write SCHANNEL registry preferences")) {

    if ($xmlExists) {
        $raw = Get-Content -Path $xmlPath -Raw -Encoding UTF8
        [xml]$xml = $raw

        $existingKeys = $xml.RegistrySettings.Registry | ForEach-Object {
            "$($_.Properties.key)|$($_.Properties.name)"
        }

        $toAdd   = [System.Collections.Generic.List[string]]::new()
        $skipped = 0

        foreach ($e in $entries) {
            $token = "$($e.Key)|$($e.Name)"
            if ($existingKeys -contains $token) {
                Write-Skipped "Already present: $($e.Protocol) $($e.Role) → $($e.Name)"
                $skipped++
            } else {
                $toAdd.Add((New-RegistryPrefNode -Key $e.Key -ValueName $e.Name -HexValue $e.Value))
                Write-Success "Queued:          $($e.Protocol) $($e.Role) → $($e.Name)"
            }
        }

        if ($toAdd.Count -gt 0) {
            $updated = $raw -replace '</RegistrySettings>', "$($toAdd -join "`n")`n</RegistrySettings>"
            [System.IO.File]::WriteAllText($xmlPath, $updated, [System.Text.Encoding]::UTF8)
            Write-Host ""
            Write-Success "$($toAdd.Count) entries added   |   $skipped skipped (already present)"
        } else {
            Write-Host ""
            Write-Info "All $($entries.Count) entries already exist in this GPO — nothing to do."
            exit 0
        }

    } else {
        if (-not (Test-Path $sysvolBase)) {
            New-Item -ItemType Directory -Path $sysvolBase -Force | Out-Null
        }

        $nodes = ($entries | ForEach-Object {
            New-RegistryPrefNode -Key $_.Key -ValueName $_.Name -HexValue $_.Value
        }) -join "`n"

        $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<RegistrySettings clsid="{A3CCFC41-DFDB-43a5-8D26-0FE8B954DA51}">
$nodes
</RegistrySettings>
"@
        [System.IO.File]::WriteAllText($xmlPath, $xmlContent, [System.Text.Encoding]::UTF8)
        Write-Success "Registry.xml created with $($entries.Count) entries."
    }

    # ── Update gpcMachineExtensionNames (required for GPMC visibility + client processing) ──
    Write-Host ""
    Write-Info "Updating GPO extension GUIDs in Active Directory..."

    $csePair    = "[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]"
    $dcPath     = "LDAP://CN={$gpoId},CN=Policies,CN=System,DC=$($Domain.Replace('.',',DC='))"
    $gpoAD      = [adsi]$dcPath

    $currentExt = [string]$gpoAD.gpcMachineExtensionNames
    if ($currentExt -notlike "*35378EAC*") {
        # Append to existing extensions, or set fresh if empty
        $newExt = if ([string]::IsNullOrWhiteSpace($currentExt)) {
            $csePair
        } else {
            # Insert in GUID-sorted order as GPMC expects
            ($currentExt + $csePair) -replace '\]\[', ']['
        }
        $gpoAD.gpcMachineExtensionNames = $newExt
        Write-Success "gpcMachineExtensionNames updated."
    } else {
        Write-Skipped "gpcMachineExtensionNames already contains Registry CSE GUID."
    }

    # ── Increment GPO version counter ─────────────────────────────────────
    Write-Info "Incrementing GPO version counter..."

    $curVer  = [int]$gpoAD.versionNumber[0]
    $userVer = ($curVer -shr 16) -band 0xFFFF
    $compVer = ($curVer -band 0xFFFF) + 1
    $newVer  = ($userVer -shl 16) -bor $compVer
    $gpoAD.versionNumber = $newVer

    $gpoAD.CommitChanges()
    Write-Success "AD object updated. Version: $curVer → $newVer"

    # ── Sync version into GPT.INI ──────────────────────────────────────────
    $gptIniPath = "\\$Domain\SYSVOL\$Domain\Policies\{$gpoId}\GPT.INI"
    if (Test-Path $gptIniPath) {
        $ini = Get-Content $gptIniPath -Raw
        $ini = [regex]::Replace($ini, '(?i)(Version\s*=\s*)\d+', "`${1}$newVer")
        [System.IO.File]::WriteAllText($gptIniPath, $ini, [System.Text.Encoding]::ASCII)
        Write-Success "GPT.INI version synced."
    } else {
        Write-Warn "GPT.INI not found at $gptIniPath — version not synced to SYSVOL."
    }

    # ══════════════════════════════════════════════════════════════════════════
    # DONE
    # ══════════════════════════════════════════════════════════════════════════
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                    ✔  Complete!                         ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  GPO '$($selectedGPO.DisplayName)' has been updated." -ForegroundColor White
    Write-Host "  Run " -NoNewline
    Write-Host "gpupdate /force" -ForegroundColor Cyan -NoNewline
    Write-Host " on target machines, or wait for background policy refresh." -ForegroundColor White
    Write-Host ""
}