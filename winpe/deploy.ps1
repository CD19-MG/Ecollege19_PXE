<#
  deploy.ps1 - Deploiement Windows depuis WinPE, SANS le client WDS (deprecie Server 2025).
  Lance par bootstrap.ps1 (le partage \\srv-pxe\Deploy$ est DEJA monte). A placer a la RACINE du
  partage : \\srv-pxe\Deploy$\deploy.ps1 -> editable sans reconstruire le WinPE.

  Le partage contient : images\ (WIM), drivers\ (packs par SysID), unattend\ImageUnattend.xml.
  Journal persistant dans \\srv-pxe\Deploy$\logs\. ASCII pur.
#>
$ErrorActionPreference = 'Stop'
$Server   = 'srv-pxe.ecollege19.lan'
$Share    = "\\$Server\Deploy$"
$ImgDir   = "$Share\images"
$DrvDir   = "$Share\drivers"
$Unattend = "$Share\unattend\ImageUnattend.xml"
$CaptureCmd = "$Share\Preparer-la-capture.cmd"   # depose dans un dossier ADMIN-ONLY lors d'une install NUE
$Disk     = 0

# --- Remontee d'etat vers le dashboard (Phase 3b). Best-effort : ne bloque JAMAIS le deploiement.
$ReportUrl   = 'https://stats.ecollege19.lan/pc/api/pxe/report'   # hostname du certificat (srv-pxe = alias)
$ReportToken = '<JETON_PXE>'                                      # a renseigner sur le partage (hors depot)
$JobId  = ([guid]::NewGuid()).Guid
$ImgName = ''
$Mac   = ''; try { $Mac   = @(Get-CimInstance Win32_NetworkAdapterConfiguration -EA SilentlyContinue | Where-Object { $_.IPEnabled }).MACAddress | Select-Object -First 1 } catch {}
$Model = ''; try { $Model = (Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue).Model } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } } catch {}  # WinPE, LAN : on ne valide pas le cert

function Report($phase, $status, $msg) {
    if (-not $ReportToken -or $ReportToken -like '*JETON*') { return }   # non configure -> silencieux
    try {
        $body = @{ job_id=$JobId; mac=$Mac; hostname=$env:COMPUTERNAME; model=$Model; action='deploy'; image=$ImgName; phase=$phase; status=$status; message=$msg } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $ReportUrl -Method Post -Headers @{ 'X-PXE-Token'=$ReportToken } -ContentType 'application/json' -Body $body -TimeoutSec 8 | Out-Null
    } catch { }   # une remontee ratee n'interrompt pas le deploiement
}

function Fail($m){
    Report 'erreur' 'error' $m
    Write-Host "`nERREUR: $m" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host 'Note l erreur ci-dessus, puis tape Entree pour redemarrer'
    wpeutil reboot
}

