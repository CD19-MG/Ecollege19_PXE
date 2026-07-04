# Fichiers de réponse (unattend) — déploiement WDS sans MDT

MDT étant en fin de vie, on automatise le déploiement **avec WDS seul** via deux fichiers de réponse.

| Fichier | Phase | Rôle | Où le rattacher |
|---|---|---|---|
| `WDSClientUnattend.xml` | WinPE | Langue, **partitionnement UEFI/GPT**, sélection de l'image, disque cible | WDS > Propriétés serveur > **Client** > install sans assistance (x64) |
| `ImageUnattend.xml` | OS (specialize + oobeSystem) | Locale fr-FR, **jonction `ecollege19.lan`**, admin local, OOBE silencieux | Propriétés de l'**Install Image** > mode sans assistance |

## À adapter avant usage
- `WDSClientUnattend.xml` : `ImageName` / `ImageGroup` = ceux de l'image importée dans WDS ;
  `InstallTo` disque 0 / partition 3 (Windows) selon le schéma de partitions.
- `ImageUnattend.xml` : `MachineObjectOU` (si OU cible), `ComputerName` (`*` = nommage auto).

## ⚠️ Secrets — jamais les vraies valeurs dans le dépôt
Trois secrets, laissés en `&lt;REMPLIR_HORS_DEPOT&gt;` :
- **accès WDS** (`WDSClientUnattend` > Login) ;
- **compte de jonction** `ecollege19.lan` (`ImageUnattend` > UnattendedJoin) ;
- **mot de passe admin local** (`ImageUnattend` > LocalAccount).
→ Renseigner dans une **copie locale gitignorée** (`*.local.xml`) déployée à la main, ou via un
outil de secrets. Le mot de passe de jonction est en **clair** dans l'unattend → fichier à protéger
(ACL sur RemoteInstall / partage) et compte de jonction **à moindre privilège** (droit de joindre + OU).

## Pilotes
Gérés **nativement par WDS** (packages de pilotes / groupes par modèle, ajoutés au serveur WDS) →
injectés à l'installation. Pas besoin de MDT pour les drivers.
