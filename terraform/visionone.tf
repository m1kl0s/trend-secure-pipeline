# Vision One Container Security: runtime ruleset -> policy -> cluster registration -> in-cluster agent.

resource "visionone_container_ruleset" "runtime" {
  name        = "${replace(var.cluster_name, "-", "_")}_runtime"
  description = "Managed runtime rules for ${var.cluster_name} (mitigation: ${var.runtime_mitigation})"

  rules = [
    for id in var.runtime_rule_ids : {
      id         = id
      mitigation = var.runtime_mitigation
    }
  ]
}

resource "visionone_container_policy" "this" {
  name        = "${replace(var.cluster_name, "-", "_")}_policy"
  description = "Admission + runtime policy for ${var.cluster_name}, managed by Terraform"

  default = {
    rules = [
      {
        type       = "podSecurityContext"
        action     = var.admission_action
        mitigation = "log"
        enabled    = true
        statement = {
          properties = [{
            key   = "runAsNonRoot"
            value = "false"
          }]
        }
      },
      {
        type       = "unscannedImage"
        action     = var.admission_action
        mitigation = "none"
        enabled    = true
      },
      {
        type       = "podexec"
        action     = "log"
        mitigation = "log"
        enabled    = true
      },
      {
        type       = "portforward"
        action     = "log"
        mitigation = "log"
        enabled    = true
      },
    ]
  }

  runtime = {
    rulesets = [{ id = visionone_container_ruleset.runtime.id }]
  }
  xdr_enabled = true

  malware_scan_enabled    = true
  malware_scan_mitigation = "log"
  malware_scan_schedule   = "0 2 * * *"

  secret_scan_enabled                 = true
  secret_scan_mitigation              = "log"
  secret_scan_schedule                = "0 3 * * *"
  secret_scan_skip_if_rule_not_change = true
}

resource "visionone_container_cluster" "this" {
  # Vision One cluster names allow only alphanumerics, "_" and "."
  name        = replace(var.cluster_name, "-", "_")
  description = "Amazon EKS ${var.cluster_name} in ${var.aws_region}, managed by Terraform"
  resource_id = module.eks.cluster_arn
  policy_id   = visionone_container_policy.this.id
  group_id    = var.visionone_group_id

  runtime_security_enabled   = true
  vulnerability_scan_enabled = true
  malware_scan_enabled       = true
  secret_scan_enabled        = true
  namespaces                 = ["kube-system"]
}

resource "helm_release" "trendmicro" {
  name             = "trendmicro"
  namespace        = "trendmicro-system"
  create_namespace = true
  repository       = "oci://public.ecr.aws/trendmicro/container-security"
  chart            = "trendmicro-container-security"
  wait             = false

  set_sensitive = [
    { name = "visionOne.bootstrapToken", value = visionone_container_cluster.this.api_key },
  ]

  set = [
    { name = "visionOne.endpoint", value = visionone_container_cluster.this.endpoint },
    { name = "visionOne.admissionController.enabled", value = "true" },
    { name = "visionOne.runtimeSecurity.enabled", value = tostring(visionone_container_cluster.this.runtime_security_enabled) },
    { name = "visionOne.vulnerabilityScanning.enabled", value = tostring(visionone_container_cluster.this.vulnerability_scan_enabled) },
    { name = "visionOne.malwareScanning.enabled", value = tostring(visionone_container_cluster.this.malware_scan_enabled) },
    { name = "visionOne.secretScanning.enabled", value = tostring(visionone_container_cluster.this.secret_scan_enabled) },
    { name = "visionOne.inventoryCollection.enabled", value = "true" },
  ]

  set_list = [
    { name = "visionOne.exclusion.namespaces", value = tolist(visionone_container_cluster.this.namespaces) },
  ]

  depends_on = [module.eks]
}
