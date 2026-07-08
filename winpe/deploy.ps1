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
$ConfigUrl   = 'https://stats.ecollege19.lan/pc/api/pxe/config'   # registre modeles + reglages (page web)
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

# Config depuis la page web (modeles + reglages). Repli silencieux si injoignable.
# RETRY : juste apres le montage SMB, la pile HTTPS n'est pas toujours chaude (1er appel ->
# "underlying connection was closed / unexpected error on a send"). On reessaie quelques fois.
$script:CfgErr = ''
function Get-PxeConfig {
    if (-not $ReportToken -or $ReportToken -like '*JETON*') { $script:CfgErr = 'jeton $ReportToken non renseigne (placeholder)'; return $null }
    for ($i = 1; $i -le 5; $i++) {
        try { return Invoke-RestMethod -Uri $ConfigUrl -Method Get -Headers @{ 'X-PXE-Token'=$ReportToken } -TimeoutSec 10 }
        catch { $script:CfgErr = $_.Exception.Message; if ($i -lt 5) { Start-Sleep -Seconds 3 } }
    }
    return $null
}

# Resout le dossier de pilotes via les regles du registre web (agnostique marque). $null si aucune.
function Resolve-DriverFolder($cfg) {
    if (-not $cfg -or -not $cfg.models) { return $null }
    $facts = @{}
    try { $facts['sysid'] = (Get-CimInstance Win32_BaseBoard -EA SilentlyContinue).Product } catch {}
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
        $facts['model'] = $cs.Model; $facts['manufacturer'] = $cs.Manufacturer
        if ($cs.Model -and $cs.Model.Length -ge 4) { $facts['machinetype'] = $cs.Model.Substring(0,4) }
    } catch {}
    foreach ($m in $cfg.models) {
        $fv = [string]$facts[[string]$m.match_field]
        if (-not $fv) { continue }
        $val = [string]$m.match_value
        $ok = $false
        switch ($m.match_op) {
            'equals'     { $ok = ($fv -ieq $val) }
            'contains'   { $ok = ($fv -like "*$val*") }
            'startswith' { $ok = ($fv -like "$val*") }
            'regex'      { try { $ok = ($fv -imatch $val) } catch { $ok = $false } }
        }
        if ($ok -and $m.driver_folder) { return [string]$m.driver_folder }
    }
    return $null
}

# Erreur recuperable : on affiche, on met en pause, puis on REVIENT AU MENU (throw sentinelle
# rattrapee par menu.ps1) au lieu de redemarrer le poste.
function Fail($m){
    Report 'erreur' 'error' $m
    Write-Host "`nERREUR: $m" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    Read-Host 'Note l erreur ci-dessus, puis tape Entree pour revenir au menu'
    throw 'EC19_HANDLED'
}

