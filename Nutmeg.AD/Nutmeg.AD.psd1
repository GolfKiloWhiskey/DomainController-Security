@{
    RootModule           = 'Nutmeg.AD.psm1'
    ModuleVersion        = '0.7.14'
    CompatiblePSEditions = 'Desktop', 'Core'
    GUID                 = '062a02b8-3a18-437d-9a18-bed29fc8a82a'
    Author               = 'Cliff Waite'
    CompanyName          = 'Nutmeg Technologies'
    Copyright            = '(c) 2026 Nutmeg Technologies. All rights reserved.'
    Description          = 'Menu-driven toolkit for Active Directory domain controller onboarding: OU layout, GPO baselines, readiness checks, reports and AD admin.'
    PowerShellVersion    = '5.1'
    FunctionsToExport    = '*'
    CmdletsToExport      = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags = 'ActiveDirectory', 'GroupPolicy', 'DomainController', 'MSP'
        }
    }
}
