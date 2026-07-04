# MDT — config de la séquence de déploiement

Templates de config MDT (LiteTouch). À copier dans `<DeploymentShare>\Control\`.

| Fichier | Rôle | Va dans |
|---|---|---|
| `CustomSettings.ini` | Automatisation de la séquence (jonction domaine, locale, pages sautées) | `Control\CustomSettings.ini` |
| `Bootstrap.ini` | Connexion WinPE au partage de déploiement (creds d'accès) | `Control\Bootstrap.ini` |

## ⚠️ Secrets — jamais dans le dépôt
`DomainAdminPassword` et `UserPassword` sont **vides** dans les templates :
- soit **laissés vides** → MDT/WinPE les **demande à l'exécution** (le plus sûr) ;
- soit renseignés dans une **copie locale gitignorée** (`*.local.ini`) déployée à la main dans
  `Control\`. Ne jamais committer les valeurs réelles.

Comptes à prévoir (dédiés, moindre privilège) :
- **compte de jonction** au domaine `ecollege19.lan` (droit de joindre + créer l'objet dans l'OU cible) ;
- **compte d'accès** en lecture au partage `DeploymentShare$`.

## Rappel
Après toute modif de **`Bootstrap.ini`** → *Update Deployment Share* (régénère le WinPE) puis
**réimporter l'image de boot dans WDS**. `CustomSettings.ini` est relu à chaque déploiement (pas de
régénération nécessaire).
