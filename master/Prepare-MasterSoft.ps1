<#
  Prepare-MasterSoft.ps1 - Prepare les LOGICIELS PEDA "en bloc" du master (portables + raccourcis).

  A lancer en ADMINISTRATEUR sur le poste MASTER, avant sysprep/capture. C'est le complement du
  grand public : le grand public (VLC, LibreOffice, mBlock...) s'installe via cd19pkg
  (`cd19pkg update -Master`), et CE script pose le gros bloc des logiciels peda/portables figes
  (SVT, techno...) qu'on ne veut PAS mettre un par un dans le catalogue de deploiement.

  Ce qu'il fait :
    1. copie un dossier de logiciels (portables) dans "C:\Program Files (x86)\Logiciels_colleges" ;
    2. depose les raccourcis du bureau public (les .lnk du dossier Icones).

  Les rares apps a installeur dedie (RDM6, Pulmo, L_oeil...) restent a installer a part (setup.exe).

  ASCII PUR obligatoire (PS 5.1 lit un .ps1 sans BOM en ANSI) : le chemin accentue
  "Logiciels_colleges" est construit par code caractere (0xE8 = e accent grave).

  Exemple :
    .\Prepare-MasterSoft.ps1 -SoftDir E:\master-soft\Logiciels -IconsDir E:\master-soft\Icones
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SoftDir,   # dossier des logiciels a copier (portables)
    [string]$IconsDir,                                 # dossier des .lnk -> bureau public (optionnel)
    [string]$InstallRoot,                              # cible ; defaut = C:\Program Files (x86)\Logiciels_colleges
    [string]$PublicDesktop = 'C:\Users\Public\Desktop'
)
$ErrorActionPreference = 'Stop'

# Chemin cible avec accent, construit par code char -> le script reste ASCII pur.
if (-not $InstallRoot) { $InstallRoot = Join-Path 'C:\Program Files (x86)' ('Logiciels_coll' + [char]0xE8 + 'ges') }

if (-not (Test-Path -LiteralPath $SoftDir)) { throw "SoftDir introuvable : $SoftDir" }

Write-Host ("Copie des logiciels : " + $SoftDir + "  ->  " + $InstallRoot) -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
robocopy $SoftDir $InstallRoot /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) { throw ("robocopy a echoue (code " + $LASTEXITCODE + ").") }   # robocopy : code < 8 = OK
Write-Host "Logiciels copies." -ForegroundColor Green

if ($IconsDir) {
    if (Test-Path -LiteralPath $IconsDir) {
        New-Item -ItemType Directory -Force -Path $PublicDesktop | Out-Null
        Copy-Item (Join-Path $IconsDir '*.lnk') $PublicDesktop -Force
        $n = @(Get-ChildItem $PublicDesktop -Filter *.lnk -ErrorAction SilentlyContinue).Count
        Write-Host ("Raccourcis bureau public deposes (" + $n + ").") -ForegroundColor Green
    } else {
        Write-Host ("IconsDir introuvable : " + $IconsDir + " -> raccourcis non deposes.") -ForegroundColor Yellow
    }
}

Write-Host "Prepa logiciels master terminee." -ForegroundColor Green
Write-Host "Rappel : les apps a installeur dedie (RDM6, Pulmo, L_oeil...) sont a lancer a part (setup)." -ForegroundColor DarkCyan
