# Baseline: Security - SCHANNEL Hardening (spec: docs/baselines/Security-SCHANNEL-Hardening.md). Format: Core\Baseline.ps1.
@{
    Id          = 'security-schannel-hardening'
    Name        = 'Security - SCHANNEL Hardening'
    Version     = '0.7.1'
    Description = 'Disables SSL 2.0/3.0 and TLS 1.0/1.1, leaves TLS 1.2/1.3, sets cipher suite and ECC curve order, disables weak ciphers, raises DH/PKCS minimum keys to 2048 bits, and makes .NET Framework follow OS TLS.'
    Source      = 'docs/baselines/Security-SCHANNEL-Hardening.md'
    Requires    = @()
    Notes       = @('Every setting takes effect after a restart.',
                    'Link to Devices/Workstations/GPO Test first, and run ready (SSL/TLS check) before linking to DCs and servers.',
                    'TLS 1.3 and DTLS are left at Windows defaults.')
    Parameters  = @(
        @{
            Name     = 'CipherProfile'
            Prompt   = 'TLS cipher suite profile'
            Type     = 'Choice'
            Choices  = @('Compatible', 'Modern')
            Default  = 'Compatible'
            Help     = 'Compatible keeps SHA-2 CBC and RSA-GCM suites for older LDAPS/SQL/appliances; Modern is TLS 1.3 + TLS 1.2 ECDHE AES-GCM only.'
            ValueMap = @{
                Compatible = 'TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_RSA_WITH_AES_256_GCM_SHA384,TLS_RSA_WITH_AES_128_GCM_SHA256'
                Modern     = 'TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
            }
        }
    )
    Settings    = @(
        # 1. Protocols (Preferences, registry)
        @{ Id = 'ssl20-client-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 2.0 Client Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'ssl20-client-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 2.0 Client DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'ssl20-server-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 2.0 Server Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'ssl20-server-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 2.0 Server DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }

        @{ Id = 'ssl30-client-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 3.0 Client Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'ssl30-client-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 3.0 Client DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'ssl30-server-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 3.0 Server Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'ssl30-server-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL SSL 3.0 Server DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }

        @{ Id = 'tls10-client-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.0 Client Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'tls10-client-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.0 Client DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'tls10-server-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.0 Server Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'tls10-server-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.0 Server DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }

        @{ Id = 'tls11-client-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.1 Client Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'tls11-client-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.1 Client DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'tls11-server-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.1 Server Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'tls11-server-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.1 Server DisabledByDefault = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 1; Action = 'Update' }

        @{ Id = 'tls12-client-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.2 Client Enabled = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'; ValueName = 'Enabled'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'tls12-client-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.2 Client DisabledByDefault = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'tls12-server-enabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.2 Server Enabled = 1'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'; ValueName = 'Enabled'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'tls12-server-disabled'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL TLS 1.2 Server DisabledByDefault = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'; ValueName = 'DisabledByDefault'; Type = 'DWord'; Value = 0; Action = 'Update' }

        # 2. Cipher suite order (Administrative Templates)
        @{ Id = 'ssl-cipher-suite-order'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Network/SSL Configuration Settings: SSL Cipher Suite Order = Enabled ({CipherProfile})'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'; ValueName = 'Functions'; Type = 'String'; Value = '{CipherProfile}' } ) }

        # 3. ECC curve order (Administrative Templates)
        @{ Id = 'ecc-curve-order'; Kind = 'Policy'; Side = 'Computer'; Tags = @()
           Title = 'Network/SSL Configuration Settings: ECC Curve Order = Enabled (curve25519, NistP256, NistP384)'
           Values = @( @{ Key = 'HKLM\Software\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'; ValueName = 'EccCurves'; Type = 'MultiString'; Value = @('curve25519', 'NistP256', 'NistP384') } ) }

        # 4. Weak ciphers off (Preferences, registry)
        @{ Id = 'cipher-null'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher NULL Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\NULL'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-des-56'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher DES 56/56 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\DES 56/56'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-rc2-40'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher RC2 40/128 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 40/128'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-rc2-56'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher RC2 56/128 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 56/128'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-rc2-128'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher RC2 128/128 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 128/128'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-rc4-40'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher RC4 40/128 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 40/128'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-rc4-56'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher RC4 56/128 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 56/128'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-rc4-64'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher RC4 64/128 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 64/128'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-rc4-128'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher RC4 128/128 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 128/128'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }
        @{ Id = 'cipher-3des'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Cipher Triple DES 168 Enabled = 0'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168'; ValueName = 'Enabled'; Type = 'DWord'; Value = 0; Action = 'Update' }

        # 5. Key sizes (Preferences, registry)
        @{ Id = 'dh-server-min-key'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Diffie-Hellman ServerMinKeyBitLength = 2048'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\Diffie-Hellman'; ValueName = 'ServerMinKeyBitLength'; Type = 'DWord'; Value = 2048; Action = 'Update' }
        @{ Id = 'dh-client-min-key'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL Diffie-Hellman ClientMinKeyBitLength = 2048'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\Diffie-Hellman'; ValueName = 'ClientMinKeyBitLength'; Type = 'DWord'; Value = 2048; Action = 'Update' }
        @{ Id = 'pkcs-client-min-key'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: SCHANNEL PKCS ClientMinKeyBitLength = 2048'
           Hive = 'HKLM'; Key = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\PKCS'; ValueName = 'ClientMinKeyBitLength'; Type = 'DWord'; Value = 2048; Action = 'Update' }

        # 6. .NET Framework follows the OS (Preferences, registry)
        @{ Id = 'dotnet4-64-default-tls'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 4.x (64-bit) SystemDefaultTlsVersions = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319'; ValueName = 'SystemDefaultTlsVersions'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'dotnet4-64-strong-crypto'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 4.x (64-bit) SchUseStrongCrypto = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319'; ValueName = 'SchUseStrongCrypto'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'dotnet4-32-default-tls'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 4.x (32-bit) SystemDefaultTlsVersions = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; ValueName = 'SystemDefaultTlsVersions'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'dotnet4-32-strong-crypto'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 4.x (32-bit) SchUseStrongCrypto = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; ValueName = 'SchUseStrongCrypto'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'dotnet2-64-default-tls'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 2.0 (64-bit) SystemDefaultTlsVersions = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Microsoft\.NETFramework\v2.0.50727'; ValueName = 'SystemDefaultTlsVersions'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'dotnet2-64-strong-crypto'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 2.0 (64-bit) SchUseStrongCrypto = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Microsoft\.NETFramework\v2.0.50727'; ValueName = 'SchUseStrongCrypto'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'dotnet2-32-default-tls'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 2.0 (32-bit) SystemDefaultTlsVersions = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727'; ValueName = 'SystemDefaultTlsVersions'; Type = 'DWord'; Value = 1; Action = 'Update' }
        @{ Id = 'dotnet2-32-strong-crypto'; Kind = 'PrefRegistry'; Side = 'Computer'; Tags = @()
           Title = 'Preferences/Registry: .NET 2.0 (32-bit) SchUseStrongCrypto = 1'
           Hive = 'HKLM'; Key = 'SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727'; ValueName = 'SchUseStrongCrypto'; Type = 'DWord'; Value = 1; Action = 'Update' }
    )
}
