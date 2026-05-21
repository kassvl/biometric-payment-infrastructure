# `terraform/bootstrap/`

> **One-time module.** Solves the chicken-and-egg problem of "where do I store
> the state file for the module that creates the state bucket?" The bootstrap
> module uses a **local backend**, runs once per AWS account, and produces the
> S3 + DynamoDB + KMS resources every other module in the repo will use as
> their remote backend.

---

## What this module creates

| Resource                     | Purpose                                                                                  |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| `aws_kms_key.tfstate`        | Customer-managed key (CMK) for state encryption at rest. Annual rotation enabled.        |
| `aws_kms_alias.tfstate`      | Stable, human-readable alias (`alias/payeye-tfstate`) for the CMK.                       |
| `aws_s3_bucket.logs`         | Access log bucket — receives S3 server access logs from the state bucket.                |
| `aws_s3_bucket.tfstate`      | Versioned, KMS-encrypted bucket holding remote Terraform state.                          |
| `aws_dynamodb_table.tfstate_lock` | Lock table — serializes concurrent `terraform apply` runs. PITR + KMS-encrypted.    |
| Bucket policies              | Deny non-TLS, deny unencrypted PUTs, deny wrong-KMS-key PUTs, allow log delivery only.   |

## File layout

```
terraform/bootstrap/
├── versions.tf                 # Pinned terraform + aws provider, local backend
├── variables.tf                # Typed inputs with validation
├── data.tf                     # aws_caller_identity, aws_partition
├── locals.tf                   # Computed names + common_tags
├── kms.tf                      # CMK + alias + key policy
├── s3.tf                       # Log bucket + state bucket (every safety control)
├── dynamodb.tf                 # Lock table (PAY_PER_REQUEST, KMS, PITR)
├── outputs.tf                  # state bucket, table, KMS, ready-to-paste backend snippet
├── terraform.example.tfvars    # Committed example; copy to terraform.tfvars (gitignored)
└── README.md                   # ← you are here
```

---

## Usage

```bash
cd terraform/bootstrap

# 1. Initialize with the local backend (no remote backend exists yet).
terraform init

# 2. Review what will be created.
terraform plan

# 3. Apply. Required AWS permissions: account-level admin or a scoped
#    bootstrap role with s3, dynamodb, kms, iam:GetCallerIdentity.
terraform apply

# 4. Capture the backend snippet for downstream environments.
terraform output -raw backend_config_snippet
```

After apply, every downstream environment gets a `backend.tf` like:

```hcl
terraform {
  backend "s3" {
    bucket         = "payeye-tfstate-<account-id>"
    key            = "dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "payeye-tfstate-locks"
    encrypt        = true
    kms_key_id     = "alias/payeye-tfstate"
  }
}
```

### Optional: migrate the bootstrap module's own state into the bucket it created

This is a "self-host the state" move; not required, but tidy.

```bash
# Replace the local backend in versions.tf with:
#
#   backend "s3" {
#     bucket         = "<from terraform output state_bucket_id>"
#     key            = "bootstrap/terraform.tfstate"
#     region         = "eu-central-1"
#     dynamodb_table = "<from terraform output dynamodb_table_name>"
#     encrypt        = true
#     kms_key_id     = "alias/payeye-tfstate"
#   }

terraform init -migrate-state
# Confirm 'yes' when asked to copy state to the new backend.
```

---

## Security posture (control-by-control)

| Control                                | Enforced by                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------ |
| Encryption at rest                     | KMS-CMK with annual rotation, applied via `aws_s3_bucket_server_side_encryption_configuration`. |
| Encryption in transit                  | Bucket policy `DenyInsecureTransport` (`aws:SecureTransport: false`).                |
| Reject unencrypted writes              | Bucket policy `DenyUnencryptedObjectUploads` (requires `s3:x-amz-server-side-encryption=aws:kms`). |
| Reject wrong-key writes                | Bucket policy `DenyWrongKmsKey` (key must equal our CMK ARN).                        |
| Block public access                    | `aws_s3_bucket_public_access_block` with all four flags `true` on both buckets.      |
| ACLs disabled                          | `aws_s3_bucket_ownership_controls` set to `BucketOwnerEnforced`.                     |
| Versioning + recovery                  | State bucket versioning `Enabled`; lifecycle expires noncurrent only.                |
| Audit trail                            | S3 server access logs on the state bucket → log bucket → 7-year retention.           |
| Concurrent apply safety                | DynamoDB lock table; row-per-state-key, released on apply completion.                |
| Lock table durability                  | PITR enabled, KMS-encrypted, deletion protection on (unless force_destroy).          |
| Key isolation                          | KMS key policy scopes service usage to our account ID only (confused-deputy guard). |

---

## Trade-offs (be honest about cost)

| Choice                                  | Cost impact (rough)                                              | Why we accept it                                                          |
| --------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Customer-managed KMS key                | $1/month + per-call charges                                       | Key policy control + audit isolation outweigh the trivial cost.           |
| 7-year log retention                    | Glacier Instant Retrieval is cheap (~$0.004/GB-month).           | FinTech audit windows; PCI-DSS / DORA both ask for multi-year storage.    |
| DynamoDB PAY_PER_REQUEST                | ~$0.50/month for normal team usage                                | No tuning; no over-provisioning waste.                                    |
| State bucket noncurrent versioning      | ~$0.023/GB-month for noncurrent versions                          | One-version-back recovery on accidental delete is non-negotiable.         |

---

## Mülakatta Bu Soruyu Alırsan

A short, ruthless drill on the most common interview probes around remote-state bootstrap.

### Q1. "Why do you encrypt state with a customer-managed KMS key instead of `aws/s3`?"

