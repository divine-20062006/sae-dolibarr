Séance du 22/09/2026

Fait :

Création du dépôt GitHub sae-dolibarr + structure de dossiers
Création VM Debian 13 (VirtualBox, script VBoxManage automatisé)
Configuration accès SSH à la VM
Installation Apache, MariaDB, PHP, Docker sur la VM
Téléchargement archive Dolibarr

Difficultés rencontrées :

Problème sudo (utilisateur pas dans sudoers) → résolu via mode recovery GRUB
Guest Additions VirtualBox échouées sur Debian 13 (pas bloquant, ignoré)

À faire prochaine séance :

Installation manuelle de Dolibarr (config BDD, superadmin, module Tiers)
Séance du 27/09/2026 (suite)

Fait :

Étape 3 (Dockerisation) : création docker-compose.yml avec 2 conteneurs séparés (MariaDB + Dolibarr, images officielles), script install.sh maître fonctionnel
Dolibarr Docker testé et fonctionnel sur http://localhost:8080 (en parallèle de l'installation native sur port 80)
.env + .gitignore mis en place pour ne pas exposer les mots de passe sur Git
Étape 2 (import automatisé) : script import_csv.sh créé et testé avec succès
Import direct en SQL dans llx_societe, contourne l'interface web
Test réussi : 8/8 lignes insérées, 0 erreur
Marquage des lignes importées via import_key='import_csv_sh' pour traçabilité
Exploration structure table llx_societe (97 colonnes), identification des champs clés (nom, address, zip, town, phone, email, client, fournisseur, status avec défaut=1, entity avec défaut=1, fk_pays en ID numérique)

Difficultés rencontrées :

Transfert de fichiers .env et .gitignore via scp : Windows supprime le point initial du nom de fichier au téléchargement → contournement en renommant à la destination avec scp
Comprendre pourquoi le mapping web ne proposait pas de champ "Pays" direct : fk_pays attend un ID numérique (table de référence), pas un code texte

À faire prochaine séance :

Script de sauvegarde/restauration (aspect PRA demandé dans le cahier des charges) : sauvegarder la base MariaDB + les volumes Docker, et vérifier qu'on peut repartir de zéro et tout récupérer
Nettoyer les doublons créés lors des tests d'import (8 tiers importés deux fois : une fois via interface web, une fois via script)
Continuer la documentation dans docs/
Binôme : à faire monter en compétence sur Docker (docker-compose.yml et install.sh sont sur Git, prêts à être réutilisés)
Séance du 28/09/2026

Fait :

Création de backup.sh : dump SQL (mariadb-dump) + archive des volumes Dolibarr (documents + conf.php)
Création de restore.sh : suppression complète de la stack, reconstruction depuis une sauvegarde
Test PRA validé : tiers "Client PRA" créé, sauvegarde, tiers "Apres sauvegarde" créé, restauration complète -> "Client PRA" présent, "Apres sauvegarde" absent
backups/ ajouté au .gitignore (données réelles, ne pas versionner)

À faire :

Adapter import_csv.sh à la base Docker (elle pointe pour l'instant sur MariaDB en local)
Compléter la documentation dans docs/ et le readme.md (procédure d'installation pour le binôme)
Tester la procédure complète depuis zéro sur une VM vierge (git clone, .env, install.sh, restore.sh)
Séance du 06/10/2026 - Test de reproductibilité (Lody)

Fait :

Test complet du projet sur une machine vierge (laptop Ubuntu 24.04, sans Docker au départ), en suivant la procédure de test rédigée par Divine
Installation de Docker via le script officiel (get.docker.com), clone du dépôt, création du .env
install.sh : installation réussie, Dolibarr 24.0.1 accessible sur http://localhost:8080
Menu Tiers présent sans action manuelle, pays France configuré
import_csv.sh : 8/8 lignes insérées, 0 erreur ; pays correctement converti (France)
Second lancement de l'import : aucun doublon créé (vérifié en base)
Test PRA validé : "Test Mervedi 1" créé, sauvegarde, "Test Mervedi 2" créé, restauration -> "Test Mervedi 1" présent, "Test Mervedi 2" absent, 9 tiers au total
La restauration récupère aussi la configuration (module Fournisseurs toujours actif)

Anomalies constatées :

Les tiers uniquement fournisseurs (Martin Fournitures, Petit Transport, Bernard Metallerie) sont bien en base mais invisibles dans l'interface : le module Fournisseurs n'est pas activé au démarrage. Activé à la main pendant le test, les 8 tiers sont alors visibles.
DOLIBARR_VERSION=latest : le test a installé la 24.0.1 alors que la version testée précédemment était la 24.0.0. Deux installations à quelques jours d'écart n'ont pas la même version, ce qui pose problème pour une restauration.
files.tgz fait 80 Mo (contre 816 Ko pour la base) : le volume dolibarr_html archive tout le code de Dolibarr. Le fichier appartient à root (créé depuis un conteneur).
Les tiers importés par script n'ont pas de code client, contrairement à ceux créés via l'interface (CU2610-00001) : limite connue de l'import SQL direct.
Avertissement Docker Compose : attribut version obsolète dans docker-compose.yml.

À faire :

Ajouter le module Fournisseurs au Dockerfile : DOLI_ENABLE_MODULES=Societe,Fournisseur
Figer la version dans .env.example : DOLIBARR_VERSION=24.0.1
Retirer la ligne version: '3.8' du docker-compose.yml
Étudier la réduction de la sauvegarde aux seuls fichiers utiles (documents + conf.php)
