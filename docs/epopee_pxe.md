# Épopée — Déploiement PXE (imaging des postes à MARBOT)

> Statut : **cadrage**. Périmètre volontairement restreint (poste de préparation), pas de rollout collège.

## Objectif
Réimager / provisionner **à blanc et EN MASSE** les postes que la DSIUN prépare **avant envoi en
collège**, par démarrage réseau (PXE) — remplacer l'installation manuelle par un déploiement
automatisé (image de référence + unattend + drivers), façon MDT mais adapté à notre stack.

## Menu PXE (plusieurs entrées)
Le PXE ne sert pas qu'au déploiement : le bootloader présente un **menu** avec au moins :
1. **Amorcer le disque local** — **entrée par DÉFAUT** (timeout court). ⚠️ Sécurité clé : un poste
   qui boote PXE par erreur (ou laissé en network-boot) **ne doit pas se faire réimager tout seul** ;
   le déploiement est un **choix explicite** (ou ciblé par MAC).
2. **Déployer Windows** (WinPE → apply WIM + unattend + drivers) — le cœur du besoin.
3. **HBCD — secours & outils** (Hiren's BootCD PE) : environnement de dépannage/diagnostic,
   chaîné en PXE via `wimboot` (iPXE) ou `memdisk` (ISO). Utile en atelier pour récup/réparation.

## Périmètre (V1)
- **Un seul site : MARBOT** (poste/atelier de préparation). Pas de PXE dans les collèges tant que
  l'avenir des serveurs de site n'est pas tranché.
- **Un seul subnet : `10.119.50.x`.**
- **DHCP : `srv-wvdnscollf`** (DHCP de ce réseau) → on y configure les **options d'amorçage**
  (66 = serveur TFTP, 67 = bootfile), **pas de second DHCP** côté PXE → aucun conflit, pas besoin
  de proxyDHCP.
- Cas d'usage = **provisioning / réimage complet** (bare-metal), pas mise à niveau (la bascule
  Win11 in-place existe déjà dans l'agent).

## Architecture cible
```
Poste (PXE boot, 10.119.50.x)
   │  1. DHCP DISCOVER
   ▼
srv-wvdnscollf (DHCP)  ── options 66 (next-server = PXE) + 67 (bootfile BIOS/UEFI) ──┐
   │  2. IP + où booter                                                              │
   ▼                                                                                 │
Serveur PXE @ MARBOT (IP fixe)                                                        │
   ├─ TFTP : sert le bootloader (iPXE / PXELinux) ◄──────────────────────────────────┘
   ├─ HTTP : sert le WIM + scripts (rapide, > TFTP)
   └─ (option) REST/orchestration reliée au dashboard
   │  3. chaîne vers WinPE
   ▼
WinPE (construit via Windows ADK)
   └─ script : apply WIM + unattend.xml + drivers + (option) jonction de domaine
```

## Composants à produire
1. **Amorçage** : options DHCP sur `srv-wvdnscollf` + service **TFTP** + bootloader.
   - Couche « transport » faisable en Node (cf. `node-js-pxe-server` : DHCP/TFTP/PXELinux + REST) —
     mais ici le DHCP est déjà géré, donc on ne garde que **TFTP + menu** (ou `iPXE` + `dnsmasq`
     en mode TFTP-only, éprouvé).
2. **WinPE** (une fois) : image de boot Windows PE (ADK) + script de déploiement.
3. **Image de référence** : un **WIM** capturé depuis un poste master (sysprep) + **drivers** par modèle.
4. **Unattend.xml** : automatisation (langue, partitionnement, compte local, nom, jonction éventuelle).
5. **(Option, v2.x) Orchestration dashboard** : associer **MAC/poste ↔ image**, déclencher, suivre
   l'état via une petite API — le dashboard joue le chef d'orchestre, l'imaging s'exécute à MARBOT.

## Décisions à trancher (avant de coder)
- **BIOS, UEFI, ou les deux ?** (détermine le bootfile : `pxelinux.0`/`undionly.kpxe` en BIOS vs
  `ipxe.efi`/`bootx64.efi` en UEFI ; option 67 conditionnelle à l'architecture côté DHCP).
- **Secure Boot** activé sur ces postes pendant l'imaging ? (UEFI SB → bootloader signé, ou on
  désactive SB le temps du déploiement à l'atelier).
- **Source du WIM** : capture d'un master maison, ou install.wim d'un ISO + apps post-install ?
- **Jonction de domaine** au déploiement : oui/non, et **quel domaine** ? (les postes finissent en
  collège `ecollege19.lan`, mais l'atelier MARBOT est ailleurs — join à MARBOT puis re-join, ou
  laisser hors domaine et joindre à l'arrivée ?)
- **Outil d'imaging** : WinPE + script maison (léger, contrôle total) vs **WDS** (natif Windows,
  robuste) vs **FOG** (open source, orienté multi-sites — surdimensionné pour un site). Reco V1 :
  **iPXE/TFTP + WinPE + script**, minimal et dans notre esprit self-hosted.

## Phasage
- **P1 — Amorçage** : options DHCP + TFTP + un poste de test 10.119.50.x qui **boote en WinPE**. (preuve)
- **P2 — Payload** : WinPE applique le WIM + unattend + drivers → un poste réinstallé de bout en bout.
- **P3 — Orchestration** (option) : mapping poste↔image + suivi dans le dashboard (v2.x EPM).

## Prérequis côté DSIUN
- **IP fixe** pour le serveur PXE à MARBOT + accès admin.
- Accès admin **`srv-wvdnscollf`** pour poser les options 66/67 (et policy BIOS/UEFI si besoin).
- **Windows ADK** (pour WinPE) + un **poste master** à capturer + les **drivers** par modèle.
- **ISO/WIM de HBCD PE** (Hiren's BootCD PE) pour l'entrée de secours du menu.

## Hors périmètre V1
- PXE dans les collèges (subordonné à l'avenir des serveurs de site).
- Multi-subnet / multi-VLAN.
- Bascule OS in-place (déjà couverte par l'agent EPM : `win11-stage` / `win11-upgrade`).
