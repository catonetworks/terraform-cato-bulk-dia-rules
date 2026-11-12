# Terraform Cato Bulk Dynamic IP Allocation Rules Module

This module allows you to bulk import Dynamic IP Allocation (DIA) rules and sections from a JSON configuration file, and define the order of those rules and sections within the Cato policy.

## Usage

The module reads a JSON configuration file that defines:
- **Rules**: Individual Dynamic IP Allocation rules with their configurations
- **Sections**: Logical groupings for organizing rules
- **Rule ordering**: Defines which rules belong to which sections and their order within sections

### Basic Example

```hcl
module "dia_rules" {
  source = "catonetworks/bulk-dia-rules/cato"

  dia_rules_json_file_path = "./config_data/all_dia_rules_and_sections.json"
  policy_enabled            = true # Optional - Dynamic IP Allocation ships disabled on new tenants
}
```

### JSON Configuration Structure

The JSON file should contain a nested structure with the following key components:

- `data.policy.dynamicIpAllocation.policy.rules[]` - Array of Dynamic IP Allocation rules
- `data.policy.dynamicIpAllocation.policy.sections[]` - Array of sections with index and name
- `data.policy.dynamicIpAllocation.policy.rules_in_sections[]` - Mapping of rules to sections with ordering

#### Key Fields:

**Rules Array**: Each rule is a wrapper (`{audit, rule, properties}`, ids retained for brownfield import) whose `rule` object carries: `name`, `description`, `enabled`, `range.globalIpRange` (required - name-or-id reference to a Global IP Range), `country`, `devicePostureProfile`, `platform`, and `source.{user,usersGroup}`.

**Sections Array**: Defines sections with:
- `section_index`: The order of the section in the policy
- `section_name`: The display name of the section

**Rules in Sections Array**: Maps rules to sections with:
- `index_in_section`: The order of the rule within its section
- `section_name`: The section this rule belongs to
- `rule_name`: The name of the rule to place in the section

<details>
<summary>Click to expand full JSON configuration example</summary>

```json
{
  "data": {
    "policy": {
      "dynamicIpAllocation": {
        "policy": {
          "enabled": true,
          "rules": [
            {
              "rule": {
                "name": "My DIA Rule 1",
                "description": "My DIA Rule 1",
                "enabled": true,
                "range": {
                  "globalIpRange": { "name": "My Global IP Range" }
                },
                "country": [],
                "devicePostureProfile": [],
                "platform": [],
                "source": {}
              }
            },
            {
              "rule": {
                "name": "My DIA Rule 2",
                "description": "My DIA Rule 2",
                "enabled": true,
                "range": {
                  "globalIpRange": { "name": "My Other Global IP Range" }
                },
                "country": [],
                "devicePostureProfile": [],
                "platform": [],
                "source": {}
              }
            }
          ],
          "sections": [
            {
              "section_index": 1,
              "section_name": "My DIA Section 1"
            }
          ],
          "rules_in_sections": [
            {
              "index_in_section": 1,
              "section_name": "My DIA Section 1",
              "rule_name": "My DIA Rule 1"
            },
            {
              "index_in_section": 2,
              "section_name": "My DIA Section 1",
              "rule_name": "My DIA Rule 2"
            }
          ]
        }
      }
    }
  }
}
```
</details>

### How Rule Ordering Works

Based on the example above:
1. **Section 1** ("My DIA Section 1") is created first
2. **Rule 1** is placed in Section 1 at position 1
3. **Rule 2** is placed in Section 1 at position 2

The final policy structure will be:
```
└── My DIA Section 1
    ├── My DIA Rule 1
    └── My DIA Rule 2
```

Ordering rows with `section_name: ""` (rules at the policy root, with no managed section) are excluded from `cato_bulk_dia_move_rule` and surfaced via the `unordered_rules` output instead; their order is creation order only.

### Parameters

- `dia_rules_json_file_path`: Path to your JSON configuration file
- `policy_enabled`: (Optional) Manage the account-level Dynamic IP Allocation policy toggle. `null` (default) leaves the toggle unmanaged; `true`/`false` manages it via `cato_dynamic_ip_allocation_policy`. Dynamic IP Allocation ships **disabled** on new tenants - rules saved to the draft policy have no effect until the policy itself is enabled.
- `allow_empty_policy`: (Optional) Safety guard - fails planning if the decoded JSON contains 0 rules, since that almost always means a truncated export, a renamed upstream JSON key, or an accidentally wrong-tenant JSON file. Set `true` only for an intentional greenfield/teardown config.

## Working with Existing Rules (Brownfield Deployments)

For brownfield deployments where you have existing Dynamic IP Allocation rules in your Cato Management Application, you can use the Cato CLI to export and import these rules into Terraform state.

### Installing and Configuring Cato CLI

1. **Install the Cato CLI:**
   ```bash
   pip3 install catocli
   ```

