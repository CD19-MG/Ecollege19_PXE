# Pilotes — packages WDS + groupes filtrés par modèle (parc hétérogène)

Parc **multi-modèles** (HP variés + Lenovo à venir) → on utilise les **packages de pilotes WDS** avec
des **groupes filtrés** : WDS injecte automatiquement **le bon groupe selon la machine**. Ajouter un
modèle = ajouter son pack + un groupe filtré. Aucun MDT nécessaire.

## Principe
1. **Importer les packages de pilotes** dans WDS (console WDS > *Pilotes* > *Ajouter un package de pilotes*).
   Utiliser les **driver packs constructeur** (INF, pas les .exe) :
   - **HP** : *HP Client Driver Packs* (Softpaq « Driver Pack » par modèle) — HP Image Assistant / catalogue HP.
   - **Lenovo** : *Lenovo SCCM/Deployment Driver Packs* (par machine type 4 chiffres).
2. **Créer un groupe de pilotes par modèle** (console WDS > *Pilotes* > *groupe*), avec un **filtre**
   qui matche la machine à l'install. Filtres utiles :
   - **Fabricant** (`Manufacturer` / *System Manufacturer*) — ex. `HP`, `LENOVO`
   - **Modèle** (`Product Name` / *System Product Name*) — ex. `HP Pro Mini 400 G9 Desktop PC`
   - (Lenovo affiche souvent un code type + `Version` = nom commercial → filtrer sur `Version`/`Product`.)
3. WDS applique, pour chaque poste, **le groupe dont le filtre correspond** → seuls les pilotes du modèle
   sont injectés. Un pack « fourre-tout » sans filtre marche aussi mais alourdit/ralentit — préférer les filtres.

## Récupérer les packs HP — automatisé (`Get-HPDriverPacks.ps1`)
Le script `Get-HPDriverPacks.ps1` (ce dossier) télécharge + extrait les driver packs des modèles HP
du parc (un dossier INF par modèle), via **HP CMSL** :
```powershell
.\Get-HPDriverPacks.ps1 -OutRoot D:\DriverPacks -OsVer 23H2   # en admin, acces Internet
```
Repli manuel : `support.hp.com` → modèle → « Driver Pack » → extraire le SoftPaq dans un dossier.

## Import + groupe filtré dans WDS (pas à pas)
1. Console **WDS** → **Pilotes** → clic droit → **Ajouter un package de pilotes** → pointer le dossier
   INF du modèle (ex. `D:\DriverPacks\HP Pro Mini 400 G9...`).
2. Créer un **groupe de pilotes** (clic droit *Pilotes* → *Ajouter un groupe*) → nommer par modèle.
3. Sur le groupe → **Filtres** : ajouter *Fabricant* (`Manufacturer`) et/ou *Modèle* (`Product Name`)
   = valeurs exactes du poste (`Get-CimInstance Win32_ComputerSystem | ft Manufacturer,Model`).
4. **Assigner** le package importé au groupe. WDS injectera ce groupe uniquement sur les postes
   correspondant au filtre.

## Libellés remontés par l'agent (Win32_ComputerSystem.Model)
> ⚠️ Ces libellés **ne font PAS autant de packs** : plusieurs = **même plateforme HP (SysID)** vue
> sous des noms différents (formats, BIOS, casse). On **regroupe par SysID** → moins de packs/groupes.
> Le **filtre d'un groupe WDS accepte plusieurs libellés** (OR). `Get-HPDriverPacks.ps1` résout les
> SysID, dédoublonne, et affiche le mapping libellé→plateforme à utiliser dans les filtres.

- HP EliteDesk 800 **G4** DM 35W
- HP EliteDesk 800 **G5** · « G5 » / « Desktop Mini » / « DM » → probablement **1 seul pack**
- HP Pro Mini **400 G9** Desktop PC
- HP ProDesk 400 **G4** SFF
- HP ProDesk 400 **G6** · « Desktop Mini » / « SFF » → 1 (ou 2 selon le format)
- **Lenovo** <à venir> → pack Lenovo + groupe filtré `Manufacturer=LENOVO` (⚠️ nom commercial dans
  `Win32_ComputerSystemProduct.Version`, pas dans `Model` qui = le code type).

## Alternative simple (moins de groupes)
Si gérer un groupe par plateforme est fastidieux : **un seul groupe « HP »** filtré `Manufacturer=HP`
avec **tous les packs** → Windows Setup n'installe que les pilotes **correspondant au PnP** de la machine.
Plus simple et robuste aux variations de nom ; en contrepartie, le magasin de pilotes est plus gros
(scan un peu plus long). Idéal pour démarrer, on affinera par plateforme si besoin.

## Astuce
Pour connaître les chaînes exactes de filtre d'un poste : `wmic computersystem get Manufacturer,Model`
(ou `Get-CimInstance Win32_ComputerSystem`) → utiliser **Model** tel quel dans le filtre du groupe.
La fiche poste du dashboard EPM (Identité & matériel) affiche aussi Fabricant/Modèle.

*(Les fichiers de pilotes ne sont pas versionnés — cf. `.gitignore` du projet. Ce README = la méthode
+ la liste des modèles.)*