try {
    # Journal persistant sur le partage (lisible apres reboot)
    try { New-Item -ItemType Directory -Force -Path "$Share\logs" | Out-Null } catch {}
    try { Start-Transcript -Path ("$Share\logs\deploy-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log') -Force | Out-Null } catch {}

    Write-Host "=== Deploiement eCollege19 (WinPE) ===" -ForegroundColor Cyan
    if (-not (Test-Path $ImgDir)) { Fail "Dossier $ImgDir injoignable." }

    # Liste categorisee : images par MODELE (captures, a jour) d'abord, puis installations completes.
    $modelDir = Join-Path $ImgDir 'modeles'
    $edDir    = Join-Path $ImgDir 'editions'
    $models   = @(Get-ChildItem -Path $modelDir -Filter *.wim -ErrorAction SilentlyContinue | Sort-Object Name)
    $editions = @(Get-ChildItem -Path $edDir    -Filter *.wim -ErrorAction SilentlyContinue | Sort-Object Name)
    $editions += @(Get-ChildItem -Path $ImgDir  -Filter *.wim -ErrorAction SilentlyContinue | Sort-Object Name)  # racine (compat)
    $paths = @(); $items = @()
    foreach ($m in $models)   { $paths += $m.FullName; $items += [pscustomobject]@{ Label=$m.Name; Category='Modele' } }
    foreach ($e in $editions) { $paths += $e.FullName; $items += [pscustomobject]@{ Label=$e.Name; Category='Edition' } }
    if (-not $paths.Count) { Fail "Aucun .wim (ni images\modeles\ ni images\editions\ ni racine)." }

    # Auto-recommandation par modele detecte. Un meme modele peut avoir PLUSIEURS images
    # (ex. peda / admin) -> on ne presElectionne QUE s'il n'y en a qu'une (sinon Entree
    # deploierait la mauvaise) ; si plusieurs correspondent, choix explicite obligatoire.
    function NormName($s) { if ($s) { ($s -replace '[^\w]', '').ToLower() } else { '' } }
    $modelNorm = NormName $Model
    $matches = @()
    if ($modelNorm.Length -ge 4) {
        for ($i=0; $i -lt $models.Count; $i++) {   # les modeles sont en tete de $items
            $n = NormName ([System.IO.Path]::GetFileNameWithoutExtension($models[$i].Name))
            if ($n -and ($n.Contains($modelNorm) -or $modelNorm.Contains($n))) { $matches += $i }
        }
    }
    $recIndex = -1
    if ($matches.Count -eq 1) {
        $recIndex = $matches[0]
        Write-Host ("Modele detecte : {0} -> image recommandee : {1}" -f $Model, $items[$recIndex].Label) -ForegroundColor Green
    } elseif ($matches.Count -gt 1) {
        Write-Host ("Modele detecte : {0} -> {1} images correspondent (peda/admin ?), choisis explicitement." -f $Model, $matches.Count) -ForegroundColor Yellow
    }

    # Choix via l'interface graphique si dispo (gui.ps1), sinon liste texte
    $usedGui = $false
    $gui = "$Share\gui.ps1"
    if (Test-Path $gui) { . $gui; $usedGui = (Test-Gui) }
    if ($usedGui) {
        $sel = Show-ImagePicker $items $recIndex
        $usedGui = (Test-Gui)   # a pu retomber en texte si l'affichage a echoue
    } else {
        Write-Host ''
        for ($i=0; $i -lt $items.Count; $i++) {
            if ($i -eq 0 -and $models.Count)     { Write-Host 'Images par MODELE (recommande - a jour) :' -ForegroundColor Cyan }
            if ($i -eq $models.Count)            { Write-Host 'Installation complete (Windows nu) :'     -ForegroundColor DarkCyan }
            $mark = if ($i -eq $recIndex) { '   <-- recommande pour ce poste' } else { '' }
            Write-Host ("  [{0}] {1}{2}" -f $i, $items[$i].Label, $mark)
        }
        $rprompt = if ($recIndex -ge 0) { "Numero de l image a deployer [$recIndex]" } else { 'Numero de l image a deployer' }
        $r = Read-Host $rprompt
        if ([string]::IsNullOrWhiteSpace($r) -and $recIndex -ge 0) { $sel = $recIndex }
        elseif ($r -match '^\d+$') { $sel = [int]$r }
        else { $sel = -1 }
    }
    if ($sel -lt 0 -or $sel -ge $paths.Count) { Fail 'Aucune image selectionnee / choix hors liste.' }
    $wim = $paths[$sel]
    $cat = $items[$sel].Category      # 'Modele' | 'Edition'
    $ImgName = Split-Path $wim -Leaf
    Report 'demarrage' 'running' "Image $ImgName"

    # Index : auto si le WIM ne contient qu'une image, sinon on demande
    $imgs = @(Get-WindowsImage -ImagePath $wim)
    if ($imgs.Count -eq 1) {
        $index = $imgs[0].ImageIndex
        Write-Host "Image : $($imgs[0].ImageName) (index $index)" -ForegroundColor Green
    } else {
        Write-Host "`nPlusieurs images dans ce WIM :" -ForegroundColor Cyan
        foreach ($im in $imgs) { Write-Host "  index $($im.ImageIndex) : $($im.ImageName)" }
        $index = [int](Read-Host 'Index a appliquer')
    }

    # En mode graphique, la case a cocher "Je confirme l effacement" a deja valide -> pas de re-saisie.
    if (-not $usedGui) {
        if ((Read-Host "Taper OUI pour EFFACER le disque $Disk et reinstaller") -ne 'OUI') { Fail 'Annule par l operateur.' }
    }

    # Partition GPT / UEFI
    $dp = @"
select disk $Disk
clean
convert gpt
create partition efi size=260
format quick fs=fat32 label=System
assign letter=S
create partition msr size=16
create partition primary
format quick fs=ntfs label=Windows
assign letter=W
exit
"@
    Report 'partitionnement' 'running' "Disque $Disk"
    $dp | Out-File -Encoding ascii X:\dp.txt
    diskpart /s X:\dp.txt
    if ($LASTEXITCODE -ne 0) { Fail "diskpart a echoue (code $LASTEXITCODE)." }

    # Apply du WIM
    Report 'application' 'running' "index $index"
    Write-Host "Application de l'image (peut prendre plusieurs minutes)..." -ForegroundColor Cyan
    dism /Apply-Image /ImageFile:"$wim" /Index:$index /ApplyDir:W:\
    if ($LASTEXITCODE -ne 0) { Fail "dism /Apply-Image a echoue (code $LASTEXITCODE)." }

    # Unattend (jonction + admin local + locale) -> traite au 1er boot
    New-Item -ItemType Directory -Force -Path W:\Windows\Panther | Out-Null
    Copy-Item $Unattend W:\Windows\Panther\unattend.xml -Force

    # Outil de capture : depose UNIQUEMENT sur une install NUE (edition), dans un dossier
    # RESERVE AUX ADMINISTRATEURS (jamais les eleves). Il sera ensuite embarque dans les
    # captures (donc les modeles le transportent tout seuls). ACL par SID connus (langue-independant) :
    # Administrateurs = S-1-5-32-544, SYSTEM = S-1-5-18. On coupe l'heritage -> pas d'acces "Utilisateurs".
    if ($cat -eq 'Edition' -and (Test-Path $CaptureCmd)) {
        $toolDir = 'W:\Ec19'
        New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
        Copy-Item $CaptureCmd (Join-Path $toolDir 'Preparer-la-capture.cmd') -Force
        icacls $toolDir /inheritance:r /grant "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" | Out-Null
        Write-Host "Outil de capture depose dans C:\Ec19 (admins uniquement)." -ForegroundColor Cyan
    }

    # Pilotes : dossier du modele, nomme selon le fabricant. On essaie plusieurs identifiants :
    #  - HP     : SysID = Win32_BaseBoard.Product          (ex. 8AC9)
    #  - Lenovo : machine type = 4 premiers car. du Model   (ex. 13HR)
    # On prend le premier dossier existant sous drivers\ ; sinon repli sur TOUS les pilotes (match PnP).
    Report 'pilotes' 'running' $Model
    if (Test-Path $DrvDir) {
        $cands = @()
        try { $cands += (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product } catch {}
        try { $mdl = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model; if ($mdl -and $mdl.Length -ge 4) { $cands += $mdl.Substring(0,4) } } catch {}
        $cands = @($cands | Where-Object { $_ } | Select-Object -Unique)
        $drvHit = $null
        foreach ($c in $cands) { $p = Join-Path $DrvDir $c; if (Test-Path $p) { $drvHit = $p; break } }
        if ($drvHit) {
            Write-Host ("Pilotes du modele ({0})..." -f (Split-Path $drvHit -Leaf)) -ForegroundColor Cyan
            dism /Image:W:\ /Add-Driver /Driver:$drvHit /Recurse
        } else {
            Write-Host ("Aucun dossier pilote dedie (essaye : {0}) -> tous les pilotes (PnP)..." -f ($cands -join ', ')) -ForegroundColor Cyan
            dism /Image:W:\ /Add-Driver /Driver:$DrvDir /Recurse
        }
    }

    # Rendre bootable (UEFI)
    Report 'amorcage' 'running' 'bcdboot'
    bcdboot W:\Windows /s S: /f UEFI
    if ($LASTEXITCODE -ne 0) { Fail "bcdboot a echoue (code $LASTEXITCODE)." }

    Report 'termine' 'ok' 'Deploiement termine, redemarrage'
    Write-Host "OK - redemarrage sur le disque..." -ForegroundColor Green
    try { Stop-Transcript | Out-Null } catch {}
    Start-Sleep 3
    wpeutil reboot
}
catch { Fail $_.Exception.Message }
