<#
.Created on: 05/06/2024  ** Manually inserted based on today's date **
.Author: Cliff Waite
.Email: cliff.ps@nutmegtech.com

.Synopsis
Transfers Active Directory Operation Master Roles (Schema Master, Domain Naming Master, etc.) to a specified server (by hostname, not FQDN).

.Description
**Important Note:** This script modifies Active Directory configuration and should be used with caution. It's recommended to thoroughly understand Active Directory operation master roles and their impact before running this script.  This script attempts to transfer the Schema Master, Domain Naming Master, Infrastructure Master, RID Master, and PDC Emulator roles to the specified server using the `Move-ADDirectoryServerOperationMasterRole` cmdlet.

**Warning:** The `Move-ADDirectoryServerOperationMasterRole` cmdlet is not available in PowerShell natively. It requires the Active Directory module, which is not included by default. You'll need to install the RSAT Active Directory for Windows PowerShell feature or a third-party Active Directory module to utilize this functionality.

.Example
**Scenario:** You need to migrate Active Directory operation master roles to a new server named "server1".

**Steps:**

1. **Import Active Directory Module (Optional):** If you have the RSAT Active Directory for Windows PowerShell feature installed, you can skip this step. Otherwise, install the required features or a third-party Active Directory module.
2. **Run the Script:** Open a PowerShell window with administrator privileges. Ensure the Active Directory module is loaded (if applicable). Replace "Hostname (not FQDN)" with the actual hostname of the target server. Run the script by pasting the following line and pressing Enter:

#>
Move-ADDirectoryServerOperationMasterRole -Identity "Hostname (not FQDN)" -OperationMasterRole SchemaMaster,DomainNamingMaster,InfrastructureMaster,RIDMaster,PDCEmulator -Force
