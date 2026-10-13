"""Sorties du résolveur : texte (make config / addons-plan), variables Ansible,
manifeste de déploiement, matrice de compatibilité, variables shell."""
from __future__ import annotations

import copy
import datetime as _dt
import json
import re
import shlex
import subprocess
from typing import Any

import yaml

from .catalog import PLATFORMS, STATUS_LABELS, Catalog
from .config import Config
from .resolve import KUBEADM_PLATFORMS, Plan

COLOR = {"error": "\033[31m", "warning": "\033[33m", "info": "\033[2m", "ok": "\033[32m",
         "bold": "\033[1m", "reset": "\033[0m"}
LEVEL_LABEL = {"error": "[erreur]", "warning": "[attention]", "info": "[info]"}
PLATFORM_LABELS = {"kind": "Kind", "minikube": "Minikube", "vagrant": "Vagrant", "proxmox": "Proxmox",
                   "vsphere": "vSphere", "libvirt": "libvirt", "existing": "Existing", "eks": "EKS",
                   "attach": "Attach"}
STATUS_SHORT = {"supported": "✅", "configured": "⚙️", "experimental": "🧪", "unsupported": "❌"}


def _c(key: str, color: bool) -> str:
    return COLOR[key] if color else ""


# --- issues -------------------------------------------------------------------------
def issues_text(plan: Plan, color: bool = False, show_info: bool = True) -> str:
    lines = []
    for level in ("error", "warning", "info"):
        if level == "info" and not show_info:
            continue
        for issue in [i for i in plan.issues if i.level == level]:
            lines.append(f"{_c(level, color)}{LEVEL_LABEL[level]}{_c('reset', color)} {issue.message}")
            if issue.hint:
                lines.append(f"    {issue.hint}")
    return "\n".join(lines)


def summary_text(plan: Plan, color: bool = False) -> str:
    r = plan.resolved
    b = lambda s: f"{_c('bold', color)}{s}{_c('reset', color)}"  # noqa: E731
    lines = [b("Choix résolus"), f"  Plateforme        {plan.platform} (mode {plan.mode}{' ' + plan.provider if plan.provider else ''})",
             f"  Contexte kubectl  {r.get('kube_context', '?')}"]
    if r.get("control_plane_count") is not None:
        lines.append(f"  Topologie         {r['control_plane_count']} control-plane(s) + {r['worker_count']} worker(s), HA : {r.get('ha_mode')}")
    if r.get("api_lb_provider") not in (None, "platform", "none"):
        lines.append(f"  API Kubernetes    {r.get('control_plane_endpoint') or '?'} ({r.get('api_lb_provider')})")
    os_info = r.get("node_os", {})
    if os_info.get("name") not in (None, "platform"):
        lines.append(f"  Système           {os_info.get('name')} {os_info.get('version', '')}")
    if r.get("kubernetes_minor"):
        lines.append(f"  Kubernetes        {r.get('kubernetes_version') if plan.platform in KUBEADM_PLATFORMS else r['kubernetes_minor']}")
    cni = r.get("cni", "?")
    extra = f" {r['cni_version']}" if r.get("cni_version") else ""
    mode = f", mode {r['cni_mode']}" if r.get("cni_mode") not in (None, "auto") else ""
    lines.append(f"  CNI               {cni}{extra}{mode} ; kube-proxy : {r.get('kube_proxy_mode')} ; NetworkPolicy : {r.get('network_policy_mode')}")
    if r.get("pod_cidr"):
        lines.append(f"  Réseaux           Pods {r['pod_cidr']}, Services {r['service_cidr']}, nœuds {r.get('node_network_cidr') or '?'}")
    gw = r.get("gateway_controller", "none")
    if gw != "none":
        api = r.get("gateway_api", {})
        lines.append(f"  Gateway API       {gw} (CRD {api.get('version')} {api.get('channel')}), Service {r.get('gateway_service_type')}, TLS : {'oui' if r.get('gateway_tls') else 'non'}")
    lb = r.get("loadbalancer", {})
    if lb.get("provider", "none") != "none":
        lines.append(f"  LoadBalancer      {lb['provider']} {lb.get('mode', '')} pool {','.join(lb.get('pool', []))}")
    if r.get("storage_backends"):
        dsc = r.get("default_storage_class", {})
        lines.append(f"  Stockage          {', '.join(r['storage_backends'])} (défaut : {dsc.get('name') or dsc.get('backend')})")
    if plan.nodes:
        lines.append(b("Nœuds prévus"))
        for node in plan.nodes:
            lines.append(f"  {node['name']:<22} {node['role']:<14} {node['ip']}")
    return "\n".join(lines)


