<# .NOTES 
Author: Cliff Waite 
Date: 07/22/2026
Email: cliff.ps@nutmegtech.com
Version: 1.5

.Synopsis
Audits OS-level SSL/TLS protocols, SCHANNEL registry settings, .NET Framework strong crypto, FIPS mode, GPO overrides, ECC curves, active HTTP bindings, RDP/WinRM security, and certificate health.

.Description
An interactive PowerShell utility for Windows Server and Workstation environments to audit, inspect, and export SSL/TLS security configurations.
Features:
- Audits SCHANNEL Protocols (SSL 2.0 through TLS 1.3) and calculates 'EffectiveStatus' based on OS Build defaults when registry keys are unconfigured.
- Inspects .NET Framework strong cryptography registry keys and detects built-in .NET 4.7+ default behavior.
- Audits FIPS mode policy, SCHANNEL EventLogging level, GPO Cipher Suite overrides, DH min key bit-lengths, and TLS Session Cache parameters.
- Audits Elliptic Curves (ECC Curves Order) and active OS-level TLS Cipher Suites.
- Inspects active local HTTPS/SSL certificate bindings via HttpSys (netsh http show sslcert).
- Audits RDP TLS Security Layer, NLA settings, and WinRM Unencrypted Traffic policies.
- Scans Local Machine Certificates for upcoming expirations and weak hashing algorithms (SHA-1 / MD5).
- Interactive action sub-menus with dual-output console display, Out-GridView windows, and C:\Temp CSV exports.

.Example
.\Audit-SslTlsCiphersAndProtocols.ps1

.Versioning 
1.5 - Fixed parameter type binding constraints, added null-collection safeguards, and added pause prompts across action menus.
1.4 - Integrated RDP TLS/NLA security, WinRM HTTPS/encryption policies, Minimum DH key bit lengths, Local Certificate Health (expiration & SHA-1 detection), and TLS Session Cache settings.
1.3 - Integrated FIPS Policy, SCHANNEL EventLogging, GPO Cipher Overrides, ECC Curves, SCHANNEL Subkeys, and active HttpSys SSL Bindings.
1.2 - Added OS Default Resolution Matrix and active .NET runtime protocol probing to determine effective TLS states when registry keys are unconfigured.
1.1 - Updated Full Audit workflow to present an interactive action menu with choices for Console display, Out-GridView, or CSV Export.
1.0 - Initial script creation with protocol, .NET crypto, and cipher suite audit capabilities.
#>

# ---------------------------------------------------------------------------
# GLOBAL VARIABLES & INITIALIZATION
# ---------------------------------------------------------------------------
$ScriptVersion = "1.5"
$ExportDir     = "C:\Temp"

if (-not (Test-Path -Path $ExportDir)) {
    try {
        New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
    } catch {
        # Fallback if creation fails
    }
}

$Timestamp   = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFilePath = Join-Path -Path $ExportDir -ChildPath "SslTlsAudit_$Timestamp.log"

# ---------------------------------------------------------------------------
# STANDARDIZED LOGGING FUNCTION
# ---------------------------------------------------------------------------
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $TimePrefix = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $FormattedLog = "[$TimePrefix] [$Level] $Message"

    # Console output color mapping
    switch ($Level) {
        "INFO"  { Write-Host $FormattedLog -ForegroundColor Cyan }
        "WARN"  { Write-Host $FormattedLog -ForegroundColor Yellow }
        "ERROR" { Write-Host $FormattedLog -ForegroundColor Red }
    }

    # Write to dynamic log file
    try {
        Add-Content -Path $LogFilePath -Value $FormattedLog -ErrorAction SilentlyContinue
    } catch {
        # Ignore file write failures
    }
}

# ---------------------------------------------------------------------------
# HELPER: OS BUILD & DEFAULT RESOLUTION
# ---------------------------------------------------------------------------
function Get-OSInfo {
    try {
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return @{
            Caption     = $OS.Caption
            BuildNumber = [int]$OS.BuildNumber
            Version     = $OS.Version
        }
    } catch {
        return @{
            Caption     = "Unknown OS"
            BuildNumber = 0
            Version     = "0.0"
        }
    }
}

function Resolve-EffectiveProtocolState {
    param (
        [string]$Protocol,
        [string]$Role,
        [string]$RegistryStatus,
        [int]$BuildNumber
    )

    if ($RegistryStatus -ne "Default") {
        return $RegistryStatus
    }

    switch ($Protocol) {
        "SSL 2.0" { return "Disabled (OS Default)" }
        "SSL 3.0" { return "Disabled (OS Default)" }
        "TLS 1.0" {
            if ($BuildNumber -ge 20348) {
                return "Disabled (OS Default - Win2022/Win11+)"
            } else {
                return "Enabled (OS Default - Legacy OS)"
            }
        }
        "TLS 1.1" {
            if ($BuildNumber -ge 20348) {
                return "Disabled (OS Default - Win2022/Win11+)"
            } else {
                return "Enabled (OS Default - Legacy OS)"
            }
        }
        "TLS 1.2" { return "Enabled (OS Default)" }
        "TLS 1.3" {
            if ($BuildNumber -ge 20348) {
                return "Enabled (OS Default)"
            } else {
                return "Disabled/Unsupported (OS Default)"
            }
        }
        default { return "Unknown (OS Default)" }
    }
}

