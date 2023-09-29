
#########################################################################################
#                                                                                       #
#  Name generator                                                                       #
#                                                                                       #
#########################################################################################

module "sap_namegenerator" {
  source                                        = "../../terraform-units/modules/sap_namegenerator"
  environment                                   = local.infrastructure.environment
  location                                      = local.infrastructure.region
  codename                                      = lower(try(local.infrastructure.codename, ""))
  random_id                                     = module.common_infrastructure.random_id
  sap_vnet_name                                 = local.vnet_logical_name
  sap_sid                                       = local.sap_sid
  db_sid                                        = local.db_sid
  web_sid                                       = local.web_sid

  app_ostype                                    = upper(try(local.application_tier.app_os.os_type, "LINUX"))
  anchor_ostype                                 = upper(try(local.anchor_vms.os.os_type, "LINUX"))
  db_ostype                                     = upper(try(local.database.os.os_type, "LINUX"))

  db_server_count                               = var.database_server_count
  app_server_count                              = try(local.application_tier.application_server_count, 0)
  web_server_count                              = try(local.application_tier.webdispatcher_count, 0)
  scs_server_count                              = local.application_tier.scs_high_availability ? (
                                                    2 * local.application_tier.scs_server_count) : (
                                                    local.application_tier.scs_server_count
                                                  )

  app_zones                                     = try(local.application_tier.app_zones, [])
  scs_zones                                     = try(local.application_tier.scs_zones, [])
  web_zones                                     = try(local.application_tier.web_zones, [])
  db_zones                                      = try(local.database.zones, [])

  resource_offset                               = try(var.resource_offset, 0)
  custom_prefix                                 = var.custom_prefix
  database_high_availability                    = local.database.high_availability
  database_cluster_type                         = local.database.database_cluster_type
  scs_high_availability                         = local.application_tier.scs_high_availability
  scs_cluster_type                              = local.application_tier.scs_cluster_type
  use_zonal_markers                             = var.use_zonal_markers
}

#########################################################################################
#                                                                                       #
#  Common Infrastructure                                                                #
#                                                                                       #
#########################################################################################

module "common_infrastructure" {
  source                                        = "../../terraform-units/modules/sap_system/common_infrastructure"
  providers = {
    azurerm.deployer                            = azurerm
    azurerm.main                                = azurerm.system
    azurerm.dnsmanagement                       = azurerm.dnsmanagement
  }
  is_single_node_hana                           = "true"
  application_tier                              = local.application_tier
  database                                      = local.database
  infrastructure                                = local.infrastructure
  options                                       = local.options
  key_vault                                     = local.key_vault
  naming                                        = length(var.name_override_file) > 0 ? local.custom_names : module.sap_namegenerator.naming
  service_principal                             = var.use_spn ? local.service_principal : local.account
  deployer_tfstate                              = length(var.deployer_tfstate_key) > 0 ? data.terraform_remote_state.deployer[0].outputs : null
  landscape_tfstate                             = data.terraform_remote_state.landscape.outputs
  custom_disk_sizes_filename                    = try(coalesce(var.custom_disk_sizes_filename, var.db_disk_sizes_filename), "")
  authentication                                = local.authentication
  terraform_template_version                    = var.terraform_template_version
  deployment                                    = var.deployment
  license_type                                  = var.license_type
  enable_purge_control_for_keyvaults            = var.enable_purge_control_for_keyvaults
  sapmnt_volume_size                            = var.sapmnt_volume_size
  NFS_provider                                  = var.NFS_provider
  custom_prefix                                 = var.use_prefix ? var.custom_prefix : " "
  ha_validator                                  = format("%d%d-%s",
                                                    local.application_tier.scs_high_availability ? 1 : 0,
                                                    local.database.high_availability ? 1 : 0,
                                                    upper(try(local.application_tier.app_os.os_type, "LINUX")) == "LINUX" ? var.NFS_provider : "WINDOWS"
                                                  )
  Agent_IP                                      = var.Agent_IP
  use_private_endpoint                          = var.use_private_endpoint