def config_text(cfg: Config, color: bool = False) -> str:
    """Tableau de la configuration effective (secrets masqués), par groupe du schéma."""
    lines = []
    groups: dict[str, list[str]] = {}
    for key in cfg.lab_keys:
        spec = cfg.schema.get(key)
        groups.setdefault(spec.group if spec else "misc", []).append(key)
    for group, keys in groups.items():
        lines.append(f"{_c('bold', color)}{cfg.schema.groups.get(group, group)}{_c('reset', color)}")
        for key in keys:
            source = cfg.source(key)
            marker = "" if source == "config/lab.env" else f"   ({source})"
            lines.append(f"  {key:<30} {cfg.masked(key)}{_c('info', color)}{marker}{_c('reset', color)}")
    secrets = cfg.secrets_present()
    lines.append(f"{_c('bold', color)}Identifiants{_c('reset', color)}")
    lines.append("  " + (" ".join(f"{k}=****" for k in secrets) if secrets else "aucun"))
    others = [k for k, s in cfg.sources.items() if s in (".env", "environnement") and k not in cfg.lab_keys
              and not (cfg.schema.get(k) and cfg.schema.get(k).secret)]
    if others:
        lines.append(f"{_c('bold', color)}Autres réglages de .env{_c('reset', color)}")
        for key in others:
            lines.append(f"  {key:<30} {cfg.masked(key)}")
    return "\n".join(lines)


def plan_text(plan: Plan, color: bool = False) -> str:
    lines = [f"{_c('bold', color)}Addons prévus ({len(plan.addons)}), dans l'ordre d'installation{_c('reset', color)}"]
    if not plan.addons:
        lines.append("  aucun (profil minimal : Kubernetes + CNI + CoreDNS)")
    for index, item in enumerate(plan.addons, start=1):
        versions = ", ".join(f"{c['name']} {c['version']}" for c in item.components if c.get("version")) or "—"
        status = STATUS_LABELS[item.support].lower()
        lines.append(f"  {index:>2}. {item.id:<26} phase {item.phase}  {versions}")
        lines.append(f"      pourquoi : {' ; '.join(item.reasons)}   support ({plan.platform}) : {status}")
    return "\n".join(lines)


# --- variables Ansible ----------------------------------------------------------------
def _node_prereqs(plan: Plan) -> dict[str, Any]:
    packages: dict[str, list[str]] = {"debian": [], "redhat": []}
    modules: list[str] = []
    services: list[str] = []
    ports: list[dict[str, Any]] = []
    for item in plan.addons:
        prereqs = item.addon.node_prereqs
        for family, names in prereqs.get("packages", {}).items():
            for name in names:
                if name not in packages.setdefault(family, []):
                    packages[family].append(name)
        modules += [m for m in prereqs.get("kernel_modules", []) if m not in modules]
        services += [s for s in prereqs.get("services", []) if s not in services]
        ports += [p for p in prereqs.get("firewall_ports", []) if p not in ports]
    return {"packages": packages, "kernel_modules": modules, "services": services, "firewall_ports": ports}


def _public(cfg: Config, key: str) -> bool:
    """Variable transmissible à Ansible ou au manifeste : ni secret, ni identifiant (groupe credentials).
    Les rôles lisent les identifiants dans l'environnement, au moment de créer les Secrets."""
    spec = cfg.schema.get(key)
    return not (spec and (spec.secret or spec.group == "credentials"))


