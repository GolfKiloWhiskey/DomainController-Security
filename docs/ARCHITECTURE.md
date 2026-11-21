# How Nutmeg.AD fits together

Read `CLAUDE.md` first for the rules. This page explains the pieces and where to look. The design is
the Nutmeg M365 Toolkit's (`M365-Tools/docs/ARCHITECTURE.md`), adapted: where this page is silent,
that one describes the same code.

## Layout

```
Start-NutmegAD.ps1          launcher (5.1-safe): elevation offer, PowerShell 7 offer or install, then the menu
Nutmeg.AD/
  Nutmeg.AD.psd1/.psm1      manifest; the .psm1 dot-sources Core/*.ps1 in order, then every Tools/**/*.ps1
  Core/                     everything shared (below)
  Tools/<Category>/         one file per tool; files starting with _ are skipped (_ToolTemplate.ps1)
  Data/                     OuStandard.csv (ou-layout), GpoDefaultLinks.csv (gpo-build's default links)
Tests/Invoke-*Tests.ps1     one test file per area, all against fakes; Invoke-AllTests.ps1 runs them all
Legacy/                     source material: scripts, GPO reports, screenshots; INDEX.md tracks each item
docs/                       this page, TOOL-LIST.md (the agreed plan), baselines/ (agreed baseline specs)
```

## Core, in load order

| File | What it holds |
| --- | --- |
| `Logging.ps1` | `Write-NmLog` (console + session log `NutmegAD_<time>.txt`), `Write-NmRunHistory` / `Get-NmRunHistory` (History.csv: domain, DC, tool, result) |
| `Settings.ps1` | the technician's settings (Main menu > Settings): `$script:NmSettingDefs`, `Get-NmSetting` (environment, then saved, then default), `Set-NmSetting` / `Clear-NmSetting`, DPAPI for secrets, IP range helpers (`Test-NmIpRangeText`, `Test-NmIpInRange`), `Remove-NmOldLog`. File: `%APPDATA%\NutmegAD\Settings.json` |
| `Modules.ps1` | `$script:NmServiceModules` (AD = ActiveDirectory, GPO = GroupPolicy), `Assert-NmModule` (checks and imports, never installs: they are Windows features), `Find-NmModule`, `Import-NmModule` (GroupPolicy through Windows PowerShell in 7) |
| `Export.ps1` | `Export-NmResult` (CSV with BOM / TXT to `C:\Temp`), file names `<tool>_<domain>_<time>` |
| `Menu.ps1` | `Read-NmHost` (the only place input is read), `Read-NmInput`, `Read-NmYesNo`, `Read-NmMultiChoice`, `Wait-NmKey`, `Show-NmHeader`, `Show-NmMenu`, `Show-NmResult` / `Show-NmResultMenu`, navigation (`Push-NmNav`, [M] Main menu). Copied from M365-Tools; its window hooks stay for when the window is ported |
| `Safety.ps1` | `Confirm-NmChange` (lists targets, domain and DC; `-DomainWide` / `-RequireTyped` need the domain's short name typed; `-WhatIf`) |
| `Domain.ps1` | the session (`Get-NmSession`: domain, NetBIOS, forest, SID, DN, levels, PDC, the DC in use, what is loaded), `Assert-NmConnection` (loads modules, reads the domain once), `Get-NmADParams` / `Get-NmGPParams` (splat `-Server`, and `-Domain` for GPO cmdlets), `Set-NmServer`, `Get-NmLocalComputer`, `Test-NmElevated`, `Get-NmAdminMembership`, the banner, Main menu > Domain and DC |
| `PowerShell7.ps1` | `Find-NmPwsh`, `Get-NmPwshLtsVersion` (PowerShell's release metadata), `Install-NmPowerShell7` (signed MSI, `USE_MU=1 ENABLE_MU=1 ADD_PATH=1`) |
| `ToolRegistry.ps1` | `Register-NmTool` (validates `$NmTool`), the areas (`$script:NmAdminCenters`: gpo, ad, ready, report, kit), `Get-NmTool`, `Get-NmAdminCenter`, `Invoke-NmTool` |
| `Launcher.ps1` | `Start-NmToolkit`: the main menu (area > section > tool), Search, Domain and DC, Run history, Settings, tools not loaded |

## A tool's life

1. **Load.** The `.psm1` dot-sources the file; the file sets `$NmTool` and defines functions; the loader
   calls `Register-NmTool`. A syntax error or bad metadata puts the file under "Tools not loaded".
2. **Pick.** An area, then a section, then the tool.
3. **Ask.** The tool's `Prompt` function asks its questions and returns the entry function's parameters,
   or `$null` for Back.
4. **Load what it needs.** `Assert-NmConnection` loads the modules for `Services` (AD always first) and
   reads the domain once, from this DC if it is one, or from a DC AD finds.
5. **Run.** The entry function returns objects, one per row. Every AD call gets `Get-NmADParams`
   splatted (`$p = Get-NmADParams; Get-ADUser ... @p`), so a run talks to one DC. Change tools call
   `Confirm-NmChange` first and return a `Result` per target.
6. **Show.** `Show-NmResult` prints the table; the results menu offers Re-run, Export, Grid view,
   Deep-dive, Summary and [M] Main menu.
7. **Record.** `Write-NmRunHistory` logs one line per run, plus one per change.

`$NmTool` fields:
- **Required:** `Name`, `Id`, `Category`, `Synopsis`, `Version`, `Kind`, `Services` (`AD`, `GPO` or
  `@()`), `Entry`.
- **Optional:** `Area`, `AlsoIn`, `Roles`, `Prompt`, `DeepDive`, `Summary`, `Columns`, `View`,
  `CardGroup`, `BulkAction` with `BulkActions` (as in M365-Tools).

## Tests

- **Each test file** imports the module, gives it its own temp export, data and settings folders,
  replaces `Read-NmHost` with a queue of scripted answers, and stands in for this computer
  (`Get-NmLocalComputer`), the account (`Get-NmCurrentIdentity`, `Test-NmElevated`) and the modules
  (`Find-NmModule`, `Test-NmModuleLoaded`, `Import-NmModule`) inside the module.
- **AD and GroupPolicy cmdlets** are global fake functions that record their calls. Fakes must refuse
  what the real cmdlets refuse.
- `Answer @('1', 'y')` queues answers and `Reset-Fake` clears the session; both are global, so test
  bodies (which run inside the module) can call them.
- **`Tests/Invoke-AllTests.ps1`** runs every file and prints a total. Any failure exits with code 1.

## Adding a tool: checklist

1. Copy `Tools/_ToolTemplate.ps1` to `Tools/<Category>/<Verb>-Nm<Thing>.ps1`. Fill in the header,
   `$NmTool` (with `Area`), the entry function, and optionally `Prompt`, `DeepDive` and `Summary`.
2. Follow the tool rules in `CLAUDE.md`.
3. Add tests to the matching `Tests/Invoke-*Tests.ps1`, with fakes for any new cmdlets.
4. Update `README.md` (tool table), `CHANGELOG.md`, the module version and `docs/TOOL-LIST.md`.
   If it ports a legacy script, update `Legacy/INDEX.md`.
5. Run `Tests/Invoke-AllTests.ps1`, PSScriptAnalyzer and the ASCII check (the core tests include it).
