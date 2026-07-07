<#
  capture.ps1 - Capture d'une image de reference depuis WinPE, sur le PARTAGE (editable sans
  reconstruire le WinPE). Ecrit DIRECTEMENT dans images\ -> l'image apparait aussitot dans la
  liste de deploiement (deploy.ps1). Nom propose par defaut = MODELE du poste (auto-detecte).

  Prealable : le poste modele doit avoir ete PREPARE (sysprep /generalize /oobe /shutdown) via
  "Preparer-la-capture.cmd", puis redemarre en PXE -> menu -> [2].

  IMPORTANT : svc.wds doit avoir le droit "Modifier" sur le dossier images du partage
  (en lecture seule, la capture echouerait a l'ecriture du WIM). ASCII pur.
#>
$ErrorActionPreference = 'Stop'
$Server   = 'srv-pxe.ecollege19.lan'
$Share    = "\\$Server\Deploy$"
$ImgDir    = "$Share\images"
$ModelDir  = "$ImgDir\modeles"   # les captures vont ici -> categorie "par modele" au deploiement

# --- Remontee d'etat vers le dashboard (Phase 3b). Best-effort : ne bloque JAMAIS la capture.
$ReportUrl   = 'https://stats.ecollege19.lan/pc/api/pxe/report'   # hostname du certificat (srv-pxe = alias)
$ReportToken = '<JETON_PXE>'                                      # a renseigner sur le partage (hors depot)
$JobId  = ([guid]::NewGuid()).Guid
$ImgName = ''
$Mac   = ''; try { $Mac   = @(Get-CimInstance Win32_NetworkAdapterConfiguration -EA SilentlyContinue | Where-Object { $_.IPEnabled }).MACAddress | Select-Object -First 1 } catch {}
$Model = ''; try { $Model = (Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue).Model } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } } catch {}  # WinPE, LAN : on ne valide pas le cert

function Report($phase, $status, $msg) {
    if (-not $ReportToken -or $ReportToken -like '*JETON*') { return }
    try {
        $body = @{ job_id=$JobId; mac=$Mac; hostname=$env:COMPUTERNAME; model=$Model; action='capture'; image=$ImgName; phase=$phase; status=$status; message=$msg } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $ReportUrl -Method Post -Headers @{ 'X-PXE-Token'=$ReportToken } -ContentType 'application/json' -Body $body -TimeoutSec 8 | Out-Null
    } catch { }
}

# Erreur recuperable : affichage + pause puis RETOUR AU MENU (throw sentinelle) au lieu de rebooter.
function Fail($m){
    Report 'erreur' 'error' $m
    Write-Host "`nERREUR: $m" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host 'Note l erreur ci-dessus, puis tape Entree pour revenir au menu'
    throw 'EC19_HANDLED'
}

try {
    try { New-Item -ItemType Directory -Force -Path "$Share\logs" | Out-Null } catch {}
    try { Start-Transcript -Path ("$Share\logs\capture-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log') -Force | Out-Null } catch {}

    Write-Host "=== Capture d'une image de reference ===" -ForegroundColor Cyan

    # Trouver la partition Windows (celle qui contient \Windows\System32\ntoskrnl.exe)
    $win = $null
    foreach ($v in (Get-Volume | Where-Object DriveLetter)) {
        $dl = "$($v.DriveLetter):"
        if (Test-Path "$dl\Windows\System32\ntoskrnl.exe") { $win = $dl; break }
    }
    if (-not $win) { Fail "Partition Windows introuvable. Le poste a-t-il bien ete prepare (sysprep) sans etre efface ?" }
    Write-Host "Windows detecte sur $win" -ForegroundColor Green

    # Verifier que sysprep a bien generalise (sinon l'image ne doit PAS servir sur d'autres postes)
    if (-not (Test-Path "$win\Windows\System32\Sysprep\Sysprep_succeeded.tag")) {
        Write-Host "ATTENTION : aucune trace de sysprep reussi sur $win." -ForegroundColor Yellow
        Write-Host "Une image capturee sans 'sysprep /generalize' ne doit PAS etre deployee ailleurs" -ForegroundColor Yellow
        Write-Host "(memes SID/nom/pilotes figes -> conflits). Utilise 'Preparer-la-capture.cmd' d'abord." -ForegroundColor Yellow
        if ((Read-Host "Continuer quand meme ? (tape OUI)") -ne 'OUI') { Fail 'Annule par l operateur.' }
    }

    # Nom par defaut = modele du poste (auto-detecte), nettoye pour un nom de fichier
    $model = ''
    try { $model = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model } catch {}
    $sysId = ''
    try { $sysId = (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product } catch {}
    $def = if ($model) { $model } else { 'Reference' }
    $def = ($def -replace '[^\w\-]', '_') -replace '_+', '_'
    $def = $def.Trim('_')
    if ($sysId) { Write-Host "Modele detecte : $model (SysID $sysId)" -ForegroundColor Green }

    # Nom via l'interface graphique si dispo (gui.ps1 sur le partage), sinon invite texte
    $gui = "$Share\gui.ps1"
    $name = $null
    if (Test-Path $gui) {
        . $gui
        if (Test-Gui) {
            $lbl = if ($sysId) { "$model (SysID $sysId)" } else { $model }
            $name = Show-CaptureDialog $def $lbl
            if ($null -eq $name) { Fail 'Annule par l operateur.' }
        }
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = Read-Host "Nom de l'image [$def]"
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $def }
    }
    $name = (($name -replace '[^\w\-]', '_') -replace '_+', '_').Trim('_')

    if (-not (Test-Path $ModelDir)) { New-Item -ItemType Directory -Force -Path $ModelDir | Out-Null }
    $dest = "$ModelDir\$name.wim"
    if (Test-Path $dest) {
        Write-Host "Une image '$name' existe deja." -ForegroundColor Yellow
        if ((Read-Host "La REMPLACER par la version a jour ? (tape OUI)") -ne 'OUI') { Fail 'Annule par l operateur.' }
        Remove-Item $dest -Force
    }

    $ImgName = "$name.wim"
    Report 'application' 'running' "Capture $ImgName"
    Write-Host "Capture de $win -> images\modeles\$name.wim (plusieurs minutes)..." -ForegroundColor Cyan
    dism /Capture-Image /ImageFile:"$dest" /CaptureDir:$win\ /Name:"$name" /Compress:max
    if ($LASTEXITCODE -ne 0) { Fail "dism /Capture-Image a echoue (code $LASTEXITCODE)." }

    Report 'termine' 'ok' "Image $ImgName capturee"
    Write-Host ''
    Write-Host "OK - image disponible au deploiement : modeles\$name.wim" -ForegroundColor Green
    Write-Host "Elle apparaitra en tete de liste (categorie MODELE) au prochain PXE ([1] Installer)." -ForegroundColor Green
    Write-Host "NE PAS demarrer ce poste sur son disque (il est generalise) : eteins-le depuis le menu." -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host 'Tape Entree pour revenir au menu'
    # Pas de reboot : la reference est generalisee (sysprep). Retour au menu -> Eteindre / autre.
}
catch { if ("$($_.Exception.Message)" -ne 'EC19_HANDLED') { Fail $_.Exception.Message } }