  use_custom_dns_a_registration                 = try(data.terraform_remote_state.landscape.outputs.use_custom_dns_a_registration, true)
  management_dns_subscription_id                = try(data.terraform_remote_state.landscape.outputs.management_dns_subscription_id, null)
  management_dns_resourcegroup_name             = coalesce(data.terraform_remote_state.landscape.outputs.management_dns_resourcegroup_name, local.saplib_resource_group_name)

  database_dual_nics                            = var.database_dual_nics

  azure_files_sapmnt_id                         = var.azure_files_sapmnt_id
  use_random_id_for_storageaccounts             = var.use_random_id_for_storageaccounts

  hana_ANF_volumes                              = local.hana_ANF_volumes
  sapmnt_private_endpoint_id                    = var.sapmnt_private_endpoint_id
  deploy_application_security_groups            = var.deploy_application_security_groups
  use_service_endpoint                          = var.use_service_endpoint

  use_scalesets_for_deployment                  = var.use_scalesets_for_deployment

}


#-------------------------------------------------------------------------------
#                                                                              #
#  HANA Infrastructure                                                         #
#                                                                              #
#--------------------------------------+---------------------------------------8
module "hdb_node" {
  source                                        = "../../terraform-units/modules/sap_system/hdb_node"
  depends_on                                    = [module.common_infrastructure]
  providers = {
    azurerm.deployer                            = azurerm
    azurerm.main                                = azurerm.system
    azurerm.dnsmanagement                       = azurerm.dnsmanagement
//    azapi.api             = azapi.api
  }

  admin_subnet                                  = module.common_infrastructure.admin_subnet
  anchor_vm                                     = module.common_infrastructure.anchor_vm // Workaround to create dependency from anchor to db to app
  cloudinit_growpart_config                     = null # This needs more consideration module.common_infrastructure.cloudinit_growpart_config
  custom_disk_sizes_filename                    = try(coalesce(var.custom_disk_sizes_filename, var.db_disk_sizes_filename), "")
  database                                      = local.database
  database_cluster_disk_size                    = var.database_cluster_disk_size
  database_dual_nics                            = try(module.common_infrastructure.admin_subnet, null) == null ? false : var.database_dual_nics
  database_server_count                         = upper(try(local.database.platform, "HANA")) == "HANA" ? (
                                                    local.database.high_availability ? (
                                                      2 * var.database_server_count) : (
                                                      var.database_server_count
                                                    )) : (
                                                    0
                                                  )
  database_use_premium_v2_storage               = var.database_use_premium_v2_storage
  database_vm_admin_nic_ips                     = var.database_vm_admin_nic_ips
  database_vm_db_nic_ips                        = var.database_vm_db_nic_ips
  database_vm_db_nic_secondary_ips              = var.database_vm_db_nic_secondary_ips
  database_vm_storage_nic_ips                   = var.database_vm_storage_nic_ips
  db_asg_id                                     = module.common_infrastructure.db_asg_id
  db_subnet                                     = module.common_infrastructure.db_subnet
  deploy_application_security_groups            = var.deploy_application_security_groups
  deployment                                    = var.deployment
  fencing_role_name                             = var.fencing_role_name
  hana_ANF_volumes                              = local.hana_ANF_volumes
  infrastructure                                = local.infrastructure
  landscape_tfstate                             = data.terraform_remote_state.landscape.outputs
  license_type                                  = var.license_type
  management_dns_subscription_id                = try(data.terraform_remote_state.landscape.outputs.management_dns_subscription_id, null)
  management_dns_resourcegroup_name             = coalesce(data.terraform_remote_state.landscape.outputs.management_dns_resourcegroup_name, local.saplib_resource_group_name)
  naming                                        = length(var.name_override_file) > 0 ? local.custom_names : module.sap_namegenerator.naming
  NFS_provider                                  = var.NFS_provider
  options                                       = local.options
  ppg                                           = module.common_infrastructure.ppg
  register_virtual_network_to_dns               = try(data.terraform_remote_state.landscape.outputs.register_virtual_network_to_dns, true)
  resource_group                                = module.common_infrastructure.resource_group
  sap_sid                                       = local.sap_sid
  scale_set_id                                  = module.common_infrastructure.scale_set_id
  sdu_public_key                                = module.common_infrastructure.sdu_public_key
  sid_keyvault_user_id                          = module.common_infrastructure.sid_keyvault_user_id
  sid_password                                  = module.common_infrastructure.sid_password
  sid_username                                  = module.common_infrastructure.sid_username
  storage_bootdiag_endpoint                     = module.common_infrastructure.storage_bootdiag_endpoint
  storage_subnet                                = module.common_infrastructure.storage_subnet
  terraform_template_version                    = var.terraform_template_version
  use_custom_dns_a_registration                 = try(data.terraform_remote_state.landscape.outputs.use_custom_dns_a_registration, false)
  use_loadbalancers_for_standalone_deployments  = var.use_loadbalancers_for_standalone_deployments
  use_msi_for_clusters                          = var.use_msi_for_clusters
  use_scalesets_for_deployment                  = var.use_scalesets_for_deployment
  use_secondary_ips                             = var.use_secondary_ips


}