def ansible_vars(plan: Plan, cfg: Config, catalog: Catalog) -> dict[str, Any]:
    r = plan.resolved
    comps = catalog.versions["components"]
    public_cfg = {k: v for k, v in cfg.values.items() if _public(cfg, k)}
    resolved = {k: v for k, v in r.items() if not k.startswith("_") and k != "tfvars"}
    addons = []
    for item in plan.addons:
        components = {}
        for name in item.addon.components:
            comp = dict(comps[name])
            if name == "longhorn" and r.get("longhorn_version"):
                comp["version"] = r["longhorn_version"]
            components[name] = comp
        spec = copy.deepcopy(item.addon.data)
        for release in spec.get("install", {}).get("releases", []):
            # only_if : {VARIABLE: [valeurs acceptées]} -> release installée ou non.
            release["enabled"] = all(cfg.get(key) in allowed for key, allowed in release.get("only_if", {}).items())
        addons.append({"id": item.id, "path": str(item.addon.path), "reasons": item.reasons,
                       "support": item.support, "spec": spec, "components": components,
                       "versions": {name: comp.get("version", "") for name, comp in components.items()},
                       "stateful": item.addon.stateful})
    cni_comp = comps.get(r.get("cni", ""), {})
    gateway_api = r.get("gateway_api") or {}
    gw_comp = comps["gateway-api"]
    data: dict[str, Any] = {
        "lab": resolved,
        "cfg": public_cfg,
        "lab_addons": addons,
        "lab_addon_ids": [a["id"] for a in addons],
        # Namespaces des composants qui exigent des Pods privilégiés (exclus des politiques Kyverno).
        "lab_privileged_namespaces": sorted({"kube-system"} | {
            a["spec"].get("install", {}).get("namespace") for a in addons
            if a["spec"].get("install", {}).get("pod_security") == "privileged"} - {None}),
        "lab_test_images": catalog.versions.get("test_images", {}),
        "lab_versions": {"helm": catalog.versions["helm"], "kube_vip": catalog.versions["kube_vip"],
                         "os": catalog.versions["os"]},
        # --- variables historiques des rôles kubeadm (compatibilité) ---
        "kubernetes_version": r.get("kubernetes_version"),
        "pod_cidr": r.get("pod_cidr"),
        "service_cidr": r.get("service_cidr"),
        "cni": r.get("cni") if r.get("cni") in ("flannel", "calico", "cilium", "none") else "none",
        "cni_version": r.get("cni_version", ""),
        "cni_mode": r.get("cni_mode", "auto"),
        "flannel_version": r.get("cni_version") if r.get("cni") == "flannel" else comps["flannel"]["version"],
        "container_runtime": cfg.get("CONTAINER_RUNTIME"),
        "containerd_version": r.get("containerd_version", ""),
        "containerd_selinux": cfg.bool("CONTAINERD_SELINUX"),
        "kube_proxy_mode": r.get("kube_proxy_mode"),
        "network_policy_mode": r.get("network_policy_mode"),
        "kubelet_serving_certs": cfg.get("KUBELET_SERVING_CERTS"),
        "node_swap": cfg.get("NODE_SWAP"),
        "node_firewall": cfg.get("NODE_FIREWALL"),
        "control_plane_count": r.get("control_plane_count"),
        "ha_mode": r.get("ha_mode"),
        "api_lb_provider": r.get("api_lb_provider"),
        "control_plane_vip": r.get("control_plane_vip", ""),
        "control_plane_endpoint": r.get("control_plane_endpoint", ""),
        "node_os_expected": r.get("node_os", {}),
        "node_prereqs": _node_prereqs(plan),
        "cni_component": cni_comp,
        "gateway_api_crds": {**gateway_api, "url": gw_comp["url"],
                             "sha256": gw_comp["sha256"].get(gateway_api.get("version", ""), {})} if gateway_api else {},
        "hubble": r.get("hubble", {}),
        "loadbalancer": r.get("loadbalancer", {}),
        "istio_selected": "istio" in plan.addon_ids(),
        "monitoring_selected": "monitoring" in plan.addon_ids(),
        "longhorn_disk": {
            "enabled": cfg.bool("LONGHORN_DEDICATED_DISK") and "longhorn" in plan.addon_ids(),
            "device": cfg.get("LONGHORN_DISK_DEVICE"),
            "allow_format": cfg.bool("LONGHORN_DISK_ALLOW_FORMAT"),
            "mount_path": cfg.get("LONGHORN_DATA_PATH"),
        },
        "backup": r.get("backup", {}),
        "lab_platform": plan.platform,
    }
    return data


