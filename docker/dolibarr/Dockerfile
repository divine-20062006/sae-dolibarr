# ==========================================================
# SAE51 - Image Dolibarr personnalisee
# ==========================================================
# Base : image officielle Dolibarr, dont la version est un
# parametre (docker-compose.yml / .env : DOLIBARR_VERSION).
# On y ajoute la configuration du projet : module Tiers active
# a l'installation, France, fuseau horaire Europe/Paris.
# ==========================================================

ARG DOLIBARR_VERSION=latest
FROM dolibarr/dolibarr:${DOLIBARR_VERSION}

LABEL org.opencontainers.image.title="SAE51 - Dolibarr" \
      org.opencontainers.image.description="Dolibarr pre-configure pour le POC SAE51 (gestion des Tiers)"

# Valeurs par defaut, surchargeables depuis docker-compose.yml.
# DOLI_ENABLE_MODULES et DOLI_COMPANY_* ne s'appliquent qu'a
# l'initialisation (premiere installation sur une base vide).
ENV DOLI_ENABLE_MODULES=Societe \
    DOLI_COMPANY_NAME=Mervie \
    DOLI_COMPANY_COUNTRYCODE=FR \
    PHP_INI_DATE_TIMEZONE=Europe/Paris
