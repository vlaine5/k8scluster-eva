# Historique consolidé avant le premier déploiement du homelab

Le dépôt conserve **une branche active : `master`**. Les anciennes branches ont
été intégrées **dans l'historique Git** par un commit à plusieurs parents dont
l'arbre est celui de `master`. Cela conserve les anciennes révisions
accessibles avec Git, **sans remettre leurs anciens fichiers dans la version
à déployer**.

| Ancienne branche | Ancien commit | Décision |
| --- | --- | --- |
| `feature/node-ip-subnet` | `512b2fc02fc256fe611637f3483ece8bf9853613` | Fonctionnalité intégrée par PR #10 |
| `docs/pv05-first-deploy-2026` | `26ff9549f68ed0e2e77ea582649366a4c76f44fc` | Documentation intégrée par PR #11 |
| `test/proxmox-plan-readonly` | `fee2ee77066c8f01648ef8506ba66c1babdac4f6` | Tests intégrés par PR #12 |
| `feat/bootstrap-gitops-vm` | `4fb937f01e57f0b0238bdbf7aae5806bbe4ffb57` | Script déjà présent sur master |
| `claude/charming-brown-owrjlw` | `de72265fa9da6053da8a4d2ea726600432148bcb` | État antérieur du framework |
| `claude/clever-cerf-qctq59` | `541276735334fe058c13e0ae4581c2e787361cba` | Ancienne implémentation (dont EKS) |
| `refacto/kube` | `5393eb8703e1e8ac8abcf0d1a965f6066e240fa0` | Ancien code de 2022, **non déployé** |

## Pourquoi ne pas copier tous les fichiers dans master ?

Le code des anciennes branches n'est pas nécessairement compatible avec
l'architecture actuelle : reprendre directement les anciens rôles Ansible
ou leurs inventaires écraserait le framework récent. Les branches
fonctionnelles ont déjà été intégrées par leurs PR ; les autres révisions
sont préservées **uniquement dans l'historique** pour consultation.

Il est possible d'inspecter un ancien état sans modifier `master` :

```bash
git show 5393eb8703e1e8ac8abcf0d1a965f6066e240fa0:README.md
git log --graph --all --oneline --decorate
```

Pour recréer une branche historique en local :

```bash
git branch archive/kube-2022 5393eb8703e1e8ac8abcf0d1a965f6066e240fa0
```

L'opération de nettoyage GitHub supprime **les références distantes** des
anciennes branches après vérification de leurs SHA et de leur présence
dans l'ascendance de `master`. Elle ne détruit ni les fichiers
`.env`, ni `terraform.tfvars`, ni l'état Terraform local.
