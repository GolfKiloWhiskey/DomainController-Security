<#
.Created on: March 27, 2024
.Created by: Cliff Waite
.Filename: Enable-UserKerberosEncryption.ps1

.Synopsis
This script enables Kerberos encryption (either 128-bit or 256-bit) for user accounts within a specified Organizational Unit (OU) in Active Directory.
Must be run from a DC

.Description
The script performs the following actions:

1. **Prompts for OU DN:**
    * Requests the user to enter the distinguished name (DN) of the target OU interactively.

2. **Retrieves User Accounts:**
    * Uses `Get-ADUser` to retrieve all user accounts within the specified OU.

3. **Selects Encryption Type (Optional):**
    * Prompts the user to choose between enabling 128-bit or 256-bit encryption (configurable).

4. **Updates User Attributes:**
    * Iterates through each retrieved user (`$user`).
    * Uses `Set-ADUser` with the `-Replace` parameter to update the following user attributes:
        * `msDS-SupportedEncryptionTypes` (set based on user selection or a defined variable)
        * `userAccountControl` (sets the "Smart card required for interactive logon" flag)
    * Wraps the `Set-ADUser` command in a `Try...Catch` block to handle potential errors.

5. **Confirms Updates:**
    * Writes a message indicating successful attribute updates for each user.

.Example
```powershell

#>

# Import Active Directory Module
Import-Module ActiveDirectory

# Prompt for OU DN
$ouDN = Read-Host "Enter the OU DN (e.g., OU=Users,DC=contoso,DC=com):"

# Select Encryption Type (Optional - modify as needed)
$encryptionType = Read-Host "Select Encryption Type (1 - 128-bit, 2 - 256-bit):"

# Get all user accounts in the OU
$users = Get-ADUser -Filter * -SearchBase $ouDN

# Update attributes for each user
foreach ($user in $users) {
  # Choose encryption type based on user input or a defined variable
  if ($encryptionType -eq "1") {
    $supportedEncryption = 8  # 128-bit encryption
  } else {
    $supportedEncryption = 28  # 256-bit encryption
  }

  Try {
    Set-ADUser -Identity $user -Replace @{
      'msDS-SupportedEncryptionTypes' = $supportedEncryption
      'userAccountControl' = ($user.userAccountControl -bor 0x20000)
    }
    Write-Host "Successfully updated attributes for $($user.SamAccountName)"
  } Catch {
    Write-Warning "Error updating user $($user.SamAccountName): $_"
  }
}