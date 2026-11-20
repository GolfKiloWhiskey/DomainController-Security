#
# Use this PowerShell script to export the server configuration from a downlevel version of Azure AD Connect 
# that does not support the new JSON settings import and export feature.
#
#  Migration Steps
#
#     Please read the complete instructions for performing an in-place versus a legacy settings migration before
#     attempting the following steps: https://go.microsoft.com/fwlink/?LinkID=2117122
#
#     1.) Copy this script to your production server and save the downlevel server configuration directory
#         to a file share for use in installing a new staging server.
#
#     2.) Run this script on your new staging server and pass in the location of the configuration directory
#         generated in the previous step.  This will create a JSON settings file which can then be imported
#         in the Azure Active Directory Connect tool during Custom installation.
#

Param (
    [Parameter (Mandatory=$false)]
    [string] $ServerConfiguration
)
$helpLink = "https://go.microsoft.com/fwlink/?LinkID=2117122"
$helpMsg = "Please see $helpLink for more information."
$adSyncService = "HKLM:\SYSTEM\CurrentControlSet\services\ADSync"

# An installed wizard is the baseline requirement for this script
$wizard = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Azure AD Connect" -ErrorAction Ignore
if ($wizard.WizardPath)
{
    [version] $wizardVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($wizard.WizardPath).FileVersion
    try {
        # The ADSync service must be installed in order to extract settings from the production server
        $service = Get-ItemProperty -Path $adSyncService -Name ObjectName -ErrorAction Ignore
        if (!$service.ObjectName)
        {
            Write-Host
            Write-Host "Azure AD Connect must be installed and configured on this server for settings migration to succeed."
            Write-Host "The Microsoft Azure AD Connect synchronization service (ADSync) is not present."
            Write-Host $helpMsg
            exit
        }

        $programData = [IO.Path]::Combine($Env:ProgramData, "AADConnect")
        if (!$ServerConfiguration)
        {
            # Create a temporary directory under %ProgramData%\AADConnect
            $tempDirectory = ("Exported-ServerConfiguration-" + [System.Guid]::NewGuid())
            $ServerConfiguration = [IO.Path]::Combine($programData, $tempDirectory)
        }

        # Export the server configuration in a new PS session to avoid loading legacy cmdLet assemblies
        try
        {
            # try first with new parameter that will validate the configuration 
            Get-ADSyncServerConfiguration -Path $ServerConfiguration $true
        }
        catch [System.Management.Automation.ParameterBindingException]
        {
            Get-ADSyncServerConfiguration -Path $ServerConfiguration
        }

        # Copy over the PersistedState.xml file to the configuration directory
        Copy-Item -Path "$programData\\PersistedState.xml" -Destination $ServerConfiguration

        $author = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $timeCreated = $(Get-Date).ToUniversalTime().ToString("u", [System.Globalization.CultureInfo]::InvariantCulture)
        $policyMetadata = [ordered]@{
            "type" = "migration"
            "author" = $author
            "timeCreated" = $timeCreated
            "azureADConnectVersion" =  $wizardVersion.ToString()
        }

        $hostName = ([System.Net.Dns]::GetHostByName(($env:computerName))).Hostname
        $serviceParams = Get-ItemProperty -Path "$adSyncService\Parameters" -ErrorAction Ignore
        $databaseServer = $serviceParams.Server
        $databaseInstance = $serviceParams.SQLInstance
        $databaseName = $serviceParams.DBName

        # Retrieve the service account type for documentation purposes (may not be present on old builds)
        $serviceAccountType = "Unknown"
        $msolCoexistence = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\MSOLCoExistence" -ErrorAction Ignore
        if ($msolCoexistence.ServiceAccountType)
        {
            $serviceAccountType = $adSync.ServiceAccountType
        }
        
        [string[]]$connectorIds =(Get-ADSyncConnector | Select-Object -Property Identifier).Identifier

        # NOTE: databaseType is a calculated field and is intentionally ommitted
        $deploymentMetadata = [ordered]@{
            "hostName" = $hostName
            "serviceAccount" = $service.ObjectName
            "serviceAccountType" = $serviceAccountType
            "databaseServer" = $databaseServer
            "databaseInstance" = $databaseInstance
            "databaseName" = $databaseName
            "connectorIds" = $connectorIds
        }

        $policyJSON = [ordered]@{
            "policyMetadata" = $policyMetadata
            "deploymentMetadata" = $deploymentMetadata
        }                 

        # Create MigratedPolicy.json for the production server
        $policyJSON | ConvertTo-Json | Out-File "$ServerConfiguration\MigratedPolicy.json"

        Write-Host
        Write-Host "The downlevel server configuration was successfully exported.  Copy the entire directory to"
        Write-Host "your new staging server and select 'MigratedPolicy.json' from the UI to import these settings."
        Write-Host
        Write-Host "   " $ServerConfiguration
        Write-Host
        Write-Host "Please see $helpLink for more information on completing this process."
    }
    catch {
        Write-Host "Unable to export the server configuration due to an unexpected error."
        Write-Host $helpMsg
        Write-Host "Message: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    exit
}
else
{
    Write-Host
    Write-Host "The Azure AD Connect tool must be installed on this server for settings migration to succeed."
    Write-Host $helpMsg
}
# SIG # Begin signature block
# MIInogYJKoZIhvcNAQcCoIInkzCCJ48CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBFmuzW644A2hIU
# e0doTQIQOOZ59uIfCm+FbtM2rs/A1qCCDYIwggYAMIID6KADAgECAhMzAAADXJXz
# SFtKBGrPAAAAAANcMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjMwNDA2MTgyOTIyWhcNMjQwNDAyMTgyOTIyWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDijA1UCC84R0x+9Vr/vQhPNbfvIOBFfymE+kuP+nho3ixnjyv6vdnUpgmm6RT/
# pL9cXL27zmgVMw7ivmLjR5dIm6qlovdrc5QRrkewnuQHnvhVnLm+pLyIiWp6Tow3
# ZrkoiVdip47m+pOBYlw/vrkb8Pju4XdA48U8okWmqTId2CbZTd8yZbwdHb8lPviE
# NMKzQ2bAjytWVEp3y74xc8E4P6hdBRynKGF6vvS6sGB9tBrvu4n9mn7M99rp//7k
# ku5t/q3bbMjg/6L6mDePok6Ipb22+9Fzpq5sy+CkJmvCNGPo9U8fA152JPrt14uJ
# ffVvbY5i9jrGQTfV+UAQ8ncPAgMBAAGjggF/MIIBezArBgNVHSUEJDAiBgorBgEE
# AYI3TBMBBgorBgEEAYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUXgIsrR+tkOQ8
# 10ekOnvvfQDgTHAwRQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEWMBQGA1UEBRMNMjMzMTEwKzUwMDg2ODAfBgNVHSMEGDAWgBRI
# bmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEt
# MDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBABIm
# T2UTYlls5t6i5kWaqI7sEfIKgNquF8Ex9yMEz+QMmc2FjaIF/HQQdpJZaEtDM1Xm
# 07VD4JvNJEplZ91A4SIxjHzqgLegfkyc384P7Nn+SJL3XK2FK+VAFxdvZNXcrkt2
# WoAtKo0PclJOmHheHImWSqfCxRispYkKT9w7J/84fidQxSj83NPqoCfUmcy3bWKY
# jRZ6PPDXlXERRvl825dXOfmCKGYJXHKyOEcU8/6djs7TDyK0eH9ss4G9mjPnVZzq
# Gi/qxxtbddZtkREDd0Acdj947/BTwsYLuQPz7SNNUAmlZOvWALPU7OOVQlEZzO8u
# Ec+QH24nep/yhKvFYp4sHtxUKm1ZPV4xdArhzxJGo48Be74kxL7q2AlTyValLV98
# u3FY07rNo4Xg9PMHC6sEAb0tSplojOHFtGtNb0r+sioSttvd8IyaMSfCPwhUxp+B
# Td0exzQ1KnRSBOZpxZ8h0HmOlMJOInwFqrCvn5IjrSdjxKa/PzOTFPIYAfMZ4hJn
# uKu15EUuv/f0Tmgrlfw+cC0HCz/5WnpWiFso2IPHZyfdbbOXO2EZ9gzB1wmNkbBz
# hj8hFyImnycY+94Eo2GLavVTtgBiCcG1ILyQabKDbL7Vh/OearAxcRAmcuVAha07
# WiQx2aLghOSaZzKFOx44LmwUxRuaJ4vO/PRZ7EzAMIIHejCCBWKgAwIBAgIKYQ6Q
# 0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNh
# dGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5
# WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQD
# Ex9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4
# BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe
# 0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato
# 88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v
# ++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDst
# rjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN
# 91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4ji
# JV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmh
# D+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbi
# wZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8Hh
# hUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaI
# jAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTl
# UAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNV
# HQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQF
# TuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNf
# MjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNf
# MjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnlj
# cHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5
# AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oal
# mOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0ep
# o/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1
# HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtY
# SWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInW
# H8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZ
# iWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMd
# YzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7f
# QccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKf
# enoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOpp
# O6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZO
# SEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGXYwghlyAgEBMIGVMH4xCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAANclfNIW0oEas8AAAAAA1ww
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIC27rh7y
# 5VXdMTFAmR/PdYFbszAGaWCn5XNWWwWOerkeMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEA4Lsn5+iesaHkSPcKN9ijOBbhfp7MddZ4nDkqkb3I
# tpjm3Ic8BcePFJ06IisCn0b+VUzPJZUHOgWQJCq7P6ToNQ2gZRUrAyNfH9j9Sryr
# vvv5pFM2WpQTlb6tCwRf0Tbys2J7La80MH3HQtedM/UIn6Pk2fmeBV1bTXG0+qVi
# EPdbWiSacqvMR+WN9G2O/ueBUXzzHEqBa1PoeSwDjKVCIxROZr9gcIJx5qvF9izJ
# xxGko14AhAu6kPEOoO/7LHJaJn2eNFlW6P+vFm2ZXPtZUtCnhNam1Q2AE+zGNF4y
# +U9M5HkOfV2b3aEtRodFU42vX0bNBxBZqUCBDmXI+O/KHqGCFwAwghb8BgorBgEE
# AYI3AwMBMYIW7DCCFugGCSqGSIb3DQEHAqCCFtkwghbVAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFRBgsqhkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCApDjyVGC8mu0Q50MgGZtLajDRkwqUoBJkid7qx
# Ln55MwIGZF0egN2jGBMyMDIzMDUxNzIyNTY0OC4yMTlaMASAAgH0oIHQpIHNMIHK
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMSYwJAYDVQQLEx1UaGFsZXMgVFNT
# IEVTTjpBRTJDLUUzMkItMUFGQzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaCCEVcwggcMMIIE9KADAgECAhMzAAABv99uuQQVUihYAAEAAAG/
# MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4X
# DTIyMTEwNDE5MDEyNFoXDTI0MDIwMjE5MDEyNFowgcoxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNh
# IE9wZXJhdGlvbnMxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOkFFMkMtRTMyQi0x
# QUZDMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAuExh0n1UxKMzBvkPHer47nryD4UK
# 2GVy1X6bOVC+hLVhDlsIWQ1uX/9a8IRI3zXo/y1oTDuj+rJHyX4OZQn42E0iu7x6
# swPvM34zIOSPn8lgnWzGEAsRtz9zBrLW9+4w/YhWlXI8hvc7ovqupuL3TXte8Bbm
# NOUDSL+Ou2bBfObGzsH3yY/BELvqwO13KZ9Z1OxKacnqq1u9E9Rhai90STog22lR
# 2MVRSx55FHi/emnZA/IKvsAtEH2K6JmgOyQ7/mDQrWNEA5roUjhQqLQw1/3wz/CI
# vc9+FPxX2dxR0nvvYe5VLqv8Q99cOkO6z6V4stGDyFDuO8CwtiSvCC3QrOOugAl3
# 3aPD9YZswywWRk+YGyLI+Fw+kCCUY6h1qOjTj5glz0esmds3ue45WaI2hI9usFor
# M8gy//5tDZXj0KKU1BxA04xpfEy91RZUbc6pdAvEkpYrN2jlpXhMvTD7pgdYyxkV
# SaWZv7kWp5y9NjWP/CTDGXTC6DWiGcXwPQO66QdVNWxuiGdpfPaEUnWXcKnDVua1
# khBAxO4m9wg/1qM6f7HwXf/pHifMej+qB7SUZOiJScX+1HmffmZRAFiJXS0qUDk0
# ZAZW3oX2xLyl0044eHI7Y95GPaw8OlSTeNiNAKl+MyH5OaifsUuyVHOf4rsrE+Zy
# AuS9e9ERqu5H/10CAwEAAaOCATYwggEyMB0GA1UdDgQWBBRVAolUT3eV3wK/+Luf
# /wawCPMYpzAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8E
# WDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9N
# aWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYB
# BQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEw
# KDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqG
# SIb3DQEBCwUAA4ICAQAjCREvjT6yXwJYdvkFUqTGGh6RizAY+ciuB6UOBUm0yqq5
# QC+5pCEa9WSMvbUGzxDCEFBgD93gWGnkiyYcHCazlgZK+E7WxtI3bP++Fb4RJZiW
# Lo/IC9hX12hCZZwYXIGVzC9BVAcNx/zsFqI/9u8u/bhGjDHPad47C4OQNCHrkNqz
# GYxb4GQq6Psw6o7cEty3MU3Jd4uzBazaFhPRvmBfSn+Ufd6pTNZLgIX9BjrLmZbl
# c/d2LIAurEr5W29WfW5RMRIEZzO9TaMr/zzdmW/cV6VdaDTygy5g4O3UXadt1Dra
# Upn5jcD10TVWNnyz/paeleHojrGCCksqexpelMkUsiYP0HX9pFUgNglWU10r1wEz
# FwZM9aX2Rqq3fFRrN3gu8tCX+H1nKK2AobW1vmsKLTH6PyX1LkyvRwTj45a1paeH
# IR8TGzm3+iY7wpC1MHuzqAqAdDeaIVdVlch807VJJ4hDive6AiOQCV9MwiUyhf5v
# 4P8jTGof8CqjDb3PnLlNSnFm2BFhMZ35oNTEosc37GZHScM83hTN1E481sLYJrrh
# hcdtcyNB60juMjqGUD6uQ/7DbMvtv93tFj5WjxVhMCkkY66EEYgpfFLOCb2ngJJW
# FuJCIGsCiDfDxGwE4RVYAnoFzoa2OfSqijYg2drdZfpptRRvKxMsAzu3oxkS/TCC
# B3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAw
# gYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMT
# KU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIx
# MDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# UENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57Ry
# IQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VT
# cVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhx
# XFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQ
# HJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1
# KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s
# 4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUg
# fX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3
# Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je
# 1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUY
# hEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUY
# P3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGC
# NxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4w
# HQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYB
# BAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcD
# CDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0T
# AQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNV
# HR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9w
# cm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEE
# TjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOC
# AgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/a
# ZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp
# 4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq
# 95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qB
# woEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG
# +jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3B
# FARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77
# IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJ
# fn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K
# 6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDx
# yKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggLOMIICNwIBATCB
# +KGB0KSBzTCByjELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEl
# MCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMd
# VGhhbGVzIFRTUyBFU046QUUyQy1FMzJCLTFBRkMxJTAjBgNVBAMTHE1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVADgEd+JNrp4dpvFK
# MZi91txbfic3oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAw
# DQYJKoZIhvcNAQEFBQACBQDoD4XhMCIYDzIwMjMwNTE4MDA1NzA1WhgPMjAyMzA1
# MTkwMDU3MDVaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOgPheECAQAwCgIBAAIC
# AZoCAf8wBwIBAAICE4YwCgIFAOgQ12ECAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYK
# KwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUF
# AAOBgQAcI12CMEPQvOGSbcoUc9bIAfkQYvktgL1dFnhdIA1ETeuoBHi7gSp2vN6o
# kTk0/XKLSGXJts8zIF7XES6YuZYyPc9AaenKLu7m5AiEIdt5Qp+7mrupOYe8o4fE
# BFnv65hvU4emEUOPdYTc6D1UnXw3eT2P3CWsJgrbacjO6wI0oTGCBA0wggQJAgEB
# MIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAABv99uuQQVUihY
# AAEAAAG/MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcN
# AQkQAQQwLwYJKoZIhvcNAQkEMSIEIJVcUf71JliPInsrdwQIPtv/zZKT4gxBYVW+
# 1wxnsV0WMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQg/Q4tRz63EiRj4K+1
# 9yNUwogBIOsp44CIuBfnZHCvBa4wgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMAITMwAAAb/fbrkEFVIoWAABAAABvzAiBCCbFBy1RmGrZIcSyBOV
# 30ct3Wkzk+69HKX8axcLWwmM+zANBgkqhkiG9w0BAQsFAASCAgCfnSOBim24fETZ
# Eg5neZovEWEabkLW7exsNnrFqnEsxrHAmkuy5jNjYShGUBX2GKQjLeFuGqgBQf6Z
# j687MgId5ATZYg+bv2n3Xn9DEWGyrrGwIZeBj+28oL+jTZRbcB9aQc3eDqUeyCWf
# B+GK6NAdVVUmEh2QJyHWbw2k99Kvvi4yLQBDOzd+iSWaCcNs+/BujVdZqWIKfiho
# nFWnxJ/1W+74IBhet3FRgn2cw7/TkwXjnNhEU69ULG0mMnhkI3c37i/b7T5idjVd
# oGJlZJ1YZKKfq4hGWAR9zlQRrQNGT2Jl88QcCmv/Y90GjgxpEmgq+yQr3v6zxtSL
# 4OW6CoCpf5rSVnbcXoz0JkS3muufnBYyBacfFDA+ArY14sLOexB6oY0XXaYK+Q7F
# Hd9ryLKhPgcMa6gFuA+bFN+r21tXKTB3hpQBbwINXB1XaS8ZEg3fqjAJB4os8O9A
# uWrcnVUX63xv/ItvDPHYVS9PGmaNKB9f32ukfxzCmH1u8Dt2CJaVM53wk9+oxciL
# +m6RQbNK9fU9DIsHbFPoJXd4GOp2TQPUULyyyB7nsiqT4Xw6SgR9jtqQmhZkjdbh
# 0fZnQibfSo0zs/D+7jFECQ0d/xngH3csodFjLl2OzSop+A8Ao83j8Ln7y/IZ4jw4
# yab1TR85F2WtPY8kczECATAVFyoLvg==
# SIG # End signature block
