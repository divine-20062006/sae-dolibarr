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
