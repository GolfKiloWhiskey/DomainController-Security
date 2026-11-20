# Add sMSA account to AD
New-ADServiceAccount -Name "NAME OF SERVICE eg. SQL.SA" -RestrictToSingleComputer
Add-ADComputerServiceAccount -Identity "Server to install account" -ServiceAccount "service name"

#To verify the computer object where the service account will reside and the attribute;"
Get-ADComputer -Identity "Servername" -Properties msDS-HostServiceAccount

# This gets done on the server where the account will run from, NOT the DC
Install-ADServiceAccount -Identity "service account"
Test-ADServiceAccount -Identity "service account"






