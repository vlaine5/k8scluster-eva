# Contribuer

Ce dépôt est un **laboratoire Kubernetes pédagogique** destiné à des étudiants francophones.
Il propose trois façons d'obtenir un cluster :

- **Kubernetes local** : Kind, Minikube ;
- **Kubernetes construit avec kubeadm** : Vagrant ou Terraform (Proxmox, vSphere, libvirt)
  créent des VMs, puis Ansible installe Kubernetes avec kubeadm ;
- **Kubernetes managé dans le cloud** : Terraform crée un cluster AWS EKS (control-plane géré
  par AWS, Managed Node Group), sans Ansible ni kubeadm.

Toute contribution doit préserver ces trois voies et leur rôle pédagogique.

## Architecture

```text
config/lab.env (+ .env) ──> ./k8s-lab (Bash) ──> kind | minikube | vagrant | terraform <provider>

vagrant, terraform proxmox|vsphere|libvirt
    → VMs + inventaire Ansible généré → ansible/site.yml (kubeadm, commun)

terraform eks
    → VPC + IAM + EKS + Managed Node Group → kubeconfig (aws eks update-kubeconfig)
```

- `k8s-lab` + `scripts/lib/*.sh` : le CLI. `Makefile` : raccourcis **sans logique**.
- `config/lab.env` : source unique des réglages. Terraform (`variables.tf`) et Ansible
  (`group_vars/all.yml`) en gardent des copies des valeurs par défaut pour rester utilisables
  seuls ; `scripts/check-config-sync.sh` vérifie qu'elles sont identiques.
- `terraform/modules/k8s-nodes` (nœuds, IP, cloud-init) et `terraform/modules/ansible-inventory`
  sont communs aux providers « VMs » ; `terraform/providers/<proxmox|vsphere|libvirt>/` ne fait
  **que** créer les VMs.
- `terraform/providers/eks/` est autonome : il crée un cluster managé, pas des VMs, et
  n'utilise donc ni ces modules ni Ansible. Le même code cible AWS ou LocalStack
  (`aws_target`).
- `vagrant/Vagrantfile` lit `config/lab.env` + `.env` et écrit `ansible/inventories/vagrant.ini`.
- `ansible/` : **seul** endroit où Kubernetes est installé pour les modes kubeadm (rôles
  `common`, `container_runtime`, `kubernetes`, `control_plane`, `cni`, `worker`).

## Règles

1. **Pas de duplication.** Toute logique indépendante de la plateforme va dans
   `terraform/modules/`. Aucune logique Kubernetes dans Terraform ou Vagrant pour les modes
   kubeadm. EKS n'a pas d'inventaire Ansible et n'utilise pas kubeadm.
2. **Pas de secret dans Git.** Identifiants via variables d'environnement (`.env`, ignoré) ou
   les mécanismes standards (profils AWS). Variables Terraform sensibles : `sensitive = true`.
   Jamais de mot de passe en dur, jamais de `0777`, jamais de `curl | bash`.
3. **Rien de destructif implicitement.** `deploy` est idempotent ; seule `destroy` (ou
   `--recreate`) détruit, après confirmation.
4. **Rien de payant sans action explicite.** Aucune CI automatique (push, pull request) ne crée
   de ressource AWS réelle ; le workflow EKS réel est déclenché à la main.
5. **Versions explicites et vérifiées** : pas de `latest`, pas de branche `master` ; checksum
   ou digest quand c'est possible. Vérifier les versions actuelles en ligne avant de les
   changer (voir `docs/maintenance.md`), et mettre à jour toutes les copies.
6. **Ansible idempotent** : modules dédiés plutôt que `command`/`shell` ; sinon `creates`,
   `removes` ou `changed_when`. Pas d'`ignore_errors`. FQCN (`ansible.builtin.*`).
   Variables de rôle préfixées par le nom du rôle.
7. **Pédagogie** : messages d'erreur « quoi / pourquoi / comment corriger » (fonction `die`),
   commandes exécutées affichées (fonction `run`), commentaires et documentation en français,
   noms de variables et de fonctions en anglais. Préférer la simplicité à la généricité.
8. **Honnêteté sur la validation** : ne jamais présenter comme testé ce qui ne l'a été que
   statiquement. Vagrant, Proxmox, vSphere, libvirt et EKS nécessitent une infrastructure
   réelle ; `terraform validate` ne prouve pas qu'un cluster fonctionne.
9. **Bash compatible 3.2** (macOS) : pas de tableaux associatifs, de `mapfile` ni de `${var,,}`.
10. **Documentation à deux niveaux.** Guides étudiants courts (`README.md`,
    `docs/deployment.md`, `docs/deploy-<mode>.md`) : commandes `make` uniquement et structure
    fixe (Ce que vous allez obtenir, Prérequis, 1. Vérifier votre machine, 2. Configurer,
    3. Déployer, 4. Vérifier, 5. Tester, 6. Supprimer, En cas de problème, Pour aller plus
    loin). Le détail technique va dans `docs/architecture.md`, `ansible-kubeadm.md`,
    `configuration.md`, `security.md`, `troubleshooting.md`, sans duplication.

## Vérifier ses changements

```bash
make lint                 # contrôles statiques de la CI (make help-dev : liste des cibles)
make vagrant-validate     # vagrant validate sans hyperviseur (lancé aussi en CI ; Vagrant requis)
make actionlint           # workflows GitHub Actions (lancé aussi en CI ; actionlint requis)
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

## Tester EKS pour de vrai (workflow manuel)

Aucune CI automatique ne crée de ressource AWS. Le workflow `.github/workflows/eks-e2e.yml` se
lance uniquement à la main (onglet *Actions* → « EKS E2E (manuel) » → *Run workflow*) ; il
exécute `make doctor`, `make deploy`, `kubectl get nodes`, `make test`, puis `make destroy`,
même en cas d'échec.

- `target = localstack` : secret de dépôt `LOCALSTACK_AUTH_TOKEN`, d'une licence LocalStack
  qui inclut EKS (Ultimate, Student ou open source).
- `target = aws` (**payant**) : variable de dépôt `AWS_ROLE_ARN`, un rôle IAM que GitHub
  assume par OIDC (aucune clé d'accès stockée) et qui peut créer VPC, IAM, EKS et EC2 ;
  variable facultative `AWS_REGION` ; case `confirm_aws_costs` à cocher. Guide OIDC :
  <https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services>

Le cluster de test s'appelle `k8s-lab-ci`. Les journaux d'un dépôt public sont publics :
l'identifiant du compte AWS y apparaît (dans les ARN).

## Ajouter…

- **un provider Terraform « VMs »** : `terraform/providers/<nom>/` appelant les deux modules
  communs, puis `scripts/lib/mode_terraform.sh`, `scripts/lib/doctor.sh`, `TF_DIRS` du
  Makefile, un guide `docs/deploy-<nom>.md`, `docs/deployment.md` et le tableau du README.
- **un CNI** : `ansible/roles/cni/tasks/<nom>.yml` + liste dans `roles/cni/tasks/main.yml`.
- **un réglage** : `config/lab.env` (commenté) → transmis par le CLI (`TF_VAR_*` ou
  `ansible_write_vars`) → copie de la valeur par défaut → `scripts/check-config-sync.sh` →
  `docs/configuration.md`.

## Commits et pull requests

- Messages au format Conventional Commits : `feat(terraform): …`, `fix(ansible): …`,
  `docs: …`, `ci: …`.
- Une pull request est fusionnée quand toute la CI est verte.
