#!/bin/bash
# export_csv.sh - exporte les Tiers (table llx_societe) dans un CSV au meme format que import_csv.sh
# Usage : ./export_csv.sh [fichier_sortie.csv]    (defaut : data/export_tiers_AAAA-MM-JJ.csv)

set -e  # arrete le script des qu'une commande echoue

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # dossier absolu du script
cd "$SCRIPT_DIR"                                             # on s'y place

if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable (copie .env.example vers .env)."
    exit 1
fi
set -a      # exporte automatiquement les variables definies ensuite
. ./.env    # charge DB_NAME, DB_USER, DB_PASSWORD...
set +a

DB_CONTAINER="dolibarr_db"  # nom du conteneur de la base

# Le conteneur de la base doit tourner
if [ "$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" != "true" ]; then
    echo "ERREUR : le conteneur $DB_CONTAINER ne tourne pas. Lance d'abord ./install.sh"
    exit 1
fi

# Fichier de sortie : le 1er argument s'il est donne, sinon un nom avec la date du jour
OUT_FILE="${1:-data/export_tiers_$(date +%Y-%m-%d).csv}"
mkdir -p "$(dirname "$OUT_FILE")"  # cree le dossier de sortie si besoin

# Genere l'expression SQL qui nettoie une colonne :
# IFNULL remplace NULL par du vide ; REPLACE retire ";" (separateur du CSV), tabulation et retours a la ligne
clean() {
    echo "REPLACE(REPLACE(REPLACE(REPLACE(IFNULL($1,''),';',','),CHAR(9),' '),CHAR(10),' '),CHAR(13),' ')"
}

# Requete : memes colonnes, dans le meme ordre, que le CSV d'import.
# LEFT JOIN avec llx_c_country : retrouve le code pays (FR) a partir de l'identifiant fk_pays.
# Dans Dolibarr client peut valoir 1 (client), 2 (prospect) ou 3 (les deux) : on garde 1 si client ou client+prospect.
SQL="SELECT
  $(clean s.nom),
  $(clean s.name_alias),
  $(clean s.address),
  $(clean s.zip),
  $(clean s.town),
  $(clean c.code),
  $(clean s.phone),
  $(clean s.email),
  IF(s.client IN (1,3),1,0),
  IF(s.fournisseur=1,1,0)
FROM llx_societe s
LEFT JOIN llx_c_country c ON c.rowid = s.fk_pays
ORDER BY s.rowid;"

echo "=== Export des Tiers vers $OUT_FILE ==="

# 1) ecrit la ligne d'en-tete (le ">" cree/ecrase le fichier)
echo "Nom;Nom_alias;Adresse;Code_postal;Ville;Pays;Telephone;Email;Client;Fournisseur" > "$OUT_FILE"
# 2) envoie la requete au conteneur ; mariadb -B -N sort des lignes separees par des tabulations,
#    "tr" remplace les tabulations par ";" ; ">>" ajoute au fichier sans l'ecraser
printf '%s\n' "$SQL" | docker exec -i -e MYSQL_PWD="$DB_PASSWORD" "$DB_CONTAINER" \
    mariadb -B -N -u "$DB_USER" "$DB_NAME" | tr '\t' ';' >> "$OUT_FILE"

# Nombre de tiers exportes = nombre de lignes du fichier moins l'en-tete
NB=$(( $(wc -l < "$OUT_FILE") - 1 ))
echo "Tiers exportes : $NB"
echo "Fichier : $OUT_FILE"