# --- manifeste de déploiement (sans secret) ---------------------------------------------
def deployment_manifest(plan: Plan, cfg: Config, catalog: Catalog) -> dict[str, Any]:
    r = plan.resolved
    try:
        commit = subprocess.run(["git", "-C", str(cfg.root), "rev-parse", "HEAD"], capture_output=True,
                                text=True, check=False, timeout=5).stdout.strip()
        dirty = bool(subprocess.run(["git", "-C", str(cfg.root), "status", "--porcelain"], capture_output=True,
                                    text=True, check=False, timeout=5).stdout.strip())
    except (OSError, subprocess.SubprocessError):
        commit, dirty = "", False
    os_info = {k: v for k, v in r.get("node_os", {}).items() if k in ("name", "version", "family", "kernel", "status")}
    manifest = {
        "apiVersion": "k8s-lab.io/v1",
        "kind": "DeploymentManifest",
        "generated_at": _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat(),
        "framework": {"commit": commit, "uncommitted_changes": dirty,
                      "versions_lock_checked_on": catalog.versions.get("checked_on")},
        "platform": {"mode": plan.mode, "provider": plan.provider, "platform": plan.platform,
                     "kube_context": r.get("kube_context")},
        "cluster": {"name": r.get("cluster_name"), "kubernetes_version": r.get("kubernetes_version")
                    if plan.platform in KUBEADM_PLATFORMS else r.get("kubernetes_minor"),
                    "control_planes": r.get("control_plane_count"), "workers": r.get("worker_count"),
                    "ha_mode": r.get("ha_mode"), "api_endpoint": r.get("control_plane_endpoint"),
                    "api_load_balancer": r.get("api_lb_provider")},
        "nodes": {"os": os_info, "cpus": cfg.int("NODE_CPUS"), "memory_mb": cfg.int("NODE_MEMORY_MB"),
                  "disk_gb": cfg.int("NODE_DISK_GB"), "cpu_type": cfg.get("NODE_CPU_TYPE"),
                  "image": {k: v for k, v in r.get("image", {}).items()}, "planned": plan.nodes},
        "network": {"pod_cidr": r.get("pod_cidr"), "service_cidr": r.get("service_cidr"),
                    "node_network": r.get("node_network_cidr"),
                    "cni": {"name": r.get("cni"), "version": r.get("cni_version"), "mode": r.get("cni_mode"),
                            "kube_proxy": r.get("kube_proxy_mode"), "network_policy": r.get("network_policy_mode")},
                    "gateway": {"controller": r.get("gateway_controller"), **(r.get("gateway_api") or {}),
                                "domain": cfg.get("GATEWAY_DOMAIN"), "tls": r.get("gateway_tls")},
                    "loadbalancer": r.get("loadbalancer")},
        "storage": {"backends": r.get("storage_backends"), "default_class": r.get("default_storage_class"),
                    "nfs": {"server": cfg.get("NFS_SERVER"), "share": cfg.get("NFS_SHARE"),
                            "version": cfg.get("NFS_VERSION"), "reclaim_policy": cfg.get("NFS_RECLAIM_POLICY")}
                    if "nfs-csi" in (r.get("storage_backends") or []) else None,
                    "longhorn": {"version": r.get("longhorn_version"), "replicas": cfg.int("LONGHORN_REPLICA_COUNT"),
                                 "dedicated_disk": cfg.bool("LONGHORN_DEDICATED_DISK"),
                                 "reclaim_policy": cfg.get("LONGHORN_RECLAIM_POLICY")}
                    if "longhorn" in (r.get("storage_backends") or []) else None},
        "security": {"kubelet_serving_certs": cfg.get("KUBELET_SERVING_CERTS"),
                     "containerd_selinux": cfg.bool("CONTAINERD_SELINUX"),
                     "node_firewall": cfg.get("NODE_FIREWALL"),
                     "compatibility_policy": cfg.get("COMPATIBILITY_POLICY")},
        "addons": [{"id": a.id, "reasons": a.reasons, "support": a.support,
                    "components": [{k: c[k] for k in ("name", "version", "chart") if c.get(k)} for c in a.components]}
                   for a in plan.addons],
        "backup": r.get("backup"),
        "issues": [{"level": i.level, "message": i.message} for i in plan.issues if i.level != "info"],
        "effective_configuration": {k: cfg.masked(k) for k in cfg.lab_keys
                                    if _public(cfg, k)},
    }
    return manifest