#########################################################################################
#                                                                                       #
#  App Tier Infrastructure                                                              #
#                                                                                       #
#########################################################################################

module "app_tier" {
  source                                        = "../../terraform-units/modules/sap_system/app_tier"
  providers = {
    azurerm.deployer                            = azurerm
    azurerm.main                                = azurerm.system
    azurerm.dnsmanagement                       = azurerm.dnsmanagement
  }
  depends_on                                    = [module.common_infrastructure]
  admin_subnet                                  = module.common_infrastructure.admin_subnet
  application_tier                              = local.application_tier
  cloudinit_growpart_config                     = null # This needs more consideration module.common_infrastructure.cloudinit_growpart_config
  custom_disk_sizes_filename                    = try(coalesce(var.custom_disk_sizes_filename, var.app_disk_sizes_filename), "")
  deploy_application_security_groups            = var.deploy_application_security_groups
  deployment                                    = var.deployment
  fencing_role_name                             = var.fencing_role_name
  firewall_id                                   = module.common_infrastructure.firewall_id
  idle_timeout_scs_ers                          = var.idle_timeout_scs_ers
  infrastructure                                = local.infrastructure
  landscape_tfstate                             = data.terraform_remote_state.landscape.outputs
  license_type                                  = var.license_type
  management_dns_resourcegroup_name             = try(data.terraform_remote_state.landscape.outputs.management_dns_resourcegroup_name, local.saplib_resource_group_name)
  management_dns_subscription_id                = try(data.terraform_remote_state.landscape.outputs.management_dns_subscription_id, null)
  naming                                        = length(var.name_override_file) > 0 ? local.custom_names : module.sap_namegenerator.naming
  network_location                              = module.common_infrastructure.network_location
  network_resource_group                        = module.common_infrastructure.network_resource_group
  options                                       = local.options
  order_deployment                              = null
  ppg                                           = module.common_infrastructure.ppg
  register_virtual_network_to_dns               = try(data.terraform_remote_state.landscape.outputs.register_virtual_network_to_dns, true)
  resource_group                                = module.common_infrastructure.resource_group
  route_table_id                                = module.common_infrastructure.route_table_id
  sap_sid                                       = local.sap_sid
  scale_set_id                                  = try(module.common_infrastructure.scale_set_id, null)
  scs_cluster_disk_lun                          = var.scs_cluster_disk_lun
  scs_cluster_disk_size                         = var.scs_cluster_disk_size
  sdu_public_key                                = module.common_infrastructure.sdu_public_key
  sid_keyvault_user_id                          = module.common_infrastructure.sid_keyvault_user_id
  sid_password                                  = module.common_infrastructure.sid_password
  sid_username                                  = module.common_infrastructure.sid_username
  storage_bootdiag_endpoint                     = module.common_infrastructure.storage_bootdiag_endpoint
  terraform_template_version                    = var.terraform_template_version
  use_custom_dns_a_registration                 = try(data.terraform_remote_state.landscape.outputs.use_custom_dns_a_registration, false)
  use_loadbalancers_for_standalone_deployments  = var.use_loadbalancers_for_standalone_deployments
  use_msi_for_clusters                          = var.use_msi_for_clusters
  use_scalesets_for_deployment                  = var.use_scalesets_for_deployment
  use_secondary_ips                             = var.use_secondary_ips
}

