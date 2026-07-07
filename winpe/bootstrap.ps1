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
    #
    # BOUCLE DE RETRY : juste apres wpeinit, le reseau/DNS n'est pas toujours pret (net use ->
    # erreur 53 "chemin reseau introuvable"). On reessaie plusieurs fois en laissant le temps
    # a DHCP/DNS de monter.
    $mounted = $false
    $maxTries = 8
    for ($try = 1; $try -le $maxTries -and -not $mounted; $try++) {
        if ($try -gt 1) {
            Write-Host ("Reseau/partage pas encore pret (erreur 53 ?), tentative $try/$maxTries...") -ForegroundColor Yellow
            Start-Sleep -Seconds 4
        }
        # nettoie un mapping partiel eventuel d'une tentative precedente
        try { Remove-SmbMapping -RemotePath $Share -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
        try {
            New-SmbMapping -RemotePath $Share -UserName $User -Password $Pass -ErrorAction Stop | Out-Null
        } catch {
            try { net use $Share /user:$User $Pass 2>$null | Out-Null } catch {}
        }
        # la verite = peut-on lire le partage ?
        $mounted = (Test-Path "$Share\menu.ps1") -or (Test-Path "$Share\deploy.ps1")
    }
    if (-not $mounted) {
        Fail "Partage $Share injoignable apres $maxTries tentatives (reseau/DNS srv-pxe ? carte reseau non reconnue ? creds ? alias CNAME non autorise en SMB ?)."
    }

    # Lance le menu (deploiement / capture) s'il existe, sinon directement le deploiement.
    if     (Test-Path "$Share\menu.ps1")   { & "$Share\menu.ps1" }
    else                                   { & "$Share\deploy.ps1" }
} catch { Fail $_.Exception.Message }