# --- matrice de compatibilité (docs/compatibility.md) --------------------------------------
def matrix_markdown(catalog: Catalog) -> str:
    head = "| Addon | " + " | ".join(PLATFORM_LABELS[p] for p in PLATFORMS) + " | Testé en CI |"
    sep = _md_sep(len(PLATFORMS) + 2)
    rows = [head, sep]
    notes = []
    for addon in sorted(catalog.addons.values(), key=lambda a: (a.phase, a.id)):
        cells = []
        for platform in PLATFORMS:
            support = addon.support_for(platform)
            cell = STATUS_SHORT[support.status]
            if support.note:
                notes.append(f"- **{addon.id} / {PLATFORM_LABELS[platform]}** : {support.note}")
                cell += f"<sup>{len(notes)}</sup>"
            cells.append(cell)
        validated = ", ".join(v.removeprefix("ci-") for v in addon.validated) or "non"
        rows.append(f"| [{addon.id}](addons.md#{addon.id}) | " + " | ".join(cells) + f" | {validated} |")
    legend = ("Légende : ✅ supporté · ⚙️ supporté avec configuration particulière · 🧪 expérimental · "
              "❌ non supporté. « Testé en CI » indique les environnements où l'addon est réellement "
              "installé et testé par la CI ; une case ✅ sans test signifie « supporté en théorie, non "
              "validé en conditions réelles ».")
    numbered = [f"{i}. {n[2:]}" for i, n in enumerate(notes, start=1)]
    return "\n".join(rows) + "\n\n" + legend + "\n\nNotes :\n\n" + "\n".join(numbered) + "\n"


def os_matrix_markdown(catalog: Catalog) -> str:
    rows = ["| Distribution | Version | Statut | Noyau | CPU x86-64 minimal | Testé en CI | Image épinglée |",
            _md_sep(7)]
    for name, versions in catalog.versions["os"].items():
        for version, entry in versions.items():
            image = entry["image_url"].rsplit("/", 1)[-1]
            rows.append(f"| {name} | {version} | {entry['status']} | {entry['kernel']} | {entry['x86_64_level']} | "
                        f"{'oui (kubeadm-in-docker)' if entry.get('validated') == 'ci' else 'non'} | `{image}` |")
    return "\n".join(rows) + "\n"


# --- variables shell (consommées par le CLI Bash) ---------------------------------------------
def shell_exports(plan: Plan, cfg: Config) -> str:
    r = plan.resolved
    image = r.get("image", {})
    os_info = r.get("node_os", {})
    values = {
        "LAB_R_ERRORS": str(len(plan.errors)),
        "LAB_R_PLATFORM": plan.platform,
        "LAB_R_CONTEXT": r.get("kube_context", ""),
        "LAB_R_KUBECONFIG": r.get("kubeconfig", ""),
        "LAB_R_CNI": r.get("cni", ""),
        "LAB_R_CNI_INSTALL": r.get("cni_install", ""),
        "LAB_R_KUBE_PROXY_MODE": r.get("kube_proxy_mode", ""),
        "LAB_R_KIND_NODE_IMAGE": r.get("kind_node_image", ""),
        "LAB_R_MINIKUBE_K8S": r.get("minikube_kubernetes_version", ""),
        "LAB_R_CP_COUNT": str(r.get("control_plane_count") or ""),
        "LAB_R_WORKER_COUNT": str(r.get("worker_count") if r.get("worker_count") is not None else ""),
        "LAB_R_HA_MODE": r.get("ha_mode", ""),
        "LAB_R_VIP": r.get("control_plane_vip", "") or "",
        "LAB_R_ENDPOINT": r.get("control_plane_endpoint", "") or "",
        "LAB_R_API_LB": r.get("api_lb_provider", "") or "",
        "LAB_R_ADDONS": " ".join(plan.addon_ids()),
        "LAB_R_OS_NAME": os_info.get("name", ""),
        "LAB_R_OS_VERSION": str(os_info.get("version", "")),
        "LAB_R_OS_FAMILY": os_info.get("family", ""),
        "LAB_R_SSH_USER": r.get("node_ssh_user", ""),
        "LAB_R_IMAGE_SOURCE": image.get("source", ""),
        "LAB_R_IMAGE_URL": image.get("url", ""),
        "LAB_R_IMAGE_SHA256": image.get("sha256", ""),
        "LAB_R_TEMPLATE": image.get("template", ""),
        "LAB_R_VAGRANT_BOX": image.get("box", ""),
        "LAB_R_EXISTING_INVENTORY": r.get("existing_inventory", ""),
        "LAB_R_LONGHORN_DISK": "true" if cfg.bool("LONGHORN_DEDICATED_DISK") and "longhorn" in plan.addon_ids() else "false",
        "LAB_R_ETCD_BACKUP": "true" if (r.get("backup") or {}).get("etcd_snapshots") else "false",
        "LAB_R_GATEWAY": r.get("gateway_controller", ""),
        "LAB_R_LB": (r.get("loadbalancer") or {}).get("provider", ""),
        "LAB_R_HUBBLE": "true" if (r.get("hubble") or {}).get("enabled") else "false",
        "LAB_R_CILIUM_ISTIO": "true" if "istio" in plan.addon_ids() else "false",
    }
    return "\n".join(f"export {k}={shlex.quote(v)}" for k, v in values.items()) + "\n"


