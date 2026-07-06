# WDS (sans MDT) — déploiement Windows automatisé, Secure Boot activé

**Pourquoi WDS seul** : Secure Boot doit rester **activé** → seul un bootloader **signé Microsoft**
s'exécute. WDS fournit `wdsmgfw.efi` + WinPE **signés MS** → amorçage UEFI **Secure Boot natif**.
**MDT étant en fin de vie**, on n'en dépend pas : WDS sait déployer **tout seul** via une **Install
Image** + des **fichiers de réponse** (`../unattend/`) + ses **packages de pilotes**.

## Prérequis
- `stats` = **Windows Server** avec le rôle **WDS** (fait ✅). Dossier **RemoteInstall** (ex. `D:\RemoteInstall`,
  **distinct** d'un éventuel partage) créé à la config du rôle.
- **ADK + WinPE add-on** (pour l'image de boot). *(Plus besoin de MDT.)*
- Postes atelier : **UEFI, Secure Boot ON**, sur `10.119.50.x`.

## Mise en place
1. **Image de démarrage (boot)** : importer dans WDS le `boot.wim` de l'ISO Windows 11 (`sources\boot.wim`,
   x64 UEFI, signé MS) → *Images de démarrage*.
2. **Images d'installation** : importer **les DEUX éditions** du parc (Win11 **Pro** + **Pro Éducation**)
   dans un **groupe d'images** (ex. `Win11`). Comme il y a 2 éditions, `WDSClientUnattend.xml` **ne fige
   pas** `ImageName` → **le technicien choisit l'édition au boot** (WDS affiche la liste).
3. **Pilotes** (parc multi-modèles) : **packages de pilotes** + **groupes filtrés par modèle**
   (Fabricant/Modèle) → WDS injecte le bon groupe selon la machine. Voir **`../drivers/README.md`**
   (liste des modèles HP + Lenovo à venir).
4. **Fichiers de réponse** (`../unattend/`) :
   - `WDSClientUnattend.xml` → WDS > Propriétés serveur > **Client** > *Activer l'installation sans
     assistance* > architecture **x64** > pointer ce fichier.
   - `ImageUnattend.xml` → Propriétés de l'**Install Image** > *mode sans assistance* > pointer ce fichier
     (locale, **jonction ecollege19.lan**, admin local).
   - Renseigner les **secrets en local** (hors dépôt) — cf. `../unattend/README.md`.
5. **WDS > Propriétés > Démarrage** : *Répondre à tous les clients* (ou connus), architecture par défaut x64 UEFI.
6. **DHCP `srv-wvdnscollf`** : options **066** = IP stats, **067** = `boot\x64\wdsmgfw.efi` (cf. `../dhcp/`).

## Chaîne d'amorçage
Poste UEFI (Secure Boot ON) → PXE → `wdsmgfw.efi` (signé) → **WinPE** (signé) → applique l'**install.wim**
+ **pilotes** + **unattend** (partition GPT, locale, **jonction ecollege19.lan**, admin local) → reboot.
**Rien à désactiver.**

## Décisions actées
- Image = **thin** (`install.wim` de l'ISO + pilotes/jonction via WDS/unattend). *(Capture d'un master
  sysprepé possible plus tard si on veut tout figer.)*
- **Deux éditions** importées (Pro + Pro Éducation) → **choix au boot** (pas de `ImageName` figé).
- **Pilotes par groupes filtrés** par modèle (cf. `../drivers/`), extensible (Lenovo à venir).
- **Jonction `ecollege19.lan`** (dans `ImageUnattend.xml`).

## Optionnel : image de référence capturée (« thick », éviter de réinstaller les logiciels)
En plus de l'image thin, on peut déployer un **master** avec les logiciels déjà installés :
1. **Poste de référence** : OS + apps communes + réglages, **en groupe de travail** (NE PAS joindre le domaine).
2. **Sysprep** : `C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown`
   (option `CopyProfile=true` dans un unattend sysprep si le profil par défaut est personnalisé).
3. **Image de capture WDS** : *Images de démarrage → clic droit sur le boot.wim → Créer une image de capture* → l'importer.
4. **Capturer** : PXE-boot le poste sysprepé → choisir l'**Image de capture** → l'assistant capture `C:`
   dans un WIM → upload comme **nouvelle image d'installation**.
5. **Déployer** ce WIM + rattacher `../unattend/ImageUnattend.xml` (jonction/locale/admin) comme d'habitude.

**Reco = hybride** : master = OS + apps **stables** ; apps **volatiles** = via l'agent EPM (winget/packages)
après déploiement → rapide ET maintenable. Les **pilotes** restent injectés par modèle par WDS (le master
n'a pas besoin des drivers de tous les modèles ; `/generalize` les retire).

## Ce que garde le dépôt
Les `unattend/*.xml` (templates, **sans secret**), les manifests de pilotes/notes. WIM et secrets = **hors dépôt**.