2. **Configure the CLI with your Cato credentials:**
   ```bash
   catocli configure set
   ```
   This will prompt you for your Cato Management Application credentials and account information.

### Exporting Existing Rules

To export your existing Dynamic IP Allocation rules and sections into the JSON format required by this module:

```bash
catocli export dia_rules --json-filename all_dia_rules_and_sections.json
```

This command will generate a JSON file containing all your existing DIA rules and sections in the correct format for this Terraform module.

### Importing Existing Rules into Terraform State (native import blocks)

Once you have the JSON configuration file, you can adopt the existing rules and sections into Terraform state. This is useful for:

- **Brownfield deployments**: Managing existing rules with Terraform
- **Backup and restore**: Restoring rules to a known good state after unintended changes
- **State management**: Bringing existing infrastructure under Terraform control

There are two ways to do this. All of this module's `for_each` state addresses are keyed by name (rule name, section name), which is exactly what lets both options below line up directly against the exported JSON.

<details>
<summary>Option A (recommended) — native Terraform import blocks (migration.tf)</summary>

Requires Terraform >= 1.7. Create a one-shot `migration.tf` file beside your module call with one `import` block per resource type:

```hcl
# migration.tf — one-shot; delete after a successful `terraform apply` adopts
# the existing rules/sections into state.

locals {
  migrate_json     = jsondecode(file("${path.module}/config_data/all_dia_rules_and_sections.json"))
  migrate_policy   = local.migrate_json.data.policy.dynamicIpAllocation.policy
  migrate_sections = { for s in local.migrate_policy.sections : s.section_name => s.section_id }
  migrate_rules    = { for rw in local.migrate_policy.rules : rw.rule.name => rw.rule.id }
}

import {
  for_each = local.migrate_sections
  to       = module.dia_rules.cato_dynamic_ip_allocation_section.sections[each.key]
  id       = each.value
}

import {
  for_each = local.migrate_rules
  to       = module.dia_rules.cato_dynamic_ip_allocation_rule.rules[each.key]
  id       = each.value
}

# Only if your module call sets policy_enabled to a non-null value - that's
# what makes cato_dynamic_ip_allocation_policy.policy exist as index [0]. Its
# ImportState ignores the id you pass (it hardcodes state to a fixed
# singleton value), so any string works here.
import {
  to = module.dia_rules.cato_dynamic_ip_allocation_policy.policy[0]
  id = "dynamic_ip_allocation"
}

# cato_bulk_dia_move_rule.all_dia_rules is plan-time ordering orchestration —
# it has no live object of its own, so it is never imported; it's created on
# the first apply after the resources above are adopted.
```

Preview the adoption before anything touches state:

```bash
terraform plan
```

Expect `N to import, 1 to add, 0 to change, 0 to destroy`. The "1 to add" is expected - it's `cato_bulk_dia_move_rule.all_dia_rules`, which **cannot be imported** (the provider implements no `ImportState` for it; it's a plan-time ordering/publish resource with no independent API identity of its own) and is always created fresh on the first apply after an import. Any *other* "change" on an imported section/rule means the JSON export is stale relative to the live policy - **re-export** (`catocli export dia_rules`) and regenerate the locals above, rather than letting `terraform apply` overwrite the live policy with stale config.

Once the plan is clean, adopt the resources into state:

```bash
terraform apply
```

Then delete `migration.tf` - its job is done, and leaving it in place just re-runs the same (no-op) import blocks on every future plan.

</details>

<details>
<summary>Option B — catocli import dia_rules_to_tf (imperative alternative)</summary>

An imperative alternative to Option A, for when native import blocks aren't practical (e.g. scripting a fully automated onboarding pipeline). Unlike Option A, this mutates Terraform state immediately - there is no plan preview before the import happens.

```bash
catocli import dia_rules_to_tf config_data/all_dia_rules_and_sections.json --module-name=module.dia_rules
```

**Parameters:**
- `config_data/all_dia_rules_and_sections.json`: Path to your exported JSON file
- `--module-name=module.dia_rules`: The name of your Terraform module instance

</details>

### Typical Brownfield Workflow

1. **Export existing rules:**
   ```bash
   catocli export dia_rules --json-filename all_dia_rules_and_sections.json
   ```

2. **Create your Terraform configuration:**
   ```hcl
   module "dia_rules" {
     source = "catonetworks/bulk-dia-rules/cato"

     dia_rules_json_file_path = "./config_data/all_dia_rules_and_sections.json"
   }
   ```

3. **Adopt existing state (Option A — recommended):** create `migration.tf` with the import blocks shown above, then:
   ```bash
   terraform plan    # preview: expect only "to import" (plus the un-importable move resource)
   terraform apply   # adopt into state
   ```
   Delete `migration.tf` afterwards. (Option B: `catocli import dia_rules_to_tf config_data/all_dia_rules_and_sections.json --module-name=module.dia_rules` - imperative, no plan preview.)

