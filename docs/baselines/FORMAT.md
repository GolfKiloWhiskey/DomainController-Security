# Baseline file format

Agreed with Cliff (Nov 2026). Code: `Nutmeg.AD/Core/Baseline.ps1` (loader and checks),
`Core/GpoFiles.ps1` (SYSVOL files), `Core/GpoBaseline.ps1` (writing and comparing).

- **One `.psd1` file per baseline** in `Nutmeg.AD/Baselines/`, read with `Import-PowerShellDataFile`
  (no code runs; works in Windows PowerShell 5.1 and 7; comments allowed; registry paths stay readable).
- **A baseline is a GPO's settings, nothing else.** Links, filtering and delegation are chosen per run.
- Every file is checked by the tests (`Tests/Invoke-GpoTests.ps1`); a file with problems is not offered
  by `gpo-build`, and the problem is logged.

## The file

```powershell
@{
    Id          = 'security-screen-timeout'          # lower-case-hyphenated, unique
    Name        = 'Security - Screen Timeout'        # the default GPO name; must be in Data\GpoDefaultLinks.csv
    Version     = '0.7.1'                            # the slow-moving rule: +1 on the last number per change
    Description = 'One or two sentences.'
    Source      = 'Legacy/GPO-Reports/Security - Screen Timeout.html'   # optional
    Requires    = @()                                # optional: 'Duo', 'PowerShellCore' (ADMX in the central store)
    Notes       = @('Shown before the questions.')   # optional
    Parameters  = @( ... )
    Settings    = @( ... )
}
```

## Parameters

```powershell
@{ Name = 'TimeoutSeconds'; Prompt = 'Seconds before the screen locks'; Type = 'Int'; Default = 900; Min = 60; Max = 7200 }
```

- `Type`: `String`, `Int` (`Min`, `Max`), `Choice` (`Choices`, optional `ValueMap` hashtable mapping each choice to its written setting value), `Fqdn`, `IpRange`, `Group`, `Account`.
- `Default` is required (`''` for none). It can name a toolkit setting, `{Setting:BuildTimeZone}`, or the
  session: `{Session:Pdc}`, `{Session:Domain}`, `{Session:NetBIOS}`.
- `Optional = $true` allows an empty answer; `Help` is a grey line shown before the question.
- `{Name}` in a setting's **value** is the parameter. `{{` and `}}` are literal braces. Placeholders are
  never allowed in what a setting sets (key, value name, right, group, service), so `gpo-compare` can
  always find it. Every parameter declared must be used, and every placeholder declared.

## Settings

Every setting has `Id` (unique in the file), `Kind`, `Side` (`Computer` or `User`), `Title` (as GPMC
shows it; may use placeholders), `Tags` and optionally `Note`, then the kind's own fields. Unknown fields
are refused, so a typo fails the tests.

| Kind | Written with | Fields | Side |
| --- | --- | --- | --- |
| `Policy` | `Set-GPRegistryValue` (Registry.pol) | `Values = @( @{ Key = 'HKLM\...'; ValueName; Type; Value } )`: one ADMX policy can be several values | Computer (HKLM) or User (HKCU) |
| `PrefRegistry` | `Set-GPPrefRegistryValue` | `Hive` (`HKLM`/`HKCU`), `Key` (without the hive), `ValueName`, `Type`, `Value`, `Action` (`Update` by default; `Create`, `Replace`, `Delete`) | either |
| `SecurityOption` | GptTmpl.inf `[Registry Values]` | `Key = 'MACHINE\...\ValueName'`, `Type` (`String`, `DWord`, `MultiString`), `Value` | Computer |
| `SystemAccess` | GptTmpl.inf `[System Access]` | `Name` (`EnableGuestAccount`, `NewAdministratorName`, password and lockout policy, ...), `Value` | Computer |
| `UserRight` | GptTmpl.inf `[Privilege Rights]` | `Right` (`SeRemoteInteractiveLogonRight`), `Members` (names or SIDs; written as SIDs) | Computer |
| `RestrictedGroup` | GptTmpl.inf `[Group Membership]` | `Group`, `Members`, `MemberOf` (optional). Replaces the group's members | Computer |
| `Audit` | `audit.csv` | `Subcategory` (as `auditpol` names it: `Credential Validation`), `Setting` (`Success`, `Failure`, `SuccessAndFailure`, `NoAuditing`) | Computer |
| `Service` | GptTmpl.inf `[Service General Setting]` | `Service` (the service name: `Spooler`), `StartMode` (`Automatic`, `Manual`, `Disabled`), `Sddl` (optional; default: Administrators and SYSTEM full control, interactive users read) | Computer |

Registry `Type`: `String`, `ExpandString`, `DWord`, `QWord`, `MultiString`. A DWord is written as a
number (`2147483632`, with the hex in a comment if it helps).

Accounts in `Members`, `MemberOf` and `Group` are written as SIDs: well-known names (`Administrators`,
`Remote Desktop Users`, ...) and the domain's built-in groups (`Domain Admins`, ...) from tables, anything
else looked up in AD when the GPO is built. An account that cannot be found fails only its setting.

## Control tags

`Tags = @('NIST800-53:AC-11', 'NIST800-171:3.1.10', 'HIPAA:164.312(a)(2)(iii)')`: `Framework:Control`
strings, for the compliance profiles later. Frameworks: `HIPAA`, `NIST800-53`, `NIST800-171`, `CMMC`,
`FFIEC`, `STIG`, `MSBaseline`, `CIS` (section numbers only: CIS text is licensed). `@()` until tagged.

## The stamp

`gpo-build` writes `Nutmeg baseline: <Id> <Version>` into the GPO's comment. `gpo-compare` reads it to
find the baseline, and notes when the GPO was built from an older version.

## How a GPO is compared

`gpo-compare` reads the GPO's own files in SYSVOL (`Machine` and `User\Registry.pol`,
`Preferences\Registry\Registry.xml`, `SecEdit\GptTmpl.inf`, `Audit\audit.csv`), so it sees what clients
see. Each setting: **Matches** (a parameter's value is shown in Detail), **Different**, **Missing**,
**Not filled** (a `{Param}` is still in the GPO); then **Extra** for what the GPO sets that the baseline
does not. A `{Param}` member of a user right or group matches any one account.
