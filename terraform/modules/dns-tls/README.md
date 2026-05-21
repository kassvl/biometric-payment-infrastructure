# `terraform/modules/dns-tls/`

> DNS and TLS termination. Owns the public hostnames customers hit and the
> certificates ALBs / API Gateways present.

## What this module creates

| Resource                       | Detail                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------- |
| Route 53 hosted zone (public)  | Apex zone (e.g., `payeye.example`), with health checks for active-passive failover to DR region.  |
| Route 53 hosted zone (private) | Internal-only zone (`internal.payeye.example`) attached to the VPC for service discovery.         |
| ACM certificate                | **Wildcard** cert (`*.payeye.example`) issued in eu-central-1 for the regional ALB.               |
| ACM cert (us-east-1, optional) | If we add CloudFront later, certs for global edges must live in `us-east-1`.                      |
| DNS validation records         | Auto-created in Route 53 to validate cert issuance — fully automated renewal.                     |
| Health checks                  | Endpoint health checks tied to alarm + Route 53 failover routing policy.                          |
| DNSSEC                         | Optional; can be enabled on the apex zone via a KMS-backed signing key.                           |

## Why DNS-validated wildcard

- **Wildcard** means every new subservice (`auth.`, `payments.`, `admin.`) gets HTTPS without a new cert request.
- **DNS validation** auto-renews indefinitely — no email validation, no human in the loop.
- **ACM-issued** means AWS handles renewal and key rotation; we never see the private key.

## Failover model

```
Customer ─► payeye.example (Route 53, failover routing)
              ├─ Primary  : eu-central-1 ALB  (health check OK)
              └─ Secondary: eu-west-1   ALB  (warm standby in DR)
```

The **"Mülakatta Bu Soruyu Alırsan"** Q&A (why ACM vs cert-manager,
why us-east-1 cert for CloudFront, DNSSEC trade-offs, TTL strategy
for failover) is in the upcoming `infra(dns-tls):` commit.
