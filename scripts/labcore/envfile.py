"""Lecture des fichiers KEY=VALUE (config/lab.env, .env).

Mêmes règles que load_env_file (scripts/lib/common.sh) et que le Vagrantfile :
  - lignes vides et commentaires (#) ignorés ;
  - format CLE=valeur, CLE en majuscules ;
  - guillemets englobants facultatifs ("valeur" ou 'valeur') ;
  - aucune substitution de variable (le fichier n'est jamais exécuté).
"""
from __future__ import annotations

import re
from pathlib import Path

KEY_LINE = re.compile(r"^([A-Z][A-Z0-9_]*)=(.*)$")


def parse_env_text(text: str, origin: str = "<texte>") -> tuple[dict[str, str], list[str]]:
    """Retourne (valeurs, avertissements) ; la dernière occurrence d'une clé gagne."""
    values: dict[str, str] = {}
    warnings: list[str] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip("\r")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = KEY_LINE.match(line)
        if not match:
            warnings.append(f"{origin}:{number}: ligne ignorée (format attendu CLE=valeur) : {line}")
            continue
        key, value = match.group(1), match.group(2)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        values[key] = value
    return values, warnings


def parse_env_file(path: Path) -> tuple[dict[str, str], list[str]]:
    if not path.is_file():
        return {}, []
    return parse_env_text(path.read_text(encoding="utf-8"), origin=str(path))


def env_file_keys_in_order(path: Path) -> list[str]:
    """Clés d'un fichier dans l'ordre d'apparition (pour l'affichage de make config)."""
    keys: list[str] = []
    if not path.is_file():
        return keys
    for raw in path.read_text(encoding="utf-8").splitlines():
        match = KEY_LINE.match(raw.rstrip("\r"))
        if match and match.group(1) not in keys:
            keys.append(match.group(1))
    return keys
