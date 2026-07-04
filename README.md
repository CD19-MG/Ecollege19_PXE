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

## Amorçage — voie retenue : **WDS seul (sans MDT)**, Secure Boot activé
Les postes sont **UEFI récents avec Secure Boot ON** (les legacy sont remplacés). Secure Boot
n'exécute qu'un bootloader **signé Microsoft** → on utilise **WDS** (binaires signés MS). **MDT étant
en fin de vie**, on ne l'utilise pas : WDS déploie **tout seul** via une **Install Image** + des
**fichiers de réponse** (`unattend/`) + ses **packages de pilotes** (jonction `ecollege19.lan`,
locale, partition). **Sans désactiver Secure Boot.**
*(iPXE/HTTP Boot — cf. `tftp/` — écarté car non signé MS ; conservé comme alternative si Secure Boot OFF.)*

## Structure
```
docs/      cadrage (epopee_pxe.md) + notes
dhcp/      options 66/67 à poser sur srv-wvdnscollf (pointent vers WDS)
wds/       VOIE RETENUE : mise en place WDS seul (Secure Boot natif, sans MDT)
unattend/  fichiers de réponse WDS (WinPE + OS) : partition UEFI, locale, jonction domaine
drivers/   packages de pilotes WDS + groupes filtrés par modèle (parc hétérogène)
tftp/      ALTERNATIVE (Secure Boot OFF) : bootloader iPXE + menu.ipxe — non utilisé
images/    WIM de référence — NON versionné (gros fichiers, cf. .gitignore)
```

> **Deux éditions** sur le parc (Win11 **Pro** + **Pro Éducation**) → on importe **les deux** dans WDS
> et on **laisse le technicien choisir l'édition au boot** (pas de `ImageName` figé dans l'unattend).
> **Parc multi-modèles** (HP variés + Lenovo à venir) → **pilotes par groupes filtrés** (cf. `drivers/`).

## Lien avec la console EPM
Optionnel, phase 3 : un panneau d'orchestration dans le dashboard PC (associer poste↔image,
déclencher, suivre) qui parlerait à l'API du serveur PXE. Le cœur PXE reste ici, autonome.

## État
Décisions **actées** : UEFI + Secure Boot ON, **WDS seul** (MDT écarté), image thin, jonction
`ecollege19.lan`, **2 éditions** (Pro + Pro Éducation, choix au boot), **pilotes par groupes filtrés**.
En cours : import des images dans WDS. Reste : pilotes par modèle + poste de test.
Phases : P1 amorçage → P2 déploiement → P3 orchestration (optionnelle).
