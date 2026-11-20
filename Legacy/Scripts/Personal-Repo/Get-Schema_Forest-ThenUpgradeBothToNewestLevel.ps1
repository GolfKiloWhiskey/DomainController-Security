<#
#.Created on: June 12, 2024
#.Author: Cliff Waite
#.Email: cliff.ps@nutmegtech.com

This script assesses the current Active Directory forest and schema versions and determines potential upgrade paths based on the available schema version. 
It provides informative output and prompts for user confirmation before performing upgrades.

.Synopsis
This script, ADForestUpgradeAssessment.ps1, utilizes the Active Directory module to assess the current forest and schema versions in your Active Directory domain. 
It leverages a predefined mapping to translate schema version numbers to corresponding Windows Server versions. 
Based on the schema version, the script identifies potential forest functional level upgrades and displays the highest achievable level. 
It provides options to upgrade the schema (if a newer version is available) and the forest functional level (with user confirmation).

.Important Notes
This script requires the Active Directory module to be imported before execution.
Upgrading the schema or forest functional level can have significant impacts on your Active Directory environment. It's crucial to thoroughly test the upgrade process in a non-production environment before proceeding in production.
Ensure you have the necessary administrative privileges (Schema Admin for schema upgrade and Enterprise Admin for forest functional level upgrade) before running the script.

.Example
Scenario: You want to assess potential upgrade paths for your Active Directory forest and schema.

Steps:
Import the Active Directory module (if not already loaded): Import-Module ActiveDirectory
Save the script as a .ps1 file (e.g., ADForestUpgradeAssessment.ps1).
Run the script with elevated privileges (Run as administrator).
Follow the on-screen prompts to confirm any potential upgrade actions.

Output:
The script displays the current forest functional level and schema version.
It identifies the highest available schema version based on the existing schema.
If the schema version is lower than the highest available, the script prompts for user confirmation before upgrading.
The script lists potential forest functional level upgrades based on the schema version.
It prompts for user confirmation before performing the forest functional level upgrade.
The script displays success messages after successful upgrades or informs you of any encountered errors.

Additional Notes:
The script includes placeholders for comments within the schema upgrade logic to potentially add specific pre-upgrade checks or warnings.
This script is intended to be a starting point for assessing potential Active Directory forest and schema upgrades. 
It's recommended to consult official Microsoft documentation and plan thoroughly before implementing any upgrades in a production environment.
#>

# Requires Active Directory Module
Import-Module ActiveDirectory

# Get Current Forest and Schema Information
$forest = Get-ADForest
$schema = (Get-ADObject (Get-ADRootDSE).schemaNamingContext -Property objectVersion).objectVersion

# Display Current Levels/Versions
Write-Host "Current Forest Functional Level: $($forest.ForestMode)" -ForegroundColor Green
Write-Host "Current Schema Version: $schema" -ForegroundColor Green

# Define Schema Version Mapping (Up to Windows Server 2022)
$schemaVersionMap = @{
    13 = "Windows Server 2000"
    30 = "Windows Server 2003"
    31 = "Windows Server 2003 R2"
    44 = "Windows Server 2008"
    47 = "Windows Server 2008 R2"
    56 = "Windows Server 2012"
    69 = "Windows Server 2012 R2"
    87 = "Windows Server 2016"
    88 = "Windows Server 2019, Windows Server 2022"  
    # New Schema version for Windows Server 2025 to be released. No releases as of 06/13/2024
}

# Determine Highest Available Schema Version
$latestSchemaVersion = $schemaVersionMap.Keys | Sort-Object -Descending | Select-Object -First 1

