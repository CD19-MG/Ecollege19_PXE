<#
  menu.ps1 - Menu WinPE (sur le PARTAGE, editable sans reconstruire le WinPE).
  Choix simple pour les techniciens : deployer un poste (courant) ou capturer une
  image de reference (avance). Lance par bootstrap.ps1 (partage deja monte). ASCII pur.
#>
$ErrorActionPreference = 'Stop'
$Server = 'srv-pxe.ecollege19.lan'
$Share  = "\\$Server\Deploy$"

function Fail($m){ Write-Host "`nERREUR: $m" -ForegroundColor Red; Read-Host 'Tape Entree pour redemarrer'; wpeutil reboot }

try {
    Write-Host ''
    Write-Host '=====================================================' -ForegroundColor Cyan
    Write-Host '     Deploiement eCollege19 - Atelier MARBOT'         -ForegroundColor Cyan
    Write-Host '=====================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  [1] Installer Windows sur ce poste   (deploiement)' -ForegroundColor White
    Write-Host '  [2] Capturer une image de reference  (avance)'      -ForegroundColor White
    Write-Host ''
    $c = Read-Host 'Votre choix [1]'
    if ([string]::IsNullOrWhiteSpace($c)) { $c = '1' }
    switch ($c.Trim()) {
        '1' { & "$Share\deploy.ps1" }
        '2' { & "$Share\capture.ps1" }
        default { Write-Host 'Choix invalide -> deploiement par defaut.' -ForegroundColor Yellow; & "$Share\deploy.ps1" }
    }
} catch { Fail $_.Exception.Message }
