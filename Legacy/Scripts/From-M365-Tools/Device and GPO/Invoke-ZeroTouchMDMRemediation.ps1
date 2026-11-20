<# .NOTES 
Author: Cliff Waite 
Date: 05/27/2026
Email: cliff.ps@nutmegtech.com
Version: 1.1

.Synopsis
Full remediation for broken Entra ID states and zero-touch Intune MDM enrollment.

.Description
Executes as SYSTEM to purge broken Workplace Joins and forces a clean Hybrid Azure AD Join. 
Relies on GPO for Device Credential bypass, manually injects the GCC High MDM URLs, 
and triggers the Intune Auto-Enrollment handshake.

.Example
.\Invoke-ZeroTouchMDMRemediation.ps1

.Versioning 
1.1 - Added manual registry key injection for GCC High MDM endpoints.
1.0 - Initial creation: SYSTEM-context infrastructure reset.
#>

$ScriptVersion = "1.1"
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "   ZERO-TOUCH MDM REMEDIATION (GCC HIGH)     " -ForegroundColor Yellow
Write-Host "   Author: Cliff Waite                       " -ForegroundColor DarkGray
Write-Host "   Email:cliff.ps@nutmegtech.com             " -ForegroundColor DarkGray
Write-Host "   Version: $ScriptVersion                   " -ForegroundColor DarkGray
Write-Host "=============================================" -ForegroundColor Cyan

# ---------------------------------------------------------
# 1. VERIFY EXECUTION CONTEXT
# ---------------------------------------------------------
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($currentUser -ne "NT AUTHORITY\SYSTEM") {
    Write-Host "ERROR: This script is designed for zero-touch execution and MUST be run as SYSTEM." -ForegroundColor Red
    exit 1001
}

# ---------------------------------------------------------
# 2. INFRASTRUCTURE TEARDOWN
# ---------------------------------------------------------
Write-Host "1. Purging stale Entra ID registrations and Workplace Joins..." -ForegroundColor Cyan
dsregcmd /debug /leave

Write-Host "2. Purging stale SYSTEM Kerberos tickets..." -ForegroundColor Cyan
klist -li 0x3e7 purge

Write-Host "Waiting 15 seconds for cryptographic state cleanup..." -ForegroundColor Yellow
Start-Sleep -Seconds 300

# ---------------------------------------------------------
# 3. HYBRID JOIN REBUILD
# ---------------------------------------------------------
Write-Host "3. Triggering clean Hybrid Azure AD Join..." -ForegroundColor Cyan
dsregcmd /debug /join

Write-Host "Waiting 30 seconds for tenant discovery and handshake..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# ---------------------------------------------------------
# 4. INJECT GCC HIGH MDM REGISTRY KEYS
# ---------------------------------------------------------
Write-Host "4. Injecting GCC High MDM Registry Keys..." -ForegroundColor Cyan
$TenantID = "<TENANT-ID>"   # removed for the repo: set the client tenant ID
$cdjPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\TenantInfo\$TenantID"

try {
    if (!(Test-Path $cdjPath)) {
        New-Item -Path $cdjPath -Force -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath $cdjPath -Name 'MdmEnrollmentUrl' -Value 'https://enrollment.manage.microsoft.us/enrollmentserver/discovery.svc' -PropertyType String -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -LiteralPath $cdjPath -Name 'MdmTermsOfUseUrl' -Value 'https://portal.manage.microsoft.us/TermsofUse.aspx' -PropertyType String -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -LiteralPath $cdjPath -Name 'MdmComplianceUrl' -Value 'https://portal.manage.microsoft.us/?portalAction=Compliance' -PropertyType String -Force -ErrorAction Stop | Out-Null
    Write-Host "MDM URLs injected successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to inject MDM registry keys. Execution continuing, but enrollment may fail." -ForegroundColor Red
}

# ---------------------------------------------------------
# 5. INTUNE ENROLLMENT TRIGGER
# ---------------------------------------------------------
Write-Host "5. Triggering SYSTEM-level MDM Enrollment..." -ForegroundColor Cyan
try {
    # Relies on GPO to supply the "UseDeviceCredentialEnrollment" parameter silently
    $process = Start-Process -FilePath "C:\Windows\system32\deviceenroller.exe" -ArgumentList "/c /AutoEnrollMDM" -Wait -PassThru -ErrorAction Stop
    
    if ($process.ExitCode -eq 0) {
        Write-Host "SUCCESS: MDM Enrollment triggered successfully! (Exit Code 0)" -ForegroundColor Green
    } else {
        Write-Host "deviceenroller.exe exited with error code: $($process.ExitCode)" -ForegroundColor Red
        Write-Host "NOTE: If exit code is 0x801c005a or similar, the Azure AD Connect Delta Sync has not yet replicated the new device certificate. The native scheduled task will automatically retry and succeed once the sync completes." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to launch deviceenroller.exe." -ForegroundColor Red
    exit 1001
}

Write-Host "Remediation sequence complete." -ForegroundColor Green
exit 0