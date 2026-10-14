# Journal des changements

Les changements notables sont documentés ici. Le projet vise le
[versionnement sémantique](https://semver.org/lang/fr/) pour ses versions
publiées. Les modifications internes du catalogue, des schémas ou des
variables qui changent les comportements de déploiement doivent être
signalées explicitement.

## [Non publié]

### Ajouté

- Configuration validée par schéma, catalogue déclaratif d'addons et profils.
- Modes `existing` (machines Linux déjà installées) et `attach` (cluster
  Kubernetes existant).
- Choix du système d'exploitation, du CNI et de la topologie du control-plane.
- Choix des contrôleurs Gateway API, des LoadBalancers et des backends de
  stockage NFS CSI / Longhorn.
- Commandes de diagnostic, de maintenance, de sauvegarde et de mise à niveau.
- Tests CI pour plusieurs scénarios Kubernetes locaux et documentation par mode.
- Fichiers de gouvernance : politique de sécurité, modèles de contribution,
  suivi des changements.

### Modifié

- Le Kubernetes par défaut de la refonte passe à `1.36.5` pour la matrice de
  compatibilité du catalogue ; `1.37.1` reste configurable.
- Les versions verrouillées sont centralisées dans `config/versions.yaml`.
- Les paramètres locaux continuent de se définir dans `.env`.

### À valider avant la première version stable

- Exécution réelle des providers Proxmox, vSphere, libvirt et EKS sur une
  infrastructure de test autorisée (la CI n'en valide actuellement que le code).
- Provisionnement des disques Longhorn et tests de récupération sur de vraies VM.
- Restauration complète d'applications stateful et sauvegardes hors site.
- Scénario complet de déploiement sur `pv05` avec les IP, DNS et exports NFS
  vérifiés.

**État :** la PR de refonte est une proposition de version candidate, et non
une garantie de compatibilité sur tout matériel. Ne pas publier un tag stable
avant les validations critiques ci-dessus.

## Politique de publication

1. Préparer une PR avec le changement et les migrations nécessaires.
2. Vérifier les tests statiques, les tests d'intégration et le rendu des addons.
3. Vérifier les matrices de compatibilité et les limites non testées.
4. Documenter les ruptures de compatibilité et le chemin de mise à niveau.
5. Publier une version candidate (`v1.0.0-rc.1`) avant `v1.0.0` lorsque le
   premier déploiement Proxmox réel aura été validé.
6. Utiliser des tags Git annotés et des notes de version reliées à ce journal.

Voir également [le guide de migration](docs/migration.md) et
[les mises à jour](docs/upgrades.md).
