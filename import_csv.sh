#!/bin/bash
# ==========================================================
# SAE51 - import_csv.sh (version Docker)
# Import direct de Tiers (clients/fournisseurs) dans la base
# MariaDB du conteneur dolibarr_db, sans passer par l'interface
# web de Dolibarr.
# ==========================================================
# Usage : ./import_csv.sh chemin/vers/fichier.csv
#
# Format CSV attendu (separateur ";"), avec ligne d'en-tete :
# Nom;Nom_alias;Adresse;Code_postal;Ville;Pays;Telephone;Email;Client;Fournisseur
#
# - Pays : code ISO (ex: FR), converti en ID via la table llx_c_country
# - Client / Fournisseur : 0 ou 1
# - Un tiers dont le nom existe deja en base est ignore (anti-doublon)
# ==========================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------- Configuration ----------
if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable (copie .env.example vers .env)."
    exit 1
fi
set -a
. ./.env
set +a

DB_CONTAINER="dolibarr_db"

# ---------- Verifications ----------
if [ -z "$1" ]; then
    echo "Usage : $0 chemin/vers/fichier.csv"
    exit 1
fi
CSV_FILE="$1"
if [ ! -f "$CSV_FILE" ]; then
    echo "ERREUR : fichier introuvable : $CSV_FILE"
    exit 1
fi
if [ "$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" != "true" ]; then
    echo "ERREUR : le conteneur $DB_CONTAINER ne tourne pas. Lance d'abord ./install.sh"
    exit 1
fi

# ---------- Fonctions ----------
# Execute du SQL recu sur l'entree standard dans le conteneur MariaDB
run_sql() {
    docker exec -i -e MYSQL_PWD="$DB_PASSWORD" "$DB_CONTAINER" \
        mariadb -N -B -u "$DB_USER" "$DB_NAME"
}

# Echappe les apostrophes et antislash pour SQL
sql_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

# Force une valeur a 0 ou 1
to_bool() {
    if [ "$1" = "1" ]; then echo 1; else echo 0; fi
}

echo "=== Import CSV direct en base (table llx_societe) ==="
echo "Fichier source : $CSV_FILE"
echo "Conteneur      : $DB_CONTAINER (base $DB_NAME)"
echo ""

# ---------- Import ligne par ligne ----------
LINE_NUM=0
INSERTED=0
SKIPPED=0
ERRORS=0

# tr -d '\r' : tolere les fichiers CSV au format Windows (fin de ligne CRLF)
while IFS=';' read -r nom nom_alias adresse code_postal ville pays telephone email client fournisseur || [ -n "$nom" ]; do
    LINE_NUM=$((LINE_NUM + 1))

    # Ligne d'en-tete et lignes vides
    [ "$LINE_NUM" -eq 1 ] && continue
    [ -z "$nom" ] && continue

    nom_e=$(sql_escape "$nom")
    alias_e=$(sql_escape "$nom_alias")
    adresse_e=$(sql_escape "$adresse")
    zip_e=$(sql_escape "$code_postal")
    ville_e=$(sql_escape "$ville")
    pays_e=$(sql_escape "$pays")
    tel_e=$(sql_escape "$telephone")
    email_e=$(sql_escape "$email")
    client_v=$(to_bool "$client")
    fourn_v=$(to_bool "$fournisseur")

    # Anti-doublon : le tiers existe-t-il deja ?
    EXISTE=$(printf "SELECT COUNT(*) FROM llx_societe WHERE nom='%s';" "$nom_e" | run_sql)
    if [ "$EXISTE" != "0" ]; then
        SKIPPED=$((SKIPPED + 1))
        echo "  [IGNORE] Ligne $LINE_NUM : $nom (deja present)"
        continue
    fi

    SQL="INSERT INTO llx_societe
 (nom, name_alias, address, zip, town, fk_pays, phone, email, client, fournisseur, entity, status, datec, import_key)
VALUES
 ('$nom_e', '$alias_e', '$adresse_e', '$zip_e', '$ville_e',
  COALESCE((SELECT rowid FROM llx_c_country WHERE code='$pays_e' LIMIT 1), 0),
  '$tel_e', '$email_e', $client_v, $fourn_v, 1, 1, NOW(), 'import_csv_sh');"

    if ERR=$(printf '%s\n' "$SQL" | run_sql 2>&1); then
        INSERTED=$((INSERTED + 1))
        echo "  [OK]     Ligne $LINE_NUM : $nom"
    else
        ERRORS=$((ERRORS + 1))
        echo "  [ERREUR] Ligne $LINE_NUM : $nom"
        echo "           $ERR"
    fi

done < <(tr -d '\r' < "$CSV_FILE")

echo ""
echo "=== Import termine ==="
echo "Lignes inserees  : $INSERTED"
echo "Lignes ignorees  : $SKIPPED (doublons)"
echo "Lignes en erreur : $ERRORS"

[ "$ERRORS" -eq 0 ]
