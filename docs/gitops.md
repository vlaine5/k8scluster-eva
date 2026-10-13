# GitOps avec Argo CD

L'addon `argo-cd` installe Argo CD (profils `homelab` et `enterprise-lab`). Le partage des
rôles est volontairement net :

| Géré par le framework (`make addons-apply`) | Géré par Argo CD (Git) |
| --- | --- |
| CNI, stockage, LoadBalancer, Gateway, cert-manager, supervision, Argo CD lui-même | **vos applications** |

Pourquoi ? Argo CD dépend du réseau, du stockage et des certificats : s'il les gérait, une
erreur dans Git pourrait couper la branche sur laquelle il est assis (dépendance circulaire).

## Application d'exemple

```bash
ARGOCD_REPO_URL=https://github.com/<vous>/<dépôt>.git
ARGOCD_REPO_PATH=examples/gitops/apps     # dossier synchronisé (récursif)
ARGOCD_REPO_REVISION=HEAD
ARGOCD_AUTO_SYNC=false                    # true : synchronisation automatique + auto-réparation
# Dépôt privé (.env) :
# ARGOCD_REPO_USERNAME=...
# ARGOCD_REPO_PASSWORD=<jeton en lecture seule>
```

Le framework crée l'`Application` `argocd/lab-apps`. Avec la synchronisation automatique,
`prune` reste **désactivé** : une ressource retirée de Git n'est pas supprimée du cluster
sans action de votre part. L'exemple `examples/gitops/apps/demo.yaml` déploie un namespace
`demo-gitops` (Pod Security `restricted`), un Deployment et un Service.

## Accès

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443     # https://localhost:8080 (admin)
```

ou `ARGOCD_EXPOSE=true` : `https://argocd.<GATEWAY_DOMAIN>` (TLS terminé par la Gateway).
Changez le mot de passe initial puis supprimez le Secret `argocd-initial-admin-secret`.

## Mode attach

Un composant déjà géré par Argo CD n'est **jamais** repris par le framework : l'installation
de l'addon correspondant est refusée ([attach-mode.md](attach-mode.md)).

## Test

`make addons-test ADDON=argo-cd` : API d'Argo CD (version) ; si `ARGOCD_REPO_URL` est
défini, l'application est comparée au dépôt (Synced/OutOfSync), puis `Healthy` si la
synchronisation automatique est active.
