# Changelog

Newest first. Version numbers are the module's (`Nutmeg.AD.psd1`).

## 0.1.0 - 11/20/2026

The first working version: the toolkit opens, finds the domain and runs its first tool.

- **Start it with `.\Start-NutmegAD.ps1`.** It works in Windows PowerShell 5.1 and PowerShell 7.
  - Not running as administrator: it offers to start again elevated.
  - In 5.1 it offers to start again in PowerShell 7. If 7 isn't installed, it offers to install the
    current LTS release from Microsoft. The download is only run if it is signed by Microsoft, and it
    is installed with Microsoft Update on, so it gets patched with Windows.
- **The main menu** has the areas from the tool list (Group Policy, Active Directory, Hardening
  readiness, Reports, Toolkit), Search, Domain and DC, Run history and Settings. Areas show up as
  their tools are added.
- **Nothing loads at start.** The first tool that needs the ActiveDirectory or GroupPolicy module
  loads it and reads the domain from this DC. Domain and DC shows the domain, its levels and the PDC,
  and can point the toolkit at another DC.
- **Changes always ask first.** A change to the whole domain, or to more than 25 objects, needs the
  domain's short name typed (for clientx.local: `clientx`).
- **Session and Prerequisite Check** (`session-info`, Toolkit > Diagnostics): PowerShell version,
  elevation, whether this is a DC, the AD and GroupPolicy modules, the domain and forest, whether
  you are in Domain, Schema and Enterprise Admins, and where logs and exports go.
- Logs, run history and exports go under `C:\Temp` as in the M365 toolkit (`C:\Temp\NutmegAD` for
  logs and history). Settings are per Windows user in `%APPDATA%\NutmegAD\Settings.json`.
- Not tested on a real DC yet: everything was tested against stand-ins for AD.
