# Services LoadBalancer

Sur un cloud, un Service `type: LoadBalancer` reçoit une IP publique du fournisseur. Sur
kubeadm (VMs, machines existantes) ou kind, il faut un composant qui attribue des IP d'une
plage de votre réseau et les annonce.

```bash
LOADBALANCER_PROVIDER=metallb            # none | metallb | cilium-l2 | cilium-bgp | auto (profil)
LOADBALANCER_IP_POOL=10.20.0.200-10.20.0.210
LOADBALANCER_MODE=l2                     # metallb : l2 | bgp
LOADBALANCER_INTERFACES=                 # L2 : interfaces d'annonce (regex), vide = toutes
```

| Fournisseur | Annonce | Exige |
| --- | --- | --- |
| `metallb` | L2 (ARP) ou BGP (FRR-K8s) | rien de plus |
| `cilium-l2` | L2 (ARP) par Cilium | `CNI=cilium` + remplacement de kube-proxy |
| `cilium-bgp` | BGP par Cilium | `CNI=cilium`, `BGP_LOCAL_ASN`, `BGP_PEER_ADDRESS`, `BGP_PEER_ASN` |

**Un seul fournisseur à la fois** : MetalLB et le LB IPAM de Cilium ne coexistent jamais
(avec MetalLB, le LB IPAM de Cilium est désactivé). Sur EKS, les load balancers sont fournis
par AWS ; en mode attach, la présence d'un autre fournisseur (ServiceLB de k3s…) est refusée.

## Choisir le pool

Le pool doit :

- appartenir au réseau des nœuds (`NODE_NETWORK_CIDR` ou `network_cidr` de Terraform) ;
- être **exclu du DHCP** de votre routeur et réservé dans votre IPAM ;
- ne contenir ni IP de nœud, ni la VIP de l'API, ni une adresse de `RESERVED_IPS`.

Le résolveur vérifie tout cela et compte les adresses. Exemple homelab (VLAN 20,
`10.20.0.0/16`) : nœuds `10.20.0.100-103`, pool **proposé** `10.20.0.200-10.20.0.210` — à
valider dans votre IPAM avant le déploiement.

## BGP

Le mode BGP n'est **jamais** activé par défaut : il exige un routeur configuré pour
accepter la session (ASN, voisin, filtres). Il n'est pas supposé disponible sur un pare-feu
comme un Stormshield SN300 : vérifiez la fonctionnalité et sa configuration côté pare-feu
(aucune modification automatique de vos équipements). En cas de doute : L2.

## Kind

Le pool doit être dans le réseau Docker `kind` : `docker network inspect kind` (souvent
`172.18.0.0/16`, ex. `172.18.255.200-172.18.255.250`). Les IP sont joignables depuis votre
poste Linux (pas depuis Docker Desktop sur macOS/Windows).

## Tests

`make addons-test ADDON=metallb` (ou `cilium-lb`) : Service LoadBalancer de test, IP
attribuée **dans le pool**, réponse depuis le cluster puis depuis votre poste.
