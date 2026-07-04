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

## Modèles actuels (à créer un groupe filtré chacun)
- HP **Pro Mini 400 G9** Desktop PC
- HP **ProDesk 400 G6** Desktop Mini
- HP **EliteDesk 800 G5** Desktop Mini
- HP **ProDesk 400 G6** SFF
- HP **EliteDesk 800 G4** DM 35W
- **Lenovo** <modèle à venir> → ajouter le pack Lenovo + un groupe filtré `Manufacturer=LENOVO` (+ modèle)

## Astuce
Pour connaître les chaînes exactes de filtre d'un poste : `wmic computersystem get Manufacturer,Model`
(ou `Get-CimInstance Win32_ComputerSystem`) → utiliser **Model** tel quel dans le filtre du groupe.
La fiche poste du dashboard EPM (Identité & matériel) affiche aussi Fabricant/Modèle.

*(Les fichiers de pilotes ne sont pas versionnés — cf. `.gitignore` du projet. Ce README = la méthode
+ la liste des modèles.)*
