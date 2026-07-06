<#
.SYNOPSIS
  Telecharge + extrait les Driver Packs HP (INF, prets pour import WDS) en DEDOUBLONNANT par
  plateforme (SysID) : plusieurs libelles commerciaux = souvent le meme pack. Utilise HP CMSL.

.DESCRIPTION
  Pour chaque nom de modele : resout le SysID (plateforme). Les modeles partageant un SysID
  partagent UN pack (telecharge une seule fois). Affiche le mapping nom -> SysID pour savoir
  quels libelles mettre dans le filtre de chaque GROUPE WDS.

  Prerequis : Windows + acces Internet + admin. HPCMSL installe s'il manque. Adapter -OsVer.
  IMPORTANT : ASCII pur (pas d'accent) - convention .ps1 du projet. Lancer en administrateur.

.EXAMPLE
  .\Get-HPDriverPacks.ps1 -OutRoot D:\DriverPacks -OsVer 23H2
#>
[CmdletBinding()]
param(
    [string]$OutRoot = "D:\DriverPacks",
    [string]$OsVer   = "23H2"
)
$ErrorActionPreference = 'Stop'

# Tous les libelles remontes par l'agent (Win32_ComputerSystem.Model).
$models = @(
    'HP EliteDesk 800 G4 DM 35W',
    'HP Elitedesk 800 G5',
    'HP EliteDesk 800 G5 Desktop Mini',
    'HP EliteDesk 800 G5 DM',
    'HP Pro Mini 400 G9 Desktop PC',
    'HP ProDesk 400 G4 SFF',
    'HP ProDesk 400 G6 Desktop Mini PC',
    'HP ProDesk 400 G6 SFF'
)

if (-not (Get-Module -ListAvailable -Name HPCMSL)) {
    Write-Host "Installation du module HPCMSL..." -ForegroundColor Cyan
    # Fournisseur NuGet + depot PSGallery de confiance (evite les prompts).
    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
    # -AcceptLicense n'existe que sur PowerShellGet >= 2.x : on le tente, sinon repli sans.
    try   { Install-Module -Name HPCMSL -Force -Scope AllUsers -AcceptLicense -ErrorAction Stop }
    catch { Install-Module -Name HPCMSL -Force -Scope AllUsers }
}
Import-Module HPCMSL
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

# 1. Resoudre le SysID de chaque libelle + regrouper par plateforme
$byPlat = @{}
foreach ($m in $models) {
    try {
        $sysId = (Get-HPDeviceDetails -Name $m -Like | Select-Object -First 1).SystemID
    } catch { $sysId = $null }
    if (-not $sysId) { Write-Warning "SysID introuvable pour '$m' (verifier le libelle)."; continue }
    if (-not $byPlat.ContainsKey($sysId)) { $byPlat[$sysId] = @() }
    $byPlat[$sysId] += $m
}

# 2. Un pack par plateforme (dedoublonne)
foreach ($sysId in $byPlat.Keys) {
    $names = $byPlat[$sysId]
    $dest  = Join-Path $OutRoot $sysId
    Write-Host "`n=== Plateforme $sysId ===" -ForegroundColor Yellow
    Write-Host ("  Modeles : " + ($names -join ' | ')) -ForegroundColor Gray
    try {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        New-HPDriverPack -Platform $sysId -OS win11 -OSVer $OsVer -Path $dest
        Write-Host "  OK -> $dest" -ForegroundColor Green
    } catch {
        Write-Warning "  Echec $sysId : $($_.Exception.Message) (repli : driver pack manuel sur support.hp.com)"
    }
}

# 3. Recap : mapping plateforme -> libelles (pour les filtres des groupes WDS)
Write-Host "`n===== A FAIRE DANS WDS : 1 GROUPE PAR PLATEFORME, filtre = les libelles ci-dessous =====" -ForegroundColor Cyan
foreach ($sysId in $byPlat.Keys) {
    Write-Host ("  [$sysId] " + ($byPlat[$sysId] -join '  ||  ')) -ForegroundColor White
}
Write-Host "Importer chaque dossier de $OutRoot dans WDS, l'assigner a son groupe, y mettre le filtre Modele (valeurs multiples = OR)." -ForegroundColor Cyan
