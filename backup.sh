#!/bin/bash
# backup.sh - sauvegarde complete de Dolibarr dockerise :
#   1. dump SQL de la base MariaDB   -> database.sql
#   2. archive des fichiers Dolibarr -> files.tgz (documents + conf.php)
#   3. export CSV des Tiers          -> tiers.csv (lisible, meme format que l'import)
# Usage : ./backup.sh        Resultat : dossier backups/AAAA-MM-JJ_HHhMM/

set -e  # arrete le script des qu'une commande echoue

# Chemin absolu du dossier de ce script, puis on s'y place :
# les chemins relatifs (.env, backups/) marchent ainsi quel que soit l'endroit d'ou on lance le script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Sans .env on n'a pas les mots de passe : on s'arrete
if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable."
    exit 1
fi
set -a      # a partir d'ici, toute variable definie est automatiquement exportee
. ./.env    # charge les variables du fichier .env (DB_NAME, DB_USER, ...)
set +a      # fin de l'export automatique

# Les deux conteneurs doivent tourner
for c in dolibarr_db dolibarr_app; do
    # docker inspect renvoie "true" si le conteneur tourne (2>/dev/null masque l'erreur s'il n'existe pas)
    if [ "$(docker inspect -f '{{.State.Running}}' $c 2>/dev/null)" != "true" ]; then
        echo "ERREUR : le conteneur $c ne tourne pas. Lance d'abord ./install.sh"
        exit 1
    fi
done

# Dossier de sauvegarde horodate, par exemple backups/2026-10-12_14h30
BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y-%m-%d_%Hh%M)"
mkdir -p "$BACKUP_DIR"  # -p : cree aussi les dossiers parents s'ils manquent

echo "=== Sauvegarde Dolibarr -> $BACKUP_DIR ==="

echo "--- 1/3 Dump de la base de donnees ---"
# On execute mariadb-dump DANS le conteneur de la base, et on redirige sa sortie vers un fichier sur l'hote
# --single-transaction : copie coherente sans bloquer la base ; --routines/--triggers : inclut procedures et declencheurs
docker exec dolibarr_db mariadb-dump \
    -u root -p"$DB_ROOT_PASSWORD" \
    --single-transaction --routines --triggers \
    "$DB_NAME" > "$BACKUP_DIR/database.sql"

echo "--- 2/3 Archive des fichiers Dolibarr (documents + conf) ---"
# Conteneur temporaire alpine (--rm : supprime a la fin) qui monte les memes volumes que dolibarr_app
# (--volumes-from) et le dossier de sauvegarde (-v). tar : c=creer, z=compresser, f=fichier.
# -C / : on se place a la racine pour que les chemins dans l'archive soient relatifs (var/www/...)
docker run --rm \
    --volumes-from dolibarr_app \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf /backup/files.tgz -C / var/www/documents var/www/html

echo "--- 3/3 Export CSV des Tiers ---"
# Chaque sauvegarde contient aussi un export lisible. "|| echo" : un echec de l'export ne doit pas
# faire echouer la sauvegarde, dont le dump SQL et l'archive sont deja faits.
bash ./export_csv.sh "$BACKUP_DIR/tiers.csv" || echo "ATTENTION : export CSV impossible (le dump SQL est bien sauvegarde)"

echo ""
echo "=== Sauvegarde terminee ==="
ls -lh "$BACKUP_DIR"  # affiche les fichiers crees avec leur taille
echo ""
echo "Pour restaurer : ./restore.sh $BACKUP_DIR"
