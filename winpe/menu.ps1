<#
  menu.ps1 - Menu WinPE (sur le PARTAGE, editable sans reconstruire le WinPE).
  BOUCLE : apres une action (ou une erreur/annulation), on revient au menu au lieu de
  redemarrer le poste. Redemarrer / Eteindre sont des choix explicites du menu.
  Lance par bootstrap.ps1 (partage deja monte). ASCII pur.
#>
$ErrorActionPreference = 'Stop'
$Server = 'srv-pxe.ecollege19.lan'
$Share  = "\\$Server\Deploy$"

$gui = "$Share\gui.ps1"
if (Test-Path $gui) { . $gui }   # charge l'interface graphique une fois (repli texte si indispo)

while ($true) {
    $choice = $null
    try {
        if (Test-Path $gui) { $choice = Show-MainMenu }
        if (-not $choice) {
            Write-Host ''
            Write-Host '  [1] Installer Windows sur ce poste   (deploiement)' -ForegroundColor White
            Write-Host '  [2] Capturer une image de reference  (avance)'      -ForegroundColor White
            Write-Host '  [3] Redemarrer le poste'                            -ForegroundColor White
            Write-Host '  [4] Eteindre le poste'                              -ForegroundColor White
            $c = Read-Host 'Votre choix [1]'
            if ([string]::IsNullOrWhiteSpace($c)) { $c = '1' }
            switch ($c.Trim()) { '2' { $choice = 'capture' } '3' { $choice = 'reboot' } '4' { $choice = 'shutdown' } default { $choice = 'deploy' } }
        }

        switch ($choice) {
            'reboot'   { Write-Host 'Redemarrage...' -ForegroundColor Cyan; wpeutil reboot;   return }
            'shutdown' { Write-Host 'Extinction...'  -ForegroundColor Cyan; wpeutil shutdown; return }
            'capture'  { & "$Share\capture.ps1" }   # au retour (erreur/annulation) -> re-boucle sur le menu
            default    { & "$Share\deploy.ps1" }    # succes deploy -> le script a deja redemarre le poste
        }
    } catch {
        # Erreur remontee par une action : deja affichee + pause cote script. On revient au menu.
        Write-Host ''
    }
}
