
#######################################4#######################################8
#                                                                              #
#                                Resource Group                                #
#                                                                              #
#######################################4#######################################8

// Creates the resource group
resource "azurerm_resource_group" "resource_group" {
  provider                             = azurerm.main
  count                                = local.resource_group_exists ? 0 : 1
  name                                 = local.resourcegroup_name
  location                             = local.region
  tags                                 = merge(var.infrastructure.tags, var.tags)

}

// Imports data of existing resource group
data "azurerm_resource_group" "resource_group" {
  provider                             = azurerm.main
  count                                = local.resource_group_exists ? 1 : 0
  name                                 = local.resourcegroup_name
}

// Creates the SAP VNET
resource "azurerm_virtual_network" "vnet_sap" {
  provider                             = azurerm.main
  count                                = local.SAP_virtualnetwork_exists ? 0 : 1
  name                                 = local.SAP_virtualnetwork_name
  location                             = local.resource_group_exists ? (
                                           data.azurerm_resource_group.resource_group[0].location) : (
                                           azurerm_resource_group.resource_group[0].location
                                         )
  resource_group_name                  = local.resource_group_exists ? (
                                           data.azurerm_resource_group.resource_group[0].name) : (
                                           azurerm_resource_group.resource_group[0].name
                                         )
  address_space                        = local.network_address_space
  flow_timeout_in_minutes              = local.network_flow_timeout_in_minutes
  tags                                 = var.tags
}

// Imports data of existing SAP VNET
data "azurerm_virtual_network" "vnet_sap" {
  provider                             = azurerm.main
  count                                = local.SAP_virtualnetwork_exists ? 1 : 0
  name                                 = split("/", local.SAP_virtualnetwork_id)[8]
  resource_group_name                  = split("/", local.SAP_virtualnetwork_id)[4]
}

resource "azurerm_virtual_network_dns_servers" "vnet_sap_dns_servers" {
  provider                             = azurerm.main
  count                                = local.SAP_virtualnetwork_exists && length(var.dns_settings.dns_server_list) > 0 ? 1 : 0
  virtual_network_id                   = azurerm_virtual_network.vnet_sap[0].id
  dns_servers                          = var.dns_settings.dns_server_list
}

# // Peers management VNET to SAP VNET
resource "azurerm_virtual_network_peering" "peering_management_sap" {
  provider                             = azurerm.peering
  count                                = var.peer_with_control_plane_vnet ? (
                                           local.SAP_virtualnetwork_exists || !var.use_deployer ? 0 : 1) : (
                                           0
                                         )
  name                                 = substr(
                                           format("%s_to_%s",
                                             split("/", local.deployer_virtualnetwork_id)[8],
                                             local.SAP_virtualnetwork_exists ? (
                                               data.azurerm_virtual_network.vnet_sap[0].name) : (
                                               azurerm_virtual_network.vnet_sap[0].name
                                             )
                                           ),
                                           0,
                                           80
                                         )
  virtual_network_name                 = split("/", local.deployer_virtualnetwork_id)[8]
  resource_group_name                  = split("/", local.deployer_virtualnetwork_id)[4]
  remote_virtual_network_id            = azurerm_virtual_network.vnet_sap[0].id

  allow_virtual_network_access         = true
}

// Peers SAP VNET to management VNET
resource "azurerm_virtual_network_peering" "peering_sap_management" {
  provider                             = azurerm.main
  count                                = var.peer_with_control_plane_vnet ? (
                                           local.SAP_virtualnetwork_exists || !var.use_deployer ? 0 : 1) : (
                                           0
                                         )

  name                                 = substr(
                                           format("%s_to_%s",
                                             local.SAP_virtualnetwork_exists ? (
                                               data.azurerm_virtual_network.vnet_sap[0].name) : (
                                               azurerm_virtual_network.vnet_sap[0].name
                                             ), split("/", local.deployer_virtualnetwork_id)[8]
                                           ),
                                           0,
                                           80
                                         )
  resource_group_name                  = local.SAP_virtualnetwork_exists ? (
                                           data.azurerm_virtual_network.vnet_sap[0].resource_group_name) : (
                                           azurerm_virtual_network.vnet_sap[0].resource_group_name
                                         )
  virtual_network_name                 = azurerm_virtual_network.vnet_sap[0].name

  remote_virtual_network_id            = local.deployer_virtualnetwork_id
  allow_virtual_network_access         = true
  allow_forwarded_traffic              = true
}

