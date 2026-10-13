"""Mode attach : inventaire d'un cluster Kubernetes existant, en LECTURE SEULE.

Détecte la version, la distribution, le CNI, kube-proxy, les StorageClasses,
les CRD, les releases Helm, les composants déjà présents et s'ils sont gérés
par un autre outil (Helm d'un tiers, Argo CD, distribution comme k3s).
Aucune commande d'écriture n'est exécutée.
"""
from __future__ import annotations

import json
import subprocess
from typing import Any, Optional

from .catalog import Catalog

# Empreintes des composants déjà installés (une seule suffit pour « présent »).
FINGERPRINTS: dict[str, dict[str, list[str]]] = {
    "cert-manager": {"crds": ["certificates.cert-manager.io"], "charts": ["cert-manager"]},
    "metrics-server": {"apiservices": ["v1beta1.metrics.k8s.io"], "charts": ["metrics-server"]},
    "argo-cd": {"crds": ["applications.argoproj.io"], "charts": ["argo-cd"]},
    "monitoring": {"crds": ["prometheuses.monitoring.coreos.com"], "charts": ["kube-prometheus-stack"]},
    "prometheus-operator-crds": {"crds": ["servicemonitors.monitoring.coreos.com"], "charts": ["prometheus-operator-crds"]},
    "metallb": {"crds": ["ipaddresspools.metallb.io"], "charts": ["metallb"]},
    "nfs-csi": {"csidrivers": ["nfs.csi.k8s.io"], "charts": ["csi-driver-nfs"]},
    "longhorn": {"csidrivers": ["driver.longhorn.io"], "charts": ["longhorn"]},
    "traefik": {"charts": ["traefik"], "crds": ["ingressroutes.traefik.io"]},
    "envoy-gateway": {"crds": ["envoyproxies.gateway.envoyproxy.io"], "charts": ["gateway-helm"]},
    "kyverno": {"crds": ["clusterpolicies.kyverno.io"], "charts": ["kyverno"]},
    "trivy-operator": {"crds": ["vulnerabilityreports.aquasecurity.github.io"], "charts": ["trivy-operator"]},
    "external-secrets": {"crds": ["externalsecrets.external-secrets.io"], "charts": ["external-secrets"]},
    "velero": {"crds": ["backups.velero.io"], "charts": ["velero"]},
    "keda": {"crds": ["scaledobjects.keda.sh"], "charts": ["keda"]},
    "istio": {"crds": ["virtualservices.networking.istio.io"], "charts": ["istiod"]},
    "logging": {"charts": ["loki"]},
    "tempo": {"charts": ["tempo"]},
    "opentelemetry-collector": {"charts": ["opentelemetry-collector"]},
    "reloader": {"charts": ["reloader"]},
    "descheduler": {"charts": ["descheduler"]},
    "node-feature-discovery": {"crds": ["nodefeatures.nfd.k8s-sigs.io"], "charts": ["node-feature-discovery"]},
    "falco": {"charts": ["falco"]},
    "tetragon": {"crds": ["tracingpolicies.cilium.io"], "charts": ["tetragon"]},
    "external-dns": {"charts": ["external-dns"]},
    "snapshot-controller": {"crds": ["volumesnapshots.snapshot.storage.k8s.io"]},
}
CNI_DAEMONSETS = {
    "cilium": "cilium", "calico-node": "calico", "kube-flannel-ds": "flannel", "aws-node": "aws-vpc-cni",
    "kindnet": "kindnet", "weave-net": "weave", "canal": "canal", "kube-router": "kube-router",
    "antrea-agent": "antrea", "rke2-canal": "canal", "kube-ovn-cni": "kube-ovn",
}
STATE_NAMESPACE = "k8s-lab-system"
STATE_CONFIGMAP = "k8s-lab-addons"


class Kubectl:
    def __init__(self, kubeconfig: str, context: str):
        self.base = ["kubectl", "--kubeconfig", kubeconfig, "--context", context, "--request-timeout=20s"]
        self.kubeconfig, self.context = kubeconfig, context

    def json(self, *args: str) -> Optional[Any]:
        try:
            out = subprocess.run(self.base + list(args) + ["-o", "json"], capture_output=True, text=True,
                                 timeout=60, check=False)
        except (OSError, subprocess.SubprocessError):
            return None
        if out.returncode != 0:
            return None
        try:
            return json.loads(out.stdout)
        except json.JSONDecodeError:
            return None

    def helm_releases(self) -> Optional[list[dict[str, Any]]]:
        """Releases Helm de tous les namespaces (Helm 4 : tous les états par défaut).
        None si helm échoue : la détection serait incomplète, l'appelant doit refuser."""
        try:
            out = subprocess.run(["helm", "--kubeconfig", self.kubeconfig, "--kube-context", self.context,
                                  "list", "--all-namespaces", "-o", "json"],
                                 capture_output=True, text=True, timeout=60, check=False)
        except (OSError, subprocess.SubprocessError):
            return None
        if out.returncode != 0:
            return None
        try:
            return json.loads(out.stdout or "[]")
        except json.JSONDecodeError:
            return None


