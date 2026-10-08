**SAE51 - Installation d'un ERP/CRM (Dolibarr)**
============================================

Projet BUT3 Réseaux & Télécoms - IUT Rouen

**Équipe**

- Chef de projet : Divine OUBOURRA
- Membre : Mervedi LODY

**Objectif**

Migrer une solution ERP/CRM externalisée vers **Dolibarr hébergé en interne**, avec :

- une installation automatisée (`install.sh`),
- un import automatisé des données CSV de l'ancien système (`import_csv.sh`) et un export au même format (`export_csv.sh`),
- une installation **dockerisée** (Dolibarr et MariaDB dans deux conteneurs séparés),
- une **sauvegarde et une restauration complètes** (PRA) : `backup.sh` et `restore.sh`.

Périmètre fonctionnel : gestion des **Tiers** (clients / fournisseurs), dans une logique de POC.

**Contenu du dépôt**

```
sae-dolibarr/
|-- docker-compose.yml   # stack : MariaDB + Dolibarr (2 conteneurs)
|-- docker/dolibarr/
|   |-- Dockerfile       # image Dolibarr personnalisée (module Tiers, société)
|-- .env.example         # modèle de configuration (à copier en .env)
|-- install.sh           # installation automatisée
|-- import_csv.sh        # import CSV direct en base
|-- export_csv.sh        # export des Tiers en CSV (même format que l'import)
|-- backup.sh            # sauvegarde complète
|-- restore.sh           # restauration complète (PRA)
|-- planifier.sh         # planifie la sauvegarde + l'export automatiques (cron)
|-- data/import/         # CSV importés automatiquement à l'installation
|-- docs/                # documentation détaillée
|-- sources.md           # sources utilisées
|-- suivi_projet.md      # journal de bord
```

Le fichier `.env` (mots de passe) et le dossier `backups/` ne sont **pas versionnés** (voir `.gitignore`).

Documentation détaillée : [docs/etude_choix_techniques.md](docs/etude_choix_techniques.md)

**Prérequis**

