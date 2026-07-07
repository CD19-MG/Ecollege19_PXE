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
    # Garde-fou : le placeholder n'a pas ete remplace -> message clair (au lieu d'une erreur net use cryptique).
    if ([string]::IsNullOrWhiteSpace($Pass) -or $Pass -like '*MOT_DE_PASSE*') {
        Fail "Mot de passe non renseigne : ce WinPE embarque le modele bootstrap.ps1 (placeholder). Reinjecte bootstrap.local.ps1 (avec le vrai mot de passe svc.wds), renommee bootstrap.ps1."
    }
    Write-Host "Connexion a $Share (utilisateur $User)" -ForegroundColor Cyan
    # Montage SANS cmd : le mot de passe peut contenir & | < > ^ ( ) etc. qui casseraient
    # une ligne "cmd /c net use ...". On tente d'abord New-SmbMapping (mot de passe passe en
    # parametre .NET, aucun parsing shell -> tous caracteres OK) ; repli sur net.exe appele
    # DIRECTEMENT par PowerShell (pas via cmd -> les metacaracteres ne sont pas interpretes).
    $mounted = $false
    try {
        New-SmbMapping -RemotePath $Share -UserName $User -Password $Pass -ErrorAction Stop | Out-Null
        $mounted = $true
    } catch {
        net use $Share /user:$User $Pass
        $mounted = ($LASTEXITCODE -eq 0)
    }
    if (-not $mounted) { Write-Host "Montage du partage en echec (creds ? alias CNAME srv-pxe ? reseau ?)." -ForegroundColor Yellow }

    # Lance le menu (deploiement / capture) s'il existe, sinon directement le deploiement.
    if     (Test-Path "$Share\menu.ps1")   { & "$Share\menu.ps1" }
    elseif (Test-Path "$Share\deploy.ps1") { & "$Share\deploy.ps1" }
    else { Fail "Ni menu.ps1 ni deploy.ps1 sur $Share (creds ? reseau ? alias CNAME srv-pxe non autorise en SMB ? carte reseau non reconnue ?)." }
} catch { Fail $_.Exception.Message }
