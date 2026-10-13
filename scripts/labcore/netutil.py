"""Outils réseau : CIDR, plages d'adresses, chevauchements (IPv4)."""
from __future__ import annotations

import ipaddress
from dataclasses import dataclass


class NetError(ValueError):
    """Valeur réseau invalide (message en français, destiné à l'utilisateur)."""


@dataclass(frozen=True)
class IPRange:
    """Plage inclusive d'adresses IPv4 [first, last]."""

    first: ipaddress.IPv4Address
    last: ipaddress.IPv4Address
    text: str

    @property
    def size(self) -> int:
        return int(self.last) - int(self.first) + 1

    def overlaps(self, other: "IPRange") -> bool:
        return int(self.first) <= int(other.last) and int(other.first) <= int(self.last)

    def contains_ip(self, ip: ipaddress.IPv4Address) -> bool:
        return int(self.first) <= int(ip) <= int(self.last)

    def within(self, network: ipaddress.IPv4Network) -> bool:
        return self.first in network and self.last in network

    def __str__(self) -> str:  # pragma: no cover - affichage
        return self.text


def parse_cidr(text: str) -> ipaddress.IPv4Network:
    """CIDR IPv4 strict (10.244.0.0/16) ; refuse les bits d'hôte (10.244.1.0/16)."""
    value = text.strip()
    if "/" not in value:
        raise NetError(f"« {text} » n'est pas un CIDR (format attendu : 10.244.0.0/16)")
    try:
        network = ipaddress.ip_network(value, strict=True)
    except ValueError as exc:
        try:
            ipaddress.ip_network(value, strict=False)
        except ValueError:
            raise NetError(f"« {text} » n'est pas un CIDR valide") from exc
        raise NetError(f"« {text} » contient des bits d'hôte : utilisez l'adresse de réseau "
                       f"{ipaddress.ip_network(value, strict=False)}") from exc
    if network.version != 4:
        raise NetError(f"« {text} » : seul l'IPv4 est géré par ce lab")
    return network  # type: ignore[return-value]


def parse_cidr_list(text: str) -> list[ipaddress.IPv4Network]:
    return [parse_cidr(part) for part in split_list(text)]


def parse_ip(text: str) -> ipaddress.IPv4Address:
    try:
        ip = ipaddress.ip_address(text.strip())
    except ValueError as exc:
        raise NetError(f"« {text} » n'est pas une adresse IP") from exc
    if ip.version != 4:
        raise NetError(f"« {text} » : seul l'IPv4 est géré par ce lab")
    return ip  # type: ignore[return-value]


def parse_range(text: str) -> IPRange:
    """Accepte « a.b.c.d », « a.b.c.d-a.b.c.e » ou un CIDR."""
    value = text.strip()
    if not value:
        raise NetError("plage vide")
    if "/" in value:
        net = parse_cidr(value)
        return IPRange(net.network_address, net.broadcast_address, value)
    if "-" in value:
        start, _, end = value.partition("-")
        first, last = parse_ip(start), parse_ip(end)
        if int(last) < int(first):
            raise NetError(f"« {text} » : la fin de la plage précède son début")
        return IPRange(first, last, value)
    ip = parse_ip(value)
    return IPRange(ip, ip, value)


def parse_ranges(text: str) -> list[IPRange]:
    return [parse_range(part) for part in split_list(text)]


def split_list(text: str) -> list[str]:
    return [part.strip() for part in (text or "").split(",") if part.strip()]


def network_as_range(network: ipaddress.IPv4Network) -> IPRange:
    return IPRange(network.network_address, network.broadcast_address, str(network))


def ranges_overlap(a: list[IPRange], b: list[IPRange]) -> list[tuple[IPRange, IPRange]]:
    return [(x, y) for x in a for y in b if x.overlaps(y)]


def overlapping_pairs(named: dict[str, list[IPRange]]) -> list[tuple[str, str, IPRange, IPRange]]:
    """Tous les chevauchements entre groupes nommés (chaque paire une seule fois)."""
    names = list(named)
    result = []
    for i, left in enumerate(names):
        for right in names[i + 1:]:
            for x, y in ranges_overlap(named[left], named[right]):
                result.append((left, right, x, y))
    return result
