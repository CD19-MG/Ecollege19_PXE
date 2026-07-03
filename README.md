# Ecollege19_PXE — Déploiement de postes par le réseau (imaging en masse)

Projet **distinct de l'agent EPM** (`Ecollege19_Monitor_PC`) : l'EPM **supervise/agit** sur le parc
en fonctionnement ; **ce projet provisionne/image** des postes neufs ou remis à blanc **à l'atelier**
(collège MARBOT) avant envoi. Remplace l'installation manuelle. Inspiré de MDT/PDQ Deploy, adapté à
notre stack self-hosted.

## Périmètre V1
- **Un seul site : MARBOT** (poste/atelier de préparation). Pas de PXE dans les collèges.
- **Un seul subnet : `10.119.50.x`.**
- **DHCP : `srv-wvdnscollf`** (DHCP du réseau) → on y pose les **options d'amorçage** (66 = serveur
  TFTP, 67 = bootfile). **Pas de second DHCP** côté PXE → aucun conflit, pas de proxyDHCP.
- Usage = **provisioning / réimage à blanc EN MASSE** (bare-metal). La mise à niveau in-place (Win11)
  reste gérée par l'agent EPM.

## Menu PXE
1. **Amorcer le disque local** — entrée par **défaut** (sécurité : pas de réimage accidentel).
2. **Déployer Windows** — WinPE → apply WIM + unattend + drivers.
3. **HBCD** (Hiren's BootCD PE) — secours / diagnostic.

## Structure
```
docs/    cadrage (epopee_pxe.md) + notes
dhcp/    options 66/67 à poser sur srv-wvdnscollf (exemples/notes)
tftp/    bootloader iPXE/PXELinux + menu (menu.ipxe)
winpe/   scripts de build WinPE + déploiement WIM + unattend + drivers
images/  WIM de référence — NON versionné (gros fichiers, cf. .gitignore)
```

## Lien avec la console EPM
Optionnel, phase 3 : un panneau d'orchestration dans le dashboard PC (associer poste↔image,
déclencher, suivre) qui parlerait à l'API du serveur PXE. Le cœur PXE reste ici, autonome.

## État
**Cadrage** (cf. `docs/epopee_pxe.md`). Décisions à trancher avant P1 : BIOS/UEFI, Secure Boot,
source du WIM, jonction de domaine, outil (WinPE maison vs WDS). Phases : P1 amorçage → P2 payload
→ P3 orchestration.