4. **Run Terraform plan to verify:**
   ```bash
   terraform plan
   ```
   This should show no changes if the import was successful.

### Backup and Restore Workflow

If unintended changes are made directly to rules and sections in the Cato Management Application, you can restore to the last known good state:

1. **Apply your last known good configuration:**
   ```bash
   terraform apply
   ```
   This will restore rules and sections to match your Terraform configuration.

2. **Alternatively, re-export and compare:**
   ```bash
   catocli export dia_rules --json-filename all_dia_rules_and_sections.json
   # Compare with your existing JSON file to identify changes
   ```

## Using Module Outputs

The module provides outputs that can be used for monitoring, auditing, integration with other systems, and operational insights. Below are practical examples of how to use these outputs in your Terraform configuration.

<details>
<summary>Click to expand example client-side outputs</summary>

```hcl
# Basic deployment information
output "deployment_info" {
  description = "Basic information about the Dynamic IP Allocation deployment"
  value = {
    total_sections = module.dia_rules.deployment_summary.sections
    total_rules    = module.dia_rules.deployment_summary.rules
  }
}

# Quick reference for rule and section IDs
output "quick_reference" {
  description = "Quick reference maps for rules and sections"
  value = {
    section_ids = module.dia_rules.section_ids
    rule_ids    = module.dia_rules.rule_ids
  }
}

# Example: Rules that might need attention
output "rules_needing_attention" {
  description = "rules_in_sections rows that could not be ordered by the move resource"
  value = {
    unordered_rules       = module.dia_rules.unordered_rules
    unordered_rules_count = length(module.dia_rules.unordered_rules)
  }
}

# Example: For integration with monitoring systems
output "monitoring_metrics" {
  description = "Example metrics that could be sent to monitoring systems"
  value = {
    deployment_timestamp = timestamp()
    total_dia_rules      = module.dia_rules.deployment_summary.rules
    total_dia_sections   = module.dia_rules.deployment_summary.sections
  }
}
```
</details>

### Output Use Cases

These example outputs demonstrate various practical applications:

- **`deployment_info`**: Quick deployment overview for dashboards
- **`quick_reference`**: ID mappings for referencing resources in other modules
- **`rules_needing_attention`**: Identifying rules this module could not order (surfaced via `unordered_rules`) for manual review
- **`monitoring_metrics`**: Metrics formatted for monitoring systems

## Known limitations

- Ordering rows with `section_name: ""` are excluded from the move resource and surfaced via `unordered_rules`; their order is creation order.
- Run applies with `-parallelism=1` when several module instances share an account.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_cato"></a> [cato](#requirement\_cato) | >= 1.3.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_cato"></a> [cato](#provider\_cato) | >= 1.3.1 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [cato_bulk_dia_move_rule.all_dia_rules](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/bulk_dia_move_rule) | resource |
| [cato_dynamic_ip_allocation_policy.policy](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/dynamic_ip_allocation_policy) | resource |
| [cato_dynamic_ip_allocation_rule.rules](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/dynamic_ip_allocation_rule) | resource |
| [cato_dynamic_ip_allocation_section.sections](https://registry.terraform.io/providers/catonetworks/cato/latest/docs/resources/dynamic_ip_allocation_section) | resource |
| [terraform_data.guard_empty_policy](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_empty_policy"></a> [allow\_empty\_policy](#input\_allow\_empty\_policy) | Safety guard: fail planning when the policy JSON contains 0 rules unless explicitly allowed. Protects against a truncated or wrong-tenant export destroying the live policy. Set true only for intentional greenfield/teardown. | `bool` | `false` | no |
| <a name="input_dia_rules_json_file_path"></a> [dia\_rules\_json\_file\_path](#input\_dia\_rules\_json\_file\_path) | Path to the Dynamic IP Allocation JSON export produced by `catocli export dia_rules` (data.policy.dynamicIpAllocation.policy root). | `string` | n/a | yes |
| <a name="input_policy_enabled"></a> [policy\_enabled](#input\_policy\_enabled) | Manage the account-level Dynamic IP Allocation policy toggle. null leaves the toggle unmanaged; true/false manages it via cato\_dynamic\_ip\_allocation\_policy. | `bool` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_deployment_summary"></a> [deployment\_summary](#output\_deployment\_summary) | Counts of managed Dynamic IP Allocation objects. |
| <a name="output_rule_ids"></a> [rule\_ids](#output\_rule\_ids) | Map of rule name to rule id. |
| <a name="output_section_ids"></a> [section\_ids](#output\_section\_ids) | Map of section name to section id. |
| <a name="output_unordered_rules"></a> [unordered\_rules](#output\_unordered\_rules) | rules\_in\_sections rows excluded from cato\_bulk\_dia\_move\_rule (no managed section to order within). |
<!-- END_TF_DOCS -->
