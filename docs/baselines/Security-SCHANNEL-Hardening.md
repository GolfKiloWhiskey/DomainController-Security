# Baseline: Security - SCHANNEL Hardening

Status: agreed with Cliff (Nov 2026). Becomes a baseline file when the format exists (`docs/TOOL-LIST.md`,
order of work step 2). Sources are Microsoft Learn pages, read Nov 20, 2026 (listed at the end).

Turns off SSL 2.0/3.0 and TLS 1.0/1.1, leaves TLS 1.2 and 1.3, sets the cipher suite and curve order,
removes weak ciphers and short DH keys, and makes .NET Framework apps follow the OS settings. It replaces
`CreateGPO-SSL_TLS-Disable.ps1`, which only set the protocols.

**Every setting takes effect after a restart.**

## Default links

Domain Controllers, `Devices/Member Servers`, `Devices/Workstations`. Link to `Devices/Workstations/GPO Test`
first, and run `ready` (the SSL/TLS check on each DC and server) before linking to DCs and servers.

## Parameters

| Parameter | Choices | Default | What it changes |
| --- | --- | --- | --- |
| `CipherProfile` | `Compatible`, `Modern` | `Compatible` | The cipher suite list below. Move to `Modern` once nothing needs the extra suites |

## 1. Protocols (Preferences, registry)

Key: `HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\<Protocol>\<Client|Server>`

| Protocol | Client and Server: `Enabled` | `DisabledByDefault` |
| --- | --- | --- |
| SSL 2.0 | 0 | 1 |
| SSL 3.0 | 0 | 1 |
| TLS 1.0 | 0 | 1 |
| TLS 1.1 | 0 | 1 |
| TLS 1.2 | 1 | 0 |
| TLS 1.3 | not set | not set |

- TLS 1.3 is on by default in Windows 11 and Windows Server 2022 and later. Microsoft says turning it on
  in older Windows is not a safe configuration, so the baseline leaves it alone.
- TLS 1.0 and 1.1 are already off by default in Windows Server 2025 and current Windows 11. The baseline
  makes that explicit for 2016, 2019 and 2022 servers and older Windows 10 and 11 builds.
- DTLS is not set: RDP over UDP uses it.

## 2. Cipher suite order (Administrative Templates)

`Network > SSL Configuration Settings > SSL Cipher Suite Order`: Enabled, with the list below.
A configured list replaces Windows' default list, and suites left out can't be used. That is why the TLS 1.3
suites are listed even though the GPO is mostly about TLS 1.2. Windows ignores suites an older version
doesn't support. The setting is limited to 1,023 characters; both lists are well under.

**Modern** (TLS 1.3, then TLS 1.2 with forward secrecy and AES-GCM only):

```
TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

**Compatible** (the default): Modern, then the SHA-2 CBC suites and RSA key exchange with AES-GCM, for
older LDAPS clients, appliances, printers and SQL drivers that don't do ECDHE with GCM:

```
TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_RSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_128_GCM_SHA256
```

Left out of both, compared with Windows Server 2025's default list: every SHA-1 CBC suite
(`..._CBC_SHA`), RSA key exchange with CBC, 3DES, RC4, DES, NULL, export, DHE and PSK suites.

## 3. Curve order (Administrative Templates)

`Network > SSL Configuration Settings > ECC Curve Order`: Enabled, `curve25519`, `NistP256`, `NistP384`
(Windows' default order, made explicit so it doesn't drift).

Post-quantum ML-KEM groups are in the newest Windows builds, off by default and not yet in released
Windows Server 2025. Not part of the baseline yet; revisit when they ship in general releases.

## 4. Weak ciphers off (Preferences, registry)

Key: `HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\<Cipher>`, `Enabled` = 0,
for: `NULL`, `DES 56/56`, `RC2 40/128`, `RC2 56/128`, `RC2 128/128`, `RC4 40/128`, `RC4 56/128`,
`RC4 64/128`, `RC4 128/128`, `Triple DES 168`.

The cipher suite order already excludes these; this also covers apps that ask Schannel for specific
algorithms. Hashes are not set: turning off MD5 or SHA-1 here breaks more than it protects, and the suite
order already leaves out SHA-1 suites.

## 5. Key sizes (Preferences, registry)

| Key | Value | Data |
| --- | --- | --- |
| `...\SCHANNEL\KeyExchangeAlgorithms\Diffie-Hellman` | `ServerMinKeyBitLength` | 2048 |
| `...\SCHANNEL\KeyExchangeAlgorithms\Diffie-Hellman` | `ClientMinKeyBitLength` | 2048 |
| `...\SCHANNEL\KeyExchangeAlgorithms\PKCS` | `ClientMinKeyBitLength` | 2048 |

Windows' default minimum for each is 1024.

## 6. .NET Framework follows the OS (Preferences, registry)

`SystemDefaultTlsVersions` = 1 and `SchUseStrongCrypto` = 1 under each of:

- `HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319`
- `HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319`
- `HKLM\SOFTWARE\Microsoft\.NETFramework\v2.0.50727`
- `HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727`

Without these, older .NET apps keep asking for TLS 1.0 and fail once it is off.

## Checks (`ready` and `gpo-compare`)

- Before: `ready` runs the SSL/TLS audit on each DC and server (from `Audit-SslTlsCiphersAndProtocols.ps1`)
  and looks for Schannel event 36871 and TLS 1.0/1.1 use.
- After: Schannel events 36871 (credential), 36874 and 36888 (handshake failures) in the System log
  point at an app or device that needs `Compatible`, or an update.

## Sources

- [TLS Cipher Suites in Windows Server 2025 and later](https://learn.microsoft.com/windows/win32/secauthn/tls-cipher-suites-in-windows-server-2025)
- [TLS Cipher Suites in Windows 11](https://learn.microsoft.com/windows/win32/secauthn/tls-cipher-suites-in-windows-11)
- [Manage Transport Layer Security (TLS)](https://learn.microsoft.com/windows-server/security/tls/manage-tls)
- [TLS registry settings](https://learn.microsoft.com/windows-server/security/tls/tls-registry-settings)
- [Protocols in TLS/SSL (Schannel SSP)](https://learn.microsoft.com/windows/win32/secauthn/protocols-in-tls-ssl--schannel-ssp-)
- [TLS 1.0 and TLS 1.1 deprecation in Windows](https://learn.microsoft.com/windows/win32/secauthn/tls-10-11-deprecation-in-windows)
- [TLS Supported Groups in Windows 11 24H2 and later](https://learn.microsoft.com/windows/win32/secauthn/tls-supported-groups-in-windows-11-24h2-and-later)
- [TLS best practices with .NET Framework](https://learn.microsoft.com/dotnet/framework/network-programming/tls)
- [Features removed or no longer developed in Windows Server](https://learn.microsoft.com/windows-server/get-started/removed-deprecated-features-windows-server)