#########################################################################################
#                                                                                       #
#  AnyDB Infrastructure                                                                 #
#                                                                                       #
#########################################################################################

module "anydb_node" {
  source                                        = "../../terraform-units/modules/sap_system/anydb_node"
  providers = {
    azurerm.deployer                            = azurerm
    azurerm.main                                = azurerm.system
    azurerm.dnsmanagement                       = azurerm.dnsmanagement
  }
  depends_on                                    = [module.common_infrastructure]

  admin_subnet                                  = try(module.common_infrastructure.admin_subnet, null)
  anchor_vm                                     = module.common_infrastructure.anchor_vm // Workaround to create dependency from anchor to db to app
  cloudinit_growpart_config                     = null # This needs more consideration module.common_infrastructure.cloudinit_growpart_config
  custom_disk_sizes_filename                    = try(coalesce(var.custom_disk_sizes_filename, var.db_disk_sizes_filename), "")
  database                                      = local.database
  database_vm_db_nic_ips                        = var.database_vm_db_nic_ips
  database_vm_db_nic_secondary_ips              = var.database_vm_db_nic_secondary_ips
  database_vm_admin_nic_ips                     = var.database_vm_admin_nic_ips
  database_server_count                         = upper(try(local.database.platform, "HANA")) == "HANA" ? (
                                                  0) : (
                                                    local.database.high_availability ? 2 * var.database_server_count : var.database_server_count
                                                  )
  db_asg_id                                     = module.common_infrastructure.db_asg_id
  db_subnet                                     = module.common_infrastructure.db_subnet
  deploy_application_security_groups            = var.deploy_application_security_groups
  deployment                                    = var.deployment
  fencing_role_name                             = var.fencing_role_name
  infrastructure                                = local.infrastructure
  landscape_tfstate                             = data.terraform_remote_state.landscape.outputs
  license_type                                  = var.license_type
  management_dns_resourcegroup_name             = coalesce(data.terraform_remote_state.landscape.outputs.management_dns_resourcegroup_name, local.saplib_resource_group_name)
  management_dns_subscription_id                = try(data.terraform_remote_state.landscape.outputs.management_dns_subscription_id, null)
  naming                                        = length(var.name_override_file) > 0 ? local.custom_names : module.sap_namegenerator.naming
  options                                       = local.options
  order_deployment                              = local.enable_db_deployment ? (
                                                    local.db_zonal_deployment && local.application_tier.enable_deployment ? (
                                                      try(module.app_tier.scs_vm_ids[0], null)
                                                    ) : (null)
                                                  ) : (null)
  ppg                                           = module.common_infrastructure.ppg
  register_virtual_network_to_dns               = try(data.terraform_remote_state.landscape.outputs.register_virtual_network_to_dns, true)
  resource_group                                = module.common_infrastructure.resource_group
  sap_sid                                       = local.sap_sid
  scale_set_id                                  = try(module.common_infrastructure.scale_set_id, null)
  sdu_public_key                                = module.common_infrastructure.sdu_public_key
  sid_keyvault_user_id                          = module.common_infrastructure.sid_keyvault_user_id
  sid_password                                  = module.common_infrastructure.sid_password
  sid_username                                  = module.common_infrastructure.sid_username
  storage_bootdiag_endpoint                     = module.common_infrastructure.storage_bootdiag_endpoint
  terraform_template_version                    = var.terraform_template_version
  use_custom_dns_a_registration                 = data.terraform_remote_state.landscape.outputs.use_custom_dns_a_registration
  use_loadbalancers_for_standalone_deployments  = var.use_loadbalancers_for_standalone_deployments
  use_msi_for_clusters                          = var.use_msi_for_clusters
  use_observer                                  = var.use_observer
  use_scalesets_for_deployment                  = var.use_scalesets_for_deployment
  use_secondary_ips                             = var.use_secondary_ips

}

