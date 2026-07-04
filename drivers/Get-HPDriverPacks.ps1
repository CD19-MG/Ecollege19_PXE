<#
.SYNOPSIS
  Telecharge + extrait les Driver Packs HP (format INF, prets pour import WDS) pour les modeles
  du parc, un dossier par modele. Utilise HP CMSL (HP Client Management Script Library).

.DESCRIPTION
  Pour chaque modele : resout l'identifiant plateforme (SysID) depuis le nom, puis construit le
  driver pack Win11 dans <OutRoot>\<Modele>\. Ces dossiers (INF) s'importent ensuite dans WDS
  (console WDS > Pilotes > Ajouter un package de pilotes > pointer le dossier).

  Prerequis : Windows + acces Internet + admin. Le module HPCMSL est installe s'il manque.
  Adapter -OsVer selon l'edition deployee (ex. "23H2"). Lancer en administrateur.

  IMPORTANT : fichier en ASCII pur (aucun accent / signe typographique) — cf. convention du projet
  (Windows PowerShell 5.1 lit un .ps1 sans BOM en codepage ANSI). Ne pas reintroduire d'accents.

.EXAMPLE
  .\Get-HPDriverPacks.ps1 -OutRoot D:\DriverPacks -OsVer 23H2
#>
[CmdletBinding()]
param(
    [string]$OutRoot = "D:\DriverPacks",
    [string]$OsVer   = "23H2"
)
$ErrorActionPreference = 'Stop'

# Modeles HP du parc (noms tels qu'affiches par Win32_ComputerSystem.Model / la fiche EPM).
$models = @(
    'HP Pro Mini 400 G9 Desktop PC',
    'HP ProDesk 400 G6 Desktop Mini PC',
    'HP EliteDesk 800 G5 Desktop Mini',
    'HP ProDesk 400 G6 SFF',
    'HP EliteDesk 800 G4 DM 35W'
)

# 1. Module HP CMSL
if (-not (Get-Module -ListAvailable -Name HPCMSL)) {
    Write-Host "Installation du module HPCMSL..." -ForegroundColor Cyan
    Install-Module -Name HPCMSL -Force -AcceptLicense -Scope AllUsers
}
Import-Module HPCMSL

New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

foreach ($m in $models) {
    Write-Host "=== $m ===" -ForegroundColor Yellow
    try {
        # SysID (plateforme) depuis le nom commercial
        $sysId = (Get-HPDeviceDetails -Name $m -Like | Select-Object -First 1).SystemID
        if (-not $sysId) {
            Write-Warning "SysID introuvable pour '$m' - verifier le libelle exact."
            continue
        }
        $safe = ($m -replace '[\\/:*?<>|]', '_')
        $dest = Join-Path $OutRoot $safe
        New-Item -ItemType Directory -Force -Path $dest | Out-Null

        Write-Host "SysID $sysId -> construction du driver pack Win11 $OsVer dans $dest" -ForegroundColor Cyan
        New-HPDriverPack -Platform $sysId -OS win11 -OSVer $OsVer -Path $dest
        Write-Host "OK : $dest" -ForegroundColor Green
    }
    catch {
        Write-Warning "Echec pour '$m' : $($_.Exception.Message)"
        Write-Warning "  Repli manuel : telecharger le Driver Pack du modele sur support.hp.com, l'extraire, l'importer dans WDS."
    }
}

Write-Host "Termine. Importer chaque dossier de $OutRoot dans WDS (Pilotes > Ajouter un package)," -ForegroundColor Green
Write-Host "puis creer un GROUPE filtre par modele (Fabricant/Modele). Cf. drivers/README.md." -ForegroundColor Green
