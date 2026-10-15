# Premier déploiement sur le homelab « pv05 »

Procédure **manuelle**, à dérouler après revue du code. Le framework n'a jamais été lancé sur
cette infrastructure : aucune VM n'a été créée, aucun `terraform apply` n'a été exécuté, ni
par la CI ni pendant le développement. Chaque étape qui modifie quelque chose est signalée
par **[modifie]** et demande votre confirmation.

| Élément | Valeur | Statut |
| --- | --- | --- |
| Hyperviseur | Proxmox VE, nœud `pv05` (Dell T610, Xeon X5690, 188 Gio) | existant |
| API Proxmox | `https://10.20.0.31:8006` | existant |
| Réseau des VMs | `vmbr0`, déjà sur le VLAN 20 (`10.20.0.0/16`, passerelle `10.20.0.1`) | existant, **aucun tag VLAN ajouté** |
| Nœuds | `k8s-cp-1` 10.20.50.10/16, `k8s-worker-1..3` 10.20.50.11-13/16 (4 vCPU, 4 Gio, 300 Gio) | **à réserver** dans l'IPAM |
| Pool LoadBalancer | `10.20.80.100-10.20.80.200` | **proposition à valider** |
| NAS | Synology `10.20.0.30`, export `/volume1/kubevolume` | **proposition à valider** ; jamais modifié par le framework |
| Pare-feu | Stormshield SN300 entre VLAN | jamais modifié par le framework |
| Réseaux Kubernetes | Pods `10.244.0.0/16`, Services `10.250.0.0/16` | le défaut `10.96.0.0/12` chevaucherait `10.101-105.0.0/16` |

Fichiers fournis : [../examples/profiles/homelab-pv05.env](../examples/profiles/homelab-pv05.env)
(configuration) et [../examples/homelab/terraform.tfvars.example](../examples/homelab/terraform.tfvars.example)
(infrastructure Proxmox).

## 0. Ce que le déploiement fera, et ne fera pas

Il **créera** : 4 VMs (IDs attribués par Proxmox, ou `vm_id_start`), l’image cloud Debian
13 datée (SHA-256 vérifié par Proxmox) dans un stockage acceptant **Import**, un disque système
de 300 Gio par VM sur `Store` et un disque Longhorn **neuf** de 100 Gio par worker sur `VM-ZFS`
(numéro de série `k8slab-longhorn`), puis Kubernetes et les addons dans ces VMs.

Il **ne touchera pas** : aux autres VMs de `pv05`, à la configuration réseau de Proxmox, au
NAS (ni partage, ni règle NFS, ni donnée), au Stormshield, à votre DNS. Un disque qui
contient des données n'est jamais formaté ; `kubeadm reset` n'est jamais lancé
automatiquement ; `make destroy` ne supprime ni les données du NAS ni les sauvegardes.

Capacité logique à prévoir sur les datastores : **4 × 300 + 3 × 100 = 1 500 Gio**
(`Store` pour les systèmes, `VM-ZFS` pour les disques Longhorn). Le provisionnement fin
peut réduire l’occupation réelle initiale, sans supprimer le besoin de capacité future.
Mémoire allouée : 16 Gio sur 188.

## 1. Vérifications réseau (IPAM) — vous seul

1. `10.20.50.10` à `10.20.50.13` libres (ping, table ARP de la passerelle, IPAM), hors DHCP.
2. `10.20.80.100` à `10.20.80.200` libres, hors DHCP, réservées pour les Services
   LoadBalancer (MetalLB les annonce en ARP sur le VLAN 20).