#########################################################################################
#                                                                                       #
#  Output files                                                                         #
#                                                                                       #
#########################################################################################

module "output_files" {
  source                                        = "../../terraform-units/modules/sap_system/output_files"
  depends_on                                    = [module.anydb_node, module.common_infrastructure, module.app_tier, module.hdb_node]
  providers = {
    azurerm.deployer                            = azurerm
    azurerm.main                                = azurerm.system
    azurerm.dnsmanagement                       = azurerm.dnsmanagement
  }

  database                                      = local.database
  infrastructure                                = local.infrastructure
  authentication                                = local.authentication
  authentication_type                           = try(local.application_tier.authentication.type, "key")
  tfstate_resource_id                           = var.tfstate_resource_id
  landscape_tfstate                             = data.terraform_remote_state.landscape.outputs
  naming                                        = length(var.name_override_file) > 0 ? (
                                                    local.custom_names) : (
                                                    module.sap_namegenerator.naming
                                                  )
  save_naming_information                       = var.save_naming_information
  configuration_settings                        = var.configuration_settings
  random_id                                     = module.common_infrastructure.random_id

  #########################################################################################
  #  Database tier                                                                        #
  #########################################################################################
  nics_anydb_admin                              = module.anydb_node.nics_anydb_admin
  nics_dbnodes_admin                            = module.hdb_node.nics_dbnodes_admin
  db_server_ips                                 = upper(try(local.database.platform, "HANA")) == "HANA" ? (module.hdb_node.db_server_ips
                                                  ) : (module.anydb_node.db_server_ips
                                                  )
  db_server_secondary_ips                       = upper(try(local.database.platform, "HANA")) == "HANA" ? (module.hdb_node.db_server_secondary_ips
                                                  ) : (module.anydb_node.db_server_secondary_ips
                                                  )
  disks                                         = distinct(compact(concat(module.hdb_node.dbtier_disks,
                                                    module.anydb_node.dbtier_disks,
                                                    module.app_tier.apptier_disks
                                                  )))
  anydb_loadbalancers                           = module.anydb_node.anydb_loadbalancers
  loadbalancers                                 = module.hdb_node.loadbalancers
  db_ha                                         = upper(try(local.database.platform, "HANA")) == "HANA" ? (
                                                    module.hdb_node.db_ha) : (
                                                    module.anydb_node.db_ha
                                                  )
  db_lb_ip                                      = upper(try(local.database.platform, "HANA")) == "HANA" ? (
                                                    module.hdb_node.db_lb_ip[0]) : (
                                                    module.anydb_node.db_lb_ip[0]
                                                  )
  database_admin_ips                            = upper(try(local.database.platform, "HANA")) == "HANA" ? (
                                                    module.hdb_node.db_admin_ip) : (
                                                    module.anydb_node.anydb_admin_ip
                                                  ) #TODO Change to use Admin IP
  db_auth_type                                  = try(local.database.authentication.type, "key")
  db_clst_lb_ip                                 = module.anydb_node.db_clst_lb_ip
  db_subnet_netmask                             = module.common_infrastructure.db_subnet_netmask

