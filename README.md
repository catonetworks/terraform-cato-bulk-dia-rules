# terraform-cato-bulk-dia-rules

Bulk-manages the Cato **Dynamic IP Allocation (dynamicIpAllocation)** policy from a single
JSON export: sections and rules (flat policy - no sub-policies exist for this
type), with ordering and publishing via `cato_bulk_dia_move_rule`.

## Resources managed

| Resource | Keyed by | Notes |
|---|---|---|
| `cato_dynamic_ip_allocation_section.sections` | `section_name` | created `LAST_IN_POLICY`; ordered by the move resource |
| `cato_dynamic_ip_allocation_rule.rules` | rule name | placement: managed section -> `LAST_IN_SECTION`; sectionless -> `LAST_IN_POLICY` |
| `cato_bulk_dia_move_rule.all_dia_rules` | - | orders sections (`section_index`) and rules (`index_in_section`) and **publishes** |
| `cato_dynamic_ip_allocation_policy.policy` | - | optional account-level enable/disable toggle (`policy_enabled` variable) |

**Publishing:** the rule/section resources save to the draft policy only -
`cato_bulk_dia_move_rule` is this stack's single publisher. Dynamic IP Allocation ships
**disabled** on new tenants - set `policy_enabled = true` (or enable it in
the CMA) for published rules to take effect.

## Input JSON

```bash
catocli export dia_rules --json-filename all_dia_rules_and_sections.json
```

Root: `data.policy.dynamicIpAllocation.policy` with `sections[]`, `rules[]`
(wrappers `{audit, rule, properties}`, ids retained for brownfield import),
and `rules_in_sections[]`. Rule fields: range.globalIpRange (required), country, devicePostureProfile, platform, source{user,usersGroup}.

## Usage

```hcl
module "dia_rules" {
  source                   = "catonetworks/bulk-dia-rules/cato"
  dia_rules_json_file_path = "${path.module}/config_data/all_dia_rules_and_sections.json"
}
```

## Brownfield import

```bash
catocli import dia_rules_to_tf config_data/all_dia_rules_and_sections.json \
  --module-name module.dia_rules --auto-approve
terraform plan   # expect: only cato_bulk_dia_move_rule to add
```

## Known limitations

- Ordering rows with `section_name: ""` are excluded from the move resource
  and surfaced via `unordered_rules`; their order is creation order.
- Run applies with `-parallelism=1` when several module instances share an
  account.