3. Réservez aussi `10.20.50.9` si vous comptez passer plus tard à 3 control-planes (VIP de
   l'API, [high-availability.md](high-availability.md)).
4. Complétez `RESERVED_IPS` (plage DHCP du VLAN 20) et `RESERVED_CIDRS` (tous les réseaux
   du homelab) dans `.env` : le résolveur refusera tout chevauchement.
5. DNS : `dns_servers = ["10.20.0.30"]` dans l’exemple. Vérifiez que cette IP héberge
   réellement un service DNS avant le premier déploiement.

## 2. Préparer Proxmox **[modifie Proxmox, à la main]**

Sur `pv05` (shell root ou interface web) :

1. Pour `image_datastore`, choisissez un stockage **fichier** qui accepte `Import`
   (ex. *Datacenter → Storage → local → Edit → Content* : cochez **Import**).
   Attention : un stockage Proxmox de type **zfspool** ne permet généralement pas
   d’y télécharger le fichier image cloud via `proxmox_download_file`.
   Vérifiez également `Store` (disques système) et `VM-ZFS` (Longhorn).
2. Créez un utilisateur et un token **dédiés**, avec le rôle minimal décrit dans
   [deploy-proxmox.md](deploy-proxmox.md#2-configurer) (`pveum role add K8sLab ...`,
   `pveum user token add terraform@pve k8s-lab --privsep 0`). Notez le secret, affiché une
   seule fois.
3. Vérifiez que `vmbr0` est bien le bridge du VLAN 20 : aucune option `vlan_id` ne doit être
   définie dans `terraform.tfvars`.

## 3. Préparer le NAS et le pare-feu **[modifie le NAS et le pare-feu, à la main]**

Uniquement si vous gardez NFS (`STORAGE_BACKENDS=nfs-csi,...`). Le framework vérifie mais ne
configure jamais le NAS ni le pare-feu.

1. DSM → *Panneau de configuration → Services de fichiers → NFS* : activez NFS, protocole
   maximal **NFSv4.1**.
2. Dossier partagé `/volume1/kubevolume` (chemin exact à confirmer sur le NAS) → *Autorisations NFS* :
   créer des règles **pour les seules IP des nœuds** `10.20.50.10-13`, en lecture/écriture,
   et vérifier les options d'export proposées par DSM. **Conserver le root squashing si
   possible.** Le NFS CSI doit pouvoir créer ses sous-dossiers ; tester une création de PVC
   et corriger les permissions sur cet export dédié si nécessaire. Le mode sans squash
   (`no_root_squash`) est un compromis de sécurité : ne l'activer qu'en connaissance de cause,
   exclusivement pour cet export et pour les clients nécessaires. Ne pas ouvrir l'export
   à tout `10.20.0.0/16` ni exposer NFS à Internet.
3. Le NAS et les VMs sont dans le même VLAN 20 : vérifiez le pare-feu local
   du NAS, les ACL NFS et la connectivité **TCP 2049**. Le Stormshield n’est normalement
   pas traversé pour ce flux direct sur le même réseau.
4. Vérifiez après la création des VMs (étape 6) : test de montage depuis un worker,
   [storage-nfs.md](storage-nfs.md).

Sans NFS : retirez `nfs-csi` de `STORAGE_BACKENDS` ; seul Longhorn sera installé.

## 4. Configurer votre poste

```bash
git clone https://github.com/vlaine5/k8scluster-eva.git && cd k8scluster-eva
make venv                       # environnement Python épinglé (Ansible, PyYAML...)
test -f .env || cp examples/profiles/homelab-pv05.env .env
# Ne remplace pas votre configuration personnelle déjà présente :
test -f terraform/providers/proxmox/terraform.tfvars || \
  cp examples/homelab/terraform.tfvars.example terraform/providers/proxmox/terraform.tfvars
```

Ajoutez à la fin de `.env` (jamais dans un fichier versionné) :

```bash
PROXMOX_VE_ENDPOINT=https://10.20.0.31:8006/
PROXMOX_VE_API_TOKEN=terraform@pve!k8s-lab=<secret>
# PROXMOX_VE_INSECURE=true      # seulement si le certificat de Proxmox est auto-signé
```

Relisez les lignes « À VALIDER » de `.env` et de `terraform.tfvars`.

## 5. Valider sans rien modifier

```bash
make doctor                     # outils, connexion à l'API Proxmox, token, configuration
make config                     # configuration résolue, avertissements, réseaux vérifiés
make addons-plan                # 9 addons, dépendances, ordre, versions
make validate
make plan MODE=terraform PROVIDER=proxmox   # vrai plan Terraform, sans apply
```

Attendu : aucune erreur ; avertissements connus et assumés pour ce homelab :

- Longhorn sur un seul hyperviseur : les réplicas protègent d'une panne de VM, pas d'une
  panne de `pv05` ni de son stockage — d'où les sauvegardes (étape 9) ;
- Longhorn 1.13 non vérifié par son projet sur Debian 13 (vérifiés : 26.04, Rocky 10) ;
- Cilium (VXLAN) assure les NetworkPolicy et le réseau des Pods.

## 6. Déployer **[modifie : crée les VMs]**

```bash
make deploy
```

1. `terraform plan` s'affiche avec son résumé (les 4 VMs, l'image, l'inventaire) :
   **relisez-le**. Un plan qui détruit quelque chose est signalé par un avertissement ;
   refusez-le s'il n'est pas attendu. Rien n'est créé avant votre « o ».
2. Terraform crée les VMs après votre confirmation.
3. Ansible : contrôles préalables en lecture seule (OS, ressources, ports,
   disques), préparation des nœuds, containerd, kubeadm, Cilium, disques Longhorn (formatés
   seulement s'ils sont vides et créés par le lab), puis jonction des workers.
4. Addons, contrôles de santé, puis tests fonctionnels.

En cas d'échec, corrigez la cause indiquée et relancez `make deploy` : chaque étape est
idempotente et le cluster existant est conservé.

## 7. Vérifier

```bash
export KUBECONFIG="$PWD/.kube/config"
make status
kubectl get nodes -o wide                         # 4 nœuds Ready, IP 10.20.50.10-13
make test                                         # nginx + Service + DNS
make addons-status
make addons-test                                  # tests fonctionnels de chaque addon
make health                                       # etcd, certificats, services, disques
kubectl get gateway -A                           # ADDRESS prise dans 10.20.80.100-200
```

Ensuite, dans **votre** DNS : `*.k8s.homelab.internal` → l'adresse de la Gateway
`lab-gateway` (servie par Traefik). Le certificat de la CA interne de cert-manager est à
importer dans vos navigateurs ([gateway-api.md](gateway-api.md)).

## 8. Stockage

```bash
kubectl get storageclass                          # longhorn (défaut), nfs-csi
kubectl -n longhorn-system get nodes.longhorn.io  # 3 nœuds prêts, disque /var/lib/longhorn
```

Les deux classes sont en `Retain` : supprimer un PVC ne supprime ni le volume Longhorn ni le
dossier sur le NAS ([storage.md](storage.md)).

## 9. Sauvegardes

```bash
make backup                                       # instantané etcd → .lab/backups/homelab-proxmox/
```

Copiez ce dossier hors du poste (il contient les secrets du cluster : à chiffrer). Pour les
volumes : `LONGHORN_BACKUP_ENABLED=true` vers le NAS, ou Velero
([backup-dr.md](backup-dr.md)). Faites un premier exercice de restauration sur un cluster
de test avant d'en avoir besoin.

## 10. Tests destructifs (facultatifs, quand vous le décidez)

```bash
make addons-test DESTRUCTIVE=1                    # perte d'un réplica Longhorn
make storage-failure-test NODE=k8s-worker-2       # perte d'un worker entier (nom à retaper)
```

Le second arrête kubelet, les Pods et containerd sur le worker pendant plusieurs minutes,
puis les redémarre toujours ([storage-longhorn.md](storage-longhorn.md#tests)).

## 11. Revenir en arrière

```bash
make destroy                                      # supprime les 4 VMs (confirmation)
```

Restent en place : les données du NAS (`/volume1/kubevolume`), les sauvegardes, l'image
cloud dans `local` (réutilisée au prochain déploiement). Les disques Longhorn sont supprimés
avec les VMs : sauvegardez d'abord les volumes utiles.

## Liste de contrôle

- [ ] IP des nœuds et pool LoadBalancer réservés, `RESERVED_IPS` / `RESERVED_CIDRS` complétés
- [ ] Token Proxmox dédié, secret uniquement dans `.env`
- [ ] Stockage `image_datastore` compatible **Import** ; `Store`/`VM-ZFS` ont assez d’espace ; pas de `vlan_id`
- [ ] Export NFS, règles et flux TCP 2049 validés (ou NFS retiré)
- [ ] `make doctor`, `make config`, `make validate`, `make plan` réussis avant `make deploy`
- [ ] Plan Terraform relu avant confirmation
- [ ] `make test`, `make addons-test`, `make health` réussis
- [ ] Entrée DNS de la Gateway créée, CA interne importée
- [ ] Première sauvegarde etcd copiée hors du poste
