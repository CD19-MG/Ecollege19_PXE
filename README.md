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

## Amorçage — voie retenue : **WDS (+ MDT)**, Secure Boot activé
Les postes sont **UEFI récents avec Secure Boot ON** (les legacy sont remplacés). Secure Boot
n'exécute qu'un bootloader **signé Microsoft** → on utilise **WDS** (binaires signés MS) + **MDT**
pour la séquence de déploiement. C'est le « MDT en PXE » cible, **sans désactiver Secure Boot**.
*(iPXE/HTTP Boot — cf. `tftp/` — est écarté car non signé MS ; conservé comme alternative si un jour
Secure Boot OFF.)*

## Structure
```
docs/    cadrage (epopee_pxe.md) + notes
dhcp/    options 66/67 à poser sur srv-wvdnscollf (pointent vers WDS)
wds/     VOIE RETENUE : mise en place WDS + MDT (Secure Boot natif)
winpe/   personnalisation WinPE / deploy + unattend + drivers (via MDT)
tftp/    ALTERNATIVE (Secure Boot OFF) : bootloader iPXE + menu.ipxe — non utilisé pour l'instant
images/  WIM de référence — NON versionné (gros fichiers, cf. .gitignore)
```

## Lien avec la console EPM
Optionnel, phase 3 : un panneau d'orchestration dans le dashboard PC (associer poste↔image,
déclencher, suivre) qui parlerait à l'API du serveur PXE. Le cœur PXE reste ici, autonome.

## État
**Cadrage** (cf. `docs/epopee_pxe.md`). Décisions à trancher avant P1 : BIOS/UEFI, Secure Boot,
source du WIM, jonction de domaine, outil (WinPE maison vs WDS). Phases : P1 amorçage → P2 payload
→ P3 orchestration.
