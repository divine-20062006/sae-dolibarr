# Étude des choix techniques

Ce document justifie les choix faits pour chaque volet du cahier des charges.

## 1. Installation manuelle de Dolibarr (découverte)

Avant d'automatiser, Dolibarr a été installé à la main sur une VM Debian 13 pour
comprendre son fonctionnement : Apache 2.4, PHP 8.4, MariaDB 11.8, Dolibarr 22.0.1
(version « source »).

Étapes réalisées :

1. Installation des paquets : `apache2 mariadb-server php php-cli php-mysql php-curl php-gd
   php-intl php-mbstring php-xml php-zip php-imagick unzip wget`.
2. Extraction de l'archive dans `/var/www/html/dolibarr`, création de `/var/www/documents`,
   droits donnés à `www-data`.
3. Création de la base `dolibarr` et d'un utilisateur MariaDB dédié avec droits limités à
   cette base.
4. Passage par l'assistant web (`/dolibarr/htdocs/install/`) : vérification des prérequis,
   connexion à la base, création du compte administrateur.
5. Création d'un compte utilisateur standard, activation du module Tiers, attribution des
   permissions sur ce module.

Ce qu'on en retient : Dolibarr est modulaire (rien n'est activé après l'installation),
l'installation demande beaucoup d'étapes manuelles et une configuration fine des droits.
C'est ce qui justifie de la scripter et de la conteneuriser.

## 2. Import des données : interface web ou SQL direct

Les deux méthodes ont été testées sur les mêmes 8 tiers fictifs.

| Critère | Import via l'interface (menu Outils) | Import SQL direct (`import_csv.sh`) |
|---|---|---|
| Automatisable | Non, manipulation manuelle dans les menus | Oui, une seule commande |
| Contrôle du mapping | Limité aux champs proposés par l'assistant | Total (on choisit chaque colonne) |
| Champ Pays | Aucun champ de mapping adapté : « FR » s'est retrouvé dans « Nom alternatif » | Converti en identifiant via `llx_c_country` |
| Doublons | Non gérés | Ignorés (contrôle sur le nom) |
| Validation préalable | Oui, simulation avant import | Non (mais erreurs affichées ligne par ligne) |
| Règles métier de Dolibarr | Respectées | Contournées |

L'étude de la table `llx_societe` (97 colonnes) a montré que le champ « État »
signalé comme obligatoire par l'assistant web correspond à la colonne `status`, qui a une
valeur par défaut (1 = actif) : l'avertissement n'était donc pas bloquant. De même,
`fk_pays` attend un identifiant numérique et non un code texte.

**Choix retenu** : l'import SQL direct, seul compatible avec l'exigence d'un import
automatisé par un unique script.

**Limites assumées** : en écrivant directement en base, on contourne la logique de
Dolibarr (génération automatique des codes client, événements internes). Le script
est aussi lié à la structure des tables, qui peut évoluer d'une version à l'autre : il a
fonctionné sur Dolibarr 22.0.1 (installation manuelle) et 24.0.0 (Docker), mais devrait
être revérifié après une mise à jour majeure.

## 3. Dockerisation

**Deux conteneurs séparés** (Dolibarr + MariaDB) plutôt qu'un seul :

- cycles de vie indépendants (on peut mettre à jour ou redémarrer l'un sans l'autre),
- sauvegarde plus simple (dump de la base d'un côté, fichiers de l'autre),
- conforme à la pratique courante et à la recommandation du sujet.

**MariaDB : image officielle sans modification** (`mariadb:11`). Écrire un
Dockerfile maison aurait demandé de réinstaller et sécuriser un serveur MariaDB pour
un résultat identique : aucun intérêt pédagogique ou technique ici.

**Dolibarr : Dockerfile basé sur l'image officielle** (`docker/dolibarr/Dockerfile`).
Partir de zéro (installer PHP, Apache, toutes les extensions nécessaires comme lors de
l'installation manuelle) aurait été long et fragile pour un résultat équivalent à
l'image officielle. Le Dockerfile sert donc à **personnaliser** cette base plutôt qu'à
la remplacer : variables d'environnement figées pour le projet (`DOLI_ENABLE_MODULES`,
`DOLI_COMPANY_NAME`, `DOLI_COMPANY_COUNTRYCODE`, fuseau horaire), afin que le module
Tiers et la société soient prêts dès le premier démarrage, sans étape manuelle. C'est un
compromis entre « tout réécrire » et « utiliser l'image telle quelle ».

**Persistance** : trois volumes nommés (`db_data`, `dolibarr_documents`,
`dolibarr_html`). Le volume `dolibarr_html` contient notamment `conf.php`, ce qui permet
de retrouver la configuration après une restauration.

**Configuration** : les mots de passe sont dans un fichier `.env`, exclu de Git, avec un
`.env.example` versionné comme modèle.

**Port** : Dolibarr est exposé sur le 8080 pour cohabiter avec l'installation manuelle
(port 80) pendant les tests.

## 4. Sauvegarde et PRA

La sauvegarde (`backup.sh`) produit deux éléments :

- un **dump SQL** de la base (`mariadb-dump --single-transaction`, cohérent sans arrêter
  le service),
- une **archive des fichiers** Dolibarr (documents et configuration), réalisée avec un
  conteneur temporaire qui monte les mêmes volumes (`--volumes-from`).

La restauration (`restore.sh`) repart de zéro : suppression des conteneurs et volumes,
démarrage de MariaDB, création du conteneur Dolibarr sans le lancer, restauration des
fichiers puis de la base, et enfin démarrage de Dolibarr.

**Validation** : un tiers « Client PRA » a été créé puis sauvegardé, un second tiers a
été créé après la sauvegarde, puis la restauration complète a été lancée. Le premier
tiers a été retrouvé et le second avait disparu, ce qui prouve que l'état restauré est
bien celui de la sauvegarde.

**Limites** : les sauvegardes restent sur la machine qui les produit. En cas de perte de
la machine, elles seraient perdues aussi. Une vraie stratégie de PRA imposerait une copie
régulière vers un autre emplacement, et un test de restauration périodique.
