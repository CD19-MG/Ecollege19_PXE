<#
  bootstrap.ps1 - FIGE dans le WinPE (stable, change rarement). Monte le partage et lance
  \\<serveur>\Deploy$\deploy.ps1 -> deploy.ps1 s'edite sur le PARTAGE, sans reconstruire le WinPE.
  Lance par winpeshl.ini (apres wpeinit). ASCII pur.
#>
$ErrorActionPreference = 'Stop'
$Server = 'srv-pxe.ecollege19.lan'          # alias de stats (ou IP)
$Share  = "\\$Server\Deploy$"
$User   = 'ECOLLEGE19\svc.wds'

function Fail($m){ Write-Host "`nERREUR (bootstrap): $m" -ForegroundColor Red; Read-Host 'Tape Entree pour redemarrer'; wpeutil reboot }

try {
    Write-Host "Connexion a $Share" -ForegroundColor Cyan
    Write-Host "Mot de passe de $User :" -ForegroundColor Yellow
    $pw = Read-Host -AsSecureString
    $pwPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))
    cmd /c "net use $Share /user:$User $pwPlain" | Out-Null
    if (-not (Test-Path "$Share\deploy.ps1")) { Fail "deploy.ps1 introuvable sur $Share (creds ? reseau ? carte reseau non reconnue ?)." }
    & "$Share\deploy.ps1"
} catch { Fail $_.Exception.Message }
