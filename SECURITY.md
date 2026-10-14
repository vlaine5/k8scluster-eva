# Politique de sécurité

Ce projet automatise la création et l'administration de clusters Kubernetes. Il peut
manipuler des **identifiants d'hyperviseurs, des certificats administrateur, des états
Terraform et des sauvegardes etcd** : traitez ces éléments comme des secrets.

## Signaler une vulnérabilité

**Ne publiez pas d'identifiants, de clés, de kubeconfigs, de fichiers Terraform state
ou de détails d'exploitation dans une issue publique.**

1. Utilisez de préférence la fonction **Report a vulnerability** dans l'onglet
   **Security** du dépôt, si elle est activée.
2. Si ce canal n'est pas disponible, contactez le mainteneur par un canal privé
   indiqué dans son profil GitHub. N'ouvrez une issue publique que pour demander
   comment joindre le mainteneur, **sans y décrire l'exploitation**.
3. Fournissez en privé la version ou le commit concerné, la configuration minimale
   (sans secrets), les étapes de reproduction et l'impact.

Aucun délai de traitement n'est garanti. La divulgation sera coordonnée avec
l'auteur du signalement dans la mesure du possible.

## Périmètre et modèle de confiance

- Le framework s'exécute avec des accès élevés **uniquement sur les machines et
  clusters explicitement ciblés**. Vérifiez toujours le mode, le provider, le
  kubeconfig, le contexte Kubernetes et le plan Terraform avant une action.
- **Les fichiers `.env`, `.lab/`, `.kube/` et `*.tfstate` sont sensibles.**
  Ils sont ignorés par Git, mais cette protection ne remplace pas des permissions
  locales restrictives, le chiffrement du disque et des sauvegardes.
- Une sauvegarde etcd peut contenir tous les Secrets Kubernetes. Les sauvegardes
  des volumes applicatifs doivent être gérées séparément.
- L'option `PROXMOX_VE_INSECURE=true` désactive la vérification TLS. Réservez-la
  aux environnements de test avec certificat autosigné ; préférez une autorité
  de certification de confiance.
- Les rôles et tokens API Proxmox doivent être dédiés et limités aux ressources
  nécessaires. N'utilisez pas votre compte administrateur quotidien pour
  l'automatisation.
- N'activez pas par défaut l'exposition des consoles d'administration, du
  dashboard Longhorn ou des interfaces de monitoring.
- Les mécanismes NFS sans root squashing donnent davantage de pouvoir au client
  NFS : limitez-les à un export dédié et aux IP strictement nécessaires.

## Avant d'ouvrir une issue

Expurgez vos journaux et captures : noms de domaine internes, adresses publiques,
tokens, URL portant un mot de passe, certificats, clés, informations de connexion,
contenu des sauvegardes et sortie brute de `terraform show -json`.

En cas de fuite, **révoquez et renouvelez immédiatement** les secrets concernés.

Pour les garanties techniques et les limites du framework, consultez
[le guide de sécurité](docs/security.md), [la sauvegarde et restauration](docs/backup-dr.md)
et [la matrice de compatibilité](docs/compatibility.md).