try {
    # Journal persistant sur le partage (lisible apres reboot)
    try { New-Item -ItemType Directory -Force -Path "$Share\logs" | Out-Null } catch {}
    try { Start-Transcript -Path ("$Share\logs\deploy-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log') -Force | Out-Null } catch {}

    Write-Host "=== Deploiement eCollege19 (WinPE) ===" -ForegroundColor Cyan
    if (-not (Test-Path $ImgDir)) { Fail "Dossier $ImgDir injoignable." }
    # La config web est recuperee PLUS BAS (apres le choix de l'image) : la pile HTTPS a alors
    # eu le temps de chauffer, le 1er GET ne casse plus ("unexpected error on a send").

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

    # gui.ps1 charge une fois (interface graphique si dispo, sinon invites texte).
    $gui = "$Share\gui.ps1"
    $guiLoaded = $false
    if (Test-Path $gui) { . $gui; $guiLoaded = (Test-Gui) }

    # Type de poste : PEDAGOGIQUE (joint au domaine du college) ou ADMINISTRATIF (hors domaine,
    # gere par le rectorat -> compte admin local, aucune jonction). Choisi UNE fois au debut.
    $posteType = 'peda'
    if (Get-Command Show-PosteType -ErrorAction SilentlyContinue) {
        $posteType = Show-PosteType
    } else {
        Write-Host "`nType de poste : [1] Pedagogique  [2] Administratif" -ForegroundColor Cyan
        $r = Read-Host 'Choix [1]'
        $posteType = if ($r.Trim() -eq '2') { 'admin' } else { 'peda' }
    }
    if ([string]::IsNullOrEmpty($posteType)) {
        Report 'annule' 'error' 'Annule au choix du type de poste (retour menu)'
        Write-Host 'Annulation -> retour au menu.' -ForegroundColor Yellow
        try { Stop-Transcript | Out-Null } catch {}
        throw 'EC19_HANDLED'
    }
    if ($posteType -eq 'admin') { Write-Host 'Type : ADMINISTRATIF (hors domaine, compte admin local).' -ForegroundColor Magenta }
    else { Write-Host 'Type : PEDAGOGIQUE (joint au domaine du college).' -ForegroundColor Green }

    # Boucle de navigation : image -> (index/config) -> OU -> Nom.
    # Depuis l'ecran OU/Nom on peut REVENIR (Retour) a l'etape precedente, ou ANNULER
    # (retour menu AVEC remontee de statut) -> plus besoin d'eteindre le poste pour sortir.
    $usedGui = $guiLoaded
    $masterMode = $false; $adminMode = $false; $ouDn = ''; $pcName = ''
    $deployReady = $false
    while (-not $deployReady) {
        # --- Choix de l'image ---
        $usedGui = $guiLoaded
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

        # --- Index : auto si le WIM ne contient qu'une image, sinon on demande ---
        $imgs = @(Get-WindowsImage -ImagePath $wim)
        if ($imgs.Count -eq 1) {
            $index = $imgs[0].ImageIndex
            Write-Host "Image : $($imgs[0].ImageName) (index $index)" -ForegroundColor Green
        } else {
            Write-Host "`nPlusieurs images dans ce WIM :" -ForegroundColor Cyan
            foreach ($im in $imgs) { Write-Host "  index $($im.ImageIndex) : $($im.ImageName)" }
            $index = [int](Read-Host 'Index a appliquer')
        }

        # --- Config web (registre modeles + reglages), recuperee ICI : la pile HTTPS a chauffe
        # pendant le choix de l'image -> le GET passe (contrairement a un appel des le demarrage).
        $PxeCfg = Get-PxeConfig
        if ($PxeCfg) {
            Write-Host ("[config] recue : models=" + @($PxeCfg.models).Count + " ous=" + @($PxeCfg.ous).Count + " settings.disk=" + $PxeCfg.settings.disk) -ForegroundColor DarkCyan
        } else {
            Write-Host ("[config] AUCUNE config recue. Erreur : " + $script:CfgErr) -ForegroundColor Yellow
            Write-Host ("[config] URL testee : " + $ConfigUrl) -ForegroundColor DarkGray
        }
        if ($PxeCfg -and $PxeCfg.settings) {
            if ("$($PxeCfg.settings.disk)" -match '^\d+$') { $Disk = [int]$PxeCfg.settings.disk }
            if ($PxeCfg.settings.unattend) { $Unattend = Join-Path "$Share\unattend" ([string]$PxeCfg.settings.unattend) }
        }
        $oarr = @(); if ($PxeCfg -and $PxeCfg.ous) { $oarr = @($PxeCfg.ous) }

        # --- OU / Nom : sous-navigation (Retour = re-choix image ; Annuler = retour menu) ---
        $goBackToImage = $false
        $masterMode = $false; $adminMode = $false; $ouDn = ''; $pcName = ''
        if ($posteType -eq 'admin') {
            # Poste ADMINISTRATIF : pas de choix d'OU, jamais joint au domaine (rectorat) -> on va
            # directement au nom, avec compte admin local (jonction retiree de l'unattend plus bas).
            $adminMode = $true
            Write-Host "Destination : ADMINISTRATIF -> hors domaine (aucune jonction)." -ForegroundColor Magenta
            $stage = 'name'
        } else {
            $stage = 'ou'
        }
        while ($true) {
            if ($stage -eq 'ou') {
                # Choix college -> OU (ou MASTER sans jonction). Toujours propose (AUCUN + MASTER meme sans OU).
                if (Get-Command Show-OuPicker -ErrorAction SilentlyContinue) {
                    $ouChoice = Show-OuPicker $oarr
                } else {
                    Write-Host "`nDestination :" -ForegroundColor Cyan
                    Write-Host '  [0] AUCUN (OU par defaut)'
                    for ($i=0; $i -lt $oarr.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i+1), $oarr[$i].label) }
                    Write-Host ("  [{0}] Preparer un MASTER (NE PAS joindre le domaine)" -f ($oarr.Count+1))
                    Write-Host '  [r] Revenir au choix de l image     [a] Annuler (retour menu)'
                    $r = Read-Host 'Numero [0]'
                    if     ($r -match '^(r|R)$') { $ouChoice = '__BACK__' }
                    elseif ($r -match '^(a|A)$') { $ouChoice = '__CANCEL__' }
                    elseif ($r -match '^\d+$' -and [int]$r -ge 1 -and [int]$r -le $oarr.Count) { $ouChoice = [string]$oarr[[int]$r-1].ou_dn }
                    elseif ($r -match '^\d+$' -and [int]$r -eq ($oarr.Count+1)) { $ouChoice = '__MASTER__' }
                    else { $ouChoice = '' }
                }
                if ($ouChoice -eq '__CANCEL__') {
                    Report 'annule' 'error' 'Annule par l operateur (retour menu)'
                    Write-Host 'Annulation -> retour au menu.' -ForegroundColor Yellow
                    try { Stop-Transcript | Out-Null } catch {}
                    throw 'EC19_HANDLED'
                }
                if ($ouChoice -eq '__BACK__') { $goBackToImage = $true; break }
                $masterMode = ($ouChoice -eq '__MASTER__')
                $ouDn = if ($masterMode) { '' } else { $ouChoice }
                if ($masterMode)  { Write-Host "Mode MASTER : le poste NE sera PAS joint au domaine (image de reference)." -ForegroundColor Magenta }
                elseif ($ouDn)    { Write-Host "OU de jonction : $ouDn" -ForegroundColor Green }
                if ($masterMode) { $pcName = ''; break }   # pas de nom en mode master
                $stage = 'name'; continue
            }
            if ($stage -eq 'name') {
                # Nom du poste : vide = automatique (renomme sur site). Retour -> revient a l'OU.
                if (Get-Command Show-InputDialog -ErrorAction SilentlyContinue) {
                    $pcName = Show-InputDialog 'Nom du poste' "Nom de l'ordinateur (laisser VIDE = automatique, renomme sur site ; max 15 car.).  Retour = revenir a la destination." ''
                } else {
                    $pcName = Read-Host "Nom de l'ordinateur (vide = automatique ; 'retour' = revenir a la destination)"
                }
                if ($pcName -eq '__BACK__') {
                    if ($adminMode) { $goBackToImage = $true; break }   # pas d'OU en admin -> retour au choix de l'image
                    $stage = 'ou'; continue
                }
                if ($pcName) {
                    $pcName = ($pcName -replace '[^A-Za-z0-9\-]', '')
                    if ($pcName.Length -gt 15) { $pcName = $pcName.Substring(0, 15) }
                }
                if ($pcName) { Write-Host "Nom du poste : $pcName" -ForegroundColor Green } else { Write-Host "Nom : automatique (a renommer sur site)." -ForegroundColor DarkGray }
                break
            }
        }
        if ($goBackToImage) { continue }
        $deployReady = $true
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

    # Apply du WIM (barre de progression au lieu du mode verbeux si dispo)
    Report 'application' 'running' "index $index"
    Write-Host "Application de l'image (peut prendre plusieurs minutes)..." -ForegroundColor Cyan
    if (Get-Command Invoke-DismBar -ErrorAction SilentlyContinue) {
        $code = Invoke-DismBar ('/Apply-Image /ImageFile:"' + $wim + '" /Index:' + $index + ' /ApplyDir:W:\')
    } else {
        dism /Apply-Image /ImageFile:"$wim" /Index:$index /ApplyDir:W:\
        $code = $LASTEXITCODE
    }
    if ($code -ne 0) { Fail "dism /Apply-Image a echoue (code $code)." }

    # Unattend (jonction + admin local + locale) -> traite au 1er boot. On personnalise :
    #  - nom du poste (<ComputerName>) si fourni ; vide -> '*' (auto) conserve ;
    #  - OU de jonction (<MachineObjectOU>) si un college a ete choisi ;
    #  - mode MASTER : on RETIRE le composant UnattendedJoin -> le poste reste hors domaine.
    New-Item -ItemType Directory -Force -Path W:\Windows\Panther | Out-Null
    if ($masterMode -or $adminMode -or $ouDn -or $pcName) {
        $xmlua = Get-Content $Unattend -Raw
        if ($pcName) { $xmlua = $xmlua -replace '<ComputerName>.*?</ComputerName>', "<ComputerName>$pcName</ComputerName>" }
        if ($masterMode -or $adminMode) {
            # MASTER (image de reference) OU ADMINISTRATIF (rectorat) : hors domaine -> on RETIRE
            # le composant UnattendedJoin (le compte admin local de l'unattend suffit).
            $xmlua = $xmlua -replace '(?s)\s*<component name="Microsoft-Windows-UnattendedJoin".*?</component>', ''
        } elseif ($ouDn) {
            $xmlua = $xmlua -replace '(?m)^\s*<MachineObjectOU>.*?</MachineObjectOU>\s*\r?\n', ''
            $xmlua = $xmlua -replace '</JoinDomain>', "</JoinDomain>`r`n        <MachineObjectOU>$ouDn</MachineObjectOU>"
        }
        [System.IO.File]::WriteAllText('W:\Windows\Panther\unattend.xml', $xmlua, (New-Object System.Text.UTF8Encoding($false)))
        $nom = if ($pcName) { $pcName } else { 'auto' }
        $jonc = if ($masterMode) { 'MASTER (hors domaine)' } elseif ($adminMode) { 'ADMINISTRATIF (hors domaine)' } elseif ($ouDn) { "OU $ouDn" } else { 'OU par defaut' }
        Write-Host "Unattend prepare (nom: $nom ; jonction: $jonc)." -ForegroundColor Cyan
    } else {
        Copy-Item $Unattend W:\Windows\Panther\unattend.xml -Force
    }

    # Outil de capture : depose UNIQUEMENT sur une install NUE (edition), dans un dossier
    # RESERVE AUX ADMINISTRATEURS (jamais les eleves). Il sera ensuite embarque dans les
    # captures (donc les modeles le transportent tout seuls). ACL par SID connus (langue-independant) :
    # Administrateurs = S-1-5-32-544, SYSTEM = S-1-5-18. On coupe l'heritage -> pas d'acces "Utilisateurs".
    if ($cat -eq 'Edition' -and (Test-Path $CaptureCmd)) {
        $toolDir = 'W:\Ec19'
        New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
        Copy-Item $CaptureCmd (Join-Path $toolDir 'Preparer-la-capture.cmd') -Force
        # generalize.xml (SkipRearm) a cote du .cmd -> re-sysprep du master sans limite de rearm
        $genXml = "$Share\generalize.xml"
        if (Test-Path $genXml) { Copy-Item $genXml (Join-Path $toolDir 'generalize.xml') -Force }
        icacls $toolDir /inheritance:r /grant "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" | Out-Null
        Write-Host "Outil de capture depose dans C:\Ec19 (admins uniquement)." -ForegroundColor Cyan
    }

    # Pilotes : dossier du modele, nomme selon le fabricant. On essaie plusieurs identifiants :
    #  - HP     : SysID = Win32_BaseBoard.Product          (ex. 8AC9)
    #  - Lenovo : machine type = 4 premiers car. du Model   (ex. 13HR)
    # On prend le premier dossier existant sous drivers\ ; sinon repli sur TOUS les pilotes (match PnP).
    Report 'pilotes' 'running' $Model
    if (Test-Path $DrvDir) {
        $drvHit = $null
        # 1) Registre web (regles de detection, toutes marques)
        $cfgFolder = Resolve-DriverFolder $PxeCfg
        if ($cfgFolder) { $p = Join-Path $DrvDir $cfgFolder; if (Test-Path $p) { $drvHit = $p } }
        # 2) Repli heuristique : SysID HP puis machine type Lenovo
        $cands = @()
        try { $cands += (Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue).Product } catch {}
        try { $mdl = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Model; if ($mdl -and $mdl.Length -ge 4) { $cands += $mdl.Substring(0,4) } } catch {}
        $cands = @($cands | Where-Object { $_ } | Select-Object -Unique)
        if (-not $drvHit) { foreach ($c in $cands) { $p = Join-Path $DrvDir $c; if (Test-Path $p) { $drvHit = $p; break } } }
        if ($drvHit) {
            Write-Host ("Injection des pilotes du modele ({0})..." -f (Split-Path $drvHit -Leaf)) -ForegroundColor Cyan
            $drvTarget = $drvHit
        } else {
            Write-Host ("Aucun dossier pilote dedie (essaye : {0}) -> tous les pilotes (PnP)..." -f ($cands -join ', ')) -ForegroundColor Cyan
            $drvTarget = $DrvDir
        }
        # Barre de progression (comme l'apply) ; sinon dism direct.
        if (Get-Command Invoke-DismBar -ErrorAction SilentlyContinue) {
            Invoke-DismBar ('/Image:W:\ /Add-Driver /Driver:"' + $drvTarget + '" /Recurse') | Out-Null
        } else {
            dism /Image:W:\ /Add-Driver /Driver:$drvTarget /Recurse
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
catch { if ("$($_.Exception.Message)" -ne 'EC19_HANDLED') { Fail $_.Exception.Message } }
