variable "dia_rules_json_file_path" {
  description = "Path to the Dynamic IP Allocation JSON export produced by `catocli export dia_rules` (data.policy.dynamicIpAllocation.policy root)."
  type        = string
}

variable "policy_enabled" {
  description = "Manage the account-level Dynamic IP Allocation policy toggle. null leaves the toggle unmanaged; true/false manages it via cato_dynamic_ip_allocation_policy."
  type        = bool
  default     = null
}
