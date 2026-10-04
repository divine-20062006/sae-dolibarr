# SAE51 - Projet 3 : Dolibarr dockerisé

POC d'ERP/CRM Dolibarr hébergé en interne, limité à la gestion des Tiers (clients/fournisseurs).
Équipe : Divine Ouboura (chef de projet), Lody Mervedi.

## Architecture

Deux conteneurs séparés : `dolibarr_db` (MariaDB 11, non exposée) et `dolibarr_app` (Dolibarr, port 8080). Les séparer permet de mettre à jour ou de sauvegarder la base indépendamment de l'application. Les données sont stockées dans des volumes Docker.

## Installation

Prérequis : Docker et Docker Compose v2.

    git clone https://github.com/divine-20062006/sae-dolibarr.git
    cd sae-dolibarr
    cp .env.example .env
    nano .env
    ./install.sh

Dans `.env`, renseigner les mots de passe de la base (`DB_*`) et les identifiants du superadmin Dolibarr (`DOLI_ADMIN_*`). Ce fichier n'est pas versionné.

Dolibarr est ensuite accessible sur http://localhost:8080. Le premier démarrage prend une à deux minutes.

## Import des Tiers

    ./import_csv.sh data/tiers_import_test.csv

Format attendu (séparateur `;`, ligne d'en-tête obligatoire) :

    Nom;Nom_alias;Adresse;Code_postal;Ville;Pays;Telephone;Email;Client;Fournisseur
    Dupont Menuiserie;Dupont Menuiserie SARL;12 rue des Artisans;76000;Rouen;FR;0235123456;contact@dupont-menuiserie.fr;1;0

Le script insère directement dans la table `llx_societe`, sans passer par l'interface web : l'import intégré de Dolibarr demande une manipulation manuelle et ne peut pas être automatisé.

- `Pays` : code ISO (FR, BE...), converti en identifiant numérique
- `Client` / `Fournisseur` : `0` ou `1`
- un tiers dont le nom existe déjà est ignoré, l'import peut donc être relancé sans risque
- les lignes importées sont marquées `import_key = 'import_csv_sh'`

## Sauvegarde et restauration (PRA)

    ./backup.sh

Crée `backups/AAAA-MM-JJ_HHhMM/` avec `database.sql` (dump MariaDB) et `files.tgz` (documents et configuration Dolibarr).

    ./restore.sh backups/AAAA-MM-JJ_HHhMM

**Supprime toute la stack actuelle**, puis la reconstruit à partir de la sauvegarde. La base est restaurée avant le démarrage de Dolibarr : sinon, Dolibarr démarrerait sur une base vide et en créerait une neuve.

Le test PRA a été validé : un tiers créé avant la sauvegarde est présent après restauration, un tiers créé après la sauvegarde ne l'est plus.

## Commandes utiles

    docker compose ps          # état des conteneurs
    docker compose logs -f     # logs
    docker compose down        # arrêt (données conservées)
    docker compose down -v     # arrêt + suppression des données

## Documentation

- [suivi_projet.md](suivi_projet.md) : journal de bord
- [sources.md](sources.md) : sources consultées
- [docs/](docs/) : documentation détaillée
