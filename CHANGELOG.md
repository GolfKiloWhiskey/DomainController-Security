# Changelog

Newest first. Version numbers are the module's (`Nutmeg.AD.psd1`).

How the numbers move (Cliff, Nov 2026): every change adds to the last number (0.7.1, 0.7.2, ...
0.7.15 is fine). The middle number moves only at a milestone Cliff names. **1.0.0-beta** is the
whole package built and ready for testing as a release; **1.0.0** is the release.

## 0.7.3 - 11/21/2026

- **The New Forest Build's results say what is being built** (Cliff). The first card,
  "Build: cotc.local", lists the forest (name, NetBIOS, level, more DCs planned), this server
  (new name, time zone), the network (IP, prefix, adapter, gateway, DNS), the folders, and when the
  build started with its log file. The console's table starts with the same rows.
- **A "Still to do" card at the end** lists the steps left after the restart (AD DS, the forest
  with the DSRM password, the restart and who to sign in as, the check, the finish).
- A card whose lines all share one status ("Done") no longer repeats "- Done" on every line; the
  badge on the card says it. Mixed cards still show each line's status.
- Not run on Windows yet: tested against stand-ins (199 tests).

## 0.7.2 - 11/21/2026

New Forest Build, from Cliff's review:

- **The server check comes first, in its own pop-up** in the window: the checks with their
  badges, then **Continue** (or Cancel). The domain name question opens after it, on its own.