Une machine Debian (VM VirtualBox dans notre cas) avec Docker et le plugin Docker Compose :

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER      # puis se déconnecter / reconnecter
```

**Installation**

```bash
git clone https://github.com/divine-20062006/sae-dolibarr.git
cd sae-dolibarr
cp .env.example .env
nano .env                          # remplacer les valeurs CHANGE_ME
chmod +x *.sh
./install.sh
```

Dolibarr est ensuite accessible sur **http://localhost:8080** avec le compte
`DOLI_ADMIN_LOGIN` / `DOLI_ADMIN_PASSWORD` défini dans `.env`.

Le premier lancement construit l'image Dolibarr (`docker compose up -d --build`),
télécharge MariaDB et initialise la base : compter quelques minutes.

Le module **Third parties** (Tiers) et la société (nom, pays) sont activés
automatiquement à l'initialisation, via les variables `DOLI_ENABLE_MODULES`,
`DOLI_COMPANY_NAME` et `DOLI_COMPANY_COUNTRYCODE` définies dans le `Dockerfile`.
Aucune étape manuelle n'est nécessaire après `./install.sh`.

**Import des données CSV**

Format attendu (séparateur `;`, ligne d'en-tête obligatoire) :

```
Nom;Nom_alias;Adresse;Code_postal;Ville;Pays;Telephone;Email;Client;Fournisseur
```

Exemple fourni : `data/import/tiers_import_test.csv` (8 tiers fictifs).

```bash
./import_csv.sh data/import/tiers_import_test.csv
```

Le script insère directement dans la table `llx_societe` du conteneur MariaDB :

- le pays (code ISO, ex. `FR`) est converti en identifiant via la table `llx_c_country`,
- un tiers dont le nom existe déjà est ignoré (on peut relancer le script sans doublon),
- les lignes importées sont marquées `import_key = 'import_csv_sh'` pour être retrouvées.

**Export des données**

```bash
./export_csv.sh                      # crée data/export_tiers_AAAA-MM-JJ.csv
./export_csv.sh mon_fichier.csv      # ou vers un fichier de son choix
```

Le fichier produit a le **même format** que celui lu par `import_csv.sh` (mêmes colonnes,
séparateur `;`) : on peut exporter puis réimporter. Le code pays est reconstitué à partir de
l'identifiant stocké en base. Les `;` présents dans une valeur sont remplacés par des virgules.

L'interface de Dolibarr propose aussi un export (menu *Tools > New export*), mais il n'est
pas automatisable : c'est la raison d'être du script.

**Fonctionnement automatique**

- **Import** : à la fin de `./install.sh`, tous les fichiers `data/import/*.csv` sont importés
  sans intervention. Il suffit de déposer un CSV dans ce dossier avant (ou après) l'installation.
  Relancer `./install.sh` est sans risque : les tiers déjà présents sont ignorés.
- **Export** : chaque sauvegarde (`./backup.sh`) produit aussi un `tiers.csv` dans son dossier.
- **Planification** : `./install.sh` programme automatiquement une sauvegarde (donc un export) chaque
  nuit à 02h00 via cron, grâce à `planifier.sh`. Un autre horaire peut être donné en lançant
  `./planifier.sh "30 1 * * *"`. Le journal est écrit dans `backups/backup.log`.
- **Pourquoi** : l'export régulier limite la perte de données en cas d'incident, et l'import (ou
  `restore.sh` pour une restauration complète) permet de les récupérer sans manipulation manuelle.

**Sauvegarde et restauration (PRA)**

**Sauvegarde** (les conteneurs doivent tourner) :

```bash
./backup.sh
```

Crée `backups/AAAA-MM-JJ_HHhMM/` contenant :

- `database.sql` : dump de la base MariaDB,
- `files.tgz` : documents Dolibarr et configuration (`conf.php`),
- `tiers.csv` : export CSV des Tiers (même format que l'import).

**Restauration** (repart de zéro : supprime conteneurs et volumes actuels) :

```bash
./restore.sh backups/AAAA-MM-JJ_HHhMM
```

**Reprise complète sur une machine vierge** :

1. Installer Docker, cloner le dépôt, créer le `.env`.
2. Copier le dossier de sauvegarde dans `backups/` (par exemple avec `scp`).
3. Lancer `./restore.sh backups/<dossier>`.

Point d'attention : `DB_NAME`, `DB_USER` et `DB_PASSWORD` du `.env` doivent être
**identiques** à ceux utilisés au moment de la sauvegarde, car Dolibarr les relit dans
le fichier `conf.php` restauré.

**Test réalisé et validé** : création d'un tiers, sauvegarde, création d'un second tiers,
restauration complète. Résultat : le premier tiers est présent, le second a disparu.

**Choix techniques (résumé)**

- **MariaDB** : image officielle utilisée telle quelle (`mariadb:11`).
- **Dolibarr** : image officielle utilisée comme **base** d'un `Dockerfile` propre au
  projet (`docker/dolibarr/Dockerfile`), qui pré-configure le module Tiers et la
  société via des variables d'environnement. Évite de réinstaller PHP/Apache à la main
  tout en automatisant complètement l'initialisation.
- **Deux conteneurs séparés** (application / base de données), avec volumes persistants.
- **Import SQL direct** plutôt que l'import de l'interface web, non automatisable.

Justifications détaillées dans [docs/etude_choix_techniques.md](docs/etude_choix_techniques.md).

**Limites et pistes d'amélioration**

- Les sauvegardes sont stockées sur la même machine : pour un vrai PRA, il faut les
  copier régulièrement vers un autre site ou serveur.
- La version de Dolibarr n'est pas figée par défaut (`DOLIBARR_VERSION=latest` dans
  `.env`) : pour un environnement stable, fixer une version précise (ex. `24.0.0`).
- Les sauvegardes planifiées ne sont pas purgées : sur la durée, il faudrait une rotation (ne garder que les N dernières).
- Les mots de passe sont en clair dans `.env` (acceptable pour un POC uniquement).
- L'import ne couvre que les Tiers, pas les contacts, factures ou commandes.
