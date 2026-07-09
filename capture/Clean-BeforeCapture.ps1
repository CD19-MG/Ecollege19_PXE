<#
  Clean-BeforeCapture.ps1 - Nettoyage du poste MODELE avant sysprep/capture (reduit la taille du WIM).

  Appele par Preparer-la-capture.cmd juste AVANT la generalisation. A lancer en ADMINISTRATEUR.
  Chaque etape est tolerante (un echec n'arrete pas le reste). PowerShell 5.1, ASCII pur.

  Etapes :
    1. Composants WinSxS : dism /StartComponentCleanup /ResetBase (purge les composants superseded)
    2. Cache Windows Update : arret wuauserv/bits, vidage de SoftwareDistribution\Download, redemarrage
    3. Cache Delivery Optimization
    4. Fichiers temporaires (Windows\Temp, TEMP systeme, Temp de chaque profil)
    5. Corbeille (tous lecteurs)
    6. Prefetch
#>
$ErrorActionPreference = 'Continue'
function Step($n) { Write-Host ("`n== " + $n + " ==") -ForegroundColor Cyan }
function Ok($m)   { Write-Host ("   " + $m) -ForegroundColor Green }
function Warn($m) { Write-Host ("   " + $m) -ForegroundColor DarkGray }
function RmContent($path) {
    if (Test-Path -LiteralPath $path) {
        try { Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
}

# 1. Composants WinSxS (le plus gros gain sur la taille de l'image)
Step "Composants WinSxS (peut prendre plusieurs minutes)"
try { dism /online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null; if ($LASTEXITCODE -eq 0) { Ok "WinSxS nettoye (ResetBase)." } else { Warn "dism code $LASTEXITCODE" } } catch { Warn $_.Exception.Message }

# 2. Cache Windows Update
Step "Cache Windows Update"
try {
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    RmContent (Join-Path $env:WINDIR 'SoftwareDistribution\Download')
    Start-Service bits, wuauserv -ErrorAction SilentlyContinue
    Ok "SoftwareDistribution\Download vide."
} catch { Warn $_.Exception.Message }

# 3. Delivery Optimization
Step "Cache Delivery Optimization"
try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Ok "Cache DO vide." }
catch { RmContent (Join-Path $env:WINDIR 'SoftwareDistribution\DeliveryOptimization'); Warn "cmdlet indispo -> vidage dossier." }

# 4. Fichiers temporaires
Step "Fichiers temporaires"
RmContent (Join-Path $env:WINDIR 'Temp')
RmContent $env:TEMP
foreach ($u in (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
    RmContent (Join-Path $u.FullName 'AppData\Local\Temp')
}
Ok "Temp Windows + profils vides."

# 4b. Dossiers Downloads des profils (installeurs/telechargements traineurs sur le master)
Step "Dossiers Downloads des profils"
foreach ($u in (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
    RmContent (Join-Path $u.FullName 'Downloads')
}
Ok "Downloads des profils vides."

# 5. Corbeille
Step "Corbeille"
try { Clear-RecycleBin -Force -ErrorAction Stop; Ok "Corbeille videe." }
catch { Warn ("Clear-RecycleBin : " + $_.Exception.Message) }

# 6. Prefetch
Step "Prefetch"
RmContent (Join-Path $env:WINDIR 'Prefetch')
Ok "Prefetch vide."

Write-Host "`nNettoyage termine." -ForegroundColor Green
