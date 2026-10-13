# Gateway API

La [Gateway API](https://gateway-api.sigs.k8s.io/) est l'API standard de Kubernetes pour
publier des applications HTTP(S). Le lab installe un **contrôleur**, les **CRD** et une
**Gateway partagée** `gateway-system/lab-gateway` que vos applications utilisent avec des
`HTTPRoute`.

```bash
GATEWAY_CONTROLLER=traefik        # none | traefik | envoy-gateway | cilium | auto (profil)
GATEWAY_DOMAIN=lab.example.org    # noms <app>.lab.example.org
GATEWAY_TLS=auto                  # HTTPS si cert-manager est présent
GATEWAY_SERVICE_TYPE=auto         # LoadBalancer si un fournisseur LoadBalancer existe, sinon NodePort
```

| Contrôleur | Données | Points forts |
| --- | --- | --- |
| `traefik` | proxy Traefik | simple, tableau de bord, Ingress aussi supporté |
| `envoy-gateway` | Envoy | implémentation de référence très complète |
| `cilium` | Envoy intégré à Cilium | aucun composant supplémentaire ; exige `CNI=cilium` et le remplacement de kube-proxy |

## Ce qui est installé

1. **CRD Gateway API** (canal `GATEWAY_API_CHANNEL=standard`), version exigée par le
   contrôleur, manifeste officiel vérifié par SHA-256 ; un seul propriétaire (gestionnaire de
   champs `k8s-lab`) : un CRD installé par un autre outil n'est jamais repris.
2. **Le contrôleur** et sa `GatewayClass`.
3. **La Gateway partagée** `lab-gateway` : écouteur HTTP (80), écouteur HTTPS (443) avec un
   certificat wildcard `*.GATEWAY_DOMAIN` émis par cert-manager, redirection HTTP → HTTPS.
   Seuls les namespaces étiquetés `gateway.k8s-lab.io/expose=true` peuvent y attacher des
   routes (Grafana, Argo CD, Longhorn reçoivent l'étiquette quand vous demandez leur
   exposition).

## Publier une application

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: demo
  labels:
    gateway.k8s-lab.io/expose: "true"
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo
  namespace: demo
spec:
  parentRefs:
    - {name: lab-gateway, namespace: gateway-system, sectionName: https}
  hostnames: ["demo.lab.example.org"]
  rules:
    - backendRefs:
        - {name: demo, port: 80}
```

Un backend dans un **autre** namespace exige une `ReferenceGrant` dans le namespace du
Service (le test de l'addon `gateway` le vérifie).

## TLS

- `CERT_MANAGER_ISSUER=selfsigned-ca` (défaut) : CA interne du lab, aucun domaine public
  requis. Pour que votre navigateur fasse confiance aux certificats, importez la CA :
  `kubectl -n cert-manager get secret k8s-lab-ca -o jsonpath='{.data.tls\.crt}' | base64 -d > k8s-lab-ca.crt`.
- `CERT_MANAGER_ISSUER=acme-dns01` : Let's Encrypt (staging par défaut) par DNS-01
  (Cloudflare, RFC2136, Route 53) ; adapté à un domaine public dont la zone est pilotable.
- `CERT_MANAGER_ISSUER=acme-http01` : le nom doit être joignable **depuis Internet** sur le
  port 80 ; rarement adapté à un homelab.

## DNS

Créez un enregistrement `*.GATEWAY_DOMAIN` vers l'adresse de la Gateway
(`kubectl -n gateway-system get gateway lab-gateway`), ou installez ExternalDNS
(`EXTERNAL_DNS_PROVIDER`), qui crée les noms des HTTPRoute sans jamais en supprimer.

## Tests

`make addons-test ADDON=gateway` : application de test, HTTPRoute, réponse HTTP et HTTPS
(certificat), redirection 301, backend inter-namespace avec ReferenceGrant, et appel depuis
votre poste par l'IP de LoadBalancer de la Gateway si elle en a une.
