# CLAUDE.md — guide pour les sessions Claude Code

Ce dépôt est un **laboratoire Kubernetes pédagogique** (public : étudiants francophones).
Il crée un cluster de plusieurs façons : Kind, Minikube, Vagrant + Ansible + kubeadm,
Terraform (Proxmox, vSphere, libvirt) + Ansible + kubeadm.

## Architecture (à respecter)

```text
config/lab.env (+ .env) ──> ./k8s-lab (Bash) ──> kind | minikube | vagrant | terraform
                                                            │            │
                                              inventaire Ansible généré  │
                                                            └─────┬──────┘
                                                                  ▼
                                               ansible/site.yml (kubeadm, commun)
```

- `k8s-lab` + `scripts/lib/*.sh` : le CLI. `Makefile` : raccourcis **sans logique**.
- `config/lab.env` : source unique des réglages. Terraform (`variables.tf`) et Ansible
  (`group_vars/all.yml`) en gardent des copies des valeurs par défaut pour rester utilisables
  seuls ; `scripts/check-config-sync.sh` vérifie qu'elles sont identiques.
- `terraform/modules/k8s-nodes` (nœuds, IP, cloud-init) et `terraform/modules/ansible-inventory`
  sont communs ; `terraform/providers/<p>/` ne fait **que** créer les VMs.
- `vagrant/Vagrantfile` lit `config/lab.env` + `.env` et écrit `ansible/inventories/vagrant.ini`.
- `ansible/` : **seul** endroit où Kubernetes est installé (rôles `common`,
  `container_runtime`, `kubernetes`, `control_plane`, `cni`, `worker`).

## Règles

1. **Pas de duplication entre providers.** Toute logique indépendante de la plateforme va dans
   `terraform/modules/`. Aucune logique Kubernetes dans Terraform ou Vagrant.
2. **Pas de secret dans Git.** Identifiants via variables d'environnement (`.env`, ignoré).
   Variables Terraform sensibles : `sensitive = true`. Jamais de mot de passe en dur, jamais de
   `0777`, jamais de `curl | bash`.
3. **Rien de destructif implicitement.** `deploy` est idempotent ; seule `destroy` (ou
   `--recreate`) détruit, après `confirm`.
4. **Versions explicites et vérifiées** : pas de `latest`, pas de branche `master` ; checksum
   ou digest quand c'est possible. Vérifier les versions actuelles en ligne avant de les
   changer (voir `docs/maintenance.md`), et mettre à jour toutes les copies.
5. **Ansible idempotent** : modules dédiés plutôt que `command`/`shell` ; sinon `creates`,
   `removes` ou `changed_when`. Pas d'`ignore_errors`. FQCN (`ansible.builtin.*`).
   Variables de rôle préfixées par le nom du rôle.
6. **Pédagogie** : messages d'erreur « quoi / pourquoi / comment corriger » (fonction `die`),
   commandes exécutées affichées (fonction `run`), commentaires et documentation en français,
   noms de variables/fonctions en anglais. Préférer la simplicité à la généricité.
7. **Honnêteté sur la validation** : ne jamais présenter comme testé ce qui ne l'a été que
   statiquement (Proxmox, vSphere, libvirt, Vagrant nécessitent une infrastructure réelle).
8. Bash compatible 3.2 (macOS) : pas de tableaux associatifs, `mapfile`, `${var,,}`.
9. **Documentation à deux niveaux.** Guides étudiants courts (`README.md`,
   `docs/deployment.md`, `docs/deploy-<mode>.md`) : commandes `make` uniquement et structure
   fixe (Ce que vous allez obtenir, Prérequis, 1. Vérifier votre machine, 2. Configurer,
   3. Déployer, 4. Vérifier, 5. Tester, 6. Supprimer, En cas de problème, Pour aller plus
   loin). Le détail technique va dans `docs/architecture.md`, `ansible-kubeadm.md`,
   `configuration.md`, `security.md`, `troubleshooting.md`, sans duplication.

## Commandes de test

```bash
make lint                 # contrôles statiques de la CI (make help-dev : liste des cibles)
make vagrant-validate     # vagrant validate sans hyperviseur (lancé aussi en CI ; Vagrant requis)
make shellcheck           # scripts Bash
make yamllint ansible-lint ansible-syntax
make terraform-fmt terraform-validate terraform-test tflint
make markdownlint check-docs   # style + liens, pages et commandes make cités
make check-config         # cohérence config/lab.env <-> Terraform / Ansible / kind
make deploy MODE=kind && make test && make destroy MODE=kind YES=1   # e2e (Docker, cgroup v2)
make test-kubeadm         # site.yml réel sur des nœuds conteneurs systemd + idempotence + nginx
```

Outils de lint Python : `pip install -r requirements-dev.txt` (ansible-core, ansible-lint,
yamllint) puis `ansible-galaxy collection install -r ansible/requirements.yml`.

## Ajouter…

- **un provider Terraform** : `terraform/providers/<nom>/` appelant les deux modules communs,
  puis `scripts/lib/mode_terraform.sh`, `scripts/lib/doctor.sh`, `TF_DIRS` du Makefile, un
  guide `docs/deploy-<nom>.md`, `docs/deployment.md` et le tableau du README.
- **un CNI** : `ansible/roles/cni/tasks/<nom>.yml` + liste dans `roles/cni/tasks/main.yml`.
- **un réglage** : `config/lab.env` (commenté) → transmis par le CLI (`TF_VAR_*` ou
  `ansible_write_vars`) → copie de la valeur par défaut → `scripts/check-config-sync.sh` →
  `docs/configuration.md`.

## Commits

Conventional Commits (`feat(terraform): …`, `fix(ansible): …`, `docs: …`, `ci: …`).
