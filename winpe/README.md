# WinPE — image de boot + script de déploiement

WinPE (construit avec le **Windows ADK** + WinPE add-on) est l'environnement dans lequel on boote pour
**appliquer un WIM** (image de référence), l'`unattend.xml` et les drivers, puis rebooter sur le poste
installé.

## À produire
1. **Build WinPE** (une fois, sur un poste ADK) :
   - `copype amd64 C:\winpe_amd64`
   - monter `media\sources\boot.wim`, y injecter : les **drivers réseau/stockage**, le script de
     déploiement (`deploy.ps1`), et le lancer via `startnet.cmd` / `winpeshl.ini`.
   - démonter + commit → `boot.wim` publié dans `tftp` (servi en HTTP par le serveur PXE).
2. **`deploy.ps1`** (dans WinPE) — squelette de la séquence :
   - partitionner le disque (GPT/UEFI ou MBR/BIOS) ;
   - `DISM /Apply-Image` du **WIM de référence** (récupéré en HTTP depuis `images/`) ;
   - copier l'`unattend.xml` (langue, nom, compte local, **jonction de domaine** éventuelle) ;
   - injecter les **drivers** par modèle ;
   - `bcdboot` + reboot.

## Décisions à trancher (avant de coder)
- **Source du WIM** : capture d'un master sysprepé, ou `install.wim` d'un ISO + apps post-install ?
- **Jonction de domaine** au déploiement : oui/non, et **quel domaine** (atelier MARBOT vs collège cible) ?
- **BIOS/UEFI** (schéma de partitionnement) + **Secure Boot**.
- **Outil** : WinPE + `deploy.ps1` maison (léger, contrôle total) vs **WDS** (natif Windows).

*(À produire : `deploy.ps1`, `unattend.xml` (modèle, sans secret), notes de build WinPE.)*
