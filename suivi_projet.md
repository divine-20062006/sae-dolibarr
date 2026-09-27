## Séance du 22/09/2026

**Fait :**
- Création du dépôt GitHub sae-dolibarr + structure de dossiers
- Création VM Debian 13 (VirtualBox, script VBoxManage automatisé)
- Configuration accès SSH à la VM
- Installation Apache, MariaDB, PHP, Docker sur la VM
- Téléchargement archive Dolibarr

**Difficultés rencontrées :**
- Problème sudo (utilisateur pas dans sudoers) → résolu via mode recovery GRUB
- Guest Additions VirtualBox échouées sur Debian 13 (pas bloquant, ignoré)

**À faire prochaine séance :**
- Installation manuelle de Dolibarr (config BDD, superadmin, module Tiers)

## Séance du 27/09/2026 (suite)

**Fait :**
- Étape 3 (Dockerisation) : création docker-compose.yml avec 2 conteneurs séparés
  (MariaDB + Dolibarr, images officielles), script install.sh maître fonctionnel
- Dolibarr Docker testé et fonctionnel sur http://localhost:8080 (en parallèle
  de l'installation native sur port 80)
- .env + .gitignore mis en place pour ne pas exposer les mots de passe sur Git
- Étape 2 (import automatisé) : script import_csv.sh créé et testé avec succès
  - Import direct en SQL dans llx_societe, contourne l'interface web
  - Test réussi : 8/8 lignes insérées, 0 erreur
  - Marquage des lignes importées via import_key='import_csv_sh' pour traçabilité
- Exploration structure table llx_societe (97 colonnes), identification des
  champs clés (nom, address, zip, town, phone, email, client, fournisseur,
  status avec défaut=1, entity avec défaut=1, fk_pays en ID numérique)

**Difficultés rencontrées :**
- Transfert de fichiers .env et .gitignore via scp : Windows supprime le point
  initial du nom de fichier au téléchargement → contournement en renommant à
  la destination avec scp
- Comprendre pourquoi le mapping web ne proposait pas de champ "Pays" direct :
  fk_pays attend un ID numérique (table de référence), pas un code texte

**À faire prochaine séance :**
- Script de sauvegarde/restauration (aspect PRA demandé dans le cahier des
  charges) : sauvegarder la base MariaDB + les volumes Docker, et vérifier
  qu'on peut repartir de zéro et tout récupérer
- Nettoyer les doublons créés lors des tests d'import (8 tiers importés deux
  fois : une fois via interface web, une fois via script)
- Continuer la documentation dans docs/
- Binôme : à faire monter en compétence sur Docker (docker-compose.yml et
  install.sh sont sur Git, prêts à être réutilisés)
