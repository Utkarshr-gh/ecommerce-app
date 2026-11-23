terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  app_name      = "${var.app_name_prefix}-${random_string.suffix.result}"
  https_enabled = var.ssl_pfx_path != ""
}

# ---------- Resource group ----------
resource "azurerm_resource_group" "rg" {
  name     = "rg-ecomm-demo"
  location = var.location
}

# ---------- Network: VNet + public/private subnets ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-ecomm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
}

# Public subnet: only the Application Gateway lives here
resource "azurerm_subnet" "public" {
  name                 = "snet-public-agw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Private subnet 1: App Service outbound traffic (VNet integration)
resource "azurerm_subnet" "private_app" {
  name                 = "snet-private-app"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "appservice"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Private subnet 2: private endpoint (inbound to App Service)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

# NSG for the Application Gateway subnet (required rules for the v2 SKU)
resource "azurerm_network_security_group" "agw" {
  name                = "nsg-agw"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "Allow-HTTP-Internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Port 443 is only opened when a certificate is supplied
  dynamic "security_rule" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                       = "Allow-HTTPS-Internet"
      priority                   = 105
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "Internet"
      destination_address_prefix = "*"
    }
  }

  security_rule {
    name                       = "Allow-GatewayManager"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-AzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "agw" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.agw.id
}

# ---------- App Service ----------
resource "azurerm_service_plan" "plan" {
  name                = "asp-ecomm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
}

resource "azurerm_linux_web_app" "app" {
  name                      = local.app_name
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  service_plan_id           = azurerm_service_plan.plan.id
  virtual_network_subnet_id = azurerm_subnet.private_app.id
  https_only                = true

  site_config {
    always_on                         = true
    health_check_path                 = "/actuator/health"
    health_check_eviction_time_in_min = 5

    application_stack {
      java_server         = "JAVA"
      java_server_version = "17"
      java_version        = "17"
    }

    # Public internet cannot reach the site itself; traffic comes in through the private endpoint.
    # The deployment (SCM/Kudu) endpoint stays reachable so GitHub Actions / Azure DevOps can deploy.
    ip_restriction_default_action     = "Deny"
    scm_ip_restriction_default_action = "Allow"
  }

  app_settings = {
    WEBSITES_PORT = "8080"
  }
}

# ---------- Private endpoint + private DNS ----------
resource "azurerm_private_dns_zone" "web" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "web" {
  name                  = "link-vnet-ecomm"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.web.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "app" {
  name                = "pe-ecomm-app"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-ecomm-app"
    private_connection_resource_id = azurerm_linux_web_app.app.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.web.id]
  }
}

# ---------- Application Gateway (the Layer-7 load balancer) ----------
resource "azurerm_public_ip" "agw" {
  name                = "pip-agw-ecomm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "agw" {
  name                = "agw-ecomm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "gateway-ip"
    subnet_id = azurerm_subnet.public.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  dynamic "frontend_port" {
    for_each = local.https_enabled ? [1] : []
    content {
      name = "https"
      port = 443
    }
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.agw.id
  }

  # Certificate (.pfx) for the HTTPS listener. Optional.
  dynamic "ssl_certificate" {
    for_each = local.https_enabled ? [1] : []
    content {
      name     = "shopeasy-cert"
      data     = filebase64(var.ssl_pfx_path)
      password = var.ssl_pfx_password
    }
  }

  backend_address_pool {
    name  = "appservice"
    fqdns = [azurerm_linux_web_app.app.default_hostname]
  }

  probe {
    name                                      = "app-probe"
    protocol                                  = "Https"
    path                                      = "/actuator/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
    match {
      status_code = ["200-399"]
    }
  }

  backend_http_settings {
    name                                = "https-settings"
    port                                = 443
    protocol                            = "Https"
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = "app-probe"
  }

  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "public"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  dynamic "http_listener" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                           = "listener-https"
      frontend_ip_configuration_name = "public"
      frontend_port_name             = "https"
      protocol                       = "Https"
      ssl_certificate_name           = "shopeasy-cert"
    }
  }

  dynamic "redirect_configuration" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                 = "http-to-https"
      redirect_type        = "Permanent"
      target_listener_name = "listener-https"
      include_path         = true
      include_query_string = true
    }
  }

  # HTTP rule: forwards to the app, or redirects to HTTPS when a certificate is supplied
  request_routing_rule {
    name                        = "route-http"
    priority                    = 100
    rule_type                   = "Basic"
    http_listener_name          = "listener-http"
    backend_address_pool_name   = local.https_enabled ? null : "appservice"
    backend_http_settings_name  = local.https_enabled ? null : "https-settings"
    redirect_configuration_name = local.https_enabled ? "http-to-https" : null
  }

  # HTTPS rule: forwards to the app through the private endpoint
  dynamic "request_routing_rule" {
    for_each = local.https_enabled ? [1] : []
    content {
      name                       = "route-https"
      priority                   = 110
      rule_type                  = "Basic"
      http_listener_name         = "listener-https"
      backend_address_pool_name  = "appservice"
      backend_http_settings_name = "https-settings"
    }
  }

  depends_on = [
    azurerm_private_endpoint.app,
    azurerm_subnet_network_security_group_association.agw
  ]
}
