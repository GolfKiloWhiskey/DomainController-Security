<#
.Created on: 05/06/2024

.Author: Cliff Waite
.Email: cliff.ps@nutmegtech.com

.Synopsis
Generates a report listing all members of the "Domain Admins" group and their group memberships in Active Directory.

.Description
This script retrieves a list of users belonging to the "Domain Admins" group and iterates through each user. 
It leverages the `Get-ADGroupMember` and `Get-ADPrincipalGroupMembership` cmdlets to retrieve the user's name and their group memberships within the domain. 
The script then writes this information to a specified output file (`c:\temp\domain_admin_memberships.txt`) and displays it in the console for immediate viewing.

**Important Notes:**

* This script requires the Active Directory module to be imported (`Import-Module ActiveDirectory`).
* The script writes the output to the file `c:\temp\domain_admin_memberships.txt`. Adjust the path if necessary.
* The script requires administrative privileges to access Active Directory information.

.Example
**Scenario:** You need to generate a report of all domain admins and their group memberships for auditing purposes.

**Steps:**

1. **Save the Script:** Save this script as a file named `GetDomainAdminMemberships.ps1`.
2. **Import Active Directory Module:** Open a PowerShell window with administrator privileges and run `Import-Module ActiveDirectory`.
3. **Run the Script:** Navigate to the directory where you saved the script using the `cd` command (e.g., `cd C:\path\to\scripts`). Run the script by entering its name followed by `.PS1` (e.g., `.\GetDomainAdminMemberships.ps1`).

**Output:**

The script will generate a file named `domain_admin_memberships.txt` in the `c:\temp` directory, containing a list of all domain admins and their group memberships. 
Additionally, the information will be displayed in the console window.

This script can be helpful for maintaining an overview of privileged user accounts and their associated group memberships within your Active Directory environment.
#>

Import-Module ActiveDirectory

# Specify the output file path
$OutputFile = "c:\temp\domain_admin_memberships.txt"

# Get members of Domain Admins group
$DomainAdmins = Get-ADGroupMember -Identity "Domain Admins"

# Iterate through each Domain Admin
foreach ($Admin in $DomainAdmins) {
  $UserName = $Admin.Name
  "User: $UserName" | Out-File -FilePath $OutputFile -Append -Encoding utf8
  Write-Host "User:" $UserName # Also display on console

  # Get group memberships for the user
  $UserGroups = Get-ADPrincipalGroupMembership -Identity $Admin | Select-Object -ExpandProperty Name

  # Print and append each group membership
  foreach ($Group in $UserGroups) {
    "- Member of: $Group" | Out-File -FilePath $OutputFile -Append -Encoding utf8
    Write-Host "- Member of:" $Group # Also display on console
  }

  "" | Out-File -FilePath $OutputFile -Append -Encoding utf8
  Write-Host "" 
}
