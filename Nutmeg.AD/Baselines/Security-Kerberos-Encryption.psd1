# Baseline: Security - Kerberos Encryption (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-kerberos-encryption'
    Name        = 'Security - Kerberos Encryption'
    Version     = '0.7.1'
    Description = 'Kerberos encryption types: AES256 and future types only (DES, RC4 and AES128 off).'
    Source      = 'Legacy/GPO-Reports/Security - Kerberos Encryption.html'
    Requires    = @()
    Notes       = @('Linked at the domain root. Run ready first: accounts without AES keys stop working.')
    Parameters  = @()
    Settings    = @(
        # AES256_HMAC_SHA1 (0x10) + future encryption types (0x7FFFFFE0) = 0x7FFFFFF0.
        @{ Id = 'encryption-types'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'Network security: Configure encryption types allowed for Kerberos = AES256_HMAC_SHA1, Future encryption types'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters\SupportedEncryptionTypes'; Type = 'DWord'; Value = 2147483632 }
    )
}
