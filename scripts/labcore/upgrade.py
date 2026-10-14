"""Plan de mise à niveau de Kubernetes (make upgrade-plan) : lecture seule.

Compare la version du cluster (et des kubelets) à KUBERNETES_VERSION, applique
les règles officielles (une mineure à la fois, écart de version kubelet/API),
la politique UPGRADE_POLICY et la compatibilité des addons avec la version
cible. Rien n'est exécuté : ./k8s-lab upgrade lance ensuite upgrade.yml.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .catalog import Catalog
from .resolve import Plan, minor_of, version_tuple

# Écart maximal kubelet / kube-apiserver (règle officielle : kubelet jusqu'à 3 mineures en dessous).
KUBELET_SKEW = 3

NOTHING_TO_DO = 10


@dataclass
class UpgradePlan:
    current: str
    target: str
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    steps: list[str] = field(default_factory=list)
    nothing: bool = False

    @property
    def code(self) -> int:
        if self.errors:
            return 1
        return NOTHING_TO_DO if self.nothing else 0


def _minor_number(version: str) -> int:
    return version_tuple(minor_of(version))[1]


def build(plan: Plan, catalog: Catalog, policy: str, server_version: str,
          nodes: list[dict[str, Any]]) -> UpgradePlan:
    target = plan.resolved.get("kubernetes_version", "")
    current = server_version.lstrip("v").split("-")[0].split("+")[0]
    up = UpgradePlan(current=current, target=target)
    if not plan.resolved.get("kubeadm"):
        up.errors.append(f"Mode {plan.platform} : la version de Kubernetes n'est pas gérée par kubeadm "
                         "(kind/minikube : recréer le cluster ; EKS : EKS_KUBERNETES_VERSION puis terraform apply).")
        return up
    lock = catalog.versions["kubernetes"]
    cur_t, tgt_t = version_tuple(current), version_tuple(target)
    if tgt_t == cur_t:
        up.nothing = True
    elif tgt_t < cur_t:
        up.errors.append(f"KUBERNETES_VERSION={target} est plus ancienne que le cluster ({current}) : une "
                         "rétrogradation n'est pas supportée par kubeadm (restauration etcd = docs/backup-dr.md).")
    else:
        jump = _minor_number(target) - _minor_number(current)
        if jump > 1:
            path = []
            for minor in range(_minor_number(current) + 1, _minor_number(target) + 1):
                key = f"1.{minor}"
                path.append(lock.get("latest_patches", {}).get(key, f"{key}.x"))
            up.errors.append(f"{current} -> {target} saute {jump} mineures : kubeadm n'avance que d'une mineure à la "
                             f"fois. Chemin : {' -> '.join([current] + path)} (une mise à niveau par étape).")
        elif jump == 1 and policy == "patch":
            up.errors.append(f"{current} -> {target} change de mineure, mais UPGRADE_POLICY=patch.",)
        if minor_of(target) not in lock["supported_minors"]:
            up.errors.append(f"Kubernetes {minor_of(target)} n'est pas supporté par le framework "
                             f"({', '.join(lock['supported_minors'])}).")
    # Écart de version des kubelets : aucun nœud plus récent que l'API, ni trop ancien pour la cible.
    for node in nodes:
        name = node.get("metadata", {}).get("name", "?")
        kubelet = node.get("status", {}).get("nodeInfo", {}).get("kubeletVersion", "")
        if not kubelet:
            continue
        if version_tuple(kubelet) > version_tuple(target):
            up.errors.append(f"Le kubelet de {name} ({kubelet}) est plus récent que la cible {target}.")
        elif _minor_number(target) - _minor_number(kubelet) > KUBELET_SKEW:
            up.errors.append(f"Le kubelet de {name} ({kubelet}) serait à plus de {KUBELET_SKEW} mineures de l'API "
                             f"{target} : mettez d'abord ce nœud à niveau (étapes intermédiaires).")
        if node.get("spec", {}).get("unschedulable"):
            up.warnings.append(f"{name} est déjà « cordoned » (unschedulable) : il le restera après sa mise à niveau.")
        ready = [c for c in node.get("status", {}).get("conditions", []) if c.get("type") == "Ready"]
        if ready and ready[0].get("status") != "True":
            up.errors.append(f"{name} n'est pas Ready : réparez le cluster avant de le mettre à niveau.")
    # Compatibilité des composants avec la version cible (même règle que le résolveur).
    for issue in plan.errors:
        up.errors.append(issue.message)
    for issue in plan.warnings:
        if "Kubernetes" in issue.message:
            up.warnings.append(issue.message)
    if up.nothing or up.errors:
        return up
    up.steps = [
        "Instantané etcd sur chaque control-plane (.lab/backups/<cluster>/), conservé localement",
        f"Dépôt des paquets Kubernetes {minor_of(target)} ; kubeadm {target} sur le 1er control-plane",
        f"kubeadm upgrade plan puis kubeadm upgrade apply v{target} (1er control-plane)",
        "kubeadm upgrade node sur les autres control-planes, un par un (quorum etcd conservé)",
        "Pour chaque nœud, un par un : drain, kubelet/kubectl, redémarrage du kubelet, uncordon",
        "Vérifications : nœuds Ready à la bonne version, Pods système, santé etcd, API",
        "Addons : make addons-upgrade si config/versions.yaml propose de nouvelles versions",
    ]
    return up


def text(up: UpgradePlan) -> str:
    lines = [f"Mise à niveau de Kubernetes : {up.current} -> {up.target}"]
    if up.nothing:
        lines.append("  Le cluster est déjà à la version demandée : rien à faire.")
    for error in up.errors:
        lines.append(f"  [erreur] {error}")
    for warning in up.warnings:
        lines.append(f"  [attention] {warning}")
    if up.steps:
        lines.append("  Étapes (make upgrade, après confirmation) :")
        lines += [f"    {i}. {step}" for i, step in enumerate(up.steps, 1)]
        lines.append("  Les workloads sont déplacés (drain) : prévoyez des PodDisruptionBudget pour les applications.")
    return "\n".join(lines)
