<#
  RMAppxCLG.ps1 - Debloat des applis Windows preinstallees (AppX) pour le master eCollege19.

  A lancer en ADMINISTRATEUR. Retire, pour CHAQUE motif :
    - le paquet installe pour TOUS les utilisateurs (Remove-AppxPackage -AllUsers)
    - le paquet PROVISIONNE (Remove-AppxProvisionedPackage) -> ne revient PAS pour les nouveaux
      profils crees apres sysprep. C'est ce point qui compte pour un master.

  Idempotent (rejouable), tolerant (un echec sur un paquet n'arrete pas le reste), et journalise.
  Optionnel : -NumLock active le pave numerique au demarrage (ecran de connexion + nouveaux profils).

  NE PAS retirer : Store (WindowsStore), App Installer/winget (DesktopAppInstaller), dependances
  (VCLibs, NET.Native, UI.Xaml), Terminal, et les outils utiles (Calculatrice, Photos, Paint,
  Bloc-notes, Outil Capture, Camera). Ils sont volontairement absents de la liste ci-dessous.

  .EXAMPLE
    .\RMAppxCLG.ps1 -NumLock
#>
[CmdletBinding()]
param([switch]$NumLock, [switch]$KeepTeams)   # -KeepTeams : garde MSTeams (master ADMIN : le rectorat s'en sert)
$ErrorActionPreference = 'Continue'

# Motifs a retirer (comparaison -like, donc les variantes/editeurs sont captures). Grouper par theme.
$Remove = @(
    # --- Xbox / jeux ---
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.Xbox.TCUI'
    'Microsoft.GamingApp'                       # "Xbox" (Win11)
    'Microsoft.MicrosoftSolitaireCollection'
    # --- Communication / social (Win11 : les "conneries") ---
    '*WhatsApp*'                                # 5319275A.WhatsAppDesktop
    'Microsoft.OutlookForWindows'              # "nouveau Outlook"
    'MicrosoftTeams'                            # Teams perso (consumer)
    'MSTeams'                                    # Teams (nouvelle base Win11)
    'microsoft.windowscommunicationsapps'       # Courrier & Calendrier
    'Microsoft.People'
    'Microsoft.SkypeApp'
    'Microsoft.YourPhone'                       # Mobile / Phone Link
    'Microsoft.Messaging'
    '*LinkedIn*'                                # 7EE7776C.LinkedInforWindows
    # --- Media / creation grand public ---
    'Microsoft.ZuneMusic'                       # Media Player (Groove)
    'Microsoft.ZuneVideo'                       # Films et TV
    'Clipchamp.Clipchamp'                       # editeur video
    'Microsoft.Microsoft3DViewer'
    'Microsoft.Print3D'
    'Microsoft.MixedReality.Portal'
    # --- Productivite / promo ---
    'Microsoft.MicrosoftOfficeHub'              # "Office" / Microsoft 365 (promo)
    'Microsoft.Office.OneNote'
    'Microsoft.Todos'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Windows.DevHome'
    # --- Bing / Copilot / Cortana / assistants ---
    'Microsoft.BingWeather'
    'Microsoft.BingNews'
    'Microsoft.BingSearch'
    'Microsoft.Copilot'
    'Microsoft.Windows.Ai.Copilot.Provider'
    'Microsoft.549981C3F5F10'                   # Cortana
    # --- Divers / telemetrie ---
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'                      # "Conseils"
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.OneConnect'                      # Mobile Plans
    'Microsoft.Wallet'
    'Microsoft.WindowsMaps'
    'MicrosoftCorporationII.QuickAssist'        # Assistance rapide
    'Microsoft.Windows.Family'                  # Controle parental (Family)
)

# -KeepTeams : on retire Teams de la liste (master ADMIN). 'MicrosoftTeams' = Teams perso, 'MSTeams' = Teams (base Win11).
if ($KeepTeams) { $Remove = @($Remove | Where-Object { $_ -notin @('MicrosoftTeams', 'MSTeams') }) }

function Write-Log($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

$removedInst = 0; $removedProv = 0
foreach ($pat in $Remove) {
    # 1) Provisionne (image) EN PREMIER : le retrait -AllUsers deprovisionne souvent au passage, ce qui
    #    ferait afficher "0 provisionne" a tort. On retire donc le provisionne avant l'installe -> compte fidele.
    try {
        foreach ($pp in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $pat })) {
            try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null; $removedProv++; Write-Log ("  - retire (provisionne) : " + $pp.DisplayName) 'Yellow' }
            catch { Write-Log ("  ! echec retrait provisionne : " + $pp.DisplayName + " (" + $_.Exception.Message + ")") 'DarkGray' }
        }
    } catch {}
    # 2) Installe pour tous les utilisateurs
    try {
        foreach ($p in @(Get-AppxPackage -AllUsers -Name $pat -ErrorAction SilentlyContinue)) {
            try { Remove-AppxPackage -AllUsers -Package $p.PackageFullName -ErrorAction Stop; $removedInst++; Write-Log ("  - retire (installe) : " + $p.Name) 'DarkYellow' }
            catch { Write-Log ("  ! echec retrait installe : " + $p.Name + " (" + $_.Exception.Message + ")") 'DarkGray' }
        }
    } catch {}
}
Write-Log ("Debloat termine : " + $removedInst + " installe(s) retire(s) + " + $removedProv + " provisionne(s) retire(s).") 'Green'

