# Baseline: Security - WinRM Hardening

Status: agreed with Cliff (Nov 2026). Becomes a baseline file in `Nutmeg.AD/Baselines/` alongside
Step 4 (Firewall + PKI) and the planned Member Server Roles track (ADCS on a dedicated member
server).

Hardens Windows Remote Management (WinRM) on **both Domain Controllers and Member Servers** to
Kerberos-only authentication with no unencrypted traffic, paired with hub-and-spoke Windows Firewall
rules so **only DCs can connect to Member Servers** (never member-to-member, and never member-to-DC).

## Default links

`Domain Controllers`, `Devices/Member Servers`.

## Hub-and-spoke topology (enforced by Firewall in Step 4)

- **Member Servers:** accept inbound WinRM (`5986` HTTPS; `5985` HTTP only during Day-1 bootstrap)
  **from DC IP(s) only**. Member-to-member WinRM is blocked.
- **Domain Controllers:** accept inbound WinRM **from other DCs / management IPs only** — never from
  member servers.
- **Important Windows detail (`IPv4Filter`):** the WinRM GPO setting `IPv4Filter` only controls
  which **local NIC IP(s)** WinRM binds to on the server (typically `*` for IPv4, with `IPv6Filter`
  empty). It does **not** restrict remote source IPs; source-IP lockdown must be enforced by Windows
  Firewall.

## Transport lifecycle: Bootstrap (5985) -> Steady State (5986 HTTPS)

Best practice is **WinRM over HTTPS (`5986`)**, which requires an internal CA (ADCS). Because ADCS
never runs on a DC and is deployed onto a dedicated member server:

1. **Day 1 (bootstrap, before ADCS exists):** Windows Server enables Kerberos-encrypted HTTP WinRM
   (`5985`) by default. From the DC (by FQDN), the planned Member Server Roles tool deploys ADCS
   Enterprise Root CA onto a dedicated member server over `5985` (firewall-scoped to DC IP(s) only).
2. **Steady state (after ADCS + PKI baseline):** the PKI baseline (`Security - PKI - CA
   Infrastructure`, Step 4) deploys the CA root and Server Authentication auto-enrollment. Once
   member servers enroll a Server Auth certificate, an HTTPS (`5986`) WinRM listener is bound to the
   cert and the HTTP (`5985`) listener/firewall rule can be disabled.
3. **Listener note:** Group Policy (`AllowAutoConfig`) only creates an HTTP (`5985`) listener; GPO
   cannot natively create an HTTPS (`5986`) listener bound to a certificate thumbprint. Binding the
   `5986` listener will be handled by a toolkit step (remote from the DC) or a companion startup
   task/script after PKI enrollment.

## 1. WinRM Service (`Service`)

- `WinRM` start mode: `Automatic`.

## 2. WinRM Service Hardening (`Policy` — Administrative Templates)

Key: `HKLM\Software\Policies\Microsoft\Windows\WinRM\Service`

| Setting | ValueName | Type | Value | Why |
| --- | --- | --- | --- | --- |
| Allow Basic authentication | `AllowBasic` | DWord | `0` | No cleartext credentials |
| Allow unencrypted traffic | `AllowUnencryptedTraffic` | DWord | `0` | Enforces encryption even on 5985 |
| Disallow WinRM from storing RunAs credentials | `DisableRunAs` | DWord | `1` | Prevents stored RunAs creds |
| Allow CredSSP authentication | `AllowCredSSP` | DWord | `0` | Prevents credential delegation theft |
| Allow Kerberos authentication | `AllowKerberos` | DWord | `1` | Domain-native mutual auth + encryption |
| Allow Negotiate authentication | `AllowNegotiate` | DWord | `0` | Kerberos-only for WinRM (OS-level NTLMv2 remains available for legacy apps) |

**Operational note:** with `AllowNegotiate = 0` (Kerberos-only), WinRM connections from the DC must
target member servers by **FQDN/hostname** (`SRV01.clientx.local`), not by raw IP.

## 3. WinRM Client Hardening (`Policy` — Administrative Templates)

Key: `HKLM\Software\Policies\Microsoft\Windows\WinRM\Client`

| Setting | ValueName | Type | Value | Why |
| --- | --- | --- | --- | --- |
| Allow Basic authentication | `AllowBasic` | DWord | `0` | No cleartext credentials |
| Allow unencrypted traffic | `AllowUnencryptedTraffic` | DWord | `0` | Never send unencrypted WinRM |
| Disallow Digest authentication | `AllowDigest` | DWord | `0` | Legacy/weak auth off |
| Allow CredSSP authentication | `AllowCredSSP` | DWord | `0` | No credential delegation |

Leave `TrustedHosts` unconfigured so Kerberos SPN validation stays enforced.

## 4. WinRS (`Policy` — Administrative Templates)

Key: `HKLM\Software\Policies\Microsoft\Windows\WinRM\Service\WinRS`

- `AllowRemoteShellAccess` (DWord) = `1` (explicitly allows PowerShell Remoting / WinRS; idle and
  shell count limits left at Windows defaults unless tightened later).

## 5. Remote Event Viewer & Computer Management (Step 4 Firewall Note)

Opening **Event Viewer** (`eventvwr.msc`), **Computer Management** (`compmgmt.msc`), or **Services**
(`services.msc`) on the DC against a remote member server uses **RPC/DCOM (TCP `135` + Dynamic RPC
`49152-65535`)** and **SMB (TCP `445`)**, **not** WinRM. (Server Manager, `Invoke-Command` /
`Get-WinEvent`, `Get-CimInstance`, and `Install-WindowsFeature -ComputerName` use WinRM.)

In **Step 4** (`Windows Firewall - Servers (Default)`), scope **both**:
- Inbound **WinRM** (`5986`, plus `5985` during bootstrap if needed), **and**
- Inbound **Remote Event Log Management** and **Remote Service Management**

to **DC IP(s) only** on Member Servers, so the DC gets full MMC + PowerShell remote management
while member-to-member lateral movement stays blocked.
