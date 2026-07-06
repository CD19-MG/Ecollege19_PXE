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
    # Interface graphique si dispo (gui.ps1 sur le partage), sinon menu texte
    $choice = $null
    $gui = "$Share\gui.ps1"
    if (Test-Path $gui) { . $gui; $choice = Show-MainMenu }
    if (-not $choice) {
        Write-Host ''
        Write-Host '  [1] Installer Windows sur ce poste   (deploiement)' -ForegroundColor White
        Write-Host '  [2] Capturer une image de reference  (avance)'      -ForegroundColor White
        $c = Read-Host 'Votre choix [1]'
        if ([string]::IsNullOrWhiteSpace($c)) { $c = '1' }
        $choice = if ($c.Trim() -eq '2') { 'capture' } else { 'deploy' }
    }
    switch ($choice) {
        'capture' { & "$Share\capture.ps1" }
        default   { & "$Share\deploy.ps1" }
    }
} catch { Fail $_.Exception.Message }