//Route table
resource "azurerm_route_table" "rt" {
  provider                             = azurerm.main
  count                                = local.SAP_virtualnetwork_exists ? 0 : (local.create_nat_gateway ? 0 : 1)
  depends_on                           = [
                                           azurerm_virtual_network.vnet_sap
                                         ]
  name                                 = format("%s%s%s%s",
                                           var.naming.resource_prefixes.routetable,
                                           local.prefix,
                                           var.naming.separator,
                                           local.resource_suffixes.routetable
                                         )
  bgp_route_propagation_enabled        = local.network_enable_route_propagation
  resource_group_name                  = azurerm_virtual_network.vnet_sap[0].resource_group_name
  location                             = azurerm_virtual_network.vnet_sap[0].location

  tags                                 = var.tags
}

resource "azurerm_route" "admin" {
  provider                             = azurerm.main
  count                                = length(local.firewall_ip) > 0 ? local.SAP_virtualnetwork_exists ? 0 : (local.create_nat_gateway ? 0 : 1) : 0
  depends_on                           = [
                                           azurerm_route_table.rt
                                         ]
  name                                 = format("%s%s%s%s",
                                           var.naming.resource_prefixes.fw_route,
                                           local.prefix,
                                           var.naming.separator,
                                           local.resource_suffixes.fw_route
                                         )
  resource_group_name                  = local.SAP_virtualnetwork_exists ? (
                                           data.azurerm_virtual_network.vnet_sap[0].resource_group_name) : (
                                           azurerm_virtual_network.vnet_sap[0].resource_group_name
                                         )
  route_table_name                     = azurerm_route_table.rt[0].name
  address_prefix                       = "0.0.0.0/0"
  next_hop_type                        = "VirtualAppliance"
  next_hop_in_ip_address               = local.firewall_ip

}

resource "azurerm_management_lock" "vnet_sap" {
  provider                             = azurerm.main
  count                                = (local.SAP_virtualnetwork_exists) ? 0 : var.place_delete_lock_on_resources ? 1 : 0
  name                                 = format("%s-lock", local.SAP_virtualnetwork_name)
  scope                                = azurerm_virtual_network.vnet_sap[0].id
  lock_level                           = "CanNotDelete"
  notes                                = "Locked because it's needed by the Workload"
  lifecycle {
              prevent_destroy = false
            }
}

# // Peers management VNET to SAP VNET
resource "azurerm_virtual_network_peering" "peering_agent_sap" {
  provider                             = azurerm.peering
  count                                = length(var.agent_network_id) > 0 ? 1:0
  name                                 = substr(
                                           format("%s_to_%s",
                                             split("/", var.agent_network_id)[8],
                                             local.SAP_virtualnetwork_exists ? (
                                               data.azurerm_virtual_network.vnet_sap[0].name) : (
                                               azurerm_virtual_network.vnet_sap[0].name
                                             )
                                           ),
                                           0,
                                           80
                                         )
  virtual_network_name                 = split("/", var.agent_network_id)[8]
  resource_group_name                  = split("/", var.agent_network_id)[4]
  remote_virtual_network_id            = local.SAP_virtualnetwork_exists ? (
                                           data.azurerm_virtual_network.vnet_sap[0].id) : (
                                           azurerm_virtual_network.vnet_sap[0].id
                                         )

  allow_virtual_network_access         = true
}

// Peers SAP VNET to management VNET
resource "azurerm_virtual_network_peering" "peering_sap_agent" {
  provider                             = azurerm.main
  count                                = length(var.agent_network_id) > 0 ? 1:0
  name                                 = substr(
                                           format("%s_to_%s",
                                             local.SAP_virtualnetwork_exists ? (
                                               data.azurerm_virtual_network.vnet_sap[0].name) : (
                                               azurerm_virtual_network.vnet_sap[0].name
                                             ), split("/", var.agent_network_id)[8]
                                           ),
                                           0,
                                           80
                                         )
  resource_group_name                  = local.SAP_virtualnetwork_exists ? (
                                           data.azurerm_virtual_network.vnet_sap[0].resource_group_name) : (
                                           azurerm_virtual_network.vnet_sap[0].resource_group_name
                                         )
  virtual_network_name                 = local.SAP_virtualnetwork_exists ? (
                                           data.azurerm_virtual_network.vnet_sap[0].name) : (
                                           azurerm_virtual_network.vnet_sap[0].name
                                         )
  remote_virtual_network_id            = var.agent_network_id
  allow_virtual_network_access         = true
  allow_forwarded_traffic              = true
}
