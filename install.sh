#!/bin/bash
# install.sh - installe et demarre la stack Dolibarr + MariaDB avec Docker Compose,
# puis importe automatiquement les fichiers CSV deposes dans data/import/
# Usage : ./install.sh   (a lancer depuis le dossier du projet)

set -e  # arrete le script des qu'une commande echoue (evite de continuer sur une erreur)

echo "=== SAE51 - Installation Dolibarr (Docker) ==="  # titre affiche a l'ecran

# Docker est-il installe ? "command -v" cherche la commande, "&> /dev/null" masque sa sortie
if ! command -v docker &> /dev/null; then
    echo "ERREUR : Docker n'est pas installe."                          # message d'erreur
    echo "Installe-le avec : curl -fsSL https://get.docker.com | sh"    # indique comment l'installer
    exit 1                                                               # quitte avec un code d'erreur
fi

# Le plugin "docker compose" est-il disponible ?
if ! docker compose version &> /dev/null; then
    echo "ERREUR : Docker Compose n'est pas disponible."
    exit 1
fi

# Le fichier .env (mots de passe) existe-t-il ? "-f" teste l'existence d'un fichier, "!" inverse
if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable."
    echo "Copie .env.example vers .env et remplace les CHANGE_ME avant de relancer."
    exit 1
fi
set -a      # a partir d'ici, toute variable definie est automatiquement exportee
. ./.env    # charge les variables du .env : necessaire pour interroger la base plus bas
set +a      # fin de l'export automatique

echo "--- Lancement des conteneurs (MariaDB + Dolibarr) ---"
# up -d : demarre les conteneurs en arriere-plan ; --build : construit l'image Dolibarr depuis le Dockerfile
docker compose up -d --build

echo "--- Attente que Dolibarr soit pret (1 a 2 minutes au premier lancement) ---"
sleep 5  # petite pause pour laisser les conteneurs demarrer
# "until" repete la boucle tant que la commande echoue.
# On lit les logs du conteneur (2>/dev/null masque les erreurs) et "grep -q" cherche sans rien afficher
# la ligne qu'Apache ecrit quand il est lance : c'est le signal que Dolibarr est pret.
until docker compose logs dolibarr 2>/dev/null | grep -q "apache2 -D FOREGROUND"; do
    echo "  ... patiente, Dolibarr initialise la base de donnees ..."
    sleep 5  # attend 5 secondes avant de reessayer
done

echo "--- Import automatique des donnees (data/import/*.csv) ---"
# On attend que les tables de Dolibarr soient creees et remplies : on compte les pays de llx_c_country.
# La requete echoue tant que la table n'existe pas ; "grep -qE '^[1-9]'" reussit des que le nombre est >= 1.
until docker exec -e MYSQL_PWD="$DB_PASSWORD" dolibarr_db \
      mariadb -N -B -u "$DB_USER" "$DB_NAME" -e "SELECT COUNT(*) FROM llx_c_country" 2>/dev/null \
      | grep -qE '^[1-9]'; do
    echo "  ... attente de l'initialisation des tables ..."
    sleep 5
done

shopt -s nullglob  # si aucun fichier ne correspond au motif, la boucle ne s'execute pas (au lieu de recevoir le texte du motif)
for f in data/import/*.csv; do
    echo "Import de $f"
    # "bash ./import_csv.sh" (et non "./import_csv.sh") : marche meme si le droit d'execution est perdu.
    # "|| echo" : une erreur d'import ne doit pas arreter l'installation.
    bash ./import_csv.sh "$f" || echo "ATTENTION : des erreurs sont survenues pendant l'import de $f"
done

echo "--- Planification de la sauvegarde automatique (export CSV inclus) ---"
# Programme une sauvegarde chaque nuit avec cron (voir planifier.sh).
# "|| echo" : l'installation continue meme si cron est absent.
bash ./planifier.sh || echo "ATTENTION : planification impossible (installe cron : sudo apt install -y cron)"

echo ""
echo "=== Installation terminee ! ==="
echo "Dolibarr est accessible sur : http://localhost:8080"
echo "Identifiants : DOLI_ADMIN_LOGIN / DOLI_ADMIN_PASSWORD (voir .env)"
echo ""
echo "Logs en direct : docker compose logs -f"
echo "Arreter        : docker compose down"
echo "Tout supprimer : docker compose down -v"