def detect(kubeconfig: str, context: str, kubectl: Optional[Kubectl] = None) -> dict[str, Any]:
    if not kubeconfig or not context:
        return {"reachable": False, "error": "EXISTING_KUBECONFIG et EXISTING_CONTEXT sont obligatoires."}
    k = kubectl or Kubectl(kubeconfig, context)
    version = k.json("version")
    if not version or "serverVersion" not in version:
        return {"reachable": False, "error": f"cluster injoignable avec le contexte {context}"}
    raw = {
        "version": version,
        "nodes": k.json("get", "nodes") or {"items": []},
        "daemonsets": k.json("get", "daemonsets", "--all-namespaces") or {"items": []},
        "storageclasses": k.json("get", "storageclasses") or {"items": []},
        "crds": k.json("get", "customresourcedefinitions") or {"items": []},
        "csidrivers": k.json("get", "csidrivers") or {"items": []},
        "apiservices": k.json("get", "apiservices") or {"items": []},
        "gatewayclasses": k.json("get", "gatewayclasses") or {"items": []},
        "deployments": k.json("get", "deployments", "--all-namespaces") or {"items": []},
        "state": k.json("get", "configmap", "-n", STATE_NAMESPACE, STATE_CONFIGMAP),
        "kubeadm_config": k.json("get", "configmap", "-n", "kube-system", "kubeadm-config"),
        "helm": k.helm_releases(),
    }
    return analyse(raw, context)


