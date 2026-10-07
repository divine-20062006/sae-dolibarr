#!/bin/bash
# ==========================================================
# SAE51 - import_csv.sh
# Import direct de donnees Tiers (clients/fournisseurs) dans
# la base MariaDB de Dolibarr, en contournant l'interface web.
# ==========================================================
# Usage : ./import_csv.sh chemin/vers/fichier.csv
#
# Format CSV attendu (separateur ";"), avec en-tete :
# Nom;Nom_alias;Adresse;Code_postal;Ville;Pays;Telephone;Email;Client;Fournisseur
#
# Variables de connexion : lues depuis .env si present dans le
# meme dossier, sinon valeurs par defaut ci-dessous (adaptees
# a l'installation native, pas Docker).
# ==========================================================

set -e

# ---------- Chargement de la config ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

DB_HOST="${DB_HOST:-localhost}"
DB_NAME="${DB_NAME:-dolibarr}"
DB_USER="${DB_USER:-dolibarruser}"
DB_PASSWORD="${DB_PASSWORD:-DolibarrPass2026!}"

# ---------- Verification des arguments ----------
if [ -z "$1" ]; then
    echo "Usage : $0 chemin/vers/fichier.csv"
    exit 1
fi

CSV_FILE="$1"

if [ ! -f "$CSV_FILE" ]; then
    echo "ERREUR : fichier introuvable : $CSV_FILE"
    exit 1
fi

echo "=== Import CSV direct en base (table llx_societe) ==="
echo "Fichier source : $CSV_FILE"
echo "Base cible     : $DB_NAME sur $DB_HOST"
echo ""

# ---------- Fonction d'echappement SQL simple ----------
sql_escape() {
    echo "$1" | sed "s/'/''/g"
}

# ---------- Lecture et import ligne par ligne ----------
LINE_NUM=0
INSERTED=0
SKIPPED=0

# On lit le fichier avec le separateur ";"
while IFS=';' read -r nom nom_alias adresse code_postal ville pays telephone email client fournisseur; do
    LINE_NUM=$((LINE_NUM + 1))

    # On saute la ligne d'en-tete
    if [ "$LINE_NUM" -eq 1 ]; then
        continue
    fi

    # On saute les lignes vides
    if [ -z "$nom" ]; then
        continue
    fi

    # Nettoyage / echappement des valeurs pour eviter les injections SQL
    nom_esc=$(sql_escape "$nom")
    nom_alias_esc=$(sql_escape "$nom_alias")
    adresse_esc=$(sql_escape "$adresse")
    ville_esc=$(sql_escape "$ville")
    telephone_esc=$(sql_escape "$telephone")
    email_esc=$(sql_escape "$email")

    # client/fournisseur : 0 ou 1, valeur par defaut 0 si vide
    client_val="${client:-0}"
    fournisseur_val="${fournisseur:-0}"

    # Construction de la requete INSERT
    SQL="INSERT INTO llx_societe (nom, name_alias, address, zip, town, phone, email, client, fournisseur, entity, status, datec, import_key)
VALUES ('$nom_esc', '$nom_alias_esc', '$adresse_esc', '$code_postal', '$ville_esc', '$telephone_esc', '$email_esc', $client_val, $fournisseur_val, 1, 1, NOW(), 'import_csv_sh');"

    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" -e "$SQL" 2>/tmp/import_error.log; then
        INSERTED=$((INSERTED + 1))
        echo "  [OK] Ligne $LINE_NUM : $nom"
    else
        SKIPPED=$((SKIPPED + 1))
        echo "  [ERREUR] Ligne $LINE_NUM : $nom -- voir /tmp/import_error.log"
    fi

done < "$CSV_FILE"

echo ""
echo "=== Import termine ==="
echo "Lignes inserees : $INSERTED"
echo "Lignes en erreur : $SKIPPED"