- **A pending restart no longer risks the AD DS install:**
  - At the check it is a Warning: "Windows is waiting for a restart: the build restarts the
    server before installing AD DS."
  - Phase 0 ends with a restart when the name changes (as before) **or** Windows is waiting for
    one. A VM renamed by hand used to skip the restart and go straight to the roles; now the plan
    says "Restart (Windows is waiting for one)" and does it.
  - Just before AD DS is installed, the build checks again. If Windows is still waiting (an update
    queued another restart), **it stops, installs nothing, and asks**: **Restart now** (in 60
    seconds) or **Restart in 30 minutes**, with a reminder every 5 minutes ("The server restarts in
    20 minutes": Remind me again / Restart now). Back leaves it to you. After the restart and
    sign-in the build carries on.
- Not run on Windows yet: tested against stand-ins (198 tests).

## 0.7.1 - 11/21/2026

From Cliff's review of the first full window run on the VM:

**The build's questions**
- **Answers are saved as you give them.** If the questions stop (Cancel, Back, a closed window),
  the next run says "Answers saved on ...: cotc.local, COTCDC0, ..." and offers to carry on. Each
  saved answer is checked again before it is used: a domain that now answers on the network, or an
  address now in use, is asked again. A new domain name asks the NetBIOS name again; another
  adapter asks the network again. Answering No starts the questions afresh. Once the plan is
  approved, the saved answers give way to the build's own record, which already carried on after
  every restart.
- **The domain and the IP are checked at their question**: "Domain controllers for cotc.local
  already answer on this network" or "Something already answers on 172.20.16.50" appears in red
  and the question is asked again, instead of the build stopping after the last question.
- **Time zone is a list of names** ("(UTC-05:00) Eastern Time (US & Canada)" and the other US zones,
  UTC), the default (Eastern) first, Enter or OK takes it. "Another time zone" still lets you type one.
- Clearer questions: "Prefix length (24 = 255.255.255.0)"; "DNS servers until promotion" with a
  note about commas and the DC's own DNS; the folders question is short, with the paths under it.
- **The plan shows the new forest and this server** ("New forest: cotc.local (COTC)",
  "This server: WIN-... > COTCDC0"), not "Domain: no domain", with numbered steps.
- **A restart is announced**: "Restarting in 60 seconds. Sign in as ... and the build carries on."
  (a pop-up in the window).
- Results read by phase: "Phase 0: Prepare the server", "Phase 1: Promote to the first DC".

**The window**
- Dialogs keep the same width and fit inside the window (the first one ran off the VM's screen).
- Check tables show a coloured badge per row (OK green, Warning amber, Not ready red) and the
  detail in full; their title is short ("Server check").
- The section label ("THE NEW FOREST") stays on every question under it, not just the first.
- The status bar says which question is open ("Question: This server > Computer name") instead
  of "Checking this server..." throughout.
- The text behind the dialogs is hidden while questions are asked.
- No clock icon on "Windows Server 2016 (older DCs can join later)".
- **The build's results are one card per phase**, a line per step ("Time zone: Eastern Standard
  Time (was Pacific Standard Time) - Done"), instead of a card per step titled "0 Prepare".
- **Output panel:** wraps instead of scrolling sideways; no repeated header blocks; a cancelled
  question ends its line with "> (cancelled)"; the time zone change notes that log times jump.
- Not run on Windows yet: tested against stand-ins (191 tests).

## 0.7.0 - 11/21/2026

- **`.\Start-NutmegAD.ps1` checks the server when it starts** (Cliff: on the workgroup VM it opened
  the normal window, with no build in it). Without `-NewForest` or `-Toolkit`:
  - a build in progress on this server: the build opens and carries on;
  - a workgroup server (not joined to a domain): the New Forest Build opens;
  - a DC, a domain member, or a server whose build is finished: the toolkit opens.
  It says why in the console window, for example "WIN-1 is in a workgroup: opening the New Forest Build".
- `-Toolkit` opens the toolkit anyway; `-NewForest` opens the build anyway.
- Not run on Windows yet: tested against stand-ins (177 tests).

## 0.6.0 - 11/21/2026

- **`.\Start-NutmegAD.ps1` opens the window** (Cliff). `-Console` opens the console menu instead;
  `-Gui` still works but is no longer needed. The same goes for the New Forest Build:
  `.\Start-NutmegAD.ps1 -NewForest` is the window, `-NewForest -Console` the console.
- **PowerShell 7 whenever it is installed** (Cliff): started in Windows PowerShell 5.1, the launcher
  moves to PowerShell 7 without asking ("Start the toolkit in PowerShell 7?" is gone). If it isn't
  installed, it offers to install it (now Yes by default). The New Forest Build still runs in 5.1.
- A build started in the console keeps reopening in the console after its restarts (its sign-in
  task now says `-Console`); one started in the window reopens in the window.
- `Get-NutmegAD.ps1` 1.9 asks the launcher for the console with `-Console` when you choose it.
- Not run on Windows yet: tested against stand-ins (175 tests).

## 0.5.0 - 11/21/2026

**A modern look in the window** (Cliff: no console text in the pop-ups; same order of questions as
the console).

- **Questions are clean dialogs.** Each question still comes on its own, in the same order as in the
  console, but the dialog shows only:
  - the section it belongs to ("THE NEW FOREST") and the question itself;
  - the suggested answer already in the box (press OK to take it);
  - warnings and errors as coloured lines, for example a red line when an answer was refused
    ("Use a DNS name with at least two parts");
  - any table the tool showed, as a real table (the server check in the first question).
  Log lines and console borders stay out: they go to the status bar and the Output panel.
- **Changes are approved in one dialog**: what changes, the domain, DC and scope, every target in a
  list, and the box for the word to type (Approve stays greyed out until it matches). The New
  Forest Build's plan is approved this way.
- **The window keeps responding during long steps.** The role install, Microsoft's pre-checks and
  the forest creation run in the background, with the elapsed time at the bottom of the window.
- **While building a forest the header shows this server** (name, workgroup, IP and whether it is
  DHCP), not "Domain and DC: not read yet"; the module chips are hidden until there is a domain.
- The password box only notes problems ("The two did not match"), no log lines.
- The console is unchanged. Not run on Windows yet: tested against stand-ins (174 tests).

## 0.4.0 - 11/21/2026

From a fresh server to the window in one run of `Get-NutmegAD.ps1` (Cliff):

- **`Get-NutmegAD.ps1` installs PowerShell 7** after the download if it is missing, without asking:
  the current LTS, Microsoft's signed MSI, Microsoft Update on (the toolkit's own install, so the
  signature check and the log are the same). It needs administrator; `-SkipPowerShell7` leaves it out.
  A failure is reported and the rest carries on.
- **Then it opens the window**: the New Forest Build on a workgroup server, the toolkit on a
  domain-joined server or DC. `-Console` uses the console instead, for either.
- **The New Forest Build runs in the window** (`.\Start-NutmegAD.ps1 -NewForest -Gui`):
  - the window shows only the build, and its pre-flight and questions start as soon as it opens;
    **Start or continue the build** starts them again;
  - the plan approval (type the short name) and every question are dialogs;
  - the DSRM password is a password box: never shown, saved or logged (the output shows "(hidden)").
    Cancel stops the build with nothing made;
  - the sign-in task reopens the window after each restart, so the whole build stays in it. A build
    started in the console still reopens in the console;
  - it still runs in Windows PowerShell 5.1 (the server roles' modules live there), even with
    PowerShell 7 installed. The window may stop responding while the roles install and the forest
    is made (a few minutes each): wait, it comes back.
- PowerShell 7 isn't needed for the window itself: Windows PowerShell 5.1 runs it too.
- Not run on Windows yet: tested against stand-ins (165 tests). `docs/NEW-FOREST-TESTING.md` has the
  window run.

## 0.3.1 - 11/21/2026

- **`Get-NutmegAD.ps1` opens the window** after the download on a domain-joined server or DC (Cliff),
  instead of the console menu. `-Console` opens the console menu instead. A workgroup server still
  gets the New Forest Build, in the console. The window carries on in the same log
  (`Get-NutmegAD.ps1` 1.7). (Merged into 0.4.0.)

## 0.3.0 - 11/21/2026

**The window** (ported from the M365 toolkit's, now that the New Forest Build's first two phases
passed QA on the VM).

- **Start it with `.\Start-NutmegAD.ps1 -Gui`.** The same tools as the console menu, in a window:
  - the areas on the left (Group Policy, Active Directory, and so on, as tools arrive), the tools of
    the chosen section in the middle, and search across all of them at the top;
  - each tool's options as a form built from its parameters (drop-downs, tick boxes, numbers, lists,
    dates; required boxes marked `*`), or **Guided...** to answer the tool's own questions;
  - results as cards (tags to filter by, such as Created or Failed) or as a table, with a filter,
    Export CSV/TXT, Summary and Row details. Results stay with each tool until cleared;
  - every question, menu and change confirmation the console would show becomes a dialog, with the
    same rules: a domain-wide change still needs the domain's short name typed;
  - the header shows the domain and the DC every tool works against. Click it for **Domain and DC**
    (status, another DC, read the domain again). Moving to another DC clears what was on screen;
  - chips show whether the ActiveDirectory and GroupPolicy modules are loaded (they still load only
    when a tool needs them). The cog opens Settings, and **Run history** lists the last 200 runs.
- **The New Forest Build stays in the console.** It is not in the window, and
  `-NewForest -Gui` starts it in the console.
- `-Gui` is carried through the offers to start as administrator and in PowerShell 7 (started with
  `-STA`, which the window needs), and so is `-LogPath`.
- **New setting:** Settings > Window > Show results as (Cards or Table).
- Left out from the M365 window: the tenant chooser, the cloud switch, sign-in and disconnect, and the
  part-of-a-name lookups for mailboxes and users.
- **Not run on Windows yet.** The window can't run here (WPF is Windows only). Its logic was tested
  without WPF, its layouts were checked as XML, and every control the code looks up was checked to be
  in them. The first run on the VM is the real test.

## 0.2.11 - 11/21/2026

- **`Get-NutmegAD.ps1` updates itself.** Run from outside the toolkit folder (Cliff keeps it in
  `C:\Temp`), it now replaces itself with the copy it just downloaded, so the next run is the latest.
  Seen on the VM: the old 1.4 copy in `C:\Temp` kept the hand-off bug after the toolkit itself was
  fixed, so the toolkit's lines went to a log of their own.
- **Updating from inside the toolkit folder works:** it steps out of the folder before moving it to
  `.previous` (Windows will not rename the folder the console is in).

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
