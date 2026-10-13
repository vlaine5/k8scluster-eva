"""k8s-lab : chargement, validation et résolution de la configuration.

Ce paquet est utilisé par le CLI Bash (./k8s-lab) via scripts/labctl. Il ne
modifie jamais rien : il lit config/lab.env, .env, l'environnement, le
catalogue d'addons (addons/*/addon.yaml) et le verrouillage des versions
(config/versions.yaml), puis produit un plan validé.

Python >= 3.9, dépendance unique : PyYAML.
"""

__all__ = ["envfile", "netutil", "schema", "config", "catalog", "inventory", "resolve", "render"]
