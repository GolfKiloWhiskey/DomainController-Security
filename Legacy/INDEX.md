# Legacy intake index

Every script, screenshot and GPO report sent for the toolkit, and where it goes. Nothing in `Legacy/` is
loaded by `Nutmeg.AD`. Once an item is ported or its deletion is confirmed it is removed from this
folder (git history keeps it) and its row stays here.

Statuses: **Ported** (tool id), **To do**, **Reference** (kept to read, not run), **Deleted**, **Retire**, **Keep outside**.

## From M365-Tools

Scripts the M365 toolkit set aside as "keep outside" (server-side, on-prem AD or device scripts).
Copied as they were in `M365-Tools/Legacy`; they stay there too until that repo's index is updated.

| Script | Status | What it does | Notes |
| --- | --- | --- | --- |
| [AAD Sync/AADSyncHealth.ps1](Scripts/From-M365-Tools/AAD%20Sync/AADSyncHealth.ps1) | To do | Checks Entra Connect connectors, password hash sync and heartbeat events on the sync server | Runs on the Entra Connect server, not a DC |
| [AAD Sync/MigrateSettings.ps1](Scripts/From-M365-Tools/AAD%20Sync/MigrateSettings.ps1) | Reference | Microsoft's script: exports an old Entra Connect config for upgrade | Not Cliff's; don't port |
| [Get-EventIDHashTables.ps1](Scripts/From-M365-Tools/Get-EventIDHashTables.ps1) | To do | Reads a Security event (4625) into its named fields | Seed for an event lookup helper in the core |
| [AzureUserHygeine(Look first).ps1](Scripts/From-M365-Tools/AzureUserHygeine%28Look%20first%29.ps1) | Reference | Account hygiene export joining on-prem AD (via a local GC) with MSOnline/AzureAD | MSOnline and AzureAD are retired; only the on-prem AD half (stale, disabled accounts) is worth reusing |
| [Device and GPO/MDM Join.ps1](Scripts/From-M365-Tools/Device%20and%20GPO/MDM%20Join.ps1) | To do | Registry key and scheduled task to start MDM auto-enrollment | Likely becomes a GPO baseline item (MDM auto-enrollment policy) |
| [Device and GPO/Invoke-ZeroTouchMDMRemediation.ps1](Scripts/From-M365-Tools/Device%20and%20GPO/Invoke-ZeroTouchMDMRemediation.ps1) | To do | Clears broken Entra join state, forces Hybrid join and Intune enrollment (GCC High URLs) | Relies on a GPO; pairs with the hybrid join / MDM GPO |
| [Device and GPO/PreventBingInstall.ps1](Scripts/From-M365-Tools/Device%20and%20GPO/PreventBingInstall.ps1) | To do | Sets the Office policy value that stops the Bing extension install | One registry policy value; belongs in a GPO baseline, not a script |

Left in M365-Tools (workstation troubleshooting, not DC or GPO work): `Get-EntraID_RegisteredState.ps1`,
`Purge-MicrosoftOfficeLoginData.ps1`, `Purge-O365Token_Creds.ps1`.

## Your scripts

(None yet.)

## Screenshots

(None yet.)

## GPO baselines

(None yet.)
