<#
  deploy.ps1 - Deploiement Windows depuis WinPE, SANS le client WDS (deprecie en Server 2025).
  WDS ne sert qu'a amorcer ce WinPE (transport PXE). Ce script fait tout : partition GPT (UEFI),
  apply du WIM depuis un partage, unattend, injection pilotes, bcdboot, reboot.

  A placer dans le WinPE (via winpeshl.ini). Le partage \\srv-pxe\Deploy$ contient :
    images\   -> les WIM (install-pro-edu.wim, install-pro.wim, ou master.wim)
    drivers\  -> les packs de pilotes HP (INF, recursif)
    unattend\ -> ImageUnattend.xml (locale + jonction ecollege19.lan + admin local)

  IMPORTANT : ASCII pur (convention du projet). A ADAPTER + TESTER (chemins, noms de WIM).
#>
$ErrorActionPreference = 'Stop'

# --- Config ---------------------------------------------------------------
$Server   = 'srv-pxe.ecollege19.lan'          # alias de stats (ou IP)
$Share    = "\\$Server\Deploy$"
$ImgDir   = "$Share\images"
$DrvDir   = "$Share\drivers"
$Unattend = "$Share\unattend\ImageUnattend.xml"
$Disk     = 0                                  # disque cible

function Pause-Fail($m){ Write-Host "`nERREUR: $m" -ForegroundColor Red; Write-Host "Tape une touche pour redemarrer..."; [void][System.Console]::ReadKey($true); wpeutil reboot }

try {
    Write-Host "=== Deploiement eCollege19 (WinPE) ===" -ForegroundColor Cyan

    # 1. Connexion au partage (compte lecture ; saisie du mot de passe)
    $user = "ECOLLEGE19\svc.wds"
    Write-Host "Mot de passe de $user :" -ForegroundColor Yellow
    $pw = Read-Host -AsSecureString
    $pwPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))
    cmd /c "net use $Share /user:$user $pwPlain" | Out-Null
    if (-not (Test-Path $ImgDir)) { Pause-Fail "Partage $ImgDir injoignable (creds ? reseau ?)." }

    # 2. Choix de l'image (WIM) et de l'edition
    $wims = Get-ChildItem -Path $ImgDir -Filter *.wim
    if (-not $wims) { Pause-Fail "Aucun .wim dans $ImgDir." }
    for ($i=0; $i -lt $wims.Count; $i++) { Write-Host "  [$i] $($wims[$i].Name)" }
    $sel = Read-Host "Numero du WIM a deployer"
    $wim = $wims[[int]$sel].FullName
    dism /Get-ImageInfo /ImageFile:$wim
    $index = Read-Host "Index a appliquer (edition)"

    # 3. Confirmation (efface le disque !)
    Write-Host "`n!!! Le disque $Disk va etre EFFACE et reinstalle !!!" -ForegroundColor Red
    if ((Read-Host "Taper OUI pour continuer") -ne 'OUI') { Pause-Fail "Annule par l'operateur." }

    # 4. Partition GPT / UEFI (diskpart)
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

    # 5. Apply du WIM sur W:
    Write-Host "Application de l'image..." -ForegroundColor Cyan
    dism /Apply-Image /ImageFile:$wim /Index:$index /ApplyDir:W:\

    # 6. Unattend (jonction + admin local + locale) -> traite au 1er boot
    New-Item -ItemType Directory -Force -Path W:\Windows\Panther | Out-Null
    Copy-Item $Unattend W:\Windows\Panther\unattend.xml -Force

    # 7. Injection des pilotes : cible le dossier du MODELE (nomme par SysID = Win32_BaseBoard.Product,
    #    ex. 8AC9), sinon replie sur TOUS les pilotes (/Recurse) et laisse Windows matcher par PnP.
    if (Test-Path $DrvDir) {
        $sysId = (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product
        $modelDir = if ($sysId) { Join-Path $DrvDir $sysId } else { $null }
        if ($modelDir -and (Test-Path $modelDir)) {
            Write-Host "Pilotes du modele $sysId (dossier dedie)..." -ForegroundColor Cyan
            dism /Image:W:\ /Add-Driver /Driver:$modelDir /Recurse
        } else {
            Write-Host "SysID '$sysId' sans dossier dedie -> injection de TOUS les pilotes (match PnP)..." -ForegroundColor Cyan
            dism /Image:W:\ /Add-Driver /Driver:$DrvDir /Recurse
        }
    }

    # 8. Rendre bootable (UEFI)
    bcdboot W:\Windows /s S: /f UEFI

    # 9. Reboot sur le disque
    Write-Host "OK - redemarrage..." -ForegroundColor Green
    Start-Sleep 3
    wpeutil reboot
}
catch { Pause-Fail $_.Exception.Message }