# Determine Possible Forest Upgrades based on Schema
$possibleForestUpgrades = Switch ($forest.ForestMode) {
    "Windows2000Forest"  { if ($latestSchemaVersion -ge 88) { "Windows2003Forest", "Windows2008Forest", "Windows2008R2Forest", "Windows2012Forest", "Windows2012R2Forest", "Windows2016Forest" } }  # Up to Windows2016Forest
    "Windows2003Forest"  { if ($latestSchemaVersion -ge 88) { "Windows2008Forest", "Windows2008R2Forest", "Windows2012Forest", "Windows2012R2Forest", "Windows2016Forest" } }  # Up to Windows2016Forest
    "Windows2008Forest"  { if ($latestSchemaVersion -ge 88) { "Windows2008R2Forest", "Windows2012Forest", "Windows2012R2Forest", "Windows2016Forest" } }  # Up to Windows2016Forest
    "Windows2008R2Forest" { if ($latestSchemaVersion -ge 88) { "Windows2012Forest", "Windows2012R2Forest", "Windows2016Forest" } }  # Up to Windows2016Forest
    "Windows2012Forest"   { if ($latestSchemaVersion -ge 88) { "Windows2012R2Forest", "Windows2016Forest" } }  # Up to Windows2016Forest
    "Windows2012R2Forest" { if ($latestSchemaVersion -ge 88) { "Windows2016Forest" } }  # Up to Windows2016Forest
    "Windows2016Forest"   { $null } 

    # Once Windows Server 2025 is released, it will include a new Forest Level called "Windows2025Forest". Add to this once released. 

    Default { $null } 
}

# Display Upgrade Options and Highest Available Levels
if ($latestSchemaVersion -gt $schema) {
    Write-Host "Highest Available Schema Version: $latestSchemaVersion ($($schemaVersionMap[$latestSchemaVersion]))" -ForegroundColor Green
} else {
    Write-Host "No Schema Version upgrades available." -ForegroundColor Cyan
}
# Forest Level Output
if ($possibleForestUpgrades) {
    $highestForestLevel = $possibleForestUpgrades
    Write-Host "Highest Available Forest Functional Level: $highestForestLevel" -ForegroundColor Green
} else {
    Write-Host "No forest functional level upgrades available." -ForegroundColor Cyan
}

# Schema Upgrade Logic
$schemaFSMORoleOwner = (Get-ADDomainController -Filter {OperationMasterRoles -like "*SchemaMaster*"}).Name

if ($latestSchemaVersion -gt $schema) { # Only prompt if schema is lower
    Write-Warning "The schema version ($schema) is lower than the highest available ($latestSchemaVersion). Schema upgrade is recommended before proceeding."
    $confirmSchemaUpgrade = Read-Host "Do you want to upgrade the schema to $latestSchemaVersion ($($schemaVersionMap[$latestSchemaVersion]))? (yes/no)"

    if ($confirmSchemaUpgrade.ToLower() -eq "yes") {
        try {
            # Perform Schema Upgrade (requires Schema Admin privileges on the Schema Master FSMO role owner)
            Invoke-Command -ComputerName $schemaFSMORoleOwner -ScriptBlock {
                Import-Module ActiveDirectory
                adprep /forestprep
            }           
        } catch {
            Write-Host "Error upgrading schema: $($_.Exception.Message)" -ForegroundColor Red
            return # Stop further processing in case of schema upgrade errors
        }
    } else {
        Write-Host "Schema upgrade cancelled." -ForegroundColor Yellow
        return # Stop further processing if the user doesn't want to upgrade the schema
    }

    # Update the schema version after the upgrade is successful (or if it was not needed)
    $schema = (Get-ADObject (Get-ADRootDSE).schemaNamingContext -Property objectVersion).objectVersion

    # Verify Schema Upgrade
    Write-Host "Schema is at version: $schema ($($schemaVersionMap[$schema]))" -ForegroundColor Green
}

# Forest Upgrade Logic
if ($possibleForestUpgrades) {
    # User Confirmation for Upgrade
    $confirm = Read-Host "Do you want to upgrade the forest functional level? (yes/no)" 

    if ($confirm.ToLower() -eq "yes") {

        try {
            # Store Original Level for Comparison
            $originalForestLevel = $forest.ForestMode

            # Perform Forest Functional Level Upgrade (requires Enterprise Admin privileges)
            Set-ADForestMode -Identity $forest -ForestMode $highestForestLevel

            # Verify Upgrade and Display Results
            $forest = Get-ADForest
            Write-Host "Forest functional level upgraded from $originalForestLevel to $($forest.ForestMode)" -ForegroundColor Green

        } catch {
            Write-Host "Error upgrading forest functional level: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Upgrade cancelled." -ForegroundColor Yellow
    }
}
