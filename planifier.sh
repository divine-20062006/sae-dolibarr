#!/bin/bash
# planifier.sh - programme une sauvegarde automatique (qui inclut l'export CSV des Tiers) avec cron
# Usage : ./planifier.sh                   (tous les jours a 02h00)
#         ./planifier.sh "30 1 * * *"      (autre horaire, syntaxe cron : minute heure jour mois jour_semaine)

set -e  # arrete le script des qu'une commande echoue

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # dossier absolu du projet
SCHEDULE="${1:-0 2 * * *}"                                    # horaire donne en argument, sinon 2h du matin

# cron doit etre installe
if ! command -v crontab &> /dev/null; then
    echo "ERREUR : cron n'est pas installe. Installe-le avec : sudo apt install -y cron"
    exit 1
fi

mkdir -p "$SCRIPT_DIR/backups"  # dossier qui recevra les sauvegardes et le journal

# Ligne ajoutee a la table cron : se place dans le projet, lance la sauvegarde, ecrit le resultat dans un journal
LINE="$SCHEDULE cd $SCRIPT_DIR && bash ./backup.sh >> $SCRIPT_DIR/backups/backup.log 2>&1"

# On relit la table cron actuelle, on en retire toute ancienne ligne "backup.sh" (pour ne pas avoir de doublon),
# puis on ajoute la nouvelle ligne et on reinstalle le tout. "|| true" evite l'arret si la table est vide.
{ crontab -l 2>/dev/null | grep -v "backup.sh" || true; echo "$LINE"; } | crontab -

echo "Sauvegarde automatique planifiee ($SCHEDULE). Table cron actuelle :"
crontab -l | grep "backup.sh"
echo "Journal : $SCRIPT_DIR/backups/backup.log"
