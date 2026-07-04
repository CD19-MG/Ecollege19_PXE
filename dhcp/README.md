# DHCP — options d'amorçage PXE (sur `srv-wvdnscollf`)

Le DHCP du réseau `10.119.50.x` reste **`srv-wvdnscollf`** (pas de second DHCP côté PXE). On y ajoute
les **options d'amorçage** pointant vers **WDS** (sur `stats`, même subnet `10.119.50.x`).

> Voie retenue = **WDS** (Secure Boot activé → bootloader signé Microsoft). Cf. `../wds/README.md`.

## Options (étendue `10.119.50.x`) — UEFI x64 + Secure Boot
- **066** (Boot Server Host Name) = **IP de `stats`** (le serveur WDS), ex. `10.119.50.X`.
- **067** (Bootfile Name) = **`boot\x64\wdsmgfw.efi`** (boot manager UEFI **signé MS** de WDS).
  - backslashes `\`, **pas** de `/`, **pas** de `\` initial.

WDS sert ce fichier en **TFTP** ; tout étant sur le même subnet, aucun routage/relais à prévoir.
Parc **UEFI uniquement** → **une seule** valeur 067, pas de stratégie BIOS/UEFI mixte.

### ⚠️ NE PAS poser l'option 060 (`PXEClient`)
Elle ne sert que si DHCP **et** WDS sont sur la **même** machine. Ici ils sont **séparés**
(`srv-wvdnscollf` ≠ `stats`) → on utilise **066 (next-server)**. Poser 060 casserait le boot.

### Console `dhcpmgmt.msc`
IPv4 → étendue `10.119.50.x` → clic droit **Options d'étendue** → *Configurer les options* :
- **066** → chaîne = `10.119.50.X` (IP de stats)
- **067** → chaîne = `boot\x64\wdsmgfw.efi`

### PowerShell (sur `srv-wvdnscollf`, adapter IP + ScopeId)
```powershell
Set-DhcpServerv4OptionValue -ScopeId 10.119.50.0 -OptionId 66 -Value "10.119.50.X"
Set-DhcpServerv4OptionValue -ScopeId 10.119.50.0 -OptionId 67 -Value "boot\x64\wdsmgfw.efi"
Get-DhcpServerv4OptionValue -ScopeId 10.119.50.0 | Where-Object OptionId -in 66,67   # verif
```

> Vérifier qu'aucune stratégie/option « HTTPClient » ne parasite (on est en PXE/TFTP WDS, pas HTTP Boot).

## Pare-feu
Même subnet → autoriser (hôte `stats`) le **TFTP (UDP/69)** entrant depuis `10.119.50.x`, plus les ports
WDS (UDP 67/4011). Le partage MDT (SMB 445) doit être joignable pour l'application du WIM.

*(Alternative HTTP Boot / iPXE — cf. `../tftp/` — écartée car incompatible Secure Boot sans shim signé.)*
