# WinPE maison — déploiement par script (Voie B, car le client WDS est déprécié en Server 2025)

Le **client WDS** (assistant qui déploie les install images) est **déprécié** en Windows Server 2025
(« la fonctionnalité du client des Services de déploiement Windows est partiellement déconseillée »
→ OK → reboot disque). On n'utilise donc plus le déploiement WDS : **WDS n'amorce qu'un WinPE**
(transport PXE, non déprécié) et **ce WinPE déploie par script** (`deploy.ps1`).

## À savoir
- Le `winpe.wim` de base de l'ADK (`...\Windows Preinstallation Environment\amd64\en-us\winpe.wim`)
  boote sur une **invite de commande** (pas le client WDS) → parfait comme base, mais il faut y
  **ajouter PowerShell** (absent du WinPE de base) et notre script.
- Secure Boot OK : WinPE ADK + `wdsmgfw.efi` (amorçage WDS) sont signés Microsoft.

## Construire le WinPE (poste avec ADK + WinPE add-on)
```powershell
copype amd64 C:\WinPE_amd64
Dism /Mount-Image /ImageFile:C:\WinPE_amd64\media\sources\boot.wim /Index:1 /MountDir:C:\WinPE_amd64\mount

# Ajouter PowerShell + dependances (ORDRE important) depuis WinPE_OCs de l'ADK
$ocs = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"
foreach ($c in 'WinPE-WMI','WinPE-NetFX','WinPE-Scripting','WinPE-PowerShell','WinPE-StorageWMI','WinPE-DismCmdlets') {
    Dism /Add-Package /Image:C:\WinPE_amd64\mount /PackagePath:"$ocs\$c.cab"
}

# Injecter le BOOTSTRAP (stable) + le shell de lancement. deploy.ps1 n'est PAS fige dans le
# WinPE : il vit sur le partage (voir plus bas) -> editable sans reconstruire le WinPE.
# IMPORTANT : injecter bootstrap.LOCAL.ps1 (copie gitignoree ou l'on met le VRAI mot de passe
# svc.wds), renommee en bootstrap.ps1 dans le WinPE. Ne jamais commiter bootstrap.local.ps1.
Copy-Item .\bootstrap.local.ps1  C:\WinPE_amd64\mount\bootstrap.ps1 -Force
Copy-Item .\winpeshl.ini         C:\WinPE_amd64\mount\Windows\System32\winpeshl.ini -Force

# (option) pilotes reseau/stockage dans le WinPE si une carte n'est pas reconnue :
# Dism /Add-Driver /Image:C:\WinPE_amd64\mount /Driver:<dossier_inf> /Recurse

# Demonter en commitant
Dism /Unmount-Image /MountDir:C:\WinPE_amd64\mount /Commit
```

## Importer dans WDS + partage de déploiement
1. WDS → **Images de démarrage** → importer `C:\WinPE_amd64\media\sources\boot.wim` (ce WinPE custom).
2. Créer un **partage** `\\stats\Deploy$` pour `svc.wds` (**Lecture** partout, **Modifier sur `images\`**
   pour permettre la capture) contenant, **à la RACINE** (tous éditables sans rebuild) :
   - **`menu.ps1`** — menu au démarrage : `[1]` déployer / `[2]` capturer ;
   - **`deploy.ps1`** — déploiement (partition GPT, apply WIM, unattend, pilotes, bcdboot, reboot) ;
   - **`capture.ps1`** — capture d'une image de référence → écrit dans `images\`, nom = modèle auto ;
   - `images\` : les WIM déployables (éditions `Win11_Pro.wim`… **et** les images capturées par modèle) ;
   - `drivers\` : les packs HP en dossiers **par SysID** (`8AC9\`, `8591\`…), récursif ;
   - `unattend\ImageUnattend.xml` (jonction + admin local + locale — copie **remplie**, hors dépôt).
3. Options DHCP 66/67 inchangées → le poste PXE-boote le WinPE → `wpeinit` → **`bootstrap.ps1`**
   (monte le partage) → **`menu.ps1`** → `deploy.ps1` ou `capture.ps1`. Journal dans `\\...\Deploy$\logs\`.

## Pattern bootstrap (pourquoi)
`bootstrap.ps1` (figé, stable) monte le partage et lance **`menu.ps1` depuis le partage** (fallback
`deploy.ps1` si absent) → on **édite menu/deploy/capture sur le partage** sans jamais reconstruire le
WinPE. En cas d'erreur : **pause `Read-Host`** (l'écran reste, lisible) + **transcript** dans `\logs\`.

## Boucle capture → déploiement
`capture.ps1` écrit **directement dans `images\`** (d'où le droit *Modifier* pour `svc.wds`) → l'image
capturée **apparaît aussitôt** dans la liste de `deploy.ps1`. Prérequis : le poste modèle a été
généralisé via `../capture/Preparer-la-capture.cmd` (sysprep). Détail : `../capture/README.md`.

## Fichiers de ce dossier
- `bootstrap.ps1` : modèle **figé dans le WinPE** — monte le partage (creds `svc.wds`, mot de passe **figé** pour l'imaging sans saisie) et lance `menu.ps1` du partage. `$Pass` = placeholder.
- `bootstrap.local.ps1` : **copie gitignorée** de `bootstrap.ps1` avec le **vrai** mot de passe `svc.wds`. C'est ELLE qu'on injecte (renommée `bootstrap.ps1`) dans le WinPE. **Jamais commitée.**
- `menu.ps1` : **à copier à la racine du partage** — menu déployer/capturer. Éditable sans rebuild.
- `deploy.ps1` : **à copier à la racine du partage** — le déploiement. Éditable sans rebuild. ASCII pur.
- `capture.ps1` : **à copier à la racine du partage** — la capture d'image de référence. Éditable sans rebuild. ASCII pur.
- `winpeshl.ini` : lance `wpeinit` puis `bootstrap.ps1`.
