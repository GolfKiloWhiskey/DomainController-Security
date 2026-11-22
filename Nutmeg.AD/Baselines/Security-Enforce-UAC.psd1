# Baseline: Security - Enforce UAC (from Cliff's GPO report). Format: Core\Baseline.ps1.
@{
    Id          = 'security-enforce-uac'
    Name        = 'Security - Enforce UAC'
    Version     = '0.7.1'
    Description = 'User Account Control on everywhere: admin approval mode (the built-in Administrator too), credentials on the secure desktop for admins and users, installs detected.'
    Source      = 'Legacy/GPO-Reports/Security - Enforce UAC.html'
    Requires    = @()
    Notes       = @('Linked at the domain root (Data\GpoDefaultLinks.csv).')
    Parameters  = @()
    Settings    = @(
        @{ Id = 'admin-approval-builtin'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'User Account Control: Admin Approval Mode for the Built-in Administrator account = Enabled'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\FilterAdministratorToken'; Type = 'DWord'; Value = 1 }
        @{ Id = 'uiaccess-secure-desktop'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'User Account Control: Allow UIAccess applications to prompt for elevation without using the secure desktop = Disabled'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableUIADesktopToggle'; Type = 'DWord'; Value = 0 }
        @{ Id = 'prompt-admins'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'User Account Control: Behavior of the elevation prompt for administrators in Admin Approval Mode = Prompt for credentials on the secure desktop'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorAdmin'; Type = 'DWord'; Value = 1 }
        @{ Id = 'prompt-users'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'User Account Control: Behavior of the elevation prompt for standard users = Prompt for credentials on the secure desktop'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\ConsentPromptBehaviorUser'; Type = 'DWord'; Value = 1 }
        @{ Id = 'detect-installs'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'User Account Control: Detect application installations and prompt for elevation = Enabled'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableInstallerDetection'; Type = 'DWord'; Value = 1 }
        @{ Id = 'admin-approval-all'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'User Account Control: Run all administrators in Admin Approval Mode = Enabled'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\EnableLUA'; Type = 'DWord'; Value = 1 }
        @{ Id = 'secure-desktop'; Kind = 'SecurityOption'; Side = 'Computer'; Tags = @()
           Title = 'User Account Control: Switch to the secure desktop when prompting for elevation = Enabled'
           Key = 'MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\PromptOnSecureDesktop'; Type = 'DWord'; Value = 1 }
    )
}