# ---------------------------------------------------------------------------
# AUDIT FUNCTIONS
# ---------------------------------------------------------------------------
function Get-SchannelProtocolStatus {
    <#
    .SYNOPSIS
    Queries SCHANNEL registry subkeys and evaluates Effective OS Protocol Status.
    #>
    Write-Log "Auditing SCHANNEL Protocol Registry Configuration & Effective OS Defaults..." "INFO"
    
    $OSInfo        = Get-OSInfo
    Write-Log "Detected Operating System: $($OSInfo.Caption) (Build $($OSInfo.BuildNumber))" "INFO"

    $ProtocolNames = @("SSL 2.0", "SSL 3.0", "TLS 1.0", "TLS 1.1", "TLS 1.2", "TLS 1.3")
    $SchannelPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
    $Results       = [System.Collections.Generic.List[PSObject]]::new()
    $Index         = 1

    foreach ($Proto in $ProtocolNames) {
        foreach ($Role in @("Client", "Server")) {
            $KeyPath = "$SchannelPath\$Proto\$Role"
            
            $EnabledVal          = "Not Configured (OS Default)"
            $DisabledByDefaultVal = "Not Configured (OS Default)"
            $RegStatus           = "Default"

            if (Test-Path -Path $KeyPath) {
                try {
                    $Enabled = Get-ItemProperty -Path $KeyPath -Name "Enabled" -ErrorAction SilentlyContinue
                    if ($null -ne $Enabled) { $EnabledVal = $Enabled.Enabled }

                    $Disabled = Get-ItemProperty -Path $KeyPath -Name "DisabledByDefault" -ErrorAction SilentlyContinue
                    if ($null -ne $Disabled) { $DisabledByDefaultVal = $Disabled.DisabledByDefault }

                    if ($EnabledVal -eq 0 -or $DisabledByDefaultVal -eq 1) {
                        $RegStatus = "Disabled"
                    } elseif ($EnabledVal -eq 1) {
                        $RegStatus = "Explicitly Enabled"
                    }
                } catch {
                    Write-Log "Failed to read registry path: $KeyPath" "WARN"
                }
            }

            $EffectiveStatus = Resolve-EffectiveProtocolState -Protocol $Proto -Role $Role -RegistryStatus $RegStatus -BuildNumber $OSInfo.BuildNumber

            $Results.Add([PSCustomObject]@{
                "#"                 = $Index++
                "Protocol"          = $Proto
                "Role"              = $Role
                "EffectiveStatus"   = $EffectiveStatus
                "RegistryConfig"    = $RegStatus
                "EnabledValue"      = $EnabledVal
                "DisabledByDefault" = $DisabledByDefaultVal
                "RegistryPath"      = $KeyPath
            })
        }
    }

    return $Results
}

