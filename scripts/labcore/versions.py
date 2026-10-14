"""Versions verrouillées et recherche de versions plus récentes (sans rien installer).

Sources officielles interrogées :
  - Kubernetes : https://dl.k8s.io/release/stable-<mineure>.txt
  - charts Helm : index.yaml du dépôt du chart (ou tags OCI via helm show chart)
  - manifestes (Flannel, Gateway API, external-snapshotter) : tags Git (git ls-remote)
"""
from __future__ import annotations

import re
import subprocess
import urllib.request
from typing import Any, Optional

import yaml

from .catalog import Catalog

GIT_REPOS = {
    "flannel": "https://github.com/flannel-io/flannel",
    "gateway-api": "https://github.com/kubernetes-sigs/gateway-api",
    "snapshot-controller": "https://github.com/kubernetes-csi/external-snapshotter",
    "kube_vip": "https://github.com/kube-vip/kube-vip",
    "helm": "https://github.com/helm/helm",
}
SEMVER = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def _parse(version: str) -> Optional[tuple[int, int, int]]:
    match = SEMVER.match(version.strip())
    return tuple(int(x) for x in match.groups()) if match else None  # type: ignore[return-value]


def locked_table(catalog: Catalog) -> str:
    v = catalog.versions
    lines = [f"Versions verrouillées (config/versions.yaml, vérifiées le {v.get('checked_on')})", "",
             f"  {'Kubernetes (défaut)':<28} {v['kubernetes']['version']}",
             f"  {'containerd':<28} {v['containerd']['version']}",
             f"  {'Helm (nœuds)':<28} {v['helm']['version']}",
             f"  {'kube-vip':<28} {v['kube_vip']['version']}"]
    for name, comp in sorted(v["components"].items()):
        detail = comp.get("chart", "") if comp["type"] != "manifest" else "manifeste + SHA-256"
        lines.append(f"  {name:<28} {comp.get('version', '-'):<12} {detail}")
    lines.append("")
    for os_name, versions in v["os"].items():
        for version, entry in versions.items():
            lines.append(f"  {os_name + ' ' + version:<28} {entry['image_url'].rsplit('/', 1)[-1]}")
    return "\n".join(lines)


def _fetch(url: str, timeout: int = 30) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "k8s-lab-versions-check"})
    with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - URL officielles
        return response.read().decode("utf-8")


def _helm_index_latest(repo: str, chart: str) -> Optional[str]:
    index = yaml.safe_load(_fetch(repo.rstrip("/") + "/index.yaml", timeout=120))
    best, best_key = None, None
    for entry in index.get("entries", {}).get(chart, []):
        key = _parse(entry["version"])
        if key and (best_key is None or key > best_key):
            best, best_key = entry["version"], key
    return best


def _git_latest(url: str) -> Optional[str]:
    out = subprocess.run(["git", "ls-remote", "--tags", "--refs", url], capture_output=True, text=True,
                         timeout=120, check=False).stdout
    best, best_key = None, None
    for line in out.splitlines():
        tag = line.rsplit("refs/tags/", 1)[-1]
        key = _parse(tag)
        if key and (best_key is None or key > best_key):
            best, best_key = tag, key
    return best


def _oci_latest(chart_ref: str) -> Optional[str]:
    out = subprocess.run(["helm", "show", "chart", chart_ref], capture_output=True, text=True,
                         timeout=120, check=False).stdout
    match = re.search(r"^version:\s*(\S+)", out, re.M)
    return match.group(1) if match else None


def classify(current: str, latest: str) -> str:
    a, b = _parse(current), _parse(latest)
    if not a or not b or b <= a:
        return "à jour"
    if a[0] != b[0]:
        return "majeure"
    if a[1] != b[1]:
        return "mineure"
    return "correctif"


def check_upstream(catalog: Catalog, policy: str = "patch", only: str = "") -> int:
    wanted = {x.strip() for x in only.split(",") if x.strip()}
    rows: list[tuple[str, str, str, str]] = []
    errors = 0
    k8s = catalog.versions["kubernetes"]
    if not wanted or "kubernetes" in wanted:
        for minor in k8s["supported_minors"]:
            try:
                latest = _fetch(f"https://dl.k8s.io/release/stable-{minor}.txt").strip().lstrip("v")
                rows.append((f"kubernetes {minor}", k8s["latest_patches"].get(minor, "?"), latest,
                             classify(k8s["latest_patches"].get(minor, "0.0.0"), latest)))
            except OSError as exc:
                rows.append((f"kubernetes {minor}", "?", f"erreur : {exc}", "?"))
                errors += 1
    for name, comp in sorted(catalog.versions["components"].items()):
        if wanted and name not in wanted:
            continue
        current = comp.get("version", "")
        try:
            if comp["type"] == "helm":
                latest = _helm_index_latest(comp["repo"], comp["chart"])
            elif comp["type"] == "helm-oci":
                latest = _oci_latest(comp["chart"])
            else:
                latest = _git_latest(GIT_REPOS[name]) if name in GIT_REPOS else None
        except Exception as exc:  # noqa: BLE001 - rapport, pas d'arrêt
            rows.append((name, current, f"erreur : {exc}", "?"))
            errors += 1
            continue
        if name == "gateway-api":
            current = max(comp["sha256"], key=lambda v: _parse(v) or (0, 0, 0))
        rows.append((name, current or "-", latest or "?", classify(current, latest or "") if latest else "?"))
    print(f"{'Composant':<30} {'Verrouillée':<14} {'Disponible':<14} Écart")
    proposals = []
    for name, current, latest, kind in rows:
        print(f"{name:<30} {current:<14} {latest:<14} {kind}")
        if kind == "correctif" or (kind == "mineure" and policy == "minor"):
            proposals.append(name)
    print()
    print("Rien n'a été installé ni modifié. " + (
        f"Mises à jour proposées (UPGRADE_POLICY={policy}) : {', '.join(proposals)}." if proposals
        else f"Aucune mise à jour proposée par la politique UPGRADE_POLICY={policy}."))
    print("Procédure : modifier config/versions.yaml (et les SHA-256), vérifier les matrices de compatibilité, "
          "lancer les tests (make lint test-unit), puis make addons-plan / make upgrade-plan. docs/upgrades.md")
    return 1 if errors else 0


def summary(data: dict[str, Any]) -> str:  # pragma: no cover - utilitaire
    return yaml.safe_dump(data, sort_keys=False)
