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

## Les TROIS identifiants (à ne pas confondre)
| Identifiant | Fichier / phase | Rôle |
|---|---|---|
| **Login** | `WDSClientUnattend` (WinPE) | Compte pour que **WinPE se connecte à WDS** et télécharge l'image. Compte de domaine à **faible privilège** (accès lecture WDS) — ni admin, ni le compte de jonction. |
| **UnattendedJoin** | `ImageUnattend` (specialize) | Le **compte de jonction** au domaine `ecollege19.lan` (droit de joindre + créer l'objet). |
| **AdministratorPassword** | `ImageUnattend` (oobeSystem) | Mot de passe de l'**Administrateur local intégré** (le compte est **activé** par la commande `Enable-LocalUser` en specialize, robuste à la langue via le SID `-500`). |

## Configuration AD des comptes de service
- **`svc.wds`** (Login WDS) : simple **utilisateur du domaine** (WDS laisse les clients authentifiés
  lire les images). Mot de passe **sans expiration**, non modifiable ; interdire l'ouverture de
  session interactive/RDP (GPO) — durcissement. Optionnel : ACL Lecture sur le groupe d'images WDS.
- **`domain.join`** (UnattendedJoin) : **PAS admin du domaine**. Lui **déléguer** sur l'**OU cible**
  (Déléguer le contrôle > tâche personnalisée > Objets Ordinateur) : **Créer** (et Supprimer) les
  objets ordinateur + **Réinitialiser le mot de passe** + **écrire toutes les propriétés**. Portée =
  cette OU seulement. La délégation **contourne le quota des 10 machines** (`ms-DS-MachineAccountQuota`).
  Renseigner `MachineObjectOU` (dans `ImageUnattend.xml`) = cette OU. Réimage d'un poste connu : les
  droits ci-dessus reprennent l'objet existant (sinon supprimer l'ancien objet).

## ⚠️ Secrets — jamais les vraies valeurs dans le dépôt
Les 3 secrets sont laissés en `&lt;REMPLIR_HORS_DEPOT&gt;` → à renseigner dans les **copies locales**
(sur le serveur, hors git). Le compte de jonction + le mot de passe admin sont en **clair** dans
l'unattend → protéger le fichier (ACL) et compte de jonction à **moindre privilège**.
→ Renseigner dans une **copie locale gitignorée** (`*.local.xml`) déployée à la main, ou via un
outil de secrets. Le mot de passe de jonction est en **clair** dans l'unattend → fichier à protéger
(ACL sur RemoteInstall / partage) et compte de jonction **à moindre privilège** (droit de joindre + OU).

## Pilotes
Gérés **nativement par WDS** (packages de pilotes / groupes par modèle, ajoutés au serveur WDS) →
injectés à l'installation. Pas besoin de MDT pour les drivers.
