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

# Injecter le script + le shell de lancement
Copy-Item .\deploy.ps1     C:\WinPE_amd64\mount\deploy.ps1 -Force
Copy-Item .\winpeshl.ini   C:\WinPE_amd64\mount\Windows\System32\winpeshl.ini -Force

# (option) pilotes reseau/stockage dans le WinPE si une carte n'est pas reconnue :
# Dism /Add-Driver /Image:C:\WinPE_amd64\mount /Driver:<dossier_inf> /Recurse

# Demonter en commitant
Dism /Unmount-Image /MountDir:C:\WinPE_amd64\mount /Commit
```

## Importer dans WDS + partage de déploiement
1. WDS → **Images de démarrage** → importer `C:\WinPE_amd64\media\sources\boot.wim` (ce WinPE custom).
2. Créer un **partage** `\\stats\Deploy$` (lecture pour `svc.wds`) contenant :
   - `images\` : les WIM (`install-pro-edu.wim`, `install-pro.wim`, ou `master.wim`) ;
   - `drivers\` : les packs HP (INF, récursif) ;
   - `unattend\ImageUnattend.xml` (jonction + admin local + locale — copie **remplie**, hors dépôt).
3. Options DHCP 66/67 inchangées → le poste PXE-boote ce WinPE → **`deploy.ps1` s'exécute** (partition
   GPT, apply WIM, unattend, pilotes, bcdboot, reboot).

## Fichiers de ce dossier
- `deploy.ps1` : le déploiement (à adapter : `$Server`, noms de WIM). ASCII pur.
- `winpeshl.ini` : lance `wpeinit` puis `deploy.ps1` au démarrage du WinPE.
