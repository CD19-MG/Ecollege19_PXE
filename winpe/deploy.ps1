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

    # Choix via l'interface graphique si dispo (gui.ps1), sinon liste texte
    $usedGui = $false
    $gui = "$Share\gui.ps1"
    if (Test-Path $gui) { . $gui; $usedGui = (Test-Gui) }
    if ($usedGui) {
        $sel = Show-ImagePicker $items
        $usedGui = (Test-Gui)   # a pu retomber en texte si l'affichage a echoue
    } else {
        Write-Host ''
        for ($i=0; $i -lt $items.Count; $i++) {
            if ($i -eq 0 -and $models.Count)     { Write-Host 'Images par MODELE (recommande - a jour) :' -ForegroundColor Cyan }
            if ($i -eq $models.Count)            { Write-Host 'Installation complete (Windows nu) :'     -ForegroundColor DarkCyan }
            Write-Host ("  [{0}] {1}" -f $i, $items[$i].Label)
        }
        $r = Read-Host 'Numero de l image a deployer'
        $sel = if ($r -match '^\d+$') { [int]$r } else { -1 }
    }
    if ($sel -lt 0 -or $sel -ge $paths.Count) { Fail 'Aucune image selectionnee / choix hors liste.' }
    $wim = $paths[$sel]
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

    # Pilotes : dossier du modele (nomme par SysID) sinon tous (match PnP)
    Report 'pilotes' 'running' $Model
    if (Test-Path $DrvDir) {
        $sysId = (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product
        $modelDir = if ($sysId) { Join-Path $DrvDir $sysId } else { $null }
        if ($modelDir -and (Test-Path $modelDir)) {
            Write-Host "Pilotes du modele $sysId..." -ForegroundColor Cyan
            dism /Image:W:\ /Add-Driver /Driver:$modelDir /Recurse
        } else {
            Write-Host "SysID '$sysId' sans dossier dedie -> tous les pilotes (PnP)..." -ForegroundColor Cyan
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