function Get-DotNetTlsSettings {
    <#
    .SYNOPSIS
    Queries .NET Framework registry settings and evaluates built-in runtime defaults.
    #>
    Write-Log "Auditing .NET Framework Security & Effective Runtime Defaults..." "INFO"

    $DotNet47PlusInstalled = $false
    $ReleaseKey = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
    if (Test-Path $ReleaseKey) {
        $Release = (Get-ItemProperty -Path $ReleaseKey -Name "Release" -ErrorAction SilentlyContinue).Release
        if ($Release -ge 461808) { $DotNet47PlusInstalled = $true }
    }

    $RegPaths = @(
        @{ Framework = ".NET v4.0+ (64-bit)"; Path = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" },
        @{ Framework = ".NET v4.0+ (32-bit)"; Path = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" },
        @{ Framework = ".NET v2.0/3.5 (64-bit)"; Path = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727" },
        @{ Framework = ".NET v2.0/3.5 (32-bit)"; Path = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727" }
    )

    $Results = [System.Collections.Generic.List[PSObject]]::new()
    $Index   = 1

    foreach ($Entry in $RegPaths) {
        $Path = $Entry.Path
        $StrongCrypto = "Not Configured"
        $SystemDefault = "Not Configured"

        if (Test-Path -Path $Path) {
            try {
                $sc = Get-ItemProperty -Path $Path -Name "SchUseStrongCrypto" -ErrorAction SilentlyContinue
                if ($null -ne $sc) { $StrongCrypto = $sc.SchUseStrongCrypto }

                $sd = Get-ItemProperty -Path $Path -Name "SystemDefaultTlsVersions" -ErrorAction SilentlyContinue
                if ($null -ne $sd) { $SystemDefault = $sd.SystemDefaultTlsVersions }
            } catch {
                Write-Log "Error reading .NET registry path $Path" "WARN"
            }
        }

        $EffectiveCrypto = "Disabled/Weak (Need Reg Key)"
        if ($StrongCrypto -eq 1) {
            $EffectiveCrypto = "Explicitly Enforced (Reg Key)"
        } elseif ($DotNet47PlusInstalled -and $Entry.Framework -like "*v4.0*") {
            $EffectiveCrypto = "Enforced by Default (.NET 4.7+ Installed)"
        }

        $Results.Add([PSCustomObject]@{
            "#"                        = $Index++
            "TargetFramework"          = $Entry.Framework
            "EffectiveStrongCrypto"    = $EffectiveCrypto
            "SchUseStrongCryptoKey"    = $StrongCrypto
            "SystemDefaultTlsKeys"     = $SystemDefault
            "RegistryPath"             = $Path
        })
    }

    try {
        $CurrentRuntimeProtocols = [System.Net.ServicePointManager]::SecurityProtocol.ToString()
        Write-Log "Active PowerShell Process SecurityProtocols: $CurrentRuntimeProtocols" "INFO"
    } catch {
        # Ignore if unsupported context
    }

    return $Results
}

function Get-SystemSchannelPolicies {
    <#
    .SYNOPSIS
    Audits FIPS Mode, SCHANNEL EventLogging, GPO Cipher Overrides, DH Min Bits, TLS Cache, and Algorithm Subkeys.
    #>
    Write-Log "Auditing System Security Policies, FIPS Mode, SCHANNEL Logging, DH Bits & Cache..." "INFO"

    $Results = [System.Collections.Generic.List[PSObject]]::new()
    $Index   = 1

    # 1. FIPS Mode Check
    $FipsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy"
    $FipsVal  = "Not Configured (0 - Disabled)"
    if (Test-Path $FipsPath) {
        $f = (Get-ItemProperty -Path $FipsPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
        if ($f -eq 1) { $FipsVal = "1 (Enabled - FIPS Enforced)" }
        elseif ($f -eq 0) { $FipsVal = "0 (Disabled)" }
    }
    $Results.Add([PSCustomObject]@{
        "#"             = $Index++
        "Category"      = "FIPS Policy"
        "Setting"       = "FipsAlgorithmPolicy"
        "Value"         = $FipsVal
        "RegistryPath"  = $FipsPath
    })

    # 2. SCHANNEL Event Logging Level
    $SchannelBase = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL"
    $LogVal       = "0x0001 (Log Errors Only - Default)"
    if (Test-Path $SchannelBase) {
        $el = (Get-ItemProperty -Path $SchannelBase -Name "EventLogging" -ErrorAction SilentlyContinue).EventLogging
        if ($null -ne $el) {
            switch ($el) {
                0 { $LogVal = "0 (Logging Disabled)" }
                1 { $LogVal = "1 (Log Errors Only)" }
                3 { $LogVal = "3 (Log Warnings and Errors)" }
                7 { $LogVal = "7 (Verbose Logging - All Events)" }
                default { $LogVal = "Custom Value ($el)" }
            }
        }
    }
    $Results.Add([PSCustomObject]@{
        "#"             = $Index++
        "Category"      = "SCHANNEL Logging"
        "Setting"       = "EventLogging"
        "Value"         = $LogVal
        "RegistryPath"  = $SchannelBase
    })

    # 3. GPO Cipher Suite Overrides
    $GpoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002"
    $GpoVal  = "Not Configured (Local Cipher Order Active)"
    if (Test-Path $GpoPath) {
        $funcs = (Get-ItemProperty -Path $GpoPath -Name "Functions" -ErrorAction SilentlyContinue).Functions
        if ([string]::IsNullOrWhiteSpace($funcs) -eq $false) {
            $GpoVal = "Enforced via GPO (Custom Cipher List Defined)"
        }
    }
    $Results.Add([PSCustomObject]@{
        "#"             = $Index++
        "Category"      = "Group Policy"
        "Setting"       = "SSL Cipher Suite Order"
        "Value"         = $GpoVal
        "RegistryPath"  = $GpoPath
    })

    # 4. Diffie-Hellman Minimum Key Bit Lengths
    $DhPath = "$SchannelBase\KeyExchangeAlgorithms\Diffie-Hellman"
    $ServerMinKey = "Not Configured (OS Default: 1024/2048)"
    $ClientMinKey = "Not Configured (OS Default: 1024/2048)"
    if (Test-Path $DhPath) {
        $sMin = (Get-ItemProperty -Path $DhPath -Name "ServerMinKeyBitLength" -ErrorAction SilentlyContinue).ServerMinKeyBitLength
        if ($null -ne $sMin) { $ServerMinKey = "$sMin bits" }

        $cMin = (Get-ItemProperty -Path $DhPath -Name "ClientMinKeyBitLength" -ErrorAction SilentlyContinue).ClientMinKeyBitLength
        if ($null -ne $cMin) { $ClientMinKey = "$cMin bits" }
    }
    $Results.Add([PSCustomObject]@{
        "#"             = $Index++
        "Category"      = "DH Key Exchange"
        "Setting"       = "ServerMinKeyBitLength"
        "Value"         = $ServerMinKey
        "RegistryPath"  = $DhPath
    })
    $Results.Add([PSCustomObject]@{
        "#"             = $Index++
        "Category"      = "DH Key Exchange"
        "Setting"       = "ClientMinKeyBitLength"
        "Value"         = $ClientMinKey
        "RegistryPath"  = $DhPath
    })

    # 5. TLS Session Cache Settings
    $CacheVal = "Default OS Caching"
    if (Test-Path $SchannelBase) {
        $sCache = (Get-ItemProperty -Path $SchannelBase -Name "ServerCacheTime" -ErrorAction SilentlyContinue).ServerCacheTime
        if ($null -ne $sCache) { $CacheVal = "ServerCacheTime: $sCache ms" }
    }
    $Results.Add([PSCustomObject]@{
        "#"             = $Index++
        "Category"      = "TLS Session Cache"
        "Setting"       = "ServerCacheTime"
        "Value"         = $CacheVal
        "RegistryPath"  = $SchannelBase
    })

    # 6. SCHANNEL Algorithm Subkeys (Ciphers, Hashes, KeyExchange)
    $SubKeyTypes = @("Ciphers", "Hashes", "KeyExchangeAlgorithms")
    foreach ($SubKey in $SubKeyTypes) {
        $FullPath = "$SchannelBase\$SubKey"
        if (Test-Path $FullPath) {
            $SubKeysFound = Get-ChildItem -Path $FullPath -ErrorAction SilentlyContinue
            if ($SubKeysFound) {
                foreach ($SK in $SubKeysFound) {
                    $ItemName = $SK.PSChildName
                    $EVal = (Get-ItemProperty -Path $SK.PSPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
                    $EStatus = "Configured ($EVal)"
                    if ($EVal -eq 0) { $EStatus = "Disabled (0x0)" }
                    elseif ($EVal -eq 1 -or $EVal -eq 4294967295) { $EStatus = "Enabled" }

                    $Results.Add([PSCustomObject]@{
                        "#"             = $Index++
                        "Category"      = "SCHANNEL Subkey ($SubKey)"
                        "Setting"       = $ItemName
                        "Value"         = $EStatus
                        "RegistryPath"  = $SK.PSPath
                    })
                }
            }
        }
    }

    return $Results
}

function Get-TlsCipherSuiteAudit {
    <#
    .SYNOPSIS
    Retrieves the ordered list of OS TLS Cipher Suites using Get-TlsCipherSuite.
    #>
    Write-Log "Auditing OS-level Active TLS Cipher Suites..." "INFO"

    $Results = [System.Collections.Generic.List[PSObject]]::new()

    try {
        if (-not (Get-Command -Name "Get-TlsCipherSuite" -ErrorAction SilentlyContinue)) {
            Write-Log "Get-TlsCipherSuite cmdlet is not available on this OS/PowerShell version." "ERROR"
            return $Results
        }

        $Ciphers = Get-TlsCipherSuite -ErrorAction Stop
        $Index   = 1

        foreach ($C in $Ciphers) {
            $Results.Add([PSCustomObject]@{
                "#"            = $Index++
                "CipherSuite"  = $C.Name
                "Cipher"       = $C.Cipher
                "CipherLength" = $C.CipherLength
                "Hash"         = $C.Hash
                "KeyType"      = $C.KeyType
                "Exchange"     = $C.Exchange
            })
        }
    } catch {
        Write-Log "Failed to retrieve TLS Cipher Suites: $($_.Exception.Message)" "ERROR"
    }

    return $Results
}

function Get-TlsEccCurveAudit {
    <#
    .SYNOPSIS
    Retrieves the ordered list of configured Elliptic Curves using Get-TlsEccCurve.
    #>
    Write-Log "Auditing Configured Elliptic Curves (ECC Curves Order)..." "INFO"

    $Results = [System.Collections.Generic.List[PSObject]]::new()

    try {
        if (-not (Get-Command -Name "Get-TlsEccCurve" -ErrorAction SilentlyContinue)) {
            Write-Log "Get-TlsEccCurve cmdlet is not available on this OS/PowerShell version." "WARN"
            return $Results
        }

        $Curves = Get-TlsEccCurve -ErrorAction Stop
        $Index  = 1

        foreach ($Curve in $Curves) {
            $Results.Add([PSCustomObject]@{
                "#"         = $Index++
                "CurveName" = $Curve.Name
            })
        }
    } catch {
        Write-Log "Failed to retrieve ECC Curves: $($_.Exception.Message)" "ERROR"
    }

    return $Results
}

function Get-HttpSslCertBindings {
    <#
    .SYNOPSIS
    Audits active HttpSys SSL Certificate bindings using netsh.
    #>
    Write-Log "Auditing Active Local HTTPS/SSL Certificate Bindings (netsh http show sslcert)..." "INFO"

    $Results = [System.Collections.Generic.List[PSObject]]::new()

    try {
        $NetshOutput = netsh http show sslcert 2>&1
        if (-not $NetshOutput) { return $Results }

        $CurrentBinding = $null
        $Index          = 1

        foreach ($Line in $NetshOutput) {
            $LineStr = $Line.ToString().Trim()

            if ($LineStr -like "*IP:port*" -or $LineStr -like "*IP:Port*") {
                if ($null -ne $CurrentBinding) {
                    $Results.Add([PSCustomObject]$CurrentBinding)
                }
                $Parts = $LineStr -split ":"
                $IpPort = if ($Parts.Count -ge 2) { "$($Parts[1].Trim()):$($Parts[2].Trim())" } else { $LineStr }

                $CurrentBinding = [ordered]@{
                    "#"                = $Index++
                    "IPPort"           = $IpPort
                    "CertificateHash"  = "Not Found"
                    "ApplicationID"    = "Not Found"
                    "CertificateStore" = "Not Found"
                }
            } elseif ($null -ne $CurrentBinding) {
                if ($LineStr -like "*Certificate Hash*") {
                    $CurrentBinding["CertificateHash"] = ($LineStr -split ":")[1].Trim()
                } elseif ($LineStr -like "*Application ID*") {
                    $CurrentBinding["ApplicationID"] = ($LineStr -split ":")[1].Trim()
                } elseif ($LineStr -like "*Certificate Store Name*") {
                    $CurrentBinding["CertificateStore"] = ($LineStr -split ":")[1].Trim()
                }
            }
        }

        if ($null -ne $CurrentBinding) {
            $Results.Add([PSCustomObject]$CurrentBinding)
        }
    } catch {
        Write-Log "Failed to query netsh http sslcert bindings: $($_.Exception.Message)" "ERROR"
    }

    return $Results
}

function Get-RdpWinRmSecurity {
    <#
    .SYNOPSIS
    Audits RDP TLS Security Layer, NLA settings, and WinRM unencrypted transmission policies.
    #>
    Write-Log "Auditing RDP TLS Security Layer, NLA & WinRM Encryption Policies..." "INFO"

    $Results = [System.Collections.Generic.List[PSObject]]::new()
    $Index   = 1

    # 1. RDP Security Layer
    $RdpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    $SecLayer = "Not Configured"
    $NlaStatus = "Not Configured"

    if (Test-Path $RdpPath) {
        $sl = (Get-ItemProperty -Path $RdpPath -Name "SecurityLayer" -ErrorAction SilentlyContinue).SecurityLayer
        switch ($sl) {
            0 { $SecLayer = "0 (RDP Encryption - Weak/Legacy)" }
            1 { $SecLayer = "1 (Negotiate - SSL/TLS or RDP)" }
            2 { $SecLayer = "2 (SSL/TLS Mandatory - High Security)" }
            default { $SecLayer = "Configured Value ($sl)" }
        }

        $nla = (Get-ItemProperty -Path $RdpPath -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication
        if ($nla -eq 1) { $NlaStatus = "Enabled (NLA Enforced)" }
        elseif ($nla -eq 0) { $NlaStatus = "Disabled (NLA Not Required)" }
    }

    $Results.Add([PSCustomObject]@{
        "#"            = $Index++
        "Service"      = "Remote Desktop (RDP)"
        "Setting"      = "SecurityLayer"
        "Value"        = $SecLayer
        "RegistryPath" = $RdpPath
    })

    $Results.Add([PSCustomObject]@{
        "#"            = $Index++
        "Service"      = "Remote Desktop (RDP)"
        "Setting"      = "UserAuthentication (NLA)"
        "Value"        = $NlaStatus
        "RegistryPath" = $RdpPath
    })

    # 2. WinRM Allow Unencrypted Check
    $WinRmPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Service"
    $WinRmUnencrypted = "Not Configured (Default: False)"
    if (Test-Path $WinRmPath) {
        $unenc = (Get-ItemProperty -Path $WinRmPath -Name "allow_unencrypted" -ErrorAction SilentlyContinue).allow_unencrypted
        if ($unenc -eq 1) { $WinRmUnencrypted = "1 (ALLOWED - Insecure)" }
        elseif ($unenc -eq 0) { $WinRmUnencrypted = "0 (BLOCKED - Secure)" }
    }

    $Results.Add([PSCustomObject]@{
        "#"            = $Index++
        "Service"      = "Windows Remote Mgmt (WinRM)"
        "Setting"      = "AllowUnencrypted"
        "Value"        = $WinRmUnencrypted
        "RegistryPath" = $WinRmPath
    })

    return $Results
}

function Get-LocalCertificateHealth {
    <#
    .SYNOPSIS
    Audits Local Machine Personal Certificate Store for upcoming expirations and SHA-1/MD5 weak signatures.
    #>
    Write-Log "Auditing Local Machine Certificate Health & Weak Hashing Signatures..." "INFO"

    $Results = [System.Collections.Generic.List[PSObject]]::new()

    try {
        $Certs = Get-ChildItem -Path "Cert:\LocalMachine\My" -ErrorAction Stop | Where-Object { -not $_.PSIsContainer }
        $Index = 1
        $Now   = Get-Date

        foreach ($Cert in $Certs) {
            $DaysRemaining = [math]::Round(($Cert.NotAfter - $Now).TotalDays)
            $SigAlgo       = $Cert.SignatureAlgorithm.FriendlyName
            
            $HealthStatus  = "Valid"
            if ($Cert.NotAfter -lt $Now) {
                $HealthStatus = "EXPIRED"
            } elseif ($DaysRemaining -le 30) {
                $HealthStatus = "Expiring Soon (< 30 Days)"
            }

            if ($SigAlgo -like "*sha1*" -or $SigAlgo -like "*md5*") {
                $HealthStatus += " | WEAK ALGORITHM ($SigAlgo)"
            }

            $Results.Add([PSCustomObject]@{
                "#"                 = $Index++
                "Subject"           = $Cert.Subject
                "HealthStatus"      = $HealthStatus
                "DaysRemaining"     = $DaysRemaining
                "NotAfter"          = $Cert.NotAfter.ToString("yyyy-MM-dd")
                "SignatureAlgorithm"= $SigAlgo
                "Thumbprint"        = $Cert.Thumbprint
            })
        }
    } catch {
        Write-Log "Failed to query Local Machine Certificate Store: $($_.Exception.Message)" "ERROR"
    }

    return $Results
}

# ---------------------------------------------------------------------------
# SUB-MENU ACTION HANDLERS
# ---------------------------------------------------------------------------
function Show-ResultActionMenu {
    param (
        [object]$Data = @(),
        [string]$ReportName = "Report"
    )

    if ($null -eq $Data -or $Data.Count -eq 0) {
        Write-Host "`nNo data items found for this report category." -ForegroundColor Yellow
        Read-Host "Press [Enter] to return to Main Menu..." | Out-Null
        return
    }

    do {
        Write-Host "`n---------------------------------------------" -ForegroundColor Cyan
        Write-Host "   RESULT ACTION MENU ($ReportName)" -ForegroundColor Yellow
        Write-Host "---------------------------------------------" -ForegroundColor Cyan
        Write-Host "1. View formatted list in console"
        Write-Host "2. Open in Out-GridView window"
        Write-Host "3. Export results to CSV ($ExportDir)"
        Write-Host "R. Return to Main Menu"
        Write-Host "---------------------------------------------" -ForegroundColor Cyan
        
        $Choice = Read-Host "Select an action option [Default: 1]"
        if ([string]::IsNullOrWhiteSpace($Choice)) { $Choice = "1" }

        switch ($Choice.ToUpper()) {
            "1" {
                Write-Host "`nDisplaying results:" -ForegroundColor Cyan
                $Data | Format-Table -AutoSize
                Read-Host "`nPress [Enter] to return to action menu..." | Out-Null
            }
            "2" {
                if (Get-Command -Name "Out-GridView" -ErrorAction SilentlyContinue) {
                    Write-Log "Opening Out-GridView reference window..." "INFO"
                    $Data | Out-GridView -Title "SSL/TLS Audit - $ReportName"
                } else {
                    Write-Log "Out-GridView is not available in this environment." "WARN"
                    Read-Host "Press [Enter] to continue..." | Out-Null
                }
            }
            "3" {
                $FileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $CsvFileName  = "$($ReportName)_$FileTimestamp.csv"
                $CsvFullPath  = Join-Path -Path $ExportDir -ChildPath $CsvFileName
                
                try {
                    $Data | Export-Csv -Path $CsvFullPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                    Write-Log "Successfully exported report to: $CsvFullPath" "INFO"
                } catch {
                    Write-Log "Failed to export CSV: $($_.Exception.Message)" "ERROR"
                }
                Read-Host "Press [Enter] to continue..." | Out-Null
            }
            "R" {
                return
            }
            default {
                Write-Host "Invalid choice. Please select 1, 2, 3, or R." -ForegroundColor Red
            }
        }
    } while ($Choice.ToUpper() -ne "R")
}

function Show-FullAuditActionMenu {
    param (
        [object]$Protocols = @(),
        [object]$DotNet = @(),
        [object]$Policies = @(),
        [object]$Ciphers = @(),
        [object]$Curves = @(),
        [object]$Bindings = @(),
        [object]$RdpWinRm = @(),
        [object]$Certificates = @()
    )

    do {
        Write-Host "`n---------------------------------------------" -ForegroundColor Cyan
        Write-Host "   FULL AUDIT ACTION MENU                    " -ForegroundColor Yellow
        Write-Host "---------------------------------------------" -ForegroundColor Cyan
        Write-Host "1. View all audit sections in console"
        Write-Host "2. Open all audit sections in Out-GridView"
        Write-Host "3. Export all audit sections to CSV ($ExportDir)"
        Write-Host "R. Return to Main Menu"
        Write-Host "---------------------------------------------" -ForegroundColor Cyan

        $FullChoice = Read-Host "Select an action option [Default: 1]"
        if ([string]::IsNullOrWhiteSpace($FullChoice)) { $FullChoice = "1" }

        switch ($FullChoice.ToUpper()) {
            "1" {
                Write-Host "`n=== 1. SCHANNEL PROTOCOLS & OS DEFAULTS ===" -ForegroundColor Yellow
                if ($Protocols.Count -gt 0) { $Protocols | Format-Table -AutoSize } else { Write-Host "No data." -ForegroundColor DarkGray }
                
                Write-Host "`n=== 2. .NET FRAMEWORK TLS REGISTRY & DEFAULTS ===" -ForegroundColor Yellow
                if ($DotNet.Count -gt 0) { $DotNet | Format-Table -AutoSize } else { Write-Host "No data." -ForegroundColor DarkGray }
                
                Write-Host "`n=== 3. SYSTEM SECURITY POLICIES, DH BITS & CACHE ===" -ForegroundColor Yellow
                if ($Policies.Count -gt 0) { $Policies | Format-Table -AutoSize } else { Write-Host "No data." -ForegroundColor DarkGray }

                Write-Host "`n=== 4. ECC CURVES ORDER ===" -ForegroundColor Yellow
                if ($Curves.Count -gt 0) { $Curves | Format-Table -AutoSize } else { Write-Host "No data." -ForegroundColor DarkGray }
                
                Write-Host "`n=== 5. ACTIVE TLS CIPHER SUITES (Top 20) ===" -ForegroundColor Yellow
                if ($Ciphers.Count -gt 0) { $Ciphers | Select-Object -First 20 | Format-Table -AutoSize } else { Write-Host "No data." -ForegroundColor DarkGray }

                Write-Host "`n=== 6. ACTIVE HTTPS BINDINGS (netsh) ===" -ForegroundColor Yellow
                if ($Bindings.Count -gt 0) { $Bindings | Format-Table -AutoSize } else { Write-Host "No data found." -ForegroundColor DarkGray }

                Write-Host "`n=== 7. RDP & WINRM SECURITY POLICIES ===" -ForegroundColor Yellow
                if ($RdpWinRm.Count -gt 0) { $RdpWinRm | Format-Table -AutoSize } else { Write-Host "No data." -ForegroundColor DarkGray }

                Write-Host "`n=== 8. LOCAL MACHINE CERTIFICATE HEALTH ===" -ForegroundColor Yellow
                if ($Certificates.Count -gt 0) { $Certificates | Format-Table -AutoSize } else { Write-Host "No certificates found in Personal store." -ForegroundColor DarkGray }

                Read-Host "`nPress [Enter] to return to Full Audit menu..." | Out-Null
            }
            "2" {
                if (Get-Command -Name "Out-GridView" -ErrorAction SilentlyContinue) {
                    Write-Log "Opening Out-GridView windows for all audit results..." "INFO"
                    if ($Protocols.Count -gt 0)    { $Protocols    | Out-GridView -Title "Full Audit - 1. SCHANNEL Protocols" }
                    if ($DotNet.Count -gt 0)       { $DotNet       | Out-GridView -Title "Full Audit - 2. .NET TLS Settings" }
                    if ($Policies.Count -gt 0)     { $Policies     | Out-GridView -Title "Full Audit - 3. Security Policies & Subkeys" }
                    if ($Curves.Count -gt 0)       { $Curves       | Out-GridView -Title "Full Audit - 4. ECC Curves" }
                    if ($Ciphers.Count -gt 0)      { $Ciphers      | Out-GridView -Title "Full Audit - 5. TLS Cipher Suites" }
                    if ($Bindings.Count -gt 0)     { $Bindings     | Out-GridView -Title "Full Audit - 6. Active HTTPS Bindings" }
                    if ($RdpWinRm.Count -gt 0)     { $RdpWinRm     | Out-GridView -Title "Full Audit - 7. RDP & WinRM Security" }
                    if ($Certificates.Count -gt 0) { $Certificates | Out-GridView -Title "Full Audit - 8. Certificate Health" }
                } else {
                    Write-Log "Out-GridView is not available in this environment." "WARN"
                }
                Read-Host "Press [Enter] to continue..." | Out-Null
            }
            "3" {
                $FileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                
                try {
                    if ($Protocols.Count -gt 0)    { $Protocols    | Export-Csv -Path (Join-Path $ExportDir "FullAudit_1_Protocols_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }
                    if ($DotNet.Count -gt 0)       { $DotNet       | Export-Csv -Path (Join-Path $ExportDir "FullAudit_2_DotNet_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }
                    if ($Policies.Count -gt 0)     { $Policies     | Export-Csv -Path (Join-Path $ExportDir "FullAudit_3_Policies_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }
                    if ($Curves.Count -gt 0)       { $Curves       | Export-Csv -Path (Join-Path $ExportDir "FullAudit_4_EccCurves_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }
                    if ($Ciphers.Count -gt 0)      { $Ciphers      | Export-Csv -Path (Join-Path $ExportDir "FullAudit_5_CipherSuites_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }
                    if ($Bindings.Count -gt 0)     { $Bindings     | Export-Csv -Path (Join-Path $ExportDir "FullAudit_6_HttpBindings_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }
                    if ($RdpWinRm.Count -gt 0)     { $RdpWinRm     | Export-Csv -Path (Join-Path $ExportDir "FullAudit_7_RdpWinRm_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }
                    if ($Certificates.Count -gt 0) { $Certificates | Export-Csv -Path (Join-Path $ExportDir "FullAudit_8_CertHealth_$FileTimestamp.csv") -NoTypeInformation -Encoding UTF8 }

                    Write-Log "Full Audit Export Complete! All non-empty CSV reports generated in $ExportDir" "INFO"
                } catch {
                    Write-Log "Error exporting combined audit files: $($_.Exception.Message)" "ERROR"
                }
                Read-Host "Press [Enter] to continue..." | Out-Null
            }
            "R" {
                return
            }
            default {
                Write-Host "Invalid choice. Please select 1, 2, 3, or R." -ForegroundColor Red
            }
        }
    } while ($FullChoice.ToUpper() -ne "R")
}

# ---------------------------------------------------------------------------
# MAIN INTERACTIVE MENU
# ---------------------------------------------------------------------------
function Show-MainMenu {
    do {
        Clear-Host
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "   OS SSL/TLS CIPHERS & PROTOCOLS AUDIT      " -ForegroundColor Yellow
        Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
        Write-Host "   Email:cliff.ps@nutmegtech.com             " -ForegroundColor DarkGray
        Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
        Write-Host "=============================================" -ForegroundColor Cyan
        Write-Host "1. Audit SCHANNEL SSL/TLS Protocols & OS Defaults"
        Write-Host "2. Audit .NET Framework Strong Cryptography & Runtimes"
        Write-Host "3. Audit System Security Policies (FIPS, Logging, GPO, DH Bits)"
        Write-Host "4. Audit Active TLS Cipher Suites & ECC Curves"
        Write-Host "5. Audit Local HTTPS Bindings, RDP TLS & WinRM Security"
        Write-Host "6. Audit Local Machine Certificate Health & Weak Signatures"
        Write-Host "7. Run Complete Environment Audit"
        Write-Host "Q. Quit"
        Write-Host "=============================================" -ForegroundColor Cyan

        $Selection = Read-Host "Select an option [1-7 or Q]"

        switch ($Selection.ToUpper()) {
            "1" {
                $Protocols = Get-SchannelProtocolStatus
                Write-Host "`n--- SCHANNEL PROTOCOL AUDIT RESULTS ---" -ForegroundColor Yellow
                $Protocols | Format-Table -AutoSize
                Show-ResultActionMenu -Data $Protocols -ReportName "Schannel_Protocols"
            }
            "2" {
                $DotNet = Get-DotNetTlsSettings
                Write-Host "`n--- .NET FRAMEWORK TLS REGISTRY AUDIT RESULTS ---" -ForegroundColor Yellow
                $DotNet | Format-Table -AutoSize
                Show-ResultActionMenu -Data $DotNet -ReportName "DotNet_TLS_Settings"
            }
            "3" {
                $Policies = Get-SystemSchannelPolicies
                Write-Host "`n--- SYSTEM SECURITY POLICIES & SUBKEYS ---" -ForegroundColor Yellow
                $Policies | Format-Table -AutoSize
                Show-ResultActionMenu -Data $Policies -ReportName "System_Security_Policies"
            }
            "4" {
                $Ciphers = Get-TlsCipherSuiteAudit
                $Curves  = Get-TlsEccCurveAudit
                
                Write-Host "`n--- CONFIGURRED ECC CURVES ---" -ForegroundColor Yellow
                $Curves | Format-Table -AutoSize

                Write-Host "`n--- ACTIVE TLS CIPHER SUITES (Ordered by Priority) ---" -ForegroundColor Yellow
                Write-Host "Showing top 25 of $($Ciphers.Count) ciphers..." -ForegroundColor DarkGray
                $Ciphers | Select-Object -First 25 | Format-Table -AutoSize
                
                Show-ResultActionMenu -Data $Ciphers -ReportName "TLS_Cipher_Suites"
            }
            "5" {
                $Bindings = Get-HttpSslCertBindings
                $RdpWinRm = Get-RdpWinRmSecurity

                Write-Host "`n--- RDP & WINRM SECURITY POLICIES ---" -ForegroundColor Yellow
                $RdpWinRm | Format-Table -AutoSize

                Write-Host "`n--- ACTIVE LOCAL HTTPS BINDINGS (netsh http show sslcert) ---" -ForegroundColor Yellow
                $Bindings | Format-Table -AutoSize
                Show-ResultActionMenu -Data $Bindings -ReportName "HttpSys_SSL_Bindings"
            }
            "6" {
                $Certificates = Get-LocalCertificateHealth
                Write-Host "`n--- LOCAL MACHINE CERTIFICATE HEALTH ---" -ForegroundColor Yellow
                $Certificates | Format-Table -AutoSize
                Show-ResultActionMenu -Data $Certificates -ReportName "Local_Certificate_Health"
            }
            "7" {
                try {
                    Write-Log "Executing full SSL/TLS environment audit..." "INFO"
                    $Protocols    = Get-SchannelProtocolStatus
                    $DotNet       = Get-DotNetTlsSettings
                    $Policies     = Get-SystemSchannelPolicies
                    $Ciphers      = Get-TlsCipherSuiteAudit
                    $Curves       = Get-TlsEccCurveAudit
                    $Bindings     = Get-HttpSslCertBindings
                    $RdpWinRm     = Get-RdpWinRmSecurity
                    $Certificates = Get-LocalCertificateHealth

                    Show-FullAuditActionMenu -Protocols $Protocols -DotNet $DotNet -Policies $Policies -Ciphers $Ciphers -Curves $Curves -Bindings $Bindings -RdpWinRm $RdpWinRm -Certificates $Certificates
                } catch {
                    Write-Log "An error occurred during Full Audit execution: $($_.Exception.Message)" "ERROR"
                    Read-Host "`nPress [Enter] to return to main menu..." | Out-Null
                }
            }
            "Q" {
                Write-Log "Exiting SSL/TLS Audit Tool. Goodbye!" "INFO"
                return
            }
            default {
                Write-Host "Invalid option. Please enter 1-7 or Q." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    } while ($true)
}

# ---------------------------------------------------------------------------
# SCRIPT ENTRY POINT
# ---------------------------------------------------------------------------
Write-Log "Script started. Initializing OS SSL/TLS Audit Tool v$ScriptVersion..." "INFO"
Show-MainMenu