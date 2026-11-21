# DomainController-Security

The Nutmeg AD Toolkit (`Nutmeg.AD`): one menu-driven PowerShell module for Active Directory domain
controller onboarding after the DC is built by hand: OU layout, GPO baselines, readiness checks,
reports and day-to-day AD admin. Hardening (DC and domain) comes from the GPO baselines. Building a DC
(installing AD DS, creating the forest, promoting DCs) stays manual and is not part of the toolkit.

It follows the Nutmeg M365 Toolkit's pattern (M365-Tools): one core for menus, logging, safety
prompts, exports and settings, and one file per tool. The plan is `docs/TOOL-LIST.md`.

## Run it

On a domain controller, as a domain admin:

```powershell
.\Start-NutmegAD.ps1
```

- Works in Windows PowerShell 5.1 and PowerShell 7 (7 recommended).
- Not elevated: offers to start again as administrator.
- In 5.1: offers to start again in PowerShell 7, or to install the current PowerShell 7 LTS release
  first (Microsoft's signed MSI, with Microsoft Update on).
- `-Stay` skips both offers.

Nothing is loaded at start. The first tool that needs the ActiveDirectory or GroupPolicy module loads
it and reads the domain from this DC. **Domain and DC** in the main menu shows the domain, its levels
and the PDC, and can point the toolkit at another DC.

Logs and run history: `C:\Temp\NutmegAD`. Exports: `C:\Temp`. Settings (per Windows user):
`%APPDATA%\NutmegAD\Settings.json`.

## Tools

| Area | Section | Tool | Id | Kind |
| --- | --- | --- | --- | --- |
| Toolkit | Diagnostics | Session and Prerequisite Check (PowerShell, elevation, DC, modules, domain, admin groups, folders) | `session-info` | Report |

The rest are listed in `docs/TOOL-LIST.md` and arrive in the order given there.

## Run a tool without the menu

```powershell
Import-Module .\Nutmeg.AD\Nutmeg.AD.psd1
Invoke-NmTool -Id session-info -NoMenu
```

`Get-NmTool` lists every tool and its Id.

## Layout

```
Start-NutmegAD.ps1          launcher
Nutmeg.AD/
  Nutmeg.AD.psd1 / .psm1    module manifest and loader
  Core/                     domain session, modules, logging, menus, exports, safety, settings, registry, launcher, PowerShell 7
  Tools/<Category>/         one file per tool; _ToolTemplate.ps1 shows the format
  Data/                     OuStandard.csv, GpoDefaultLinks.csv
Tests/Invoke-CoreTests.ps1  core tests (no domain or AD module needed)
Tests/Invoke-AllTests.ps1   runs every test file and prints a total
Legacy/                     source material: scripts, GPO reports, screenshots; INDEX.md tracks each item
docs/                       ARCHITECTURE.md, TOOL-LIST.md, baselines/
```

## Add a tool

1. Copy `Nutmeg.AD/Tools/_ToolTemplate.ps1` to `Nutmeg.AD/Tools/<Category>/<Verb>-Nm<Thing>.ps1`.
2. Fill in the `$NmTool` block and the entry function. `Area` says where it shows in the menu
   (`gpo/Baselines`, `ad/Structure`, `ready`, `report`, `kit`). List the modules it needs in
   `Services` (`AD`, `GPO`); don't load them yourself. Send every AD call to the session's DC with
   `Get-NmADParams` (GroupPolicy cmdlets: `Get-NmGPParams`).
3. Change tools call `Confirm-NmChange` before every write and support `-WhatIf`.
4. Run `.\Tests\Invoke-AllTests.ps1`, then start the toolkit. A tool with a problem in its metadata
   shows under **Tools not loaded** with the reason.

## Intake

Source material lives under `Legacy/` (see `Legacy/README.md` and `Legacy/INDEX.md`): scripts,
screenshots, and the GPO HTML reports the baselines are built from. Nothing there is loaded by the
toolkit.
