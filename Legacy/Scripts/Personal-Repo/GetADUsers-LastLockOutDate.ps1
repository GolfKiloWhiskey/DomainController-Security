Get-ADUser -Filter {enabled -eq $true} -Properties lockoutTime |
Select-Object Name,@{Name="Stamp"; Expression={[DateTime]::FromFileTime($_.lockoutTime).ToString('yyyy-MM-dd_hh:mm:ss')}} | Sort Stamp