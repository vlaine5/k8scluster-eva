# Exploitation au quotidien

| Besoin | Commande |
| --- | --- |
| État des clusters du lab | `make status` |
| Santé d'un cluster kubeadm (etcd, certificats, services, disques) | `make health MODE=…` |
| Configuration et plan actuels | `make config MODE=…` |
| Manifeste du déploiement (versions, options, sans secret) | `make manifest MODE=…` |
| État et tests des addons | `make addons-status` / `make addons-test` |
| Instantané etcd / restauration | `make backup` / `make restore SNAPSHOT=…` |
| Mises à jour | [upgrades.md](upgrades.md) |
| Ajouter des workers | augmenter `WORKER_COUNT`, puis `make deploy` |
| Retirer un nœud | `make node-remove MODE=… NODE=k8s-worker-3` |

## Ajouter des nœuds

Les déploiements sont **idempotents** : augmenter `WORKER_COUNT` (ou ajouter des machines à
l'inventaire du mode existing) puis relancer `make deploy` crée/joint uniquement les nouveaux
nœuds. Passer de 1 à 3 control-planes n'est possible que si le cluster a été créé avec une
VIP ([high-availability.md](high-availability.md)).

## Retirer un nœud

```bash
make node-remove MODE=existing NODE=k8s-worker-3
```

Tapez le nom du nœud pour confirmer. Le playbook vérifie que le quorum etcd reste garanti
(control-plane), prend un instantané etcd, draine le nœud, lance `kubeadm reset` **sur ce
nœud uniquement**, supprime l'objet `Node`. La machine n'est jamais supprimée : réduisez
ensuite `WORKER_COUNT` (Terraform supprimera la VM au prochain `make deploy`, après
affichage du plan) ou retirez-la de l'inventaire.

## Manifeste du déploiement

Après chaque déploiement : `.lab/manifests/<contexte>.yaml` (versions effectives, options,
addons, commit Git du dépôt). Aucun secret. Utile pour comparer deux clusters ou documenter
un état.

## Santé

`make health` : santé et membres etcd, expiration des certificats kubeadm
(`kubeadm certs check-expiration`), services kubelet/containerd, espace disque `/var`,
`/readyz` de l'API.
