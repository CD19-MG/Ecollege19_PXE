<#
  bootstrap.ps1 - FIGE dans le WinPE (stable, change rarement). Monte le partage et lance
  \\<serveur>\Deploy$\deploy.ps1 -> deploy.ps1 s'edite sur le PARTAGE, sans reconstruire le WinPE.
  Lance par winpeshl.ini (apres wpeinit). ASCII pur.
#>
$ErrorActionPreference = 'Stop'
$Server = 'srv-pxe.ecollege19.lan'          # alias de stats (ou IP)
$Share  = "\\$Server\Deploy$"
$User   = 'ECOLLEGE19\svc.wds'
# Mot de passe fige pour l imaging sans saisie. NE PAS commiter le vrai mot de passe :
# copier ce fichier en bootstrap.local.ps1 (gitignore), y mettre le vrai mot de passe,
# et injecter bootstrap.local.ps1 dans le WinPE (voir winpe/README.md).
$Pass   = '<MOT_DE_PASSE_SVC_WDS>'

function Fail($m){ Write-Host "`nERREUR (bootstrap): $m" -ForegroundColor Red; Read-Host 'Tape Entree pour redemarrer'; wpeutil reboot }

try {
    Write-Host "Connexion a $Share (utilisateur $User)" -ForegroundColor Cyan
    cmd /c "net use $Share /user:$User $Pass"
    if (-not (Test-Path "$Share\deploy.ps1")) { Fail "deploy.ps1 introuvable sur $Share (creds ? reseau ? alias CNAME srv-pxe non autorise en SMB ? carte reseau non reconnue ?)." }
    & "$Share\deploy.ps1"
} catch { Fail $_.Exception.Message }
