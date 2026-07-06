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

function Fail($m){
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

    # Choix de l'edition = choix du fichier WIM (un WIM par edition : Pro, Pro Education...)
    $wims = @(Get-ChildItem -Path $ImgDir -Filter *.wim | Sort-Object Name)
    if (-not $wims) { Fail "Aucun .wim dans $ImgDir." }
    Write-Host "`nEditions disponibles :" -ForegroundColor Cyan
    for ($i=0; $i -lt $wims.Count; $i++) { Write-Host "  [$i] $($wims[$i].Name)" }
    $sel = [int](Read-Host 'Numero de l edition a deployer')
    if ($sel -lt 0 -or $sel -ge $wims.Count) { Fail "Choix hors liste." }
    $wim = $wims[$sel].FullName

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

    if ((Read-Host "Taper OUI pour EFFACER le disque $Disk et reinstaller") -ne 'OUI') { Fail 'Annule par l operateur.' }

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
    $dp | Out-File -Encoding ascii X:\dp.txt
    diskpart /s X:\dp.txt
    if ($LASTEXITCODE -ne 0) { Fail "diskpart a echoue (code $LASTEXITCODE)." }

    # Apply du WIM
    Write-Host "Application de l'image (peut prendre plusieurs minutes)..." -ForegroundColor Cyan
    dism /Apply-Image /ImageFile:"$wim" /Index:$index /ApplyDir:W:\
    if ($LASTEXITCODE -ne 0) { Fail "dism /Apply-Image a echoue (code $LASTEXITCODE)." }

    # Unattend (jonction + admin local + locale) -> traite au 1er boot
    New-Item -ItemType Directory -Force -Path W:\Windows\Panther | Out-Null
    Copy-Item $Unattend W:\Windows\Panther\unattend.xml -Force

    # Pilotes : dossier du modele (nomme par SysID) sinon tous (match PnP)
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
    bcdboot W:\Windows /s S: /f UEFI
    if ($LASTEXITCODE -ne 0) { Fail "bcdboot a echoue (code $LASTEXITCODE)." }

    Write-Host "OK - redemarrage sur le disque..." -ForegroundColor Green
    try { Stop-Transcript | Out-Null } catch {}
    Start-Sleep 3
    wpeutil reboot
}
catch { Fail $_.Exception.Message }
