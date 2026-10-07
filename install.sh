#!/bin/bash
# ==========================================================
# SAE51 - install.sh
# Script maitre d'installation de Dolibarr dockerise
# ==========================================================
# Usage : ./install.sh
# Prerequis : Docker + Docker Compose installes
# ==========================================================

set -e  # arrete le script au moindre erreur

echo "=== SAE51 - Installation Dolibarr (Docker) ==="

# Verifie que Docker est installe
if ! command -v docker &> /dev/null; then
    echo "ERREUR : Docker n'est pas installe."
    echo "Installe-le avec : curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# Verifie que Docker Compose est disponible
if ! docker compose version &> /dev/null; then
    echo "ERREUR : Docker Compose n'est pas disponible."
    exit 1
fi

# Verifie la presence du fichier .env
if [ ! -f .env ]; then
    echo "ERREUR : fichier .env introuvable."
    echo "Copie .env.example vers .env et adapte les mots de passe avant de relancer."
    exit 1
fi

echo "--- Lancement des conteneurs (MariaDB + Dolibarr) ---"
docker compose up -d

echo "--- Attente que Dolibarr soit pret (peut prendre 1-2 minutes au premier lancement) ---"
sleep 5
until docker compose logs dolibarr 2>/dev/null | grep -q "apache2 -D FOREGROUND"; do
    echo "  ... patiente, Dolibarr initialise la base de donnees ..."
    sleep 5
done

echo ""
echo "=== Installation terminee ! ==="
echo "Dolibarr est accessible sur : http://localhost:8080"
echo "Identifiant admin  : voir DOLI_ADMIN_LOGIN dans .env"
echo "Mot de passe admin : voir DOLI_ADMIN_PASSWORD dans .env"
echo ""
echo "Pour voir les logs en direct : docker compose logs -f"
echo "Pour arreter               : docker compose down"
echo "Pour tout supprimer (PRA)  : docker compose down -v"
