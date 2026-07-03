# DHCP — options d'amorçage PXE (sur `srv-wvdnscollf`)

Le DHCP du réseau `10.119.50.x` reste **`srv-wvdnscollf`** : on ne monte **pas** de second DHCP côté
PXE (pas de proxyDHCP). On ajoute seulement les **options d'amorçage** qui pointent vers le serveur TFTP.

## Options à poser (étendue `10.119.50.x`)
- **066** (Boot Server Host Name) = IP du **serveur PXE/TFTP** (à MARBOT).
- **067** (Bootfile Name) = nom du bootloader, **selon l'architecture** :
  - BIOS (legacy)  : `pxelinux.0` ou `undionly.kpxe` (iPXE)
  - UEFI x64       : `ipxe.efi` (ou `snponly.efi` / `bootx64.efi`)

> Sur un DHCP Windows, si le parc mélange BIOS et UEFI : utiliser des **stratégies DHCP** (DHCP policies)
> basées sur la classe fournisseur `PXEClient:Arch:00000` (BIOS) vs `00007`/`00009` (UEFI x64) pour
> servir le bon bootfile en 067. À défaut, homogénéiser le mode d'amorçage des postes de l'atelier.

## Décision à trancher
- **BIOS, UEFI, ou les deux ?** (détermine le(s) bootfile(s) et la nécessité de stratégies DHCP).
- **Secure Boot** activé pendant l'imaging ? (UEFI SB → bootloader signé, ou désactiver SB à l'atelier).

*(Exemples de commandes/captures à ajouter une fois la config posée sur `srv-wvdnscollf`.)*
