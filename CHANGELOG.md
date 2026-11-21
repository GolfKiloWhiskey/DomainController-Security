# Changelog

Newest first. Version numbers are the module's (`Nutmeg.AD.psd1`).

## 0.2.10 - 11/21/2026

- **Fixed: `Get-NutmegAD.ps1` could not hand over to PowerShell 7** ("Missing an argument for parameter
  'LogPath'", seen on the VM). It passed `-NewForest` and `-LogPath` as a list, and a PowerShell script
  takes a list in order: the log path became the text `-LogPath`, and `-NewForest` was lost, so on a
  fresh server the build would not have started either. They now go over as named parameters
  (`Get-NutmegAD.ps1` 1.5), and the launcher ignores a log path that is really a parameter name
  (0.3.2). The new test calls a copy of the launcher's parameters the way the script does.

## 0.2.9 - 11/21/2026

- **The window is left in the toolkit folder** (Cliff), ready to run it again, instead of
  `C:\WINDOWS\system32` where the build's sign-in task opened it. `Start-NutmegAD.ps1` moves to its own
  folder when it starts, and the sign-in task now starts there too.
- The finished build's message says what to run next: `.\Start-NutmegAD.ps1`.

## 0.2.8 - 11/21/2026

- **The New Forest Build offers Eastern Standard Time** as the time zone (Cliff), not whatever the
  fresh server came with. Press Enter to take it, or type another. The default lives in
  Settings > New forest build, for a client somewhere else.
- Two sessions started in the same second no longer share a log file (the second gets `_2`).

## 0.2.7 - 11/21/2026

- **One log from download to finished DC** (Cliff). `Get-NutmegAD.ps1` starts the log in
  `C:\Temp\NutmegAD\Logs` and hands it to the toolkit, which carries on in it. The New Forest Build
  records the log in its state file, so after each restart the sign-in task's session writes to the
  same file. Each new session in it starts with a line such as
  `---- Session continued: Administrator on DC01, Windows PowerShell 5.1, toolkit 0.2.7 ----`.
  Once the build is finished, sessions go back to a log each.
- `Start-NutmegAD.ps1 -LogPath <file>` carries on in a given log (and passes it on when it starts
  itself again as administrator or in another PowerShell).

## 0.2.6 - 11/21/2026

Log fixes from the second New Forest Build run on the VM (which passed):

- **Each build step now logs what it did**, for example `Build step done: Static IP - 192.0.2.50/24
  via 192.0.2.1`, or that the name or IP was already set. Before, the log only said a step started.
- **The time zone step says the log's clock moves** ("log times from here on are in the new zone"),
  so the jump in the times right after it (21:09 to 00:09 on the VM) is explained in the log itself.
- **Leaving a tool after it ran logs "Closed <tool>"**, not "Cancelled." Cancelled is now only for
  backing out before anything ran.
- **"(no domain)" no longer shows as "((no domain))"** in confirmation lines.

## 0.2.5 - 11/21/2026

- **Clean screen at start** (issue #6). `Get-NutmegAD.ps1` clears the window before its header, and
  the New Forest Build opens on a cleared screen with the toolkit header (the main menu already did).

## 0.2.4 - 11/21/2026

- **`Get-NutmegAD.ps1` starts the toolkit when the download is done** (Cliff). It changes to the
  toolkit folder and starts the New Forest Build on a workgroup server, or the main menu on a
  domain-joined server or DC. `-StartBuild` or `-Start` picks one; `-NoStart` only downloads.

## 0.2.3 - 11/21/2026

From the first run on a real DC (Cliff's Server 2025 VM, PowerShell 7.6.10):

- **GroupPolicy showed "not installed" on a DC that has it.** PowerShell 7 hides Windows PowerShell
  modules that aren't marked for 7 unless they are looked for with `-SkipEditionCheck`, and
  GroupPolicy is one of them. The toolkit now looks for them that way; GroupPolicy still loads
  through Windows PowerShell as before.
- **Long values in result tables were cut off** ("Install-WindowsFeature ..."). Tables now wrap
  them onto the next line instead.

## 0.2.2 - 11/21/2026

- **Downloads are fast in Windows PowerShell 5.1 now.** The PowerShell 7 install and
  `Get-NutmegAD.ps1` were crawling at a few hundred KB/s while a browser got the same file at once.
  The cause was 5.1's download progress bar, which it redraws for every piece it receives. Both
  now download with it off, and the PowerShell 7 install says how big the file was and how long it took.

## 0.2.1 - 11/21/2026

- **`Get-NutmegAD.ps1` puts the toolkit on a server**, or updates it. It is a standalone script,
  not part of the module: copy the one file to the server (or paste it into Windows PowerShell).
  - Asks for a GitHub token without showing it, and never saves or logs it. Use a fine-grained token
    for this repository only, with Contents: Read-only.
  - Downloads the branch you name (`main` by default) into `C:\Tools\DomainController-Security`, checks
    it really is the toolkit, keeps the copy that was there as `.previous`, and unblocks the files.
  - Shows the toolkit version and commit. `-StartBuild` goes straight into the New Forest Build.

## 0.2.0 - 11/21/2026

The New Forest Build's first two phases: a freshly installed Windows Server to the first DC of a new
forest. Built first so it can be tested on a checkpointed VM again and again.

- **Start it with `.\Start-NutmegAD.ps1 -NewForest`** on the workgroup server. It always runs in
  Windows PowerShell 5.1 (the server role modules live there) and offers to restart as administrator.
- **Pre-flight first, before any question.** It stops, changing nothing, if PowerShell isn't 5.1, it
  isn't elevated, the server is not Windows Server 2016 or later or is already a DC, it is joined to
  a domain, toolkit files are still blocked from the download, or there is no network. It warns about a
  pending restart, low disk space and a second network adapter, and notes the hypervisor.
- **Then every question, once:** domain name and NetBIOS name, functional level (2025, or 2016 if
  older DCs may join), whether more DCs are planned, computer name, time zone, the network adapter (if
  there are several), the static IP (offers `.50` in the current subnet), prefix, gateway, DNS until
  promotion, and the database folders (C:\Windows by default). It refuses a domain that already
  answers on the network, or an address something already answers on.
- **One approval:** the whole plan is shown and approved by typing the domain's short name. Nothing
  else is asked until the DSRM password.
- **Phase 0:** time zone, computer name, a sign-in task that reopens the build after each restart,
  then the static IP (last, because it drops an RDP session to the old address; it says the new one).
  Restarts if the name changed; otherwise it carries straight on.
- **Phase 1:** installs AD DS, DNS, Group Policy Management and the AD module, asks for the DSRM
  password twice (never saved or logged), runs Microsoft's own pre-checks, creates the forest and
  restarts.
- **After the restart:** sign in as `<NETBIOS>\Administrator`; the build reopens, checks the new DC
  answers for the domain, removes the sign-in task and saves the answers to `C:\Temp` as a record.
- **It picks up where it stopped.** Every step is recorded in `C:\Temp\NutmegAD\NewForest\State.json`.
  After a failure, fix the cause and run it again: finished steps are skipped.
- Phases 2 to 5 (DNS, time, OUs, GPOs, report) come next.
- Not run on Windows yet: tested against stand-ins for the server. `docs/NEW-FOREST-TESTING.md` is the
  checklist for the first runs on the VM.

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
