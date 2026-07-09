<#
  Prepare-MasterSoft.ps1 - Prepare les LOGICIELS PEDA "en bloc" du master (portables + raccourcis).

  A lancer en ADMINISTRATEUR sur le poste MASTER, avant sysprep/capture. Complement du grand public
  (VLC, LibreOffice, mBlock... via cd19pkg `cd19pkg update -Master`) : ce script pose le gros bloc
  des logiciels peda/portables figes (SVT, techno...) qu'on ne veut PAS mettre au catalogue.

  Ce qu'il fait :
    1. copie le dossier de logiciels (portables) dans "C:\Program Files (x86)\Logiciels_colleges" ;
    2. GENERE un raccourci par logiciel dans le sous-dossier "Logiciels" du bureau public (meme
       dossier que cd19pkg option 'Bureau public -> dossier Logiciels'), pointant vers l'exe
       principal (pas de dossier "Icones" a maintenir : une seule source, l'icone vient de l'exe) ;
    3. PURGE les raccourcis orphelins (dont la cible sous Logiciels_colleges n'existe plus) -> si on
       retire un logiciel, son raccourci disparait. (Desactivable avec -KeepOrphans.)

  Les rares apps a installeur dedie (RDM6, Pulmo, L_oeil...) restent a installer a part (setup).

  ASCII PUR obligatoire (PS 5.1 lit un .ps1 sans BOM en ANSI) : le chemin accentue
  "Logiciels_colleges" est construit par code caractere (0xE8 = e accent grave).

  Exemple :
    .\Prepare-MasterSoft.ps1 -SoftDir E:\master-soft\Logiciels
#>
[CmdletBinding()]
param(
    [string]$SoftDir,                                  # dossier des logiciels a copier (requis sauf -NoCopy)
    [string]$InstallRoot,                              # cible ; defaut = C:\Program Files (x86)\Logiciels_colleges
    [string]$PublicDesktop = 'C:\Users\Public\Desktop',
    [string]$ShortcutFolder = 'Logiciels',             # sous-dossier du bureau public pour les raccourcis (vide = racine) ; aligne avec cd19pkg
    [switch]$NoCopy,                                   # bloc deja en place -> raccourcis + purge seulement
    [switch]$NoShortcuts,                              # ne pas (re)generer les raccourcis
    [switch]$KeepOrphans                               # ne pas purger les raccourcis dont la cible a disparu
)
$ErrorActionPreference = 'Stop'

# Chemin cible avec accent, construit par code char -> le script reste ASCII pur.
if (-not $InstallRoot) { $InstallRoot = Join-Path 'C:\Program Files (x86)' ('Logiciels_coll' + [char]0xE8 + 'ges') }
# --- 1. Copie du bloc (sauf -NoCopy : deja copie, ex. par le WinPE en mode "Preparer un master") ---
if (-not $NoCopy) {
    if (-not $SoftDir) { throw "SoftDir requis (ou -NoCopy si le bloc est deja en place)." }
    if (-not (Test-Path -LiteralPath $SoftDir)) { throw "SoftDir introuvable : $SoftDir" }
    Write-Host ("Copie des logiciels : " + $SoftDir + "  ->  " + $InstallRoot) -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    robocopy $SoftDir $InstallRoot /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw ("robocopy a echoue (code " + $LASTEXITCODE + ").") }   # robocopy : code < 8 = OK
    Write-Host "Logiciels copies." -ForegroundColor Green
} else {
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    Write-Host "Mode -NoCopy : bloc suppose deja en place -> generation des raccourcis seulement." -ForegroundColor DarkCyan
}

function Get-Norm($s) { ($s -replace '[^A-Za-z0-9]', '').ToLower() }

# Exe "principal" d'un dossier de logiciel : on ecarte installeurs/desinstalleurs/redist/helpers ;
# on prefere l'exe dont le nom correspond au dossier, sinon le moins profond puis le plus gros.
function Get-MainExe($dir) {
    $bad = '(?i)(unins|setup|install|vcredist|redist|dxsetup|instdx|prereq|helper|elevate|builder|bssndrpt|msvbvm|acrobatreader|dotnet|_install)'
    $exes = @(Get-ChildItem -LiteralPath $dir -Recurse -Filter *.exe -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $bad })
    if (-not $exes.Count) { return $null }
    $fn = Get-Norm (Split-Path $dir -Leaf)
    $match = @($exes | Where-Object { $b = Get-Norm $_.BaseName; $b -eq $fn -or $b.Contains($fn) -or $fn.Contains($b) } |
              Sort-Object { $_.FullName.Length } | Select-Object -First 1)
    if ($match.Count) { return $match[0].FullName }
    return ($exes | Sort-Object @{ e = { ($_.FullName.ToCharArray() | Where-Object { $_ -eq '\' }).Count } }, @{ e = { $_.Length }; Descending = $true } | Select-Object -First 1).FullName
}

if (-not $NoShortcuts) {
    # Raccourcis dans un sous-dossier "Logiciels" du bureau public (meme dossier que cd19pkg
    # 'desktop-logiciels') pour un bureau coherent. -ShortcutFolder '' -> racine (ancien comportement).
    $lnkDir = if ($ShortcutFolder) { Join-Path $PublicDesktop $ShortcutFolder } else { $PublicDesktop }
    New-Item -ItemType Directory -Force -Path $lnkDir | Out-Null
    $sh = New-Object -ComObject WScript.Shell
    $made = 0; $skipped = @()
    foreach ($d in (Get-ChildItem -LiteralPath $InstallRoot -Directory -ErrorAction SilentlyContinue)) {
        $exe = Get-MainExe $d.FullName
        if (-not $exe) { $skipped += $d.Name; continue }
        $lnk = Join-Path $lnkDir ($d.Name + '.lnk')
        $s = $sh.CreateShortcut($lnk)
        $s.TargetPath = $exe
        $s.WorkingDirectory = Split-Path $exe
        $s.Save()
        $made++
    }
    $sfx = ''
    if ($skipped.Count) { $sfx = " (sans exe detecte : " + ($skipped -join ', ') + ")" }
    Write-Host ("Raccourcis generes : " + $made + $sfx) -ForegroundColor Green

    # --- 3. Purge des raccourcis orphelins (cible sous Logiciels_colleges disparue) ---
    if (-not $KeepOrphans) {
        $rootLow = $InstallRoot.ToLower()
        $purged = 0
        foreach ($l in (Get-ChildItem -LiteralPath $lnkDir -Filter *.lnk -File -ErrorAction SilentlyContinue)) {
            try {
                $tgt = $sh.CreateShortcut($l.FullName).TargetPath
                if ($tgt -and $tgt.ToLower().StartsWith($rootLow) -and -not (Test-Path -LiteralPath $tgt)) {
                    Remove-Item -LiteralPath $l.FullName -Force; $purged++
                }
            } catch { }
        }
        if ($purged) { Write-Host ("Raccourcis orphelins purges : " + $purged) -ForegroundColor Yellow }
    }
}

Write-Host "Prepa logiciels master terminee." -ForegroundColor Green
Write-Host "Rappel : les apps a installeur dedie (RDM6, Pulmo, L_oeil...) sont a lancer a part (setup)." -ForegroundColor DarkCyan
