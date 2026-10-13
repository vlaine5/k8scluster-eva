"""Lecture des inventaires Ansible (INI ou YAML) et des terraform.tfvars.

Utilisé uniquement pour VALIDER la configuration avant toute action
(nombre de control-planes, adresses, chevauchements). À l'exécution,
c'est Ansible lui-même qui lit l'inventaire.
"""
from __future__ import annotations

import re
import shlex
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import yaml


@dataclass
class Host:
    name: str
    vars: dict[str, str] = field(default_factory=dict)
    groups: set[str] = field(default_factory=set)

    @property
    def address(self) -> str:
        return self.vars.get("node_ip") or self.vars.get("ansible_host") or self.name


@dataclass
class Inventory:
    path: Path
    hosts: dict[str, Host]
    group_vars: dict[str, dict[str, str]]

    def group(self, name: str) -> list[Host]:
        return [h for h in self.hosts.values() if name in h.groups]

    @property
    def control_planes(self) -> list[Host]:
        return self.group("control_plane")

    @property
    def workers(self) -> list[Host]:
        return self.group("workers")

    def var(self, name: str) -> Optional[str]:
        for group in ("k8s_cluster", "all"):
            if name in self.group_vars.get(group, {}):
                return self.group_vars[group][name]
        return None


class InventoryError(ValueError):
    pass


def load_inventory(path: Path) -> Inventory:
    if not path.is_file():
        raise InventoryError(f"inventaire introuvable : {path}")
    text = path.read_text(encoding="utf-8")
    if path.suffix in (".yml", ".yaml"):
        return _load_yaml(path, text)
    return _load_ini(path, text)


def _load_ini(path: Path, text: str) -> Inventory:
    hosts: dict[str, Host] = {}
    children: dict[str, list[str]] = {}
    group_vars: dict[str, dict[str, str]] = {}
    section, kind = "ungrouped", "hosts"
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        header = re.fullmatch(r"\[([A-Za-z0-9_-]+)(?::(children|vars))?\]", line)
        if header:
            section, kind = header.group(1), header.group(2) or "hosts"
            continue
        if kind == "children":
            children.setdefault(section, []).append(line.split()[0])
        elif kind == "vars":
            key, _, value = line.partition("=")
            group_vars.setdefault(section, {})[key.strip()] = value.strip()
        else:
            try:
                parts = shlex.split(line)
            except ValueError as exc:
                raise InventoryError(f"{path}:{number}: ligne illisible : {line}") from exc
            name = parts[0]
            host = hosts.setdefault(name, Host(name))
            host.groups.add(section)
            for part in parts[1:]:
                if "=" not in part:
                    raise InventoryError(f"{path}:{number}: « {part} » n'est pas au format clé=valeur")
                key, _, value = part.partition("=")
                host.vars[key] = value
    _apply_children(hosts, children)
    return Inventory(path, hosts, group_vars)


def _load_yaml(path: Path, text: str) -> Inventory:
    data = yaml.safe_load(text) or {}
    hosts: dict[str, Host] = {}
    children: dict[str, list[str]] = {}
    group_vars: dict[str, dict[str, str]] = {}

    def walk(group: str, node: Any) -> None:
        node = node or {}
        for name, hvars in (node.get("hosts") or {}).items():
            host = hosts.setdefault(name, Host(name))
            host.groups.add(group)
            host.vars.update({k: str(v) for k, v in (hvars or {}).items()})
        if node.get("vars"):
            group_vars.setdefault(group, {}).update({k: str(v) for k, v in node["vars"].items()})
        for child, child_node in (node.get("children") or {}).items():
            children.setdefault(group, []).append(child)
            walk(child, child_node)

    for group, node in data.items():
        walk(group, node)
    _apply_children(hosts, children)
    return Inventory(path, hosts, group_vars)


def _apply_children(hosts: dict[str, Host], children: dict[str, list[str]]) -> None:
    """Ajoute les groupes parents (k8s_cluster:children...) à chaque hôte."""
    changed = True
    while changed:
        changed = False
        for parent, kids in children.items():
            for host in hosts.values():
                if parent not in host.groups and host.groups.intersection(kids):
                    host.groups.add(parent)
                    changed = True


# --- terraform.tfvars ------------------------------------------------------------
TFVAR_LINE = re.compile(r'^\s*([a-z_][a-z0-9_]*)\s*=\s*(.+?)\s*$')


def read_tfvars(path: Path) -> dict[str, str]:
    """Valeurs simples (chaînes, nombres, booléens, listes sur une ligne)."""
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0]
        match = TFVAR_LINE.match(line)
        if not match:
            continue
        key, value = match.group(1), match.group(2).strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        values[key] = value
    return values


def tf_variable_default(variables_tf: Path, name: str) -> Optional[str]:
    """Valeur par défaut d'une variable Terraform (chaîne ou nombre)."""
    if not variables_tf.is_file():
        return None
    inside = False
    for raw in variables_tf.read_text(encoding="utf-8").splitlines():
        if re.match(rf'^variable "{re.escape(name)}" \{{', raw):
            inside = True
            continue
        if inside and raw.startswith("}"):
            return None
        if inside:
            match = re.match(r"^\s*default\s*=\s*(.+?)\s*$", raw)
            if match:
                value = match.group(1)
                return value[1:-1] if value.startswith('"') and value.endswith('"') else value
    return None
