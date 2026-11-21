# ---------------------------------------------------------------------------
# Modules.ps1 - the Windows modules each service needs, checked and imported
# ---------------------------------------------------------------------------
# ActiveDirectory and GroupPolicy come with Windows Server features (RSAT), not the PowerShell
# Gallery, so they are never installed with Install-Module. A DC has both; elsewhere the hint
# names the feature to add.
#
# PowerShell 7 (Microsoft's module compatibility list):
# - ActiveDirectory is natively compatible.
# - GroupPolicy is not marked compatible, so in PowerShell 7 it is imported with -UseWindowsPowerShell
#   and runs in a Windows PowerShell 5.1 process behind the scenes. Objects come back deserialized:
#   read their properties, never call their methods.

$script:NmServiceModules = [ordered]@{
    AD  = @{ Name = 'ActiveDirectory'; Feature = 'RSAT-AD-PowerShell'; Label = 'Active Directory'; WindowsPowerShell = $false }
    GPO = @{ Name = 'GroupPolicy';     Feature = 'GPMC';               Label = 'Group Policy';     WindowsPowerShell = $true }
}

function Find-NmModule {
    # The newest installed copy of a module, or $null. One place, so tests can stand in for it.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    return (Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1)
}

function Test-NmModuleLoaded {
    # True when the module (or its Windows PowerShell proxy) is already in this session.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Module -Name $Name -ErrorAction SilentlyContinue)
}

function Import-NmModule {
    # Imports a module, through Windows PowerShell when asked (PowerShell 7 on Windows only).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [switch]$WindowsPowerShell)
    $viaWinPS = $WindowsPowerShell -and $PSVersionTable.PSVersion.Major -ge 6 -and $script:NmOnWindows
    if ($viaWinPS) {
        Import-Module -Name $Name -UseWindowsPowerShell -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
    } else {
        Import-Module -Name $Name -DisableNameChecking -ErrorAction Stop
    }
}

function Assert-NmModule {
    <#
    .SYNOPSIS
        Makes sure a Windows module is installed and imported. Never installs anything.
    .OUTPUTS
        $true when the module is ready, $false when it is missing or would not import.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Feature,
        [switch]$WindowsPowerShell
    )
    if (Test-NmModuleLoaded -Name $Name) { return $true }
    if (-not (Find-NmModule -Name $Name)) {
        $hint = if ($Feature) { " Add it with: Install-WindowsFeature $Feature (a DC already has it)." } else { '' }
        Write-NmLog "The $Name module is not installed on this computer.$hint" -Level ERROR
        return $false
    }
    try {
        Import-NmModule -Name $Name -WindowsPowerShell:$WindowsPowerShell
        Write-NmLog "Loaded the $Name module$(if ($WindowsPowerShell -and $PSVersionTable.PSVersion.Major -ge 6) { ' (through Windows PowerShell)' })." -Level INFO -NoConsole
        return $true
    } catch {
        Write-NmLog "Could not load the $Name module: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Assert-NmServiceModule {
    # Prepares the modules for a list of services, in a fixed order.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Services)
    $ok = $true
    foreach ($svc in $script:NmServiceModules.Keys) {
        if ($Services -notcontains $svc) { continue }
        $m = $script:NmServiceModules[$svc]
        if (-not (Assert-NmModule -Name $m.Name -Feature $m.Feature -WindowsPowerShell:([bool]$m.WindowsPowerShell))) { $ok = $false }
    }
    return $ok
}
