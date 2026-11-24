# Baseline: Network - Disable NCSI (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'network-disable-ncsi'
    Name        = 'Network - Disable NCSI'
    Version     = '0.7.1'
    Description = 'Configure Network Connectivity Status Indicator (NCSI) to use global DNS instead of binding lookups to one interface.'
    Source      = 'Legacy/GPO-Reports/Network - Disable NCSI.html'
    Requires    = @()
    Notes       = @('Linked at Devices/Workstations (Data\GpoDefaultLinks.csv). Sets NCSI global DNS (disables interface binding for NCSI DNS lookups).')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'ncsi-global-dns'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Network/Network Connectivity Status Indicator: Specify global DNS = Enabled (Use global DNS)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator'; ValueName = 'UseGlobalDNS'; Type = 'DWord'; Value = 1 } ) }
    )
}
