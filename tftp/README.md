# TFTP — bootloader + menu PXE

> **MAJ (iPXE 2.0.0) : iPXE gère désormais Secure Boot** via des **shims signés Microsoft**
> (`ipxe-shim.efi` / `snponly-shim.efi`, cf. https://ipxe.org/secboot) → **out-of-the-box, sans
> enrôlement MOK, scalable**. iPXE n'est donc PLUS réservé au « Secure Boot OFF » : il devient une
> **alternative viable pour REMPLACER WDS** (transport plus léger, + UEFI HTTP Boot possible), une
> fois le pipeline WDS actuel validé. Contrainte : binaires précompilés signés (custom via
> `autoexec.ipxe`, pas de build maison). Chaîne iPXE → WinPE (wimboot/bootmgr) à tester sous Secure Boot.


Le serveur TFTP (à MARBOT) sert le bootloader amorcé par les postes (via l'option 067 du DHCP) puis
un **menu**. Les gros fichiers (WinPE, WIM) se servent de préférence en **HTTP** (plus rapide que TFTP).

## Menu (3 entrées) — voir `menu.ipxe`
1. **Amorcer le disque local** — entrée par **DÉFAUT**, timeout court (sécurité anti-réimage accidentel).
2. **Déployer Windows** — chaîne vers WinPE (wimboot) qui lance le script de déploiement (`../winpe`).
3. **HBCD** — Hiren's BootCD PE (secours), chaîné via `wimboot` (iPXE) ou `memdisk` (ISO).

## Pistes techniques
- **iPXE** (recommandé) : HTTP natif + scripts (`menu.ipxe`), `wimboot` pour booter un WinPE/HBCD sur le réseau.
- Alternative : **PXELinux** (BIOS) + `wimboot`.
- Réf. couche transport en Node : `node-js-pxe-server` (DHCP/TFTP/PXELinux + API) — mais ici le DHCP
  est déjà géré par `srv-wvdnscollf`, on ne garde donc que **TFTP + menu** (ex. `dnsmasq` en TFTP-only,
  ou tftpd-hpa, ou un service Node TFTP).

*(À produire : `menu.ipxe`, les binaires iPXE `ipxe.efi`/`undionly.kpxe`, et le `wimboot`.)*