def to_yaml(data: Any) -> str:
    return yaml.safe_dump(data, sort_keys=False, allow_unicode=True, default_flow_style=False, width=120)


def to_json(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False, default=str)


# --- sections générées de la documentation (make docs-generate / docs-check) -------------
def _md_escape(text: str) -> str:
    """Cellule de tableau Markdown : barres échappées, URL nues entre chevrons (MD034)."""
    text = str(text).replace("|", "\\|").replace("\n", " ")
    return re.sub(r"(?<![<(`])(https?://[^\s)>`]+)", r"<\1>", text)


def _md_sep(columns: int) -> str:
    """Ligne de séparation d'un tableau Markdown (style « compact » de markdownlint)."""
    return "|" + " --- |" * columns


def variables_markdown(cfg: Config) -> str:
    """Référence de toutes les variables, par groupe (config/schema.yaml + défauts de lab.env)."""
    from .envfile import parse_env_file
    defaults, _ = parse_env_file(cfg.root / "config" / "lab.env")
    schema = cfg.schema
    out = []
    for group, title in schema.groups.items():
        specs = [s for s in schema.variables.values() if s.group == group]
        if not specs:
            continue
        out += [f"### {title}", "", "| Variable | Défaut | Type / valeurs | Description |", _md_sep(4)]
        for spec in specs:
            if spec.secret or not spec.lab_env:
                default = "*(.env uniquement)*" if spec.secret or spec.group == "credentials" else "*(alias, non défini)*"
            else:
                value = defaults.get(spec.name, "")
                default = f"`{value}`" if value else "*(vide)*"
            kind = spec.type
            if spec.values:
                kind = " · ".join(f"`{v}`" for v in spec.values)
            elif spec.minimum is not None or spec.maximum is not None:
                kind += f" ({spec.minimum if spec.minimum is not None else ''}…{spec.maximum if spec.maximum is not None else ''})"
            description = spec.description + (f" **Obsolète** : {spec.deprecated}" if spec.deprecated else "")
            if spec.secret:
                description += " *Secret : jamais affiché ni écrit dans un fichier généré.*"
            out.append(f"| `{spec.name}` | {default} | {_md_escape(kind)} | {_md_escape(description)} |")
        out.append("")
    return "\n".join(out)


def catalog_markdown(catalog: Catalog) -> str:
    rows = ["| Addon | Catégorie | Phase | Composants (versions verrouillées) | Rôle |", _md_sep(5)]
    comps = catalog.versions["components"]
    for addon in sorted(catalog.addons.values(), key=lambda a: (a.phase, a.id)):
        versions = ", ".join(f"{c} {comps[c].get('version', '')}".strip() for c in addon.components) or "—"
        flag = " *(interne)*" if addon.internal else ""
        rows.append(f"| [{addon.id}](#{addon.id}){flag} | {addon.category} | {addon.phase} | {versions} | "
                    f"{_md_escape(addon.data.get('name', addon.id))} |")
    return "\n".join(rows) + "\n"


