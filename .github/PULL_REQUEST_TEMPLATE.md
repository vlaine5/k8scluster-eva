## Objectif

Décrire le problème traité, la solution et les limites du changement.

## Périmètre

- Mode(s) : kind / minikube / vagrant / terraform (provider à préciser) / existing / attach.
- OS : Ubuntu / Debian / Rocky / non concerné.
- Composants : réseau / stockage / addons / kubeadm / CI / documentation / autre.
- Variables du \`.env\` ajoutées ou modifiées (sans valeurs secrètes).

## Validations

- [ ] \`make validate\`, \`make schema-check\`, \`make catalog-check\`.
- [ ] \`make lint\` (ou justification des contrôles non exécutables).
- [ ] Tests unitaires et tests d'intégration pertinents.
- [ ] Documentation et exemples mis à jour.
- [ ] Matrice de compatibilité fidèle aux **tests réellement effectués**.
- [ ] Aucune donnée sensible dans les commits, captures ou logs.
- [ ] Pas de modification/destruction de ressource existante sans plan et confirmation.

## Tests réels et risques

Décrire les commandes exécutées et résultats obtenus ; distinguer explicitement
les tests de CI en conteneurs des déploiements réels sur hyperviseur.

- Risque de remplacement/destruction de VM, disques, PVC ou sauvegardes :
- Plan de retour en arrière ou procédure de reprise :
- Tests et plateformes **non** validés :

## Publication

- [ ] \`CHANGELOG.md\` mis à jour si le comportement utilisateur change.
- [ ] Guide de migration ajouté si une configuration existante est impactée.
- [ ] Aucune dépendance imposée inutilement aux profils légers.
