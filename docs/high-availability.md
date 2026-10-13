# Haute disponibilité du control-plane

```bash
CONTROL_PLANE_COUNT=3        # 1, 3 ou 5 (jamais pair)
HA_MODE=auto                 # stacked-etcd dès 3 control-planes
API_LB_PROVIDER=auto         # kube-vip (VIP portée par les control-planes)
CONTROL_PLANE_VIP=10.20.0.99 # IP libre du réseau des nœuds, hors DHCP et hors pool LoadBalancer
```

## Topologie

```text
                 kubectl / kubelets / Cilium
                           │
                VIP 10.20.0.99:6443 (kube-vip, ARP)
           ┌───────────────┼───────────────┐
      k8s-cp-1         k8s-cp-2         k8s-cp-3
   apiserver+etcd   apiserver+etcd   apiserver+etcd     ← etcd « empilé » (stacked)
           └───────────────┼───────────────┘
              workers : k8s-worker-1..N
```

- **etcd empilé** : un membre etcd par control-plane. Quorum = ⌊n/2⌋+1 : 3 control-planes
  tolèrent 1 panne, 5 en tolèrent 2. Un nombre pair n'apporte rien (4 tolère 1 panne, comme
  3) : refusé. `HA_MODE=external-etcd` est refusé (non implémenté).
- **kube-vip** (pod statique sur chaque control-plane) porte la VIP par élection de leader et
  l'annonce en ARP. Elle sert **uniquement** l'API Kubernetes ; les Services `LoadBalancer`
  sont servis par MetalLB ou Cilium. La VIP n'est jamais devinée sur un réseau réel : elle
  est obligatoire (`CONTROL_PLANE_VIP`). Seul Vagrant en choisit une
  (`VAGRANT_NETWORK_PREFIX.(VAGRANT_IP_START-1)`).
- `API_LB_PROVIDER=external` + `CONTROL_PLANE_ENDPOINT=lb.example.lan:6443` : votre propre
  répartiteur (HAProxy...), non géré par le lab.

## Installation

1. `kubeadm init` sur `k8s-cp-1` avec `controlPlaneEndpoint` = VIP (kube-vip démarre avant,
   avec `super-admin.conf`, puis bascule sur `admin.conf`) ;
2. `kubeadm init phase upload-certs` : clé de certificats (chiffrée, valable 2 h) ;
3. chaque autre control-plane rejoint **un par un** (`--control-plane --certificate-key`),
   santé etcd vérifiée avant et après chaque ajout ;
4. vérifications : nombre de membres etcd = nombre de control-planes, API joignable par la VIP.

Une machine qui appartient à un autre cluster est refusée. Ajouter un control-plane à un
cluster mono-control-plane **existant** n'est possible que s'il a été créé avec un endpoint
stable (VIP) : `controlPlaneEndpoint` ne se change pas après coup.

## HA « logicielle » sur un seul hyperviseur

Trois VMs control-plane sur **un seul** Proxmox survivent à la perte d'une VM, pas à celle
de l'hôte, de son stockage ou de son réseau : le résolveur l'indique. Pour une HA physique :
`proxmox_nodes = ["pve1", "pve2", "pve3"]` (Proxmox), règle d'anti-affinité DRS (vSphere,
automatique), ou machines distinctes (mode existing).

## Tests

- CI : 3 control-planes + 1 worker, Cilium sans kube-proxy, VIP kube-vip, sur des nœuds
  conteneurs (`tests/kubeadm-in-docker`).
- Exercice manuel de panne : arrêter un control-plane, vérifier `kubectl get nodes` par la
  VIP et `make health`, redémarrer, vérifier le retour du membre etcd.
- Retrait d'un control-plane : `make node-remove NODE=k8s-cp-3` (refusé si le quorum etcd
  ne serait plus garanti).
