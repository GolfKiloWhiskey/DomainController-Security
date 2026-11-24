# Baseline: Network - Prefer IPv4 over IPv6 (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'network-prefer-ipv4-over-ipv6'
    Name        = 'Network - Prefer IPv4 over IPv6'
    Version     = '0.7.1'
    Description = 'Prefer IPv4 over IPv6 in prefix policies (Tcpip6 DisabledComponents = 0x20), keeping IPv6 enabled as Microsoft requires.'
    Source      = 'Legacy/GPO-Reports/Network - Prefer IPv4 over IPv6.html'
    Requires    = @()
    Notes       = @('Linked at the domain root (Data\GpoDefaultLinks.csv). 0x20 (32) is Microsoft''s supported value to prefer IPv4 without disabling IPv6.')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'prefer-ipv4'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: Tcpip6\Parameters\DisabledComponents = 32 (0x20, prefer IPv4 over IPv6)'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'; ValueName = 'DisabledComponents'; Type = 'DWord'; Value = 32; Action = 'Update' }
    )
}
