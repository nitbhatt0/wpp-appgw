resource "random_string" "rg" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "103-application-gateway-${random_string.rg.result}"
  location = "westus2"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "myVNet-${random_string.rg.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.21.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "myAGSubnet-${random_string.rg.result}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.21.0.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "myBackendSubnet-${random_string.rg.result}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.21.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "myAGPublicIPAddress-${random_string.rg.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}


resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "nic-${count.index+1}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "nic-ipconfig-${count.index+1}"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic"
  }
}



resource "azurerm_network_security_group" "my_terraform_nsg" {
  name                = "${random_string.rg.result}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "web"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Remote-PS"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "5985-5986"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowLoadBalancerTraffic"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
  count                   = 1
  network_interface_id      = azurerm_network_interface.nic[count.index].id
  network_security_group_id = azurerm_network_security_group.my_terraform_nsg.id
}



resource "random_password" "password" {
  length  = 16
  special = true
  lower   = true
  upper   = true
  numeric = true
}

resource "azurerm_windows_virtual_machine" "vm" {
  count               = 2
  name                = "myVM${count.index+1}-${random_string.rg.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D4s_v3"
  admin_username      = "azureadmin"
  admin_password      = random_password.password.result

  network_interface_ids = [
    azurerm_network_interface.nic[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}


resource "azurerm_virtual_machine_extension" "stop-iis" {
  count                = 1
  name                 = "stop-iis"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm[0].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
          "commandToExecute": "powershell -Command \"Add-WindowsFeature Web-Server; Add-Content -Path 'C:\\inetpub\\wwwroot\\Default.htm' -Value $($env:computername); Stop-Service -Name W3SVC\""
    
      }
  SETTINGS
}

resource "azurerm_virtual_machine_extension" "block-port-80" {
  count                = 1
  name                 = "block-port-80"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm[1].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -Command \"Add-WindowsFeature Web-Server; Add-Content -Path 'C:\\inetpub\\wwwroot\\Default.htm' -Value $($env:computername); New-NetFirewallRule -DisplayName 'Block Port 80' -Direction Inbound -LocalPort 80 -Protocol TCP -Action Block\""
    }
  SETTINGS
}



resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "nic-assoc" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.nic[count.index].id
  ip_configuration_name   = "nic-ipconfig-${count.index+1}"
  backend_address_pool_id = one(azurerm_application_gateway.main.backend_address_pool).id
}
 
resource "azurerm_log_analytics_workspace" "example" {
  name                = "example-law-${random_string.rg.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_gateway" "main" {
  name                = "myAppGateway-${random_string.rg.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "my-gateway-ip-configuration-${random_string.rg.result}"
    subnet_id = azurerm_subnet.frontend.id
  }

  frontend_port {
    name = var.frontend_port_name-${random_string.rg.result}
    port = 80
  }

  frontend_ip_configuration {
    name                 = var.frontend_ip_configuration_name-${random_string.rg.result}
    public_ip_address_id = azurerm_public_ip.pip.id
  }

  backend_address_pool {
    name = var.backend_address_pool_name-${random_string.rg.result}
  }

  backend_http_settings {
    name                  = var.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 88
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = var.listener_name
    frontend_ip_configuration_name = var.frontend_ip_configuration_name
    frontend_port_name             = var.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = var.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = var.listener_name
    backend_address_pool_name  = var.backend_address_pool_name
    backend_http_settings_name = var.http_setting_name
    priority                   = 1
  }

 waf_configuration {
    enabled                             = true
    firewall_mode                       = "Detection"
    rule_set_type                       = "OWASP"
    rule_set_version                    = "3.2"
 
  }
}
  resource "azurerm_monitor_diagnostic_setting" "example" {
  name               = "appgw-diagnostic-setting-${random_string.rg.result}"
  target_resource_id = azurerm_application_gateway.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
       }


  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
      }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
      }

  metric {
    category = "AllMetrics"
    enabled  = true
    }
}
