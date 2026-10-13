# Écrire un addon

Un addon est un dossier `addons/<id>/` ; aucune ligne de code du moteur n'est à modifier.

```text
addons/reloader/
├── addon.yaml          # fiche : dépendances, compatibilité, installation, santé, test
├── values.yaml.j2      # valeurs Helm (modèle Jinja2)
├── manifests/          # manifestes complémentaires (modèles), appliqués en server-side apply
└── tests/test.yml      # test fonctionnel (tâches Ansible)
```

## addon.yaml

```yaml
id: reloader
name: Reloader
description: >-
  Redémarre les workloads annotés quand leurs ConfigMaps ou Secrets changent.
category: operations          # network, storage, security, infrastructure, observability, gitops...
phase: 7                      # 4 CRD, 5 réseau, 6 stockage, 7 infrastructure, 8 plateforme
components: [reloader]        # composants de config/versions.yaml (version verrouillée)
depends_on: []                # addons requis (ajoutés automatiquement)
integrates_with: [prometheus-operator-crds]   # installés AVANT s'ils sont présents
conflicts_with: []
requires:                     # refus explicite si non satisfait
  # cni: [cilium]
  # settings: [VAR]           # variables obligatoires
  # secrets: [VAR]            # secrets obligatoires (.env)
  # min_workers: 2
settings: []                  # variables .env utilisées (documentation, résolveur)
secrets: []
support:
  default: supported          # supported | configured | experimental | unsupported
  minikube: {status: experimental, note: "..."}
validated: []                 # environnements de CI où l'addon est réellement testé
install:
  namespace: reloader
  pod_security: restricted    # baseline (défaut) | restricted | privileged
  # expose_setting: XXX_EXPOSE   # label d'exposition sur la Gateway si la variable est vraie
  # secrets: [{name, namespace, only_if_env | only_if_any_env, data: {clé: "env:VAR" | "cfg:VAR"}}]
  releases:
    - {name: reloader, component: reloader, namespace: reloader, values: values.yaml.j2, timeout: 5m}
    # method: template : chart rendu puis appliqué en server-side apply, sans release Helm
    # (charts de CRD dont le Secret de release dépasserait 1 Mio, ex. CRD d'Envoy Gateway)
  # manifests_pre / manifests / tasks / post_tasks
health:
  - {kind: Deployment, namespace: reloader, name: reloader-reloader}
tests: tests/test.yml
remove:
  notes: "Ce qui est conservé lors de la désinstallation."
docs: docs/addons.md#reloader
```

Variables disponibles dans les modèles : `cfg` (configuration, sans secret), `lab` (choix
résolus : `lab.platform`, `lab.gateway_tls`, `lab.loadbalancer`…), `lab_addon_ids`
(addons du plan : `{% if 'prometheus-operator-crds' in lab_addon_ids %}`),
`lab_test_images`, `addon_item` (l'addon et ses composants).

## Valeurs et manifestes

- Ne jamais mettre de secret dans un modèle : un Secret est créé par `install.secrets`
  depuis `.env`, puis référencé par son nom.
- Un manifeste qui ne doit exister que sous condition se rend vide (`{% if ... %}` autour
  du document).
- Activer la supervision seulement si les CRD sont dans le plan.

## Test

Le test s'exécute dans un namespace jetable `addon_test_ns` (supprimé à la fin). Aides :
`{{ addon_helpers }}/curl.yml` (curl dans le cluster), `loadbalancer_test.yml`,
`test_storageclass.yml` (copie `Delete` d'une StorageClass). Un test doit prouver le
fonctionnement (une requête qui traverse le composant), pas seulement que des Pods tournent.

## Vérifier

```bash
make catalog-check              # fichiers référencés, dépendances, ordre
make addons-render-check        # rendu + helm template dans 3 scénarios (ajoutez l'addon à un scénario)
make test-unit                  # résolveur
make ansible-lint
make docs-generate              # catalogue, fiches et matrices de compatibilité
```

Puis ajoutez l'addon à un scénario e2e (`tests/e2e/*.env`) pour qu'il soit installé et testé
en CI, et renseignez `validated` une fois la CI verte.
