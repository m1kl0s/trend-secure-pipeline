# trend-secure-pipeline

Reusable GitHub Actions + Terraform that take any public repository from **fork → scan → build → scan → deploy** on AWS EKS with Trend Vision One protecting every stage. Nothing runs on a laptop; GitHub Actions is the execution engine and AWS access is via OIDC.

```
 push / PR
    │
    ├─► File Security (tmfs)      malware + active content, every tracked file
    ├─► Code Security (tmas)      open-source vulnerabilities + secrets in source
    └─► build images ─► Image scan (tmas)   vulnerabilities + malware + secrets
                              │
                              ▼  (main branch or manual dispatch)
        Terraform: VPC + EKS + ECR + Vision One ruleset/policy/cluster + agent Helm chart
                              │
                              ▼
        push images to ECR ─► Helm deploy application ─► LoadBalancer URL in job summary
```

## Components

| Path | What it is |
|---|---|
| `.github/workflows/security-scan.yml` | Reusable: File Security, Code Security and image scans |
| `.github/workflows/deploy-eks.yml` | Reusable: Terraform apply, ECR publish, Helm deploy |
| `.github/workflows/destroy-eks.yml` | Reusable: Helm uninstall + Terraform destroy |
| `.github/actions/install-tmas`, `install-tmfs` | Composite actions installing the Trend CLIs from the official CDN |
| `terraform/` | EKS (managed node group), ECR, and Vision One Container Security as code |
| `bootstrap/github-oidc-bootstrap.yaml` | One-time CloudFormation: OIDC provider, deploy role, state bucket |
| `templates/caller-security-scan.yml` | The ~20-line workflow to drop into any repository |

Security policy is code: `terraform/visionone.tf` defines the runtime ruleset, the admission/runtime policy, registers the cluster, and installs the in-cluster agent. Change `admission_action` from `log` to `block` to enforce.

## One-time setup (per AWS account)

1. AWS Console → CloudFormation → *Create stack* → upload `bootstrap/github-oidc-bootstrap.yaml`. Keep the defaults (or narrow `GitHubSubjectPatterns`). Note the stack outputs.
2. Vision One → Administration → API Keys: create a key with permissions for **Run file scan via SDK**, **Artifact Scanner / Code Security scans**, and **Container Security (manage clusters and policies)**. Set an expiry.

## Onboard a repository

Repository → Settings → Secrets and variables → Actions:

| Kind | Name | Value |
|---|---|---|
| Secret | `VISIONONE_API_KEY` | the key from step 2 |
| Variable | `V1_REGION` | `eu-central-1` (Vision One region of the key) |
| Variable | `V1_REGIONAL_FQDN` | `https://api.eu.xdr.trendmicro.com` |
| Variable | `AWS_REGION` | e.g. `eu-north-1` |
| Variable | `AWS_ROLE_ARN` | `RoleArn` stack output |
| Variable | `TF_STATE_BUCKET` | `StateBucket` stack output |
| Variable | `CLUSTER_NAME` | e.g. `trend-lab-eks` |

Then copy `templates/caller-security-scan.yml` into the repository as `.github/workflows/trend-security-scan.yml`. For build + deploy, see the OpenCTI example: `m1kl0s/opencti` → `.github/workflows/trend-security-pipeline.yml`.

## Application credentials

`deploy-eks.yml` takes a `generated_secret` spec and creates that Kubernetes secret with random values on the first deploy (later runs keep it). Values files reference the secret by name, so no credential is ever committed or printed in logs. Read them with `kubectl get secret <name> -n <namespace> -o jsonpath='{.data}'`.

## Gating

Scan jobs always publish reports and a summary. Turn `evaluate_policy: true` on to let the Vision One Code Security policy decide pass/fail (TMAS exits 2 on violation); `fail_on_malware` (default true) fails on any File Security or image malware finding.

## Local use of the same scanners

```bash
export TMAS_API_KEY=$(cat ~/.config/tmas/api_key) TMFS_API_KEY=$TMAS_API_KEY
tmas scan dir:. -V -S --redacted -r eu-central-1
git archive --format=tar.gz -o /tmp/repo.tgz HEAD && tmfs scan --region eu-central-1 file:/tmp/repo.tgz --pml=true --activeContent=true
```

## Tear down

Run the calling repository's *Destroy* workflow (OpenCTI: `trend-destroy.yml`) or call `destroy-eks.yml`. The bootstrap stack and state bucket are kept on purpose.

## Notes and limits

- `tmfs dir:` is not recursive, which is why the scan archives the tree first; archives are unpacked and inner files reported.
- `tmas -M` (malware) applies to images/archives only; source trees get `-V -S`.
- EKS control plane and two `t3.large` nodes cost roughly USD 130/month while running; destroy when not demoing.
- Terraform state key is `<cluster_name>/terraform.tfstate`; one cluster per name per bucket.
