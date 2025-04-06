// ----------------------
// 1. Terraform Settings
// ----------------------
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-landingzone-core"
    storage_account_name = "mystorageacct"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

// ----------------------
// 2. Variables
// ----------------------
variable "location" {
  default = "East US"
}

variable "resource_group_name" {
  default = "rg-landingzone-core"
}

variable "vnet_name" {
  default = "vnet-landingzone"
}

variable "vnet_address_space" {
  default = ["10.0.0.0/16"]
}

variable "subnet_name" {
  default = "subnet-core"
}

variable "subnet_prefix" {
  default = ["10.0.1.0/24"]
}

variable "log_analytics_name" {
  default = "log-eastus"
}

variable "app_gateway_name" {
  default = "appgw-landingzone"
}

variable "public_ip_name" {
  default = "appgw-publicip"
}

variable "vm_name" {
  default = "winvm-01"
}

variable "admin_username" {
  default = "azureuser"
}

variable "admin_password" {
  default = "P@ssword1234!"
}

variable "domain_name" {
  default = "corp.local"
}

variable "domain_username" {
  default = "corp\\domainadmin"
}

variable "domain_password" {
  default = "DomainPassw0rd!"
}

variable "key_vault_name" {
  default = "kv-landingzone"
}

variable "tenant_id" {}
variable "admin_object_id" {}

variable "alert_email" {
  default = "admin@example.com"
}

variable "recovery_vault_name" {
  default = "vault-landingzone"
}

// ----------------------
// 3. Core Resource Group
// ----------------------
resource "azurerm_resource_group" "core" {
  name     = var.resource_group_name
  location = var.location
}

// ----------------------
// 4. Modules
// ----------------------
module "networking" {
  source              = "./modules/networking"
  location            = var.location
  resource_group_name = azurerm_resource_group.core.name
  vnet_name           = var.vnet_name
  address_space       = var.vnet_address_space
  subnet_name         = var.subnet_name
  subnet_prefix       = var.subnet_prefix
}

module "nsg" {
  source              = "./modules/nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.core.name
  subnet_id           = module.networking.subnet_id
}

module "logging" {
  source              = "./modules/logging"
  location            = var.location
  resource_group_name = azurerm_resource_group.core.name
  log_analytics_name  = var.log_analytics_name
}

module "windows_vm" {
  source              = "./modules/windows_vm"
  location            = var.location
  resource_group_name = azurerm_resource_group.core.name
  subnet_id           = module.networking.subnet_id
  vm_name             = var.vm_name
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  log_analytics_id    = module.logging.workspace_id
  domain_join         = true
  domain_name         = var.domain_name
  domain_username     = var.domain_username
  domain_password     = var.domain_password
}

module "app_gateway" {
  source              = "./modules/app_gateway"
  location            = var.location
  resource_group_name = var.resource_group_name
  vnet_name           = var.vnet_name
  subnet_id           = module.networking.subnet_id
  gateway_name        = var.app_gateway_name
  public_ip_name      = var.public_ip_name
  backend_ip_address  = module.windows_vm.private_ip
}

module "key_vault" {
  source              = "./modules/key_vault"
  location            = var.location
  resource_group_name = var.resource_group_name
  kv_name             = var.key_vault_name
  tenant_id           = var.tenant_id
  object_id           = var.admin_object_id
}

module "monitoring" {
  source              = "./modules/monitoring"
  location            = var.location
  resource_group_name = azurerm_resource_group.core.name
  log_analytics_id    = module.logging.workspace_id
  alert_email         = var.alert_email
}

module "rbac" {
  source               = "./modules/rbac"
  resource_group_name  = azurerm_resource_group.core.name
  role_definition_name = "Contributor"
  principal_id         = var.admin_object_id
}

module "backup" {
  source              = "./modules/backup"
  location            = var.location
  resource_group_name = azurerm_resource_group.core.name
  recovery_vault_name = var.recovery_vault_name
  vm_id               = module.windows_vm.vm_id
}

// ----------------------
// 5. Outputs
// ----------------------
output "resource_group_name" {
  value = azurerm_resource_group.core.name
}

output "vm_private_ip" {
  value = module.windows_vm.private_ip
}

output "app_gateway_ip" {
  value = module.app_gateway.public_ip
}

// ----------------------
// 6. GitHub Actions CI/CD Pipeline (terraform.yml)
// ----------------------
/*
name: Terraform CI/CD

on:
  push:
    branches:
      - main

jobs:
  terraform:
    name: "Terraform Plan & Apply"
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.5

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        run: terraform plan

      - name: Terraform Apply
        run: terraform apply -auto-approve
        env:
          ARM_CLIENT_ID: ${{ secrets.ARM_CLIENT_ID }}
          ARM_CLIENT_SECRET: ${{ secrets.ARM_CLIENT_SECRET }}
          ARM_SUBSCRIPTION_ID: ${{ secrets.ARM_SUBSCRIPTION_ID }}
          ARM_TENANT_ID: ${{ secrets.ARM_TENANT_ID }}
*/
