# Runbook: deploy OpenCTI to EKS under Vision One (CloudShell edition)

Everything the pipeline cannot do for you, as copy-paste commands. Region: `eu-north-1`.

## 1. Bootstrap AWS (once per account) — CloudShell

Open AWS CloudShell in `eu-north-1`.

```bash
aws sts get-caller-identity
git clone https://github.com/m1kl0s/trend-secure-pipeline.git
cd trend-secure-pipeline
aws cloudformation deploy \
  --region eu-north-1 \
  --stack-name trend-secure-bootstrap \
  --template-file bootstrap/github-oidc-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM
aws cloudformation describe-stacks --region eu-north-1 \
  --stack-name trend-secure-bootstrap \
  --query "Stacks[0].Outputs" --output table
```

If the deploy fails with `Provider with url https://token.actions.githubusercontent.com already exists`, the account already has a GitHub OIDC provider; report it and the template will be switched to reuse it.

## 2. Tell GitHub about the stack

Repository `m1kl0s/opencti` → Settings → Secrets and variables → Actions → Variables:

| Variable | Value |
|---|---|
| `AWS_ROLE_ARN` | `RoleArn` output |
| `TF_STATE_BUCKET` | `StateBucket` output |

(`AWS_REGION`, `V1_REGION`, `V1_REGIONAL_FQDN`, `CLUSTER_NAME` and the `VISIONONE_API_KEY` secret already exist.)

## 3. Deploy

Actions → *Trend Vision One – secure build, scan and deploy* → *Run workflow* → branch `trend-security-pipeline` → tick **deploy** → Run.

Timeline: scans + image build ≈ 15 min, Terraform (VPC, EKS, ECR, Vision One registration, agent) ≈ 15 min, Helm deploy of OpenCTI ≈ 10 min. The run's **Summary** tab ends with the OpenCTI URL and the command to read the generated credentials.

## 4. Verify the cluster — CloudShell

```bash
# kubectl is not preinstalled in CloudShell
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Grant your CloudShell identity admin access to the cluster (Terraform only grants the GitHub role)
PRINCIPAL=$(aws sts get-caller-identity --query Arn --output text | sed -E 's#:assumed-role/([^/]+)/.*#:role/\1#; s#:sts:#:iam:#')
aws eks create-access-entry --region eu-north-1 --cluster-name trend-lab-eks --principal-arn "$PRINCIPAL"
aws eks associate-access-policy --region eu-north-1 --cluster-name trend-lab-eks --principal-arn "$PRINCIPAL" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster

aws eks update-kubeconfig --region eu-north-1 --name trend-lab-eks
kubectl get nodes
kubectl get pods -n trendmicro-system          # Vision One agents: admission controller, scanner, runtime sensor
kubectl get pods -n opencti                     # opencti, worker, opensearch, rabbitmq, redis, rustfs
kubectl get svc -n opencti opencti              # EXTERNAL-IP = OpenCTI URL (http, port 80)
kubectl get secret opencti-credentials -n opencti -o jsonpath='{.data.APP__ADMIN__PASSWORD}' | base64 -d; echo
```

Login: `admin@opencti.local` + that password.

## 5. Verify in Vision One

Console: **Cloud Security → Container Security → Inventory → Amazon EKS** → cluster `trend_lab_eks` should be *Connected*, policy `trend_lab_eks_policy`, runtime ruleset `trend_lab_eks_runtime`. **Policies** shows the rules; **Runtime Security** shows events.

API check (paste your key into the shell yourself; it is not stored anywhere):

```bash
read -rs V1_KEY; export V1_KEY
curl -s -H "Authorization: Bearer $V1_KEY" \
  https://api.eu.xdr.trendmicro.com/v3.0/containerSecurity/kubernetesClusters | python3 -m json.tool
```

## 6. Prove the policy reacts

```bash
kubectl exec -n opencti deploy/opencti -- id       # triggers the "podexec" rule → event in Vision One
kubectl run rootdemo --image=nginx -n default        # runAsNonRoot violation → logged (blocked once admission_action=block)
kubectl delete pod rootdemo -n default
```

Events appear under Container Security → *Events* within a minute.

## 7. Tear down

Actions → *Trend Vision One – destroy EKS environment* → Run workflow → confirm `trend-lab-eks`. Removes OpenCTI, the Vision One registration, the cluster, VPC and ECR. The bootstrap stack and state bucket are kept.
