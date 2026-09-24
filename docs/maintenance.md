# Maintenance : mettre à jour les versions

Toutes les versions sont **explicites** (jamais `latest`, jamais une branche `master`) pour
que le lab soit reproductible d'une promotion à l'autre, et **centralisées** pour être faciles
à mettre à jour. Avant chaque session de cours, prévoyez une mise à jour puis un test.

## Versions actuelles

Vérifiées en septembre 2026, toutes épinglées dans `config/lab.env` (rien en `latest` ni `master`) :

| Composant | Version |
| --- | --- |
| Kubernetes (kubeadm, VMs) | 1.37.1 — dépôt officiel `pkgs.k8s.io` |
| Kind / image de nœud | kind v0.33.0 / `kindest/node:v1.37.0` (épinglée par digest) |
| Minikube | v1.39.0, Kubernetes v1.37.0 |
| OS des VMs | Ubuntu 24.04 LTS (image cloud datée, SHA-256 vérifié ; box `bento/ubuntu-24.04` pour Vagrant) |
| containerd | 2.3.x (paquet `containerd.io`), driver cgroup systemd, cgroup v2 |
| CNI | Flannel v0.28.9 (manifeste de release, SHA-256 vérifié) |
| Terraform | ≥ 1.9 (CI : 1.16.4) — OpenTofu compatible |
| Providers Terraform | `bpg/proxmox` 0.114, `vmware/vsphere` 2.17, `dmacvicar/libvirt` 0.9.9, `hashicorp/aws` 6.66 |
| AWS EKS | Kubernetes 1.36 (`EKS_KUBERNETES_VERSION`), workers Amazon Linux 2023, addons en version recommandée par AWS ; AWS CLI v2 |
| LocalStack (facultatif, EKS) | image `localstack/localstack:2026.08.4` |
| Ansible | ansible-core ≥ 2.18 (CI : version de `requirements-dev.txt`) |
| Vagrant | CI : 2.4.9 (`vagrant validate`) |

## Où sont les versions ?

| Composant | Fichier(s) | Source de vérité en ligne |
| --- | --- | --- |
| Kubernetes (kubeadm) | `config/lab.env` `KUBERNETES_VERSION` + `ansible/group_vars/all.yml` | <https://dl.k8s.io/release/stable.txt>, <https://kubernetes.io/releases/> |
| Image `pause` | `ansible/roles/container_runtime/defaults/main.yml` | `kubeadm config images list --kubernetes-version vX.Y.Z` |
| containerd | `config/lab.env` `CONTAINERD_VERSION` + `ansible/group_vars/all.yml` | dépôt Docker `containerd.io` |
| Flannel | `config/lab.env` `FLANNEL_VERSION` + `group_vars/all.yml` + checksum dans `ansible/roles/cni/defaults/main.yml` | <https://github.com/flannel-io/flannel/releases> |
| kind + image de nœud | `config/lab.env` `KIND_VERSION`, `KIND_NODE_IMAGE` ; `local/kind/kind-config.yaml` | notes de version de kind (liste des images avec digest) |
| Minikube | `config/lab.env` `MINIKUBE_VERSION`, `MINIKUBE_KUBERNETES_VERSION` | <https://github.com/kubernetes/minikube/releases> |
| Image Ubuntu des VMs | `config/lab.env` `VM_IMAGE_URL`, `VM_IMAGE_SHA256` + défauts des variables Terraform | <https://cloud-images.ubuntu.com/releases/noble/> (fichier `SHA256SUMS`) |
| Kubernetes sur EKS | `config/lab.env` `EKS_KUBERNETES_VERSION` + défaut de `terraform/providers/eks/variables.tf` | <https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html> |
| LocalStack | `docs/deploy-eks.md`, `.github/workflows/eks-e2e.yml` | <https://hub.docker.com/r/localstack/localstack/tags> |
| Box Vagrant | `config/lab.env` `VAGRANT_BOX` | <https://portal.cloud.hashicorp.com/vagrant/discover/bento> |
| Providers Terraform | `terraform/providers/*/versions.tf` + `.terraform.lock.hcl` | registry.terraform.io |
| Collections Ansible | `ansible/requirements.yml` | galaxy.ansible.com |
| Outils de la CI | `config/lab.env` (`KUBECTL_VERSION`, `TERRAFORM_VERSION`, `TFLINT_VERSION`, `VAGRANT_VERSION`, `ACTIONLINT_VERSION`…) ; `requirements-dev.txt` | — |
| Actions GitHub | `.github/workflows/*.yml` | Dependabot ouvre les PR |

## Procédure

1. Modifiez `config/lab.env`.
2. Reportez la même valeur dans les copies (valeurs par défaut de Terraform et d'Ansible) :
   `make check-config` liste précisément ce qui diffère.
3. Pour kind : `./k8s-lab config kind > local/kind/kind-config.yaml`.
4. Pour Flannel : ajoutez l'empreinte du nouveau manifeste
   (`curl -sSL <url>/kube-flannel.yml | sha256sum`) dans `cni_flannel_manifest_checksums`.
5. Pour un provider Terraform : changez la contrainte dans `versions.tf`, puis
   `terraform init -upgrade` dans le dossier du provider pour régénérer `.terraform.lock.hcl`.
6. `make lint`, puis un déploiement réel au moins en Kind (la CI le fait) et, si possible,
   sur une plateforme VM.

## Règles de compatibilité à respecter

- `kubectl` : au plus une version mineure d'écart avec le cluster.
- Kubernetes ≥ 1.35 exige des nœuds en **cgroup v2** et containerd **2.x**.
- L'image de nœud kind doit être publiée pour la version de kind utilisée.
- `EKS_KUBERNETES_VERSION` doit être en support standard sur EKS ; elle suit le calendrier
  d'AWS, souvent une version mineure derrière `KUBERNETES_VERSION`.
- Une nouvelle version mineure de Kubernetes change le dépôt APT (`pkgs.k8s.io/core:/stable:/v1.XX`) :
  c'est automatique, le rôle `kubernetes` le déduit de `KUBERNETES_VERSION`.
- Mettre à jour la version d'un cluster **existant** se fait avec `kubeadm upgrade`, pas en
  relançant le playbook (qui refuse, volontairement).
