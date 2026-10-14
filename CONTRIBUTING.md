# Contribuer à Kubernetes Lab

Ce projet est un framework pédagogique **et** extensible de création et
d'exploitation de clusters Kubernetes. Les contributions sont bienvenues
pour les providers, systèmes Linux, CNI, addons, tests et guides.

**Avant une contribution :** lire [l'architecture](docs/architecture.md),
[les modes](docs/modes.md), [la matrice de compatibilité](docs/compatibility.md)
et [la politique de sécurité](SECURITY.md).

## Architecture et responsabilités

| Répertoire | Responsabilité |
| --- | --- |
| `config/lab.env`, `config/schema.yaml` | Valeurs par défaut et schéma typé |
| `config/versions.yaml` | Versions verrouillées et empreintes des artefacts |
| `config/profiles.yaml` | Profils d'addons |
| `scripts/labctl`, `scripts/labcore/` | Résolution, validation et plan |
| `k8s-lab`, `scripts/lib/`, `Makefile` | CLI, commandes et orchestration |
| `terraform/modules/`, `terraform/providers/` | Ressources d'infrastructure, sans installation kubeadm |
| `ansible/` | Préparation OS, containerd, Kubernetes, HA, opérations |
| `addons/<id>/` | Déclaration, Helm, manifestes, santé et tests |
| `tests/`, `.github/workflows/` | Validations statiques et tests d'intégration |
| `docs/`, `examples/` | Documentation et configurations sans secrets |

Chaînes d'exécution :

- Kind / Minikube : cluster local, puis addons compatibles.
- Vagrant / Terraform Proxmox, vSphere, libvirt : VM, puis Ansible/kubeadm, puis addons.
- `existing` : machines Linux préinstallées, puis Ansible/kubeadm, puis addons.
- `attach` : cluster existant, addons uniquement ; aucune prise de contrôle implicite.
- Terraform EKS : Kubernetes managé, puis addons compatibles ; aucune installation kubeadm.

## Environnement de développement

```bash
git clone https://github.com/vlaine5/k8scluster-eva.git
cd k8scluster-eva
make venv
source .venv/bin/activate
make help-dev
make test-unit
make schema-check catalog-check docs-check
```

Les tests nécessitant Docker, Kubernetes, Vagrant, Terraform ou des services
externes ont leurs propres prérequis. **Aucun test ne doit modifier un Homelab
ou créer des ressources cloud payantes sans consentement explicite.**

## Ajouter une variable

1. Décrire type, valeurs, valeurs secrètes et dépendances dans `config/schema.yaml`.
2. Ajouter le défaut documenté dans `config/lab.env`.
3. Adapter le résolveur Python si une validation ou une transformation est nécessaire.
4. Propager la valeur à Terraform/Ansible uniquement si le composant la consomme.
5. Ajouter les tests de priorité, d'erreur et de compatibilité.
6. Regénérer la documentation : `make docs-generate`, puis `make docs-check`.
7. Ajouter un exemple non secret et documenter les migrations de variable.

Ne jamais ajouter de variable qui n'a aucun effet réel.

## Ajouter un addon

Lire impérativement [le guide dédié](docs/addon-development.md).

Déclarer `addons/<id>/addon.yaml` (dépendances, plateformes, versions,
tests, santé, désinstallation), puis les valeurs Helm, les manifestes et le
test fonctionnel. Ajouter le composant dans `config/versions.yaml` et les
réglages utiles dans le schéma. Vérifier les combinaisons incompatibles
et les dépendances conditionnelles.

Un addon doit rester optionnel, sécurisé par défaut et idempotent. Les
opérations stateful doivent préserver les données et documenter leur
restauration. Ne renseigner `validated` que pour une exécution CI réelle.

## Ajouter un OS, un CNI ou un provider

- OS : compléter la matrice `config/versions.yaml`, adapter les tâches
  Ansible par famille de distribution et ajouter des tests d'installation
  réels. Ne pas supposer la compatibilité noyau ou CPU.
- CNI : adapter le rôle `ansible/roles/cni`, les CRD/Helm et les tests
  réseau ; documenter la migration, la compatibilité et les restrictions.
- Provider : isoler la création de l'infrastructure dans
  `terraform/providers/<provider>/` et réutiliser les modules communs
  lorsque applicable ; ajouter la validation et le guide dédié.

## Exigences de qualité

- **Pas de secrets dans Git** ni dans les logs, exemples ou rapports.
- Opérations destructives explicitement confirmées ; aucune écriture sur un
  NAS, pare-feu ou cluster tiers sans une action expressément demandée.
- Versions figées ; mises à jour via `config/versions.yaml`.
- Idempotence et diagnostics actionnables pour les échecs.
- ShellCheck, Ansible-lint, Terraform validate/test, tests du résolveur
  et documentation cohérente.
- Distinguer « rendu vérifié », « testé en CI sur conteneurs » et
  « testé réellement sur VM/hyperviseur ».
- Documentation et erreurs destinées aux utilisateurs en français.
- Favoriser les évolutions sans rupture ; décrire les breaking changes
  dans `CHANGELOG.md` et `docs/migration.md`.

Commandes selon le périmètre :

```bash
make lint
make addons-render-check
make test-unit
make check-config
make docs-check
make deploy MODE=kind
make test
make destroy MODE=kind YES=1
```

Lire les avertissements de [sécurité](docs/security.md) avant les essais.

## Pull requests et releases

Créer une branche, proposer des commits courts (Conventional Commits :
`feat(scope):`, `fix(scope):`, `docs:`, `test:`, `ci:`) et
ouvrir une PR. Remplir le modèle : modes affectés, tests effectués,
risques de migration, état réel de validation. Ne pas fusionner avec des
tests essentiels rouges.

Une **CI verte** ne certifie pas automatiquement le fonctionnement sur
Proxmox, vSphere ou une machine physique. Une version stable nécessite des
tests représentatifs documentés. Mettre à jour `CHANGELOG.md` et
la documentation de migration avant de publier une release.
