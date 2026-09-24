# Déployer Kubernetes avec AWS EKS

AWS EKS fournit un control-plane Kubernetes managé.
Terraform crée le cluster EKS et ses workers.

```text
Terraform → EKS → Kubernetes
```

Ici, vous ne construisez pas le cluster : AWS fournit le control-plane, vous choisissez
seulement les workers. Comparaison avec les modes kubeadm : [modes.md](modes.md#kubeadm-ou-eks-).

> **AWS EKS utilise de vraies ressources payantes.**
> Quand le TP est terminé : `make destroy MODE=terraform PROVIDER=eks`

## Ce que vous allez obtenir

- un control-plane Kubernetes 1.36 fourni et opéré par AWS (aucune VM à gérer)
- 2 workers : des instances EC2 `t3.medium` dans un Managed Node Group
- un réseau dédié (VPC, deux sous-réseaux publics dans deux zones)
- une API Kubernetes accessible uniquement depuis votre adresse IP publique

## Prérequis

- un compte AWS, avec le droit de créer un VPC, des rôles IAM et un cluster EKS
- des identifiants AWS configurés (étape 2)
- Terraform et `kubectl`
- AWS CLI version 2 : `kubectl` l'utilise pour s'authentifier auprès d'EKS

## 1. Vérifier votre machine

```bash
make doctor MODE=terraform PROVIDER=eks
```

## 2. Configurer

Vos identifiants AWS, une seule fois :

```bash
aws configure
```

Vous avez plusieurs profils ? Indiquez celui à utiliser :
`AWS_PROFILE=default make doctor MODE=terraform PROVIDER=eks`.

Les réglages par défaut (région Paris `eu-west-3`, workers `t3.medium`) conviennent. Pour les
changer :

```bash
cp terraform/providers/eks/terraform.tfvars.example \
   terraform/providers/eks/terraform.tfvars
```

```hcl
aws_region          = "eu-west-3"
node_instance_types = ["t3.medium"]
```

## 3. Déployer

```bash
make doctor MODE=terraform PROVIDER=eks
make deploy MODE=terraform PROVIDER=eks
```

`doctor` vérifie aussi vos identifiants (`aws sts get-caller-identity`). `deploy` affiche le
plan Terraform et **demande confirmation** avant de créer quoi que ce soit. Comptez 15 à 20
minutes.

## 4. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"

kubectl get nodes
kubectl get pods -A
```

Le contexte kubectl de ce cluster s'appelle `k8s-lab-eks`. Dans `kube-system`, aucun Pod du
control-plane (etcd, API server…) : ils tournent chez AWS.

## 5. Tester

```bash
make test
```

## 6. Supprimer

```bash
make destroy MODE=terraform PROVIDER=eks
```

La commande demande confirmation, puis supprime tout ce que le lab a créé : cluster, workers,
rôles IAM, VPC. Comptez 10 à 15 minutes. `make status` doit ensuite afficher « aucun cluster ».

## En cas de problème

| Symptôme | Solution |
| --- | --- |
| `doctor` : aucun identifiant AWS valide | `aws configure`, ou `AWS_PROFILE=<profil>` ; vérifiez avec `aws sts get-caller-identity` |
| `AccessDenied`, `not authorized to perform` | votre identité AWS doit pouvoir créer VPC, IAM, EKS et EC2 : demandez ces droits |
| `kubectl` : délai dépassé (`i/o timeout`) | votre adresse IP publique a changé : relancez `make deploy MODE=terraform PROVIDER=eks` |
| `kubectl` : `You must be logged in to the server` | utilisez les mêmes identifiants AWS que pour le déploiement (même `AWS_PROFILE`) |
| `doctor` : version non proposée par EKS | changez `EKS_KUBERNETES_VERSION` dans `.env` (versions proposées : voir plus bas) |
| `destroy` refuse : Services LoadBalancer | supprimez-les d'abord : `kubectl delete service -n <namespace> <nom>` |

Plus de cas : [troubleshooting.md](troubleshooting.md).

## Pour aller plus loin

### Ce que crée Terraform

Tout est dans `terraform/providers/eks/main.tf` :

- un **VPC**, deux **sous-réseaux publics** (deux zones, minimum exigé par EKS), une passerelle
  Internet ; pas de NAT, pour rester simple et moins cher ;
- deux **rôles IAM** : celui du control-plane (`AmazonEKSClusterPolicy`) et celui des workers
  (`AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKS_CNI_Policy`) ;
- le **cluster EKS** : API publique limitée à votre IP, accès privé pour les workers ;
- les **addons** gérés par AWS : `vpc-cni` (réseau des Pods), `kube-proxy`, `coredns`, dans la
  version recommandée par AWS pour la version de Kubernetes du cluster ;
- le **Managed Node Group** : `WORKER_COUNT` workers (Amazon Linux 2023), entre 1 et
  `WORKER_COUNT + 2`.

Le groupe de sécurité du cluster est créé par EKS lui-même. En production, AWS recommande
des sous-réseaux privés et un rôle IAM dédié au réseau des Pods (Pod Identity ou IRSA).

### Réglages

| Où | Réglage | Défaut |
| --- | --- | --- |
| `.env` | `WORKER_COUNT` (ou `WORKERS=3` au déploiement) | `2` |
| `.env` | `EKS_KUBERNETES_VERSION` | `1.36` |
| `terraform.tfvars` | `aws_region` (sinon `AWS_REGION`) | `eu-west-3` |
| `terraform.tfvars` | `node_instance_types` (types x86_64) | `["t3.medium"]` |
| `terraform.tfvars` | `node_capacity_type` (`SPOT` : moins cher, instances reprises par AWS) | `ON_DEMAND` |
| `terraform.tfvars` | `api_allowed_cidrs` (qui peut joindre l'API) | votre IP publique, détectée |

### Versions de Kubernetes

EKS a son propre calendrier : chaque version y est proposée quelques semaines après sa sortie,
puis supportée 14 mois (support standard). Le lab utilise donc `EKS_KUBERNETES_VERSION`
(1.36), distincte de `KUBERNETES_VERSION` des modes kubeadm (1.37). Liste à jour :
<https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html>. Le cluster est
configuré pour être mis à jour par AWS en fin de support standard plutôt que de passer en
support étendu, facturé en supplément.

### Coûts

Sont facturés tant qu'ils existent : le cluster EKS, les instances EC2 et leurs disques, les
adresses IPv4 publiques et le trafic réseau. Les tarifs changent : consultez
<https://aws.amazon.com/eks/pricing/>. Toutes les ressources portent l'étiquette
`Project = k8s-lab`, ce qui permet de les retrouver dans la console AWS.

### Tester avec LocalStack

[LocalStack](https://docs.localstack.cloud/aws/services/eks/) émule les API AWS sur votre machine ;
son EKS crée un vrai petit cluster k3s dans Docker. Le **même code Terraform** l'utilise avec
`AWS_TARGET=localstack` (adresse `http://localhost:4566`, identifiants factices, uniquement
pour LocalStack).

