Get-ADGroupMember "Domain Admins" |
ForEach-Object {
    Get-ADUser  -Filter "SamAccountName -eq '$($_.SamAccountName)'" -SearchBase 'DC=clientx,DC=local' | ft Name
}

