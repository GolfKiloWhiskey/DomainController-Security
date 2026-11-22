# Baseline: Security - NTLM Hardening (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-ntlm-hardening'
    Name        = 'Security - NTLM Hardening'
    Version     = '0.7.1'
    Description = 'LAN Manager authentication level: send NTLMv2 only, refuse LM and NTLM.'
    Source      = 'Legacy/GPO-Reports/Security - NTLM Hardening.html'
    Requires    = @()
    Notes       = @('Linked at the domain root. Run ready first: devices still using LM or NTLMv1 stop signing in.')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'lm-level'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'Network security: LAN Manager authentication level = Send NTLMv2 response only. Refuse LM & NTLM'
           Key = 'MACHINE\System\CurrentControlSet\Control\Lsa\LmCompatibilityLevel'; Type = 'DWord'; Value = 5 }
    )
}
