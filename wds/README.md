# WDS + MDT — déploiement Windows avec Secure Boot (voie retenue)

**Pourquoi WDS** : Secure Boot doit rester **activé** sur les postes → seul un bootloader **signé
Microsoft** est exécuté. WDS fournit `wdsmgfw.efi` + WinPE **signés MS** → amorçage réseau UEFI
**Secure Boot natif**, sans rien désactiver. iPXE (non signé MS) est écarté pour cette raison
(cf. `../tftp/` conservé seulement comme alternative si un jour Secure Boot OFF).

**WDS + MDT** = le « MDT en PXE » : MDT (Microsoft Deployment Toolkit) fournit la séquence de tâches
(partitionnement, apply WIM, drivers, apps, **jonction de domaine**, unattend), WDS l'amorce par PXE.

## Prérequis
- `stats` doit être **Windows Server** (rôle WDS). *(À confirmer : édition de l'OS.)*
- **ADK + WinPE add-on** (pour l'image de boot) et **MDT** installés (sur stats ou un poste d'admin).
- Postes atelier : **UEFI**, **Secure Boot ON**, sur `10.119.50.x` (même subnet que le DHCP et stats).

## Mise en place (grandes étapes)
1. **Rôle WDS** sur stats → configurer (mode « standalone » si pas AD-intégré, ou intégré).
2. **MDT** : créer un *Deployment Share* (partage SMB), y importer :
   - le **système** (WIM de référence — cf. décision : capture master vs `install.wim`) ;
   - les **drivers** par modèle (HP Pro Mini 400 G9, etc.) ;
   - les **applications** à installer ;
   - `CustomSettings.ini` / `Bootstrap.ini` (automatisation, jonction de domaine, nommage).
3. MDT génère les **images de boot LiteTouch (WinPE)** → **importées dans WDS**.
4. **WDS** publie l'image de boot UEFI signée → les postes PXE-bootent dessus (Secure Boot OK).

## Boot & Secure Boot
- WDS sert le NBP **signé MS** (`boot\x64\wdsmgfw.efi`) via **TFTP** → WinPE (signé) → LiteTouch (MDT).
- **Aucune désactivation de Secure Boot** requise.

## Décisions à trancher (avant la séquence MDT)
- **Source du WIM** : capture d'un **master sysprepé**, ou `install.wim` d'un ISO + apps via MDT ?
- **Jonction de domaine** au déploiement : oui/non + **quel domaine** (`ecollege19.lan` ?) → renseigné
  dans `CustomSettings.ini` (avec un compte de jonction dédié, hors dépôt).

## Ce que garde le dépôt
Config MDT versionnable (`CustomSettings.ini`, `Bootstrap.ini` **sans secret**), scripts de
personnalisation, notes de build, drivers-manifest. Le WIM et les secrets restent **hors dépôt**.
