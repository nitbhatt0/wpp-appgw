terraform {
  required_version = ">=1.2"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  #USE_MSI=true
#SUBSCRIPTION_ID=f07ec78d-739f-40a0-bcbc-d71385becc02
#TENANT_ID=08ce1371-7f99-44e6-a346-ee7958e333fa
}