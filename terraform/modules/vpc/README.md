# `terraform/modules/vpc/`

> Network foundation. Every other module depends on this — EKS nodes land in
> private-app subnets, RDS Aurora lands in private-db subnets, ALBs sit in
> public subnets.

## What this module creates

| Resource           | Detail                                                                                              |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| VPC                | `10.0.0.0/16` with DNS hostnames + DNS support enabled.                                             |
| Public subnets     | `10.0.1.0/24` (AZ-a), `10.0.2.0/24` (AZ-b) — ALB, NAT GW, jumphosts (if any).                       |
| Private-app subnets| `10.0.10.0/24`, `10.0.11.0/24` — EKS nodes, internal load balancers.                                |
| Private-db subnets | `10.0.20.0/24`, `10.0.21.0/24` — Aurora, ElastiCache, no internet route.                            |
| Internet Gateway   | One per VPC.                                                                                        |
| NAT Gateways       | **One per AZ** — eliminates single-AZ failure for outbound traffic from private subnets.            |
| Route tables       | Public RT (0.0.0.0/0 → IGW), one private RT per AZ (0.0.0.0/0 → AZ-local NAT GW), DB RT (no 0/0). |
| VPC Flow Logs      | Captured to CloudWatch Logs with 1-year retention; required for PCI-DSS / DORA audit trail.         |
| Default SG         | Stripped of all ingress/egress rules (CIS benchmark recommendation).                                |

## Why this layout

Three-tier segmentation maps directly onto a PCI-DSS-style trust boundary:

```
Internet ─► Public ─► Private-app ─► Private-db
              ▲          ▲              ▲
              │          │              └── No 0.0.0.0/0 route at all (data tier).
              │          └── Outbound only via per-AZ NAT GW.
              └── Only resources allowed to face the internet (ALB, NAT).
```

The full `main.tf` and the **"Mülakatta Bu Soruyu Alırsan"** Q&A section
(why /16, why NAT per AZ vs single NAT, why Flow Logs to CloudWatch vs S3,
NACL vs SG, IPv6 plans) are written in the `infra(vpc):` commit.