# --- OneDrive : installeur Win32 (pas un AppX) -> desinstalleur dedie + coupe la reinstallation auto
#     par profil (Active Setup). L'utilisateur qui le veut peut toujours le reinstaller (Store / web). ---
Write-Log "OneDrive : desinstallation..." 'Gray'
try {
    Get-Process 'OneDrive' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $od = @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($od) { Start-Process -FilePath $od -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue; Write-Log "  - OneDrive desinstalle (OneDriveSetup /uninstall)." 'Yellow' }
    else { Write-Log "  - OneDriveSetup.exe introuvable (deja retire ?)." 'DarkGray' }
    # AppX OneDriveSync eventuel (rare)
    foreach ($p in @(Get-AppxPackage -AllUsers -Name '*OneDriveSync*' -ErrorAction SilentlyContinue)) { try { Remove-AppxPackage -AllUsers -Package $p.PackageFullName -ErrorAction Stop } catch {} }
    # Active Setup : sinon OneDriveSetup se relance a l'ouverture de session de chaque nouveau profil.
    foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Active Setup\Installed Components')) {
        Get-ChildItem $root -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue).StubPath -like '*OneDriveSetup*' } | ForEach-Object { Remove-Item $_.PsPath -Recurse -Force -ErrorAction SilentlyContinue }
    }
} catch { Write-Log ("  ! OneDrive : " + $_.Exception.Message) 'DarkGray' }

# --- Option : pave numerique (VerrNum) actif au demarrage ---
if ($NumLock) {
    # Ecran de connexion (.DEFAULT)
    try { Set-ItemProperty -Path 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2' -ErrorAction Stop; Write-Log "VerrNum : ecran de connexion OK." 'Green' } catch { Write-Log ("VerrNum .DEFAULT : " + $_.Exception.Message) 'DarkGray' }
    # Nouveaux profils : ruche Default User (C:\Users\Default\NTUSER.DAT)
    $def = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (Test-Path $def) {
        try {
            reg load 'HKU\ec19def' $def | Out-Null
            reg add 'HKU\ec19def\Control Panel\Keyboard' /v InitialKeyboardIndicators /t REG_SZ /d 2 /f | Out-Null
            [gc]::Collect(); Start-Sleep -Milliseconds 300
            reg unload 'HKU\ec19def' | Out-Null
            Write-Log "VerrNum : nouveaux profils OK." 'Green'
        } catch { Write-Log ("VerrNum Default : " + $_.Exception.Message) 'DarkGray'; try { reg unload 'HKU\ec19def' 2>$null | Out-Null } catch {} }
    }
}
