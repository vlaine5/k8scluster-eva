"""Schéma des variables (config/schema.yaml) et validation des types."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import yaml

from . import netutil

TRUE_WORDS = {"1", "true", "yes", "oui", "on"}
FALSE_WORDS = {"0", "false", "no", "non", "off"}


def to_bool(value: str) -> Optional[bool]:
    lowered = (value or "").strip().lower()
    if lowered in TRUE_WORDS:
        return True
    if lowered in FALSE_WORDS:
        return False
    return None


@dataclass
class VarSpec:
    name: str
    group: str
    type: str
    description: str = ""
    values: list[str] = field(default_factory=list)
    empty: bool = False
    secret: bool = False
    lab_env: bool = True
    pattern: Optional[str] = None
    minimum: Optional[int] = None
    maximum: Optional[int] = None
    deprecated: Optional[str] = None
    auto: bool = False

    @classmethod
    def from_dict(cls, name: str, data: dict[str, Any]) -> "VarSpec":
        return cls(
            name=name,
            group=data.get("group", "misc"),
            type=data["type"],
            description=data.get("description", ""),
            values=[str(v) for v in data.get("values", [])],
            empty=bool(data.get("empty", False)),
            secret=bool(data.get("secret", False)),
            lab_env=bool(data.get("lab_env", True)),
            pattern=data.get("pattern"),
            minimum=data.get("min"),
            maximum=data.get("max"),
            deprecated=data.get("deprecated"),
            auto=bool(data.get("auto", False)),
        )


class Schema:
    def __init__(self, groups: dict[str, str], variables: dict[str, VarSpec]):
        self.groups = groups
        self.variables = variables

    @classmethod
    def load(cls, path: Path) -> "Schema":
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        variables = {name: VarSpec.from_dict(name, spec) for name, spec in data["variables"].items()}
        return cls(data.get("groups", {}), variables)

    def __contains__(self, name: str) -> bool:
        return name in self.variables

    def get(self, name: str) -> Optional[VarSpec]:
        return self.variables.get(name)

    def secrets(self) -> list[str]:
        return [n for n, s in self.variables.items() if s.secret]

    def check(self, name: str, value: str) -> Optional[str]:
        """Retourne un message d'erreur, ou None si la valeur est valide."""
        spec = self.variables.get(name)
        if spec is None:
            return None
        return check_value(spec, value)


def check_value(spec: VarSpec, value: str) -> Optional[str]:
    value = value if value is not None else ""
    if value == "":
        if spec.empty:
            return None
        return f"{spec.name} est vide alors qu'une valeur est obligatoire ({spec.description})"
    kind = spec.type
    try:
        if kind == "int":
            if not re.fullmatch(r"[0-9]+", value):
                return f"{spec.name}={value} n'est pas un nombre entier positif"
            number = int(value)
            if spec.minimum is not None and number < spec.minimum:
                return f"{spec.name}={value} est trop petit (minimum {spec.minimum})"
            if spec.maximum is not None and number > spec.maximum:
                return f"{spec.name}={value} est trop grand (maximum {spec.maximum})"
        elif kind == "bool":
            if to_bool(value) is None:
                return f"{spec.name}={value} n'est pas un booléen (true ou false)"
        elif kind == "enum":
            if value not in spec.values:
                return f"{spec.name}={value} est invalide. Valeurs possibles : {', '.join(spec.values)}"
        elif kind == "list":
            items = netutil.split_list(value)
            if spec.values:
                bad = [i for i in items if i.lstrip("-") not in spec.values]
                if bad:
                    return f"{spec.name} : valeur(s) inconnue(s) {', '.join(bad)}. Valeurs possibles : {', '.join(spec.values)}"
        elif kind == "cidr":
            netutil.parse_cidr(value)
        elif kind == "cidr_list":
            netutil.parse_cidr_list(value)
        elif kind == "ip":
            netutil.parse_ip(value)
        elif kind == "ip_ranges":
            netutil.parse_ranges(value)
        elif kind == "endpoint":
            if not (spec.auto and value == "auto") and not re.fullmatch(r"[A-Za-z0-9.-]+:[0-9]{1,5}", value):
                return f"{spec.name}={value} : format attendu hôte:port (ex : 10.20.0.99:6443) ou auto"
        elif kind == "url":
            if not re.fullmatch(r"(https?|s3|nfs)://\S+", value):
                return f"{spec.name}={value} n'est pas une URL (http(s)://...)"
        elif kind == "cron":
            if len(value.split()) != 5:
                return f"{spec.name}={value} : format cron attendu (5 champs, ex : 0 3 * * *)"
        elif kind in ("string", "path", "version"):
            pass
        else:  # pragma: no cover - erreur de schéma
            return f"{spec.name} : type de schéma inconnu {kind}"
    except netutil.NetError as exc:
        return f"{spec.name} : {exc}"
    if spec.pattern and kind in ("string", "path", "version") and not re.fullmatch(spec.pattern, value):
        return f"{spec.name}={value} est invalide ({spec.description})"
    return None
