variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "cluster_name" {
  type    = string
  default = "trend-lab-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "node_instance_type" {
  type    = string
  default = "t3.large"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API endpoint (IAM auth still required)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ecr_repositories" {
  type    = list(string)
  default = ["opencti-platform", "opencti-worker"]
}

variable "visionone_api_key" {
  type      = string
  sensitive = true
}

variable "visionone_regional_fqdn" {
  type    = string
  default = "https://api.eu.xdr.trendmicro.com"
}

variable "visionone_group_id" {
  description = "Vision One Kubernetes cluster group; the built-in Amazon EKS group by default"
  type        = string
  default     = "00000000-0000-0000-0000-000000000001"
}

variable "admission_action" {
  description = "Admission-control action for policy rule violations: none, log or block"
  type        = string
  default     = "log"

  validation {
    condition     = contains(["none", "log", "block"], var.admission_action)
    error_message = "admission_action must be none, log or block."
  }
}

variable "runtime_mitigation" {
  description = "Runtime mitigation for the managed runtime rules: log, isolate or terminate"
  type        = string
  default     = "log"

  validation {
    condition     = contains(["log", "isolate", "terminate"], var.runtime_mitigation)
    error_message = "runtime_mitigation must be log, isolate or terminate."
  }
}

variable "runtime_rule_ids" {
  description = "Trend Micro managed runtime rule IDs to enable"
  type        = list(string)
  default     = ["TM-00000006", "TM-00000010", "TM-00000023", "TM-00000031", "TM-00000032"]
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge({
    Project   = "trend-secure-pipeline"
    Cluster   = var.cluster_name
    ManagedBy = "terraform"
  }, var.tags)
}
