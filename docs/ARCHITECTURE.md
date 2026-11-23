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
  Baselines/                one .psd1 file per GPO baseline (docs/baselines/FORMAT.md)
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
| `Menu.ps1` | `Read-NmHost` (the only place input is read; a dialog while the window is open), `Read-NmSecret` (passwords, as a SecureString), `Read-NmInput`, `Read-NmYesNo`, `Read-NmMultiChoice`, `Wait-NmKey`, `Show-NmHeader`, `Show-NmMenu`, `Show-NmResult` / `Show-NmResultMenu`, navigation (`Push-NmNav`, [M] Main menu). Copied from M365-Tools, with its window hooks |
| `Safety.ps1` | `Confirm-NmChange` (lists targets, domain and DC; `-DomainWide` / `-RequireTyped` need the domain's short name typed, or `-ConfirmWord`; `-WhatIf`; goes ahead without asking while an approved plan runs) |
| `Domain.ps1` | the session (`Get-NmSession`: domain, NetBIOS, forest, SID, DN, levels, PDC, the DC in use, what is loaded), `Assert-NmConnection` (loads modules, reads the domain once), `Get-NmADParams` / `Get-NmGPParams` (splat `-Server`, and `-Domain` for GPO cmdlets), `Set-NmServer`, `Get-NmLocalComputer`, `Test-NmElevated`, `Get-NmAdminMembership`, the banner, Main menu > Domain and DC |
| `PowerShell7.ps1` | `Find-NmPwsh`, `Get-NmPwshLtsVersion` (PowerShell's release metadata), `Install-NmPowerShell7` (signed MSI, `USE_MU=1 ENABLE_MU=1 ADD_PATH=1`) |
| `Server.ps1` | the server before and during the New Forest Build, one small wrapper per Windows call: `Get-NmOsInfo`, `Get-NmNetAdapterInfo`, `Get-NmSuggestedDcIp` (.50), `Test-NmIpInUse`, `Set-NmStaticIp`, `Set-NmComputerName`, `Set-NmTimeZone`, `Test-NmDomainAnswers` (SRV lookup), `Register-NmResumeTask` (sign-in task for the Administrators group), `Restart-NmServer`, `Install-NmAddsFeature`, `Test-NmForestInstallation`, `Install-NmForest`, `Test-NmWindowsPowerShell` |
| `Steps.ps1` | a live list of a long run's steps: `Start-NmStepList` (steps, groups, done-earlier ticks), `Set-NmStepStatus` (Running, Done, Failed; a console line when one finishes), `Write-NmStepProgress` (what a long step reports, logged once per change), `Get-NmStepListModel` (what the window draws, no WPF). `Invoke-NmBuildStep` marks build steps on it; the window draws it above the results (`Update-NmGuiSteps`) and `Invoke-NmGuiBackground` passes the background call's progress records to it |
| `Report.ps1` | `New-NmHtmlReport` (a report as sections: Facts, Table with status badges, List; one self-contained, print-ready HTML file, ASCII-safe), `Get-NmReportFolder` (`<DataRoot>\Reports`), `ConvertTo-NmPdf` (headless Edge, `Find-NmEdge` / `Invoke-NmEdgePdf`; '' when there is no Edge) |
| `DcHealth.ps1` | `Get-NmDcHealth` (FSMO roles, AD services, SYSVOL and NETLOGON, DNS zones, DNS client settings, time source, dcdiag) for this DC or another (`-ComputerName` on each wrapper: CIM/WMI, `w32tm /computer:`, `dcdiag /s:`), one wrapper per Windows call (`Get-NmDcNetwork`, `Get-NmHardwareInfo`, `Get-NmSysvolState`, ...), `ConvertFrom-NmDcDiag` (noisy-after-promotion tests as warnings) |
| `Baseline.ps1` | the baseline files (`docs/baselines/FORMAT.md`): `Get-NmBaseline` (loads `Baselines\*.psd1` once, each with its `Problems`), `Test-NmBaseline` (every rule the files must follow), `Test-NmBaselineTag`, placeholders (`Get-NmBaselinePlaceholder`, `Expand-NmBaselineText`, `Expand-NmBaselineValue`), parameters (`Get-NmBaselineDefault`, `Test-NmBaselineParamValue`, `Resolve-NmBaselineValues`, `Read-NmBaselineParameter`), the stamp (`Get-NmBaselineStamp`, `Read-NmBaselineStamp`), the audit subcategory table, `Get-NmBaselineDefaultLink` (Data\GpoDefaultLinks.csv) |
| `GpoFiles.ps1` | a GPO's files in SYSVOL, with no GroupPolicy cmdlet: `Get-NmGpoFolder` (`\\<DC>\SYSVOL\<domain>\Policies\{GUID}`; the tests point it at a temp folder), Registry.pol (`ConvertFrom-NmRegistryPol`), Registry.xml (`ConvertFrom-NmPrefRegistryXml`), GptTmpl.inf (`ConvertFrom-NmInf`, `ConvertTo-NmGptTmplLine`, `Write-NmGptTmpl`: UTF-16, merged), audit.csv (`Write-NmGpoAudit`), the GPO's extensions and version (`Merge-NmGpoExtensionName`, `Update-NmGpoVersion`: AD and GPT.INI), `Resolve-NmAccountSid` |
| `GpoBaseline.ps1` | `Invoke-NmBaselineWrite` (a baseline's settings into a GPO: cmdlets for templates and preferences, the files for the rest, the version raised once) and `Compare-NmGpoWithBaseline` (the GPO's files and the baseline as items with an identity and a value: Matches, Different, Missing, Not filled, Extra, Note). `gpo-build` and `gpo-compare` are thin tools on these, so the New Forest Build can call them |
| `Build.ps1` | the build's state file (`<DataRoot>\NewForest\State.json`: answers, never passwords; each step's status), `Invoke-NmBuildStep` (skips Done steps, records Done/Failed, run history), `Set-NmPlanApproved` (one confirmation for a whole plan) |
| `ToolRegistry.ps1` | `Register-NmTool` (validates `$NmTool`), the areas (`$script:NmAdminCenters`: gpo, ad, ready, report, kit), `Get-NmTool`, `Get-NmAdminCenter`, `Invoke-NmTool` |
| `Launcher.ps1` | `Get-NmStartMode` (what `Start-NutmegAD.ps1` opens when not told: the build on a workgroup server or with a build in progress, otherwise the toolkit), `Start-NmToolkit`: the main menu (area > section > tool), Search, Domain and DC, Run history, Settings, tools not loaded |
| `Gui.ps1` | `Start-NmToolkitGui`: the WPF window (`Start-NutmegAD.ps1` opens it; `-Console` for the console menu), ported from M365-Tools. While it is open, module-scope proxies for `Write-Host`, `Out-Host`, `Format-Table`, `Format-List` and `Write-Progress` collect what tools print, and `Read-NmHost` turns each prompt into a dialog, so tools need nothing of their own for it. The header shows the domain and DC (`Get-NmGuiDomainText`; Domain and DC opens `Show-NmDomainMenu`); results are kept per tool and per domain and DC (`Get-NmGuiTarget`). Areas in `$script:NmGuiConsoleOnlyAreas` (build) are left out of the normal window; `Start-NmToolkitGui -NewForest` (build mode) shows only them and starts the build's questions at once. `Read-NmSecret` becomes a password dialog (`Read-NmGuiSecret`, a PasswordBox; only "(hidden)" is echoed). No console text in dialogs: `Get-NmGuiDialogModel` splits what a tool wrote into a section (Cyan heading), notes (WARN/ERROR log lines, Red/Yellow/Green lines, remembered by the `Write-Host` proxy in `Marks`), plain text and the suggested answer; tables a tool prints are kept as tables and shown as grids (their text goes only to the Output panel). `Confirm-NmChange` in the window is one approval dialog (`Read-NmGuiConfirm`). Long calls (role install, forest pre-checks, promotion) go through `Invoke-NmGuiBackground`: their own runspace while the window is open, so it keeps responding. **Layout** (0.7.16): the menu button (top left) hides the areas and tools columns (`Switch-NmGuiPanelState`); drag handles (GridSplitter) between the columns, between options and results, and between results and Output; the options fold into one line after Run (`Get-NmGuiOptionsSummary`, Edit options opens them); Output is its own pane when open. Kept per person in `Window.json` beside `Settings.json` (`Read-NmGuiLayout`, `Save-NmGuiLayout`, saved on close; right-click the menu button to reset). **Look** (0.7.15): Settings > Window > Window look, Windows 11 (default) or Classic. Windows 11 is the WPF Fluent theme (`ThemeMode` on every window, .NET 9+, so PowerShell 7 only), light or dark as Windows is set (`Get-NmGuiLook`); Windows PowerShell 5.1 is always Classic, light. Colours are written once as the light palette's hex values; `Resolve-NmGuiColor` (through `Get-NmGuiBrush` and `New-NmGuiXaml` for XAML) maps them to the Nutmeg brand (`#CF2027`, from the logo, in place of the old teal) and to dark values (`$script:NmGuiBrand`, `$script:NmGuiDark`). Text that stays light on red or the sidebar is written `#FFFFFE` / `#C9CED7`. Logic that needs no WPF is in model functions (`Get-NmGuiSidebarModel`, `Get-NmGuiParamSpec`, `Get-NmGuiCardModel`, ...) tested in `Tests/Invoke-GuiTests.ps1` |

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
  `CardGroup`, `BulkAction` with `BulkActions` (as in M365-Tools), and for the window:
  - `CardGroup = @('<group>', '<split>', '<line>')`: one card per value of the first column, its rows
    listed under the values of the second, each shown as the third column alone (gpo-compare: a card per
    GPO, settings under Different / Missing / Matches). When the split column is the status, the card
    takes the worst status.
  - `Pickers = @{ <Param> = @{ Items = '<function>'; NeedsDomain; Note; Empty } }`: the parameter is
    chosen from a list instead of typed: ticks for `[string[]]` (with search, Select all / none and a
    count), a drop-down for `[string]`. The function returns items with Key (what the tool gets),
    Label, Detail (a grey line), Badge and Disabled. `NeedsDomain` waits for "Load the list".
  - `CardNoun = 'GPO'` and `CardFacet = '<column>'` (grouped cards): the headline counts cards ("9 GPOs")
    and the tags count cards by a column that is the same on every row of a card, with "All n" first;
    a tag filters whole cards (gpo-compare: `GpoState`).
  - `CardActions = @(@{ Label; Action = '<function>'; ToolTip })`: buttons on every card; the function
    gets the card's first row (gpo-compare and gpo-build: Edit GPO, View GPO).
  - `BeforeRun = '<function>'`: takes the form's arguments when Run is pressed, asks what the form
    cannot hold (dialogs), and returns the full arguments, or `$null` to run nothing (gpo-build: each
    ticked baseline's values and GPO name).

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
6. After it passes QA in the console, check it in the window (the launcher's default): its parameters become the form
   (`[ValidateSet]` a drop-down, `[switch]` a tick box, `[int]` a number, `[string[]]` a comma list,
   `[datetime]` a date; hashtables and objects are left to Guided), and a status column named
   `Result`, `Status` or `State` becomes the cards' tags.
