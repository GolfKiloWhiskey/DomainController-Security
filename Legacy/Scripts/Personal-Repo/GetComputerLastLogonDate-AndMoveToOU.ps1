 # Get, Move and Disable AD Computers/Devices 
    # Revision v1
    # Author: Cliff Waite - Senior Systems Engineer - Nutmeg Technologies
    # Email:cliff.ps@nutmegtech.com
<# ----- Legal: ----
    # Sample scripts are not supported under any Nutmeg Technologies support program or service.
    # The sample scripts are provided AS IS without warranty of any kind.
    # Nutmeg Technologies expressly disclaims all implied warranties including, warranties
    # of merchantability or of fitness for a particular purpose. 
    # In no event shall Nutmeg Technologies or any other party be liable for damages arising
    # out of the use of or inability to use the sample scripts.
# -----------------------------------------------------------#>  ## Legal
    
#Comment out or remove whatever section will not be used prior to script execution
#Edit whatever script section suits your needs. 
# $TargetOU can be an OU you created or specified. Just change the variable to your liking. Script will fail to run if you dont specify the correct OU for it to point to, or if the OU is not in AD.
#Change the variable $exclude to exclude specific devices you do NOT want to move that you know would be inside your search query. Leave as is or change one parameter to a null value such as 1 character

#First script will find devices that have been disabled and will move it to the OU specified. 

$exclude = "AZUREADSSOACC", "Server1", "Server2"
$oldComputers = Get-ADComputer -filter * -Properties LastLogonDate | Where-Object { $_.Name -notin $exclude -and $_.Enabled -eq $false }
$targetOU = Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled Computers"'
$oldComputers |  Move-ADObject -TargetPath $targetOU.DistinguishedName


#This script will find devices older than X days and move to a specific OU.
#Change ".AddDays(X) for the amount of time to go back to. 

$exclude = "AZUREADSSOACC", "Server1", "Server2"
$oldComputers = Get-ADComputer -filter * -Properties LastLogonDate | Where-Object { $_.Name -notin $exclude -and $_.LastLogonDate -LT ([DateTime]::Today).AddDays(-365) }
$targetOU = Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled Computers"'
$oldComputers | Move-ADObject -TargetPath $targetOU.DistinguishedName

#Same script, just disables the devices during the move. 
#Change ".AddDays(X) for the amount of time to go back to.

$exclude = "AZUREADSSOACC", "Server1", "Server2"
$oldComputers = Get-ADComputer -filter * -Properties LastLogonDate | Where-Object { $_.Name -notin $exclude -and $_.LastLogonDate -LT ([DateTime]::Today).AddDays(-365) }
$targetOU = Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled Computers"'
$oldComputers | Disable-ADAccount -PassThru | Move-ADObject -TargetPath $targetOU.DistinguishedName