def analyse(raw: dict[str, Any], context: str = "") -> dict[str, Any]:
    """Analyse des données brutes (séparée pour les tests unitaires)."""
    server = raw["version"]["serverVersion"]
    git_version = server.get("gitVersion", "")
    nodes = raw["nodes"].get("items", [])
    node_info = [{
        "name": n["metadata"]["name"],
        "roles": sorted(k.split("/", 1)[1] for k in n["metadata"].get("labels", {}) if k.startswith("node-role.kubernetes.io/")),
        "os_image": n["status"].get("nodeInfo", {}).get("osImage", ""),
        "kernel": n["status"].get("nodeInfo", {}).get("kernelVersion", ""),
        "runtime": n["status"].get("nodeInfo", {}).get("containerRuntimeVersion", ""),
        "kubelet": n["status"].get("nodeInfo", {}).get("kubeletVersion", ""),
        "provider_id": n.get("spec", {}).get("providerID", ""),
        "labels": n["metadata"].get("labels", {}),
    } for n in nodes]
    distribution = "kubernetes"
    if "+k3s" in git_version:
        distribution = "k3s"
    elif "+rke2" in git_version:
        distribution = "rke2"
    elif "-eks-" in git_version:
        distribution = "eks"
    elif "-gke." in git_version:
        distribution = "gke"
    elif any("talos" in n["os_image"].lower() for n in node_info):
        distribution = "talos"
    elif any(n["provider_id"].startswith("kind://") for n in node_info):
        distribution = "kind"
    elif any("minikube.k8s.io/name" in n["labels"] for n in node_info):
        distribution = "minikube"
    elif raw.get("kubeadm_config"):
        distribution = "kubeadm"
    daemonsets = raw["daemonsets"].get("items", [])
    ds_names = {(d["metadata"]["namespace"], d["metadata"]["name"]) for d in daemonsets}
    cni = sorted({CNI_DAEMONSETS[name] for _, name in ds_names if name in CNI_DAEMONSETS})
    if not cni and distribution == "k3s":
        cni = ["flannel (intégré à k3s)"]
    kube_proxy = any(name == "kube-proxy" for _, name in ds_names)
    servicelb = any(name.startswith("svclb-") for _, name in ds_names)
    storage = []
    default_sc = []
    for sc in raw["storageclasses"].get("items", []):
        annotations = sc["metadata"].get("annotations", {})
        is_default = annotations.get("storageclass.kubernetes.io/is-default-class") == "true"
        storage.append({"name": sc["metadata"]["name"], "provisioner": sc.get("provisioner"), "default": is_default})
        if is_default:
            default_sc.append(sc["metadata"]["name"])
    crds = {c["metadata"]["name"]: c for c in raw["crds"].get("items", [])}
    gateway_bundle = ""
    if "gateways.gateway.networking.k8s.io" in crds:
        gateway_bundle = crds["gateways.gateway.networking.k8s.io"]["metadata"].get("annotations", {}).get(
            "gateway.networking.k8s.io/bundle-version", "inconnue")
    apiservices = {a["metadata"]["name"]: a for a in raw["apiservices"].get("items", [])}
    csidrivers = {c["metadata"]["name"] for c in raw["csidrivers"].get("items", [])}
    releases = raw.get("helm", [])
    helm_error = releases is None
    releases = releases or []
    managed_by_lab = set()
    state = raw.get("state")
    if state:
        managed_by_lab = {k for k in state.get("data", {}) if not k.startswith("_")}
    argocd_tracked = []
    for dep in raw["deployments"].get("items", []):
        annotations = dep["metadata"].get("annotations", {})
        if "argocd.argoproj.io/tracking-id" in annotations or \
                dep["metadata"].get("labels", {}).get("argocd.argoproj.io/instance"):
            argocd_tracked.append(f"{dep['metadata']['namespace']}/{dep['metadata']['name']}")
    present: dict[str, dict[str, Any]] = {}
    for addon_id, prints in FINGERPRINTS.items():
        evidence = []
        evidence += [f"CRD {c}" for c in prints.get("crds", []) if c in crds]
        evidence += [f"APIService {a}" for a in prints.get("apiservices", []) if a in apiservices]
        evidence += [f"CSIDriver {d}" for d in prints.get("csidrivers", []) if d in csidrivers]
        charts = [r for r in releases if any(str(r.get("chart", "")).startswith(c + "-") for c in prints.get("charts", []))]
        evidence += [f"release Helm {r['namespace']}/{r['name']} ({r['chart']})" for r in charts]
        if addon_id == "traefik" and distribution in ("k3s", "rke2") and any(
                d["metadata"]["name"] == "traefik" for d in raw["deployments"].get("items", [])):
            evidence.append(f"Traefik intégré à {distribution}")
        if evidence:
            present[addon_id] = {"evidence": evidence, "managed_by_lab": addon_id in managed_by_lab,
                                 "helm_releases": [f"{r['namespace']}/{r['name']}" for r in charts]}
    return {
        "reachable": True,
        "context": context,
        "server_version": git_version,
        "minor": f"{server.get('major', '')}.{str(server.get('minor', '')).rstrip('+')}",
        "distribution": distribution,
        "nodes": [{k: v for k, v in n.items() if k != "labels"} for n in node_info],
        "cni": cni,
        "kube_proxy": kube_proxy,
        "servicelb": servicelb,
        "storage_classes": storage,
        "default_storage_classes": default_sc,
        "gateway_api_bundle": gateway_bundle,
        "gateway_classes": [g["metadata"]["name"] for g in raw["gatewayclasses"].get("items", [])],
        "helm_releases": [f"{r['namespace']}/{r['name']} {r.get('chart', '')} ({r.get('status', '')})" for r in releases],
        "helm_error": helm_error,
        "crd_count": len(crds),
        "present": present,
        "argocd_tracked": argocd_tracked,
        "managed_by_lab": sorted(managed_by_lab),
    }


