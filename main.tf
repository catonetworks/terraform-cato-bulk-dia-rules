# terraform-cato-bulk-dia-rules
#
# Bulk-manages the Cato Dynamic IP Allocation (dynamicIpAllocation) policy from one JSON
# export produced by `catocli export dia_rules`:
#   sections[] / rules[] / rules_in_sections[] - flat policy, no sub-policies.
# cato_bulk_dia_move_rule applies ordering and republishes.
# Rule fields: range.globalIpRange (required), country, devicePostureProfile, platform, source{user,usersGroup}.

locals {
  dia_json = jsondecode(file("${var.dia_rules_json_file_path}"))
  dia      = local.dia_json.data.policy.dynamicIpAllocation.policy

  sections_data_raw      = try(local.dia.sections, [])
  rules_data_raw         = try(local.dia.rules, [])
  rules_in_sections_data = try(local.dia.rules_in_sections, [])

  sections_data = {
    for s in local.sections_data_raw : s.section_name => s
  }

  rules_by_name = {
    for rw in local.rules_data_raw : rw.rule.name => rw
  }

  move_section_data = {
    for name, s in local.sections_data : name => {
      section_index = s.section_index
    }
  }

  move_rule_data = {
    for row in local.rules_in_sections_data :
    row.rule_name => {
      index_in_section = row.index_in_section
      section_name     = row.section_name
    }
    if row.section_name != "" && contains(keys(local.sections_data), row.section_name)
  }

  unordered_rules_data = [
    for row in local.rules_in_sections_data : row
    if !contains(keys(local.move_rule_data), try(row.rule_name, ""))
  ]

  rule_bodies = {
    for name, rw in local.rules_by_name : name => merge(
      {
        name    = rw.rule.name
        enabled = try(rw.rule.enabled, true)
        range = {
          global_ip_range = can(rw.rule.range.globalIpRange.name) ? { name = rw.rule.range.globalIpRange.name } : { id = rw.rule.range.globalIpRange.id }
        }
      },
      try(rw.rule.description, "") != "" ? { description = rw.rule.description } : {},
      try(length(rw.rule.country), 0) > 0 ? { country = [for x in rw.rule.country : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
      try(length(rw.rule.devicePostureProfile), 0) > 0 ? { device_posture_profile = [for x in rw.rule.devicePostureProfile : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
      try(length(rw.rule.platform), 0) > 0 ? { platform = rw.rule.platform } : {},
      try(length(rw.rule.source.user), 0) > 0 || try(length(rw.rule.source.usersGroup), 0) > 0 ? {
        source = merge(
          try(length(rw.rule.source.user), 0) > 0 ? { user = [for x in rw.rule.source.user : can(x.name) ? { name = x.name } : { id = x.id }] } : {},
          try(length(rw.rule.source.usersGroup), 0) > 0 ? { users_group = [for x in rw.rule.source.usersGroup : can(x.name) ? { name = x.name } : { id = x.id }] } : {}
        )
      } : {}
    )
  }
}

# Optional account-level policy toggle (Dynamic IP Allocation ships disabled on new
# tenants - without enabling it, published rules have no effect).
resource "cato_dynamic_ip_allocation_policy" "policy" {
  count   = var.policy_enabled == null ? 0 : 1
  enabled = var.policy_enabled
}

resource "cato_dynamic_ip_allocation_section" "sections" {
  for_each = local.sections_data
  at = {
    position = "LAST_IN_POLICY"
  }
  section = {
    name = each.value.section_name
  }
}

resource "cato_dynamic_ip_allocation_rule" "rules" {
  depends_on = [cato_dynamic_ip_allocation_section.sections]
  for_each   = local.rules_by_name

  at = contains(keys(local.sections_data), each.value.rule.section.name) ? {
    position = "LAST_IN_SECTION"
    ref      = cato_dynamic_ip_allocation_section.sections[each.value.rule.section.name].id
    } : {
    position = "LAST_IN_POLICY"
  }

  rule = local.rule_bodies[each.key]
}

# Ordering + republish on changes.
resource "cato_bulk_dia_move_rule" "all_dia_rules" {
  depends_on = [cato_dynamic_ip_allocation_section.sections, cato_dynamic_ip_allocation_rule.rules]

  section_data = local.move_section_data
  rule_data    = local.move_rule_data
}
