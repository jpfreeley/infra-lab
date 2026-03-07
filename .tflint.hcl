config {
  format = "compact"
  plugin_dir = "~/.tflint.d/plugins"
}

plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Enforce that all variables have a description
rule "terraform_documented_variables" {
  enabled = true
}

# Enforce snake_case for all resource names
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Disallow unused declarations (we will use inline ignores for the 'target' provider)
rule "terraform_unused_declarations" {
  enabled = true
}

# Enforce that all modules from a registry have a version specified
rule "terraform_module_pinned_source" {
  enabled = true
}
