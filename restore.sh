#!/bin/bash
# ==========================================================
# SAE51 - restore.sh
# Restauration complete (PRA) de Dolibarr dockerise a partir
# d'une sauvegarde creee par backup.sh.
# ==========================================================
# Usage : ./restore.sh backups/AAAA-MM-JJ_HHhMM
#
# ATTENTION : supprime les conteneurs ET les volumes actuels
# avant de restaurer (repart de zero).
# ==========================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "$1" ]; then
    echo "Usage : $0 backups/AAAA-MM-JJ_HHhMM"
    echo "Sauvegardes disponibles :"
    ls -1 backups/ 2>/dev/null || echo "  (aucune)"
    exit 1
fi

BACKUP_DIR="$(cd "$1" && pwd)"

if [ ! -f "$BACKUP_DIR/database.sql" ] || [ ! -f "$BACKUP_DIR/files.tgz" ]; then
    echo "ERREUR : $BACKUP_DIR doit contenir database.sql et files.tgz"
    exit 1
fi

if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable."
    exit 1
fi
export $(grep -v '^#' .env | xargs)

echo "=== Restauration depuis $BACKUP_DIR ==="
read -p "Cela va SUPPRIMER les donnees actuelles. Continuer ? (oui/non) " REP
if [ "$REP" != "oui" ]; then
    echo "Annule."
    exit 0
fi

echo "--- 1/5 Arret et suppression de l'existant (conteneurs + volumes) ---"
docker compose down -v

echo "--- 2/5 Demarrage de MariaDB seule ---"
docker compose up -d db
until [ "$(docker inspect -f '{{.State.Health.Status}}' dolibarr_db 2>/dev/null)" = "healthy" ]; do
    echo "  ... attente que MariaDB soit prete ..."
    sleep 3
done

echo "--- 3/5 Creation du conteneur Dolibarr (sans le demarrer) ---"
docker compose create dolibarr

echo "--- 4/5 Restauration des fichiers (documents + conf) ---"
docker run --rm \
    --volumes-from dolibarr_app \
    -v "$BACKUP_DIR":/backup \
    alpine tar xzf /backup/files.tgz -C /

echo "--- 5/5 Restauration de la base de donnees ---"
docker exec -i dolibarr_db mariadb -u root -p"$DB_ROOT_PASSWORD" "$DB_NAME" < "$BACKUP_DIR/database.sql"

echo "--- Demarrage de Dolibarr ---"
docker compose up -d dolibarr

echo ""
echo "=== Restauration terminee ==="
echo "Dolibarr est accessible sur : http://localhost:8080"
echo "Les donnees sont celles de la sauvegarde $BACKUP_DIR"
