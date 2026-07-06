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
- Le poste modèle **ne doit pas être joint au domaine** au moment de la capture (la jonction se fait
  automatiquement au déploiement via l'unattend). Construire le modèle hors domaine.
- Si `sysprep` échoue et que le poste ne s'éteint pas : cause la plus fréquente = une **application du
  Microsoft Store**. Voir `%WINDIR%\System32\Sysprep\Panther\setuperr.log`.

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
