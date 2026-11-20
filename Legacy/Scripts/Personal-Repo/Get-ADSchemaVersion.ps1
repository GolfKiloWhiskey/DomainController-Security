<#
.Created on: 05/06/2024
.Author: Cliff Waite
.Email: cliff.ps@nutmegtech.com

.Synopsis
Checks the Active Directory schema version and displays the corresponding operating system.

.Description
This script retrieves the Active Directory schema version and compares it to a predefined table to determine the likely operating system associated with that schema version. The script leverages the `Get-ADObject` and `Get-ADRootDSE` cmdlets to access the schemaNamingContext object and its `objectVersion` property. The script then displays a message indicating the schema version and the corresponding operating system based on the table provided.

**Important Notes:**

* This script provides a general mapping between schema versions and operating systems. There might be slight variations depending on your specific environment and service packs applied.
* The script assumes a single forest environment. In a multi-forest scenario, schema versions might differ across forests.

.Example
**Scenario:** You need to verify the Active Directory schema version on a domain controller.

**Steps:**

1. **Run the Script:** Open a PowerShell window and run the following script:

#>
(Get-ADObject (Get-ADRootDSE).schemaNamingContext -Property objectVersion).objectVersion
