#!/bin/bash
# restore.sh - restauration complete (PRA) a partir d'une sauvegarde creee par backup.sh
# Usage : ./restore.sh backups/AAAA-MM-JJ_HHhMM
# ATTENTION : supprime les conteneurs ET les volumes actuels avant de restaurer.

set -e  # arrete le script des qu'une commande echoue

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # dossier absolu du script
cd "$SCRIPT_DIR"                                             # on s'y place

# Il faut indiquer quelle sauvegarde restaurer ("-z" : argument vide)
if [ -z "$1" ]; then
    echo "Usage : $0 backups/AAAA-MM-JJ_HHhMM"
    echo "Sauvegardes disponibles :"
    ls -1 backups/ 2>/dev/null || echo "  (aucune)"  # liste les sauvegardes, ou "(aucune)" si le dossier n'existe pas
    exit 1
fi

BACKUP_DIR="$(cd "$1" && pwd)"  # transforme le chemin donne en chemin absolu

# La sauvegarde doit contenir les deux fichiers produits par backup.sh
if [ ! -f "$BACKUP_DIR/database.sql" ] || [ ! -f "$BACKUP_DIR/files.tgz" ]; then
    echo "ERREUR : $BACKUP_DIR doit contenir database.sql et files.tgz"
    exit 1
fi

if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable."
    exit 1
fi
set -a      # exporte automatiquement les variables definies ensuite
. ./.env    # charge les variables du .env
set +a

echo "=== Restauration depuis $BACKUP_DIR ==="
# Confirmation obligatoire : l'operation est destructrice
read -p "Cela va SUPPRIMER les donnees actuelles. Continuer ? (oui/non) " REP
if [ "$REP" != "oui" ]; then
    echo "Annule."
    exit 0
fi

echo "--- 1/5 Arret et suppression de l'existant (conteneurs + volumes) ---"
docker compose down -v  # -v supprime aussi les volumes : on repart de zero

echo "--- 2/5 Demarrage de MariaDB seule ---"
docker compose up -d db
# On attend que le healthcheck du conteneur db passe a "healthy" (base prete a recevoir des requetes)
until [ "$(docker inspect -f '{{.State.Health.Status}}' dolibarr_db 2>/dev/null)" = "healthy" ]; do
    echo "  ... attente que MariaDB soit prete ..."
    sleep 3
done

echo "--- 3/5 Creation du conteneur Dolibarr (sans le demarrer) ---"
# "create" cree le conteneur et ses volumes vides, sans le lancer : Dolibarr ne doit pas
# s'initialiser tout seul avant que ses fichiers soient restaures
docker compose create dolibarr

echo "--- 4/5 Restauration des fichiers (documents + conf) ---"
# Conteneur temporaire monte sur les volumes de dolibarr_app ; tar x = extraire l'archive a la racine
docker run --rm \
    --volumes-from dolibarr_app \
    -v "$BACKUP_DIR":/backup \
    alpine tar xzf /backup/files.tgz -C /

echo "--- 5/5 Restauration de la base de donnees ---"
# -i garde l'entree standard ouverte : le contenu de database.sql est envoye au client mariadb du conteneur
docker exec -i dolibarr_db mariadb -u root -p"$DB_ROOT_PASSWORD" "$DB_NAME" < "$BACKUP_DIR/database.sql"

echo "--- Demarrage de Dolibarr ---"
docker compose up -d dolibarr

echo ""
echo "=== Restauration terminee ==="
echo "Dolibarr est accessible sur : http://localhost:8080"
echo "Les donnees sont celles de la sauvegarde $BACKUP_DIR"