def conflicts(report: dict[str, Any], catalog: Catalog, wanted: list[str], policy: str) -> list[dict[str, str]]:
    found: list[dict[str, str]] = []
    if not report.get("reachable"):
        return [{"level": "error", "addon": "-", "message": report.get("error", "cluster injoignable")}]
    if report.get("helm_error") and wanted:
        found.append({"level": "error", "addon": "-",
                      "message": "Impossible de lister les releases Helm du cluster (helm list) : la détection des "
                                 "composants déjà installés serait incomplète, rien n'est installé.",
                      "hint": "Vérifiez helm (make doctor) et les droits du kubeconfig sur les Secrets des namespaces."})
    for addon_id in wanted:
        info = report["present"].get(addon_id)
        if info and not info["managed_by_lab"]:
            tracked = [t for t in report["argocd_tracked"] if addon_id.split("-")[0] in t]
            if tracked:
                found.append({"level": "error", "addon": addon_id,
                              "message": f"{addon_id} est déjà déployé et géré par Argo CD ({', '.join(tracked)}) : "
                                         "le framework ne reprend jamais des ressources gérées par GitOps."})
            elif policy == "skip":
                found.append({"level": "info", "addon": addon_id,
                              "message": f"{addon_id} déjà présent ({'; '.join(info['evidence'])}) : utilisé tel quel, "
                                         "non géré (EXISTING_ADDON_POLICY=skip)."})
            else:
                found.append({"level": "error", "addon": addon_id,
                              "message": f"{addon_id} est déjà installé par un autre outil "
                                         f"({'; '.join(info['evidence'])}).",
                              "hint": "Le framework ne prend pas le contrôle d'un composant existant. "
                                      "EXISTING_ADDON_POLICY=skip pour l'utiliser tel quel, ou retirez-le d'ADDONS."})
    if "metallb" in wanted and report.get("servicelb"):
        found.append({"level": "error", "addon": "metallb",
                      "message": "ServiceLB (klipper, k3s/rke2) est actif : deux fournisseurs LoadBalancer se "
                                 "disputeraient les Services. Désactivez ServiceLB d'abord (--disable=servicelb)."})
    if "metallb" in wanted and "cilium" in report.get("cni", []) and \
            "ciliumloadbalancerippools.cilium.io" in str(report.get("present", {})):
        found.append({"level": "warning", "addon": "metallb",
                      "message": "Cilium est présent : vérifiez qu'aucun CiliumLoadBalancerIPPool ne couvre le pool MetalLB."})
    needs_crds = [a for a in wanted if a in ("traefik", "envoy-gateway", "gateway", "gateway-api-crds")]
    bundle = report.get("gateway_api_bundle")
    if needs_crds and bundle:
        required = {catalog.component(c).get("gateway_api", "") for c in ("traefik", "envoy-gateway") if c in wanted}
        for version in required:
            if version and bundle != "inconnue" and _vt(bundle) < _vt(version):
                found.append({"level": "error", "addon": "gateway-api-crds",
                              "message": f"CRD Gateway API {bundle} déjà installées, {version} requises : mise à jour "
                                         "des CRD = migration à valider (elles appartiennent peut-être à un autre outil)."})
    if report.get("distribution") in ("k3s", "rke2") and "traefik" in wanted:
        found.append({"level": "error", "addon": "traefik",
                      "message": f"{report['distribution']} embarque déjà Traefik : désactivez-le ou utilisez "
                                 "GATEWAY_CONTROLLER=envoy-gateway."})
    return found


def _vt(version: str) -> tuple[int, ...]:
    out = []
    for part in version.lstrip("v").split("."):
        digits = "".join(ch for ch in part if ch.isdigit())
        out.append(int(digits) if digits else 0)
    return tuple(out)


def report_text(report: dict[str, Any], catalog: Catalog, wanted: list[str], policy: str) -> str:
    if not report.get("reachable"):
        return f"[erreur] {report.get('error')}"
    lines = [f"Cluster du contexte « {report['context']} »",
             f"  Version            {report['server_version']} (distribution détectée : {report['distribution']})",
             f"  Nœuds              {len(report['nodes'])}"]
    for node in report["nodes"]:
        lines.append(f"    {node['name']:<24} {','.join(node['roles']) or '-':<14} {node['os_image']} / {node['kernel']} / {node['runtime']}")
    lines += [f"  CNI                {', '.join(report['cni']) or 'non identifié'} ; kube-proxy : {'oui' if report['kube_proxy'] else 'non'}",
              f"  StorageClasses     {', '.join(s['name'] + (' (défaut)' if s['default'] else '') for s in report['storage_classes']) or 'aucune'}",
              f"  Gateway API        CRD {report['gateway_api_bundle'] or 'absentes'} ; classes : {', '.join(report['gateway_classes']) or 'aucune'}",
              f"  Releases Helm      {len(report['helm_releases'])}",
              f"  Gérés par k8s-lab  {', '.join(report['managed_by_lab']) or 'aucun'}"]
    if report["present"]:
        lines.append("  Composants déjà présents :")
        for addon_id, info in sorted(report["present"].items()):
            owner = "k8s-lab" if info["managed_by_lab"] else "autre outil"
            lines.append(f"    {addon_id:<24} ({owner}) {'; '.join(info['evidence'])}")
    issues = conflicts(report, catalog, wanted, policy)
    if wanted:
        lines.append("")
        lines.append(f"Addons demandés : {', '.join(wanted)}")
        if not issues:
            lines.append("  Aucun conflit détecté.")
        for issue in issues:
            label = {"error": "[erreur]", "warning": "[attention]", "info": "[info]"}[issue["level"]]
            lines.append(f"  {label} {issue['message']}")
            if issue.get("hint"):
                lines.append(f"      {issue['hint']}")
    return "\n".join(lines)
