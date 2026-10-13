"""Configuration effective : environnement > .env > config/lab.env.

La même règle de priorité que le CLI Bash (load_env_file) : une variable
présente dans l'environnement n'est jamais écrasée par un fichier.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping, Optional

from . import envfile, netutil
from .schema import Schema, to_bool

SOURCE_ENV = "environnement"
SOURCE_DOTENV = ".env"
SOURCE_DEFAULT = "config/lab.env"
SOURCE_UNSET = "-"


@dataclass
class Config:
    root: Path
    schema: Schema
    values: dict[str, str]
    sources: dict[str, str]
    lab_keys: list[str]
    file_warnings: list[str] = field(default_factory=list)

    # --- chargement ---------------------------------------------------------
    @classmethod
    def load(cls, root: Path, environ: Optional[Mapping[str, str]] = None,
             dotenv: Optional[Path] = None) -> "Config":
        environ = dict(os.environ if environ is None else environ)
        schema = Schema.load(root / "config" / "schema.yaml")
        lab_path = root / "config" / "lab.env"
        lab, warn_lab = envfile.parse_env_file(lab_path)
        dot, warn_dot = envfile.parse_env_file(dotenv or (root / ".env"))
        keys = list(dict.fromkeys(list(lab) + list(dot) + list(schema.variables)))
        values: dict[str, str] = {}
        sources: dict[str, str] = {}
        for key in keys:
            if key in environ:
                value = environ[key]
                # Le CLI Bash a déjà exporté .env et lab.env : on retrouve l'origine.
                if key in dot and dot[key] == value:
                    source = SOURCE_DOTENV
                elif key not in dot and key in lab and lab[key] == value:
                    source = SOURCE_DEFAULT
                else:
                    source = SOURCE_ENV
            elif key in dot:
                value, source = dot[key], SOURCE_DOTENV
            elif key in lab:
                value, source = lab[key], SOURCE_DEFAULT
            else:
                value, source = "", SOURCE_UNSET
            values[key] = value
            sources[key] = source
        return cls(root=root, schema=schema, values=values, sources=sources,
                   lab_keys=envfile.env_file_keys_in_order(lab_path),
                   file_warnings=warn_lab + warn_dot)

    # --- accès typé ---------------------------------------------------------
    def get(self, key: str, default: str = "") -> str:
        value = self.values.get(key, "")
        return value if value != "" else default

    def raw(self, key: str) -> str:
        return self.values.get(key, "")

    def int(self, key: str, default: int = 0) -> int:
        try:
            return int(self.get(key, str(default)))
        except ValueError:
            return default

    def bool(self, key: str, default: bool = False) -> bool:
        value = to_bool(self.get(key))
        return default if value is None else value

    def list(self, key: str) -> list[str]:
        return netutil.split_list(self.get(key))

    def explicit(self, key: str) -> bool:
        """Vrai si l'utilisateur a choisi la valeur (environnement ou .env)."""
        return self.sources.get(key) in (SOURCE_ENV, SOURCE_DOTENV) and self.values.get(key, "") != ""

    def source(self, key: str) -> str:
        return self.sources.get(key, SOURCE_UNSET)

    # --- validation des types --------------------------------------------------
    def type_errors(self) -> list[str]:
        errors = []
        for key, spec in self.schema.variables.items():
            message = self.schema.check(key, self.values.get(key, ""))
            if message:
                errors.append(message)
        return errors

    def unknown_keys(self) -> list[str]:
        """Clés de .env inconnues du schéma (faute de frappe probable)."""
        return [k for k, src in self.sources.items()
                if src == SOURCE_DOTENV and k not in self.schema.variables]

    def masked(self, key: str) -> str:
        spec = self.schema.get(key)
        value = self.values.get(key, "")
        if spec and spec.secret and value:
            return "****"
        return value

    def secrets_present(self) -> list[str]:
        return [k for k in self.schema.secrets() if self.values.get(k)]
