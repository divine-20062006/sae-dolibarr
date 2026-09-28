#!/bin/bash
# ==========================================================
# SAE51 - backup.sh
# Sauvegarde complete de la stack Dolibarr dockerisee :
#   1. dump SQL de la base MariaDB
#   2. archive des fichiers Dolibarr (documents + conf.php)
# ==========================================================
# Usage : ./backup.sh
# Resultat : dossier backups/AAAA-MM-JJ_HHhMM/ contenant
#            database.sql et files.tgz
# ==========================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable."
    exit 1
fi
export $(grep -v '^#' .env | xargs)

# Verifie que les conteneurs tournent
for c in dolibarr_db dolibarr_app; do
    if [ "$(docker inspect -f '{{.State.Running}}' $c 2>/dev/null)" != "true" ]; then
        echo "ERREUR : le conteneur $c ne tourne pas. Lance d'abord ./install.sh"
        exit 1
    fi
done

BACKUP_DIR="$SCRIPT_DIR/backups/$(date +%Y-%m-%d_%Hh%M)"
mkdir -p "$BACKUP_DIR"

echo "=== Sauvegarde Dolibarr -> $BACKUP_DIR ==="

echo "--- 1/2 Dump de la base de donnees ---"
docker exec dolibarr_db mariadb-dump \
    -u root -p"$DB_ROOT_PASSWORD" \
    --single-transaction --routines --triggers \
    "$DB_NAME" > "$BACKUP_DIR/database.sql"

echo "--- 2/2 Archive des fichiers Dolibarr (documents + conf) ---"
docker run --rm \
    --volumes-from dolibarr_app \
    -v "$BACKUP_DIR":/backup \
    alpine tar czf /backup/files.tgz -C / var/www/documents var/www/html

echo ""
echo "=== Sauvegarde terminee ==="
ls -lh "$BACKUP_DIR"
echo ""
echo "Pour restaurer : ./restore.sh $BACKUP_DIR"
