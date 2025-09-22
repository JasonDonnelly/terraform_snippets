# Jason Donnelly - 22nd September 2025
# 
# Example terraform to deliver a storage account for many clients across multiple environments.
# 
# Extending the Clients and or Environments Variables and their validation statements will allow additional
# Clients and Environments to be created easily

terraform {
  required_version = ">= 1.10.0, <2.0.0"
  required_providers {

    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.12.0, <5.0.0"
    }

  }
}

variable "clients" {
  type      = list(string)
  nullable  = false
  sensitive = false
  default   = ["abc", "def", "ghi"]

  validation {
    condition = alltrue([
    for c in var.clients : length(c) <= 14 && can(regex("^[a-z0-9]*$", c))
  ])
    error_message = "The clients list of strings must be lowercase alphanumeric characters and have a maximum length of 14 characters each."
  }
}

variable "environments" {
  type      = list(string)
  nullable  = false
  sensitive = false
  default   = ["dev", "tst", "stg", "prd"]

  validation {
  condition = alltrue([
    for e in var.environments : contains(["dev", "tst", "stg", "prd"], e)
  ])
  error_message = "Allowed environments are: dev, tst, stg, prd."
    }

}

locals {
  sa_names = {
    for sa_name in flatten([
      for c in var.clients : [
        for e in var.environments : {
          key         = join("-", [c, e])
          client      = c
          environment = e
        }
      ]
    ]) :
    sa_name.key => {
      client      = sa_name.client
      environment = sa_name.environment
    }
  }

  sa_names_with_suffix = {
    for k, v in local.sa_names : k => merge(v, {
      suffix = random_string.sa_suffix[k].result
    })
  }
}

resource "random_string" "sa_suffix" {
  for_each = local.sa_names

  length  = 4
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-storage-accounts"
  location = "North Europe"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-storage-accounts"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-storage-accounts"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_storage_account" "sa" {

  for_each = local.sa_names_with_suffix

  name                = substr(lower(join("", [each.value.client, each.value.environment, each.value.suffix])), 0, 24)
  resource_group_name = azurerm_resource_group.rg.name

  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  network_rules {
    default_action             = "Deny"
    ip_rules                   = ["100.0.0.1"]
    virtual_network_subnet_ids = [azurerm_subnet.subnet.id]
  }

  tags = {
    client      = each.value.client
    environment = each.value.environment
  }
}
