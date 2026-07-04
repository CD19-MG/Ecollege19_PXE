# DHCP — options d'amorçage PXE (sur `srv-wvdnscollf`)

Le DHCP du réseau `10.119.50.x` reste **`srv-wvdnscollf`** (pas de second DHCP côté PXE). On y ajoute
les **options d'amorçage** pointant vers **WDS** (sur `stats`, même subnet `10.119.50.x`).

> Voie retenue = **WDS** (Secure Boot activé → bootloader signé Microsoft). Cf. `../wds/README.md`.

## Options (étendue `10.119.50.x`) — UEFI x64 + Secure Boot
- **066** (Boot Server Host Name) = IP de **`stats`** (le serveur WDS).
- **067** (Bootfile Name) = **`boot\x64\wdsmgfw.efi`** (bootloader UEFI **signé MS** de WDS).

WDS sert ce fichier en **TFTP** ; comme tout est sur le même subnet, aucun routage/relais à prévoir.
Parc **UEFI uniquement** (les legacy sont remplacés) → **pas besoin de stratégie BIOS/UEFI mixte**.

> Si WDS et le DHCP étaient sur la **même** machine, WDS gère les options tout seul. Ici le DHCP est
> sur `srv-wvdnscollf` (séparé) → on pose les options 66/67 **manuellement** sur l'étendue, comme ci-dessus.
> Vérifier qu'aucune stratégie « HTTPClient » ne parasite (on est en PXE/TFTP classique, pas HTTP Boot).

## Pare-feu
Même subnet → autoriser (hôte `stats`) le **TFTP (UDP/69)** entrant depuis `10.119.50.x`, plus les ports
WDS (UDP 67/4011). Le partage MDT (SMB 445) doit être joignable pour l'application du WIM.

*(Alternative HTTP Boot / iPXE — cf. `../tftp/` — écartée car incompatible Secure Boot sans shim signé.)*