Three reasons. **First, control over the key policy** — with the AWS-managed
`aws/s3` key, you cannot restrict who can decrypt. With a CMK, the key policy
is yours; only IAM principals you grant can decrypt the state. **Second,
audit fidelity** — every cryptographic operation is recorded in CloudTrail
under your key ARN, so you know who decrypted state, when, and from where.
**Third, rotation control** — annual rotation is enabled, and if a key is
ever suspected of compromise we can rotate, re-encrypt, or schedule deletion
without help from AWS. The trade-off is roughly $1/month and a per-call cost.
For a payment-grade workload, that is rounding error.

### Q2. "What happens if someone deletes the state bucket by accident?"

Three layers of defense. **First**, versioning is enabled — a single object
delete creates a delete marker but the data is still there; we recover with
`aws s3api delete-object --version-id ...`. **Second**, the bucket itself
cannot be deleted while non-empty unless `force_destroy = true`, which is
explicitly off by default. **Third**, even an `aws s3 rb --force` would
trigger CloudTrail events that GuardDuty + Security Hub flag immediately;
the access logs go to a separate bucket so the audit trail survives. The
realistic recovery is: stop CI, restore from the most recent good version,
re-run plans to confirm no drift, resume.

### Q3. "Why DynamoDB for locking? Why not a Redis or a file lock?"

Terraform's S3 backend natively supports DynamoDB-based locking with a
specific schema (hash key `LockID`, single attribute). DynamoDB gives us
**strong consistency** and **single-digit-millisecond conditional writes**
out of the box, in the same AWS account, audited via CloudTrail. Redis
would introduce a stateful service we have to operate, secure, and back up.
A "file lock" doesn't exist on object storage. The DynamoDB lock table is
the AWS-native, regulator-friendly, $0.50/month answer.

### Q4. "Why `PAY_PER_REQUEST` instead of provisioned capacity?"

Lock-table traffic is **bursty and very low volume** — one conditional
write per `terraform apply`, maybe a few dozen requests a day at most for
a typical team. Provisioned capacity would force us to size for the peak
and over-pay 99% of the time, or under-size and get throttled mid-apply.
On-demand billing scales to zero between applies. Cost per month is well
under a dollar.

### Q5. "Walk me through the chicken-and-egg problem and how you solved it."

The state for module X has to live somewhere. If module X **creates** the
state backend, then module X cannot use that backend on its first run —
the backend doesn't exist yet. Two valid solutions exist. **The mature
one** is what we did: bootstrap module uses a `backend "local"` block; you
run `terraform apply` once with local state, the module produces the S3
bucket / DynamoDB / KMS, and afterwards every other module references those
as remote backends. The bootstrap module's own state can stay local
(committed nowhere — it's gitignored), or it can self-host by re-pointing
its backend at the bucket it just created and running
`terraform init -migrate-state`. **The bad alternative** is "bootstrap
manually in the AWS console". That's not reproducible and not auditable.

### Q6. "How does your bucket policy stop someone uploading an unencrypted state file?"

The bucket has a default SSE-KMS rule, but a misconfigured client can override
it with `--sse none` or omit the encryption header. The bucket policy adds
**two explicit Deny statements** that fire regardless of defaults: one rejects
PutObject if `s3:x-amz-server-side-encryption` is anything other than
`aws:kms`; another rejects PutObject if the KMS key ID is not our CMK ARN.
Combined, the only way to get an object into the bucket is encrypted with
our specific key. Even an account admin would have to disable this policy
first, which is a CloudTrail-visible action.

### Q7. "What about MFA-delete?"

We chose **not** to enable MFA-delete on the state bucket. MFA-delete blocks
every delete (including lifecycle transitions for noncurrent versions) until
the bucket-owning AWS account root presents an MFA token on the API call.
This breaks all automation. The trade-off is wrong for a state bucket where
we do want lifecycle to expire noncurrent versions automatically. We protect
the bucket through `force_destroy = false`, IAM policy denying `s3:Delete*`
to non-admin principals, and an SCP at the org level that pins the bucket
region. If we needed MFA-delete-grade protection, we'd put the audit trail
in a separate bucket with **S3 Object Lock** in compliance mode — which
this repo does for CloudTrail in the `security` module.

### Q8. "Why a separate access-log bucket instead of self-logging?"

Two reasons. **First**, S3 has a documented gotcha: a bucket logging into
itself can deadlock its own access log delivery. **Second**, separation of
duties for audit — if someone tampers with the state bucket, the log of
that tampering must live somewhere they cannot reach with the same
credentials. The log bucket has its own bucket policy, scoped allow-list
for `logging.s3.amazonaws.com`, and a 7-year lifecycle.

### Q9. "What if my AWS region is different? Will this module work in `us-east-1` or in GovCloud?"

Yes. The module uses `data.aws_partition.current.partition` to compose ARNs,
so it produces `arn:aws-us-gov:...` in GovCloud. Region is a variable; the
default is `eu-central-1` to match our primary, but any commercial region
works without code changes. KMS keys, DynamoDB tables, and S3 buckets are
all regional — only the bucket name is global, which is why it includes the
account ID by default.

### Q10. "How do CI runs use this without long-lived AWS credentials?"

GitHub Actions assumes an IAM role via the `aws-actions/configure-aws-credentials`
OIDC workflow. The trust policy of that role is conditioned on the GitHub
OIDC token's `sub` (repository + ref) and `aud` (`sts.amazonaws.com`). The
permissions the role needs against this module's resources are: `s3:GetObject`
and `s3:PutObject` on the state key, `dynamodb:GetItem` / `PutItem` /
`DeleteItem` on the lock row, and `kms:Decrypt` / `kms:GenerateDataKey` on
the CMK. There is no `aws_access_key_id` anywhere in the pipeline.
