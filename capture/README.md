# Capture d'une image de référence (image « épaisse » par modèle)

Objectif : préparer **un** poste modèle (Windows + logiciels installés + réglages), le **capturer**
une fois, puis **redéployer cette image complète** sur les postes identiques — sans réinstaller les
logiciels à chaque fois.

Pensé pour être **simple** : tout se fait depuis le poste et l'interface PXE, **aucune manipulation
sur le serveur** pour l'utilisateur.

## Procédure (pour les collègues) — 3 étapes

1. **Sur le poste modèle** : installer Windows + les logiciels + les réglages voulus, puis
   double-cliquer sur **`Préparer-la-capture.cmd`** (clic droit → *Exécuter en tant qu'administrateur*).
   → Le poste se généralise et **s'éteint tout seul**.

2. **Rallumer** le poste et **démarrer sur le réseau** (touche **F12** / F9 selon le modèle).

3. Dans le menu PXE, choisir **`[2] Capturer une image de référence`**.
   → Un **nom est proposé automatiquement (le modèle du poste)**, valider (Entrée) ou renommer.
   → La capture part sur le serveur. Le poste redémarre.

C'est fini : l'image apparaît **directement** dans la liste **`[1] Installer`** au prochain démarrage
PXE, prête à être déployée sur les postes du même modèle.

## Bon à savoir

- **Toujours** passer par `Préparer-la-capture.cmd` (sysprep) avant de capturer : sans ça, l'image
  garde le nom/SID/pilotes du poste modèle → conflits si on la déploie ailleurs. Le script de capture
  prévient s'il ne détecte pas de sysprep réussi.
- **Nom par modèle** : le défaut proposé est le modèle détecté (ex. `HP_EliteDesk_800_G5_DM`).
  Garde ce nom pour t'y retrouver : une image = un modèle.
- Le poste modèle **ne doit pas être joint au domaine** au moment de la capture. Le plus propre :
  déployer le master via l'option **« Préparer un MASTER (NE PAS joindre le domaine) »** au déploiement
  (deploy.ps1 retire la jonction de l'unattend) → image de référence propre ; la jonction se fait
  ensuite au déploiement des postes.
- Si `sysprep` échoue et que le poste ne s'éteint pas : cause la plus fréquente = une **application du
  Microsoft Store** (ex. winget mis à jour par-utilisateur). Voir `%WINDIR%\System32\Sysprep\Panther\setuperr.log` ;
  retirer le paquet fautif (`Get-AppxPackage <nom> | Remove-AppxPackage`). Préférer les **installeurs MSI/EXE
  machine-wide** sur un master.

## Maintenir un MASTER (le mettre à jour et re-capturer)

Les PC masters restent **au bureau** (ne pas les déployer en collège). Pour les tenir à jour :
1. **Rallumer** le master (il repasse par l'OOBE puisqu'il a été généralisé → ouvrir en admin local ;
   comme il est hors domaine, pas de jonction).
2. **Mettre à jour** (Windows Update, logiciels).
3. Relancer **`C:\Ec19\Preparer-la-capture.cmd`** → sysprep → extinction, puis PXE → **Capturer**
   (même nom → écrase l'image → elle repasse « à jour »/verte dans la console).

`Preparer-la-capture.cmd` lance sysprep avec **`generalize.xml` (SkipRearm=1)** s'il est à côté → le
**compteur de rearm** d'activation (limite ~3) n'est **pas consommé** → tu peux re-syspreper le master
autant de fois que nécessaire. `generalize.xml` est déposé automatiquement à côté du `.cmd` (dans `C:\Ec19`).

## Où trouver `Préparer-la-capture.cmd` sur un poste

- **Postes déployés par PXE (install nue)** : l'outil est déposé automatiquement dans
  **`C:\Ec19\Preparer-la-capture.cmd`**, un dossier **réservé aux administrateurs** (les élèves
  n'y ont aucun accès). Il est ensuite **embarqué dans les captures** → tout modèle capturé le
  transporte tout seul.
- **Anciens postes (non redéployés)** : copier le fichier `capture/Preparer-la-capture.cmd`
  manuellement (clé USB / partage), dans un emplacement accessible à l'admin uniquement.

> Pour que le dépôt automatique fonctionne, placer **`Preparer-la-capture.cmd` ET `generalize.xml`
> à la racine du partage** (`\\stats\Deploy$\`) — `deploy.ps1` les copie dans `C:\Ec19`.
> Note : `sysprep` exige de toute façon l'élévation administrateur ; un élève ne peut pas le lancer.

## Côté serveur (une seule fois, par l'admin)

- La capture écrit dans `\\stats\Deploy$\images\`. Le compte **`svc.wds`** (utilisé par le WinPE) doit
  donc y avoir le droit **Modifier** (et pas seulement Lecture) — sinon l'écriture du WIM échoue.
- Les scripts `menu.ps1`, `deploy.ps1`, `capture.ps1` vivent à la **racine du partage** (éditables
  sans reconstruire le WinPE). `Préparer-la-capture.cmd` se dépose sur le bureau du poste modèle.
- Journaux de capture : `\\stats\Deploy$\logs\capture-<horodatage>.log`.

## Astuce (optionnel) — propager les personnalisations du profil

Pour que le bureau / réglages du compte utilisé sur le modèle s'appliquent à tous les nouveaux profils,
lancer sysprep avec un unattend contenant `<CopyProfile>true</CopyProfile>` (passe *specialize*).
Non activé par défaut (peut créer des effets de bord) — à voir avec l'admin si besoin.