def catalog_details_markdown(catalog: Catalog) -> str:
    """Fiche de chaque addon (ancre #<id>), générée depuis addons/<id>/addon.yaml."""
    comps = catalog.versions["components"]
    out = []
    for addon in sorted(catalog.addons.values(), key=lambda a: (a.phase, a.id)):
        data = addon.data
        install = data.get("install", {})
        out += [f"### {addon.id}", "", f"**{_md_escape(data.get('name', addon.id))}** — "
                f"{' '.join(str(data.get('description', '')).split())}", ""]
        rows = [("Catégorie, phase", f"{addon.category}, phase {addon.phase}" + (" (interne)" if addon.internal else ""))]
        if addon.components:
            rows.append(("Composants", ", ".join(f"{c} {comps[c].get('version', '')}".strip() for c in addon.components)))
        if install.get("namespace"):
            rows.append(("Namespace", f"`{install['namespace']}` (Pod Security : {install.get('pod_security', 'baseline')})"))
        if addon.depends_on:
            rows.append(("Dépend de", ", ".join(addon.depends_on)))
        if addon.optional_deps:
            rows.append(("S'intègre avec", ", ".join(addon.optional_deps)))
        if addon.conflicts_with:
            rows.append(("Incompatible avec", ", ".join(addon.conflicts_with)))
        requires = data.get("requires", {})
        if requires:
            rows.append(("Exige", "; ".join(f"{k} : {', '.join(map(str, v)) if isinstance(v, list) else v}"
                                            for k, v in requires.items())))
        selected = data.get("selected_by", {})
        if selected:
            rows.append(("Activé par", "; ".join(f"`{k}={'|'.join(map(str, v))}`" for k, v in selected.items())))
        if addon.settings:
            rows.append(("Réglages (.env)", ", ".join(f"`{x}`" for x in addon.settings)))
        if addon.secrets:
            rows.append(("Secrets (.env uniquement)", ", ".join(f"`{x}`" for x in addon.secrets)))
        rows.append(("Données", "oui : jamais supprimées automatiquement" if addon.stateful else "non"))
        rows.append(("Test fonctionnel", f"`addons/{addon.id}/{data['tests']}`" if data.get("tests") else
                     "via les addons qui l'utilisent"))
        rows.append(("Testé en CI", ", ".join(v.removeprefix("ci-") for v in addon.validated)
                     or "non (validé statiquement : rendu et helm template)"))
        notes = data.get("remove", {}).get("notes")
        if notes:
            rows.append(("Désinstallation", " ".join(str(notes).split())))
        out += ["| | |", _md_sep(2)] + [f"| {k} | {_md_escape(v)} |" for k, v in rows] + [""]
    return "\n".join(out)


def versions_markdown(catalog: Catalog) -> str:
    v = catalog.versions
    k8s = v["kubernetes"]
    rows = [f"Vérifiées le **{v.get('checked_on')}** (`make versions-check` compare avec les dépôts officiels).", "",
            "| Élément | Version | Source |", _md_sep(3),
            f"| Kubernetes (défaut) | {k8s['version']} | mineures supportées : {', '.join(k8s['supported_minors'])} |",
            f"| containerd | {v['containerd']['version']} | download.docker.com (containerd.io) |",
            f"| Helm (sur les nœuds) | {v['helm']['version']} | get.helm.sh (SHA-256 verrouillé) |",
            f"| kube-vip | {v['kube_vip']['version']} | {v['kube_vip']['image']} |"]
    for minor, image in sorted(k8s.get("kind_node_images", {}).items()):
        rows.append(f"| image kind {minor} | `{image.split('@')[0].rsplit(':', 1)[-1]}` | {image.split(':')[0]} (condensé épinglé) |")
    for name, comp in sorted(v["components"].items()):
        source = {"helm": comp.get("repo", ""), "helm-oci": comp.get("chart", ""),
                  "manifest": "manifeste + SHA-256"}.get(comp["type"], comp["type"])
        rows.append(f"| {name} | {comp.get('version', '-')} | {_md_escape(source)} |")
    return "\n".join(rows) + "\n"


def generated_sections(cfg: Config, catalog: Catalog) -> dict[str, dict[str, str]]:
    """Fichier -> {marqueur: contenu} des sections générées de la documentation."""
    return {
        "docs/compatibility.md": {"addons": matrix_markdown(catalog), "os": os_matrix_markdown(catalog)},
        "docs/configuration.md": {"variables": variables_markdown(cfg)},
        "docs/addons.md": {"catalog": catalog_markdown(catalog), "details": catalog_details_markdown(catalog)},
        "docs/versions.md": {"versions": versions_markdown(catalog)},
    }