LocalStack exige un jeton d'authentification, et EKS n'est inclus que dans les licences
Ultimate, Student (GitHub Education) ou open source : pas dans l'offre gratuite Hobby.

```bash
export LOCALSTACK_AUTH_TOKEN=<votre jeton>
docker run --rm -d --name localstack \
  -p 127.0.0.1:4566:4566 -p 127.0.0.1:4510-4559:4510-4559 \
  -e LOCALSTACK_AUTH_TOKEN \
  -v /var/run/docker.sock:/var/run/docker.sock \
  localstack/localstack:2026.08.4

AWS_TARGET=localstack make doctor MODE=terraform PROVIDER=eks
AWS_TARGET=localstack make deploy MODE=terraform PROVIDER=eks
```

Sur LocalStack, les addons EKS ne sont pas créés : k3s fournit déjà le réseau et le DNS.

### Utiliser Terraform directement

```bash
cd terraform/providers/eks
terraform init
terraform apply -var='api_allowed_cidrs=["203.0.113.10/32"]'   # votre IP publique
terraform output kubectl_command
terraform destroy -var='api_allowed_cidrs=["203.0.113.10/32"]'
```

Voir aussi [terraform.md](terraform.md).

**Statut :**

- Code Terraform (`fmt`, `validate`, TFLint, `terraform test` avec AWS simulé) : **TESTÉ EN CI**.
- Déploiement sur un vrai compte AWS : **À TESTER**, avec le workflow manuel
  `.github/workflows/eks-e2e.yml` (voir [CONTRIBUTING.md](../CONTRIBUTING.md)).
- LocalStack : **NON TESTÉ** (licence LocalStack avec EKS requise).
