# Decommissioning

Two levels: **pause** (stop paying, keep the ability to recreate in ~20 min) and **full removal**.

Everything runs from AWS CloudShell in `eu-north-1`, account `737605781416`. State: S3 bucket `trend-secure-tfstate-737605781416-eu-north-1`, key `trend-lab-eks/terraform.tfstate`.

## Level 1 — Pause (removes all hourly cost)

Order matters: the Helm release must go first so its AWS load balancer is released, otherwise the VPC cannot be deleted.

```bash
aws eks update-kubeconfig --region eu-north-1 --name trend-lab-eks && helm uninstall opencti -n opencti --wait --timeout 10m; kubectl delete namespace opencti --wait --timeout=10m; cd ~/trend-secure-pipeline/terraform && (terraform init -input=false -backend-config="bucket=trend-secure-tfstate-737605781416-eu-north-1" -backend-config="key=trend-lab-eks/terraform.tfstate" -backend-config="region=eu-north-1" -backend-config="use_lockfile=true" >/dev/null) && read -rsp "Vision One API key: " TF_VAR_visionone_api_key && echo && export TF_VAR_visionone_api_key TF_VAR_aws_region=eu-north-1 TF_VAR_cluster_name=trend-lab-eks TF_VAR_visionone_regional_fqdn="https://api.eu.xdr.trendmicro.com" && terraform destroy -input=false -auto-approve 2>&1 | tee ~/tf-destroy.log | grep -E "Destroying\.\.\.|Destruction complete|Error|Destroy complete"
```

`terraform destroy` removes, in one go: the Vision One agent (Helm release), the Vision One cluster registration, policy and ruleset, the EKS cluster and node group, ECR repositories (images included), the VPC/NAT/subnets, and the EBS CSI IAM role. Ends with `Destroy complete!`.

Verify nothing is left billing:

```bash
aws eks list-clusters --region eu-north-1; aws ec2 describe-nat-gateways --region eu-north-1 --query "NatGateways[?State!='deleted'].NatGatewayId"; aws elb describe-load-balancers --region eu-north-1 --query "LoadBalancerDescriptions[].DNSName"; aws ec2 describe-volumes --region eu-north-1 --query "Volumes[?State=='available'].VolumeId"
```

Every list should be empty. Leftover `available` EBS volumes (from PersistentVolumes) can be deleted with `aws ec2 delete-volume --region eu-north-1 --volume-id <id>`.

Verify in Vision One: Cloud Security → Container Security → Inventory → Amazon EKS no longer lists `trend_lab_eks`. If it does (e.g. destroy was interrupted), remove it there manually.

Recreate later: runbook blocks 2–4 in `docs/RUNBOOK.md` (CloudShell path).

## Level 2 — Full removal

After Level 1:

```bash
BUCKET=trend-secure-tfstate-737605781416-eu-north-1; aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --output json --query '{Objects: [].{Key:Key,VersionId:VersionId}}' | sed 's/\[\].{Key:Key,VersionId:VersionId}//')" >/dev/null 2>&1; aws s3api delete-objects --bucket "$BUCKET" --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" >/dev/null 2>&1; aws s3 rb "s3://$BUCKET" --force; aws cloudformation delete-stack --region eu-north-1 --stack-name trend-secure-bootstrap 2>/dev/null; echo done
```

Then, by hand:

- **Vision One** → Administration → API Keys: delete the key used for this project (also invalidates the local copy). Container Security → Policies / Rulesets: confirm `trend_lab_eks_*` are gone.
- **GitHub** → `m1kl0s/opencti` Settings → Secrets and variables → Actions: delete secret `VISIONONE_API_KEY` and the variables. Delete the forks `m1kl0s/opencti`, `m1kl0s/ollama` and the repo `m1kl0s/trend-secure-pipeline` if no longer wanted (Settings → Danger zone). Review Settings → Applications for the Vision One GitHub App.
- **Mac**: `rm -rf ~/.config/tmas ~/.local/bin/tmas ~/.local/bin/tmfs ~/CICD/{ollama,opencti,trend-secure-pipeline} ~/Downloads/github-oidc-bootstrap.yaml`.

## Cost reference

Running: ≈ USD 0.35/hour (EKS 0.10, 2×t3.large 0.17, NAT 0.045, ELB 0.025) ≈ USD 250/month. After Level 1: ≈ USD 0. After Level 2: 0.