  #########################################################################################
  #  SAP Application information                                                          #
  #########################################################################################
  bom_name                                      = var.bom_name
  db_sid                                        = local.db_sid
  observer_ips                                  = module.anydb_node.observer_ips
  observer_vms                                  = module.anydb_node.observer_vms
  platform                                      = upper(try(local.database.platform, "HANA"))
  sap_sid                                       = local.sap_sid
  web_sid                                       = var.web_sid
  web_instance_number                           = var.web_instance_number

  #########################################################################################
  #  Application tier                                                                     #
  #########################################################################################
  ansible_user                                  = module.common_infrastructure.sid_username
  app_subnet_netmask                            = module.app_tier.app_subnet_netmask
  app_tier_os_types                             = module.app_tier.app_tier_os_types
  application_server_ips                        = module.app_tier.application_server_ips
  application_server_secondary_ips              = module.app_tier.application_server_secondary_ips
  ers_instance_number                           = var.ers_instance_number
  ers_lb_ip                                     = module.app_tier.ers_lb_ip
  nics_app_admin                                = module.app_tier.nics_app_admin
  nics_scs_admin                                = module.app_tier.nics_scs_admin
  nics_web_admin                                = module.app_tier.nics_web_admin
  pas_instance_number                           = var.pas_instance_number
  sid_keyvault_user_id                          = module.common_infrastructure.sid_keyvault_user_id
  scs_clst_lb_ip                                = module.app_tier.cluster_lb_ip
  scs_ha                                        = module.app_tier.scs_ha
  scs_instance_number                           = var.scs_instance_number
  scs_lb_ip                                     = module.app_tier.scs_lb_ip
  scs_server_ips                                = module.app_tier.scs_server_ips
  scs_server_secondary_ips                      = module.app_tier.scs_server_secondary_ips
  use_local_credentials                         = module.common_infrastructure.use_local_credentials
  use_msi_for_clusters                          = var.use_msi_for_clusters
  use_secondary_ips                             = var.use_secondary_ips
  webdispatcher_server_ips                      = module.app_tier.webdispatcher_server_ips
  webdispatcher_server_secondary_ips            = module.app_tier.webdispatcher_server_secondary_ips

  #########################################################################################
  #  Mounting information                                                                 #
  #########################################################################################
  NFS_provider                                  = var.NFS_provider
  sap_mnt                                       = module.common_infrastructure.sapmnt_path
  sap_transport                                 = try(data.terraform_remote_state.landscape.outputs.saptransport_path, "")
  install_path                                  = try(data.terraform_remote_state.landscape.outputs.install_path, "")
  shared_home                                   = var.shared_home
  hana_data                                     = [module.hdb_node.hana_data_primary, module.hdb_node.hana_data_secondary]
  hana_log                                      = [module.hdb_node.hana_log_primary, module.hdb_node.hana_log_secondary]
  hana_shared                                   = [module.hdb_node.hana_shared_primary, module.hdb_node.hana_shared_secondary]
  usr_sap                                       = module.common_infrastructure.usrsap_path

  #########################################################################################
  #  DNS information                                                                      #
  #########################################################################################
  dns                                           = try(data.terraform_remote_state.landscape.outputs.dns_label, "")
  use_custom_dns_a_registration                 = try(data.terraform_remote_state.landscape.outputs.use_custom_dns_a_registration, false)
  management_dns_subscription_id                = try(data.terraform_remote_state.landscape.outputs.management_dns_subscription_id, null)
  management_dns_resourcegroup_name             = try(data.terraform_remote_state.landscape.outputs.management_dns_resourcegroup_name, local.saplib_resource_group_name)


  #########################################################################################
  #  Server counts                                                                        #
  #########################################################################################
  app_server_count                              = try(local.application_tier.application_server_count, 0)
  db_server_count                               = var.database_server_count
  scs_server_count                              = local.application_tier.scs_high_availability ? (
                                                  2 * local.application_tier.scs_server_count) : (
                                                  local.application_tier.scs_server_count
                                                  )
  web_server_count                              = try(local.application_tier.webdispatcher_count, 0)
  use_simple_mount                              = local.validated_use_simple_mount

}
