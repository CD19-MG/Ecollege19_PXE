# Mail — Présentation du déploiement PXE (pour la hiérarchie)

**Objet : Nouveau système de déploiement des postes (PXE) — opérationnel en production**

Bonjour Antoine,

Je te fais un point sur le chantier de **déploiement automatisé des postes**, désormais **fonctionnel et validé de bout en bout**.

## Le contexte
Jusqu'ici, la préparation des postes se faisait par **clonage (ghost) avec Veeam et des clés USB, poste par poste** : une opération **manuelle, lente et peu traçable**, surtout pour du reconditionnement ou du provisioning en nombre. J'ai bâti une solution de **déploiement par le réseau (PXE)**, **intégrée à notre outil de supervision existant** (pas de logiciel ni de coût supplémentaire), et pensée pour être **utilisable par des collègues non techniques**. *(À noter : la solution Microsoft « standard » — WDS — étant en fin de vie sous Windows Server 2025, j'ai fait le choix d'une brique maison, légère et pérenne.)*

## Ce que ça change au quotidien (atelier MARBOT)
- **Installer Windows sur un poste depuis le réseau**, en quelques clics, via un **menu graphique** (Installer / Capturer / Redémarrer / Éteindre) — **fini la clé USB à brancher sur chaque poste**.
- **Détection automatique du modèle** → les **bons pilotes** sont injectés et la **bonne image** proposée, toutes marques confondues (HP, Lenovo… et compatible avec d'autres fabricants si l'on change de fournisseur).
- **Intégration au domaine dans le bon collège en 1 choix** : on sélectionne l'établissement, le poste rejoint directement la bonne unité d'organisation Active Directory (fini le script manuel post-installation).
- **Images « prêtes à l'emploi » par modèle** : on prépare un poste de référence (Windows + logiciels + réglages), on le « capture », et on le redéploie tel quel → **plus besoin de réinstaller les logiciels à chaque poste**. Ces images se **mettent à jour** facilement (mise à jour → re-capture).

## Le pilotage, depuis notre tableau de bord
Une console dédiée « Déploiement PXE » permet, **sans intervention sur le serveur** :
- de suivre les **déploiements en direct** ;
- de gérer les **images** (avec un indicateur couleur signalant celles à réactualiser) ;
- de déclarer les **modèles de postes** et la **correspondance collège ↔ OU**.

## Bénéfices
- **Gain de temps majeur** : plus de clé USB ni de clonage manuel poste par poste ; plusieurs machines en parallèle.
- **Standardisation** des postes livrés (mêmes logiciels, même configuration ; la différenciation péda/admin reste gérée par les GPO).
- **Autonomie** des collègues moins techniques, avec garde-fous (confirmations, messages clairs, robustesse réseau).
- **Traçabilité** : chaque déploiement est suivi dans le tableau de bord.
- **Pérennité** : solution maison, documentée, indépendante d'un outil obsolète.

## Statut
Le pipeline complet a été **testé en conditions réelles** (déploiement d'un poste, jonction au domaine, capture d'une image de référence). L'ensemble est en production et documenté dans un dépôt dédié.

Je reste dispo pour une démonstration quand tu veux.

Bien cordialement,
Mathias
