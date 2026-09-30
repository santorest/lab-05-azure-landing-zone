terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.7"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }

  # Partial configuration: copy backend.hcl.example to backend.hcl and run `terraform init -backend-config=backend.hcl`.
  backend "azurerm" {}
}
