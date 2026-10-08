#!/bin/bash
# import_csv.sh - importe des Tiers (clients/fournisseurs) depuis un CSV directement dans la base
# MariaDB du conteneur dolibarr_db, sans passer par l'interface web de Dolibarr.
# Usage : ./import_csv.sh chemin/vers/fichier.csv
#
# Format attendu (separateur ";", ligne d'en-tete obligatoire) :
# Nom;Nom_alias;Adresse;Code_postal;Ville;Pays;Telephone;Email;Client;Fournisseur
# - Pays : code ISO (ex FR), converti en identifiant via la table llx_c_country
# - Un tiers dont le nom existe deja est ignore (anti-doublon)

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

DB_CONTAINER="dolibarr_db"  # nom du conteneur de la base (defini dans docker-compose.yml)

# $1 = premier argument donne au script (le fichier CSV) ; "-z" : vide
if [ -z "$1" ]; then
    echo "Usage : $0 chemin/vers/fichier.csv"
    exit 1
fi
CSV_FILE="$1"
if [ ! -f "$CSV_FILE" ]; then
    echo "ERREUR : fichier introuvable : $CSV_FILE"
    exit 1
fi
# Le conteneur de la base doit tourner
if [ "$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" != "true" ]; then
    echo "ERREUR : le conteneur $DB_CONTAINER ne tourne pas. Lance d'abord ./install.sh"
    exit 1
fi

# Execute le SQL recu sur l'entree standard, dans le client mariadb du conteneur
# -i : garde l'entree ouverte ; MYSQL_PWD : mot de passe passe par variable (pas visible dans la commande)
# -N : sans noms de colonnes ; -B : sortie brute
run_sql() {
    docker exec -i -e MYSQL_PWD="$DB_PASSWORD" "$DB_CONTAINER" \
        mariadb -N -B -u "$DB_USER" "$DB_NAME"
}

# Protege une valeur avant de l'inserer dans une requete SQL :
# double les antislash et les apostrophes (sinon une apostrophe casserait la requete, voire permettrait une injection)
sql_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

# Renvoie 1 si la valeur est "1", sinon 0 (les colonnes client/fournisseur sont des booleens)
to_bool() {
    if [ "$1" = "1" ]; then echo 1; else echo 0; fi
}

echo "=== Import CSV direct en base (table llx_societe) ==="
echo "Fichier source : $CSV_FILE"
echo "Conteneur      : $DB_CONTAINER (base $DB_NAME)"
echo ""

LINE_NUM=0  # numero de la ligne en cours
INSERTED=0  # lignes inserees
SKIPPED=0   # lignes ignorees (doublons)
ERRORS=0    # lignes en erreur

# Lecture ligne par ligne. IFS=';' coupe chaque ligne sur les ";" ; -r garde les antislash tels quels ;
# les 10 variables recoivent les 10 colonnes. "|| [ -n "$nom" ]" traite aussi la derniere ligne si elle n'a pas de retour a la ligne.
while IFS=';' read -r nom nom_alias adresse code_postal ville pays telephone email client fournisseur || [ -n "$nom" ]; do
    LINE_NUM=$((LINE_NUM + 1))  # incremente le compteur de lignes

    [ "$LINE_NUM" -eq 1 ] && continue  # ligne 1 = en-tete : on passe a la suivante
    [ -z "$nom" ] && continue          # nom vide = ligne vide : on l'ignore

    # Echappe chaque valeur texte avant de l'utiliser dans le SQL
    nom_e=$(sql_escape "$nom")
    alias_e=$(sql_escape "$nom_alias")
    adresse_e=$(sql_escape "$adresse")
    zip_e=$(sql_escape "$code_postal")
    ville_e=$(sql_escape "$ville")
    pays_e=$(sql_escape "$pays")
    tel_e=$(sql_escape "$telephone")
    email_e=$(sql_escape "$email")
    client_v=$(to_bool "$client")       # 0 ou 1
    fourn_v=$(to_bool "$fournisseur")   # 0 ou 1

    # Anti-doublon : on compte les tiers qui portent deja ce nom
    EXISTE=$(printf "SELECT COUNT(*) FROM llx_societe WHERE nom='%s';" "$nom_e" | run_sql)
    if [ "$EXISTE" != "0" ]; then
        SKIPPED=$((SKIPPED + 1))
        echo "  [IGNORE] Ligne $LINE_NUM : $nom (deja present)"
        continue  # on passe a la ligne suivante sans inserer
    fi

    # Requete d'insertion dans llx_societe.
    # fk_pays : sous-requete qui retrouve l'identifiant du pays a partir de son code (0 si introuvable, grace a COALESCE)
    # entity=1 et status=1 : valeurs par defaut de Dolibarr (entite principale, tiers actif)
    # datec=NOW() : date de creation ; import_key : etiquette pour retrouver les lignes importees par ce script
    SQL="INSERT INTO llx_societe
 (nom, name_alias, address, zip, town, fk_pays, phone, email, client, fournisseur, entity, status, datec, import_key)
VALUES
 ('$nom_e', '$alias_e', '$adresse_e', '$zip_e', '$ville_e',
  COALESCE((SELECT rowid FROM llx_c_country WHERE code='$pays_e' LIMIT 1), 0),
  '$tel_e', '$email_e', $client_v, $fourn_v, 1, 1, NOW(), 'import_csv_sh');"

    # On envoie la requete a la base. Si elle reussit : [OK] ; sinon on affiche le message d'erreur SQL
    if ERR=$(printf '%s\n' "$SQL" | run_sql 2>&1); then
        INSERTED=$((INSERTED + 1))
        echo "  [OK]     Ligne $LINE_NUM : $nom"
    else
        ERRORS=$((ERRORS + 1))
        echo "  [ERREUR] Ligne $LINE_NUM : $nom"
        echo "           $ERR"
    fi

# "tr -d '\r'" retire les retours chariot Windows (CRLF) du fichier. On utilise "< <(...)" plutot qu'un pipe
# pour que la boucle tourne dans le shell principal : sinon les compteurs seraient perdus a la fin.
done < <(tr -d '\r' < "$CSV_FILE")

echo ""
echo "=== Import termine ==="
echo "Lignes inserees  : $INSERTED"
echo "Lignes ignorees  : $SKIPPED (doublons)"
echo "Lignes en erreur : $ERRORS"

# Derniere commande : son resultat devient le code de sortie du script (0 = aucune erreur)
[ "$ERRORS" -eq 0 ]
