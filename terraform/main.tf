# Resource Group
module resource_group {
    source = "./modules/resource_group"
    name     = var.resource_group_name
    location = var.location
}


# Log Analytics workspace for AKS monitoring
resource "azurerm_log_analytics_workspace" "law" {
  name                = "aks-law"
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}


# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_name
  location            = module.resource_group.location
  resource_group_name = module.resource_group.name
  dns_prefix          = "${var.aks_name}-dns"

  default_node_pool {
    name       = "system"
    # node_count = var.node_count
    # vm_size    = var.node_vm_size
    node_count = var.gpu_node_count
    vm_size    = var.gpu_node_vm_size

    # vm_size, os_type, and other options can be customized
    type                = "VirtualMachineScaleSets"
    os_disk_size_gb     = 256
    enable_auto_scaling = false
    # For production, consider using node labels, taints, and autoscaling
  }

  # An AD identity which can be used by AKS to access other Azure resources.
  identity {
    type = "SystemAssigned"
  }

  # Set up a OMS Agent which sents container monitoring data to the Log Analytics Workspace.
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  # Enable RBAC authorization in a cluster. We will be able to create Roles and Roles Bindings in a cluster.
  role_based_access_control_enabled = true

  network_profile {
    network_plugin = "azure"          # azure CNI; use "kubenet" if desired
    load_balancer_sku = "standard"
    outbound_type = "loadBalancer"
  }

  kubernetes_version = var.kubernetes_version

  tags = {
    environment = "dev"
    created_by  = "terraform"
  }
}


/*
# Add a GPU node pool to the AKS cluster
resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.gpu_node_vm_size
  node_count            = var.gpu_node_count
  mode                  = "User"

  node_labels = {
    workload = "gpu"
  }

  # Create a taint on those nodes to allow running only pods which performs GPU computations (that is only a DeepSpeed cluster)
  node_taints = [
    "gpu=true:NoSchedule"
  ]
}
*/


# Create an ACR where we will be storing a Docker image used for deploying the MLflow Tracking Server and running MLflow project.
module "acr" {
  source = "./modules/acr"
  acr_name                = var.acr_name
  resource_group_name     = var.resource_group_name
  resource_group_location = var.location
}


# Service Principal for authentication. It is going to have assigned the following roles and scopes:
# - Role 'acrpush' with scope for ACR - Enable pulling images from ACR when deploying resources on Kubernetes
# - Role 'Contributor' with scope for ACR - Enable pushing images to ACR using Azure CLI
# - Role 'Azure Kubernetes Service Cluster User Role' with scope for AKS - Enable getting credentials to AKS (creating .kube/config file)
#   using the 'az aks get-credentials' command.

module "service_principal" {
  source = "./modules/service_principal"
  service_principal_display_name = "rag_workflow"
  role_assignments = [
    {role = "acrpush", scope = module.acr.id}
    ,{role = "Contributor", scope = module.acr.id}
    ,{role = "Azure Kubernetes Service Cluster User Role", scope = azurerm_kubernetes_cluster.aks.id}
  ]
}


# Storage Account and File share for files needed to run all the apps. It will be mounted to AKS pods. Thanks to this we will not need to
# rebuild images everytime we make a change in code.
module "scripts_sa" {
  source = "./modules/storage_account"
  resource_group_name = module.resource_group.name
  resource_group_location = module.resource_group.location
  storage_account_name = "ragcriptsbulka"
}

module "scripts_sa_file_share" {
  source = "./modules/sa_file_share"
  name = "rag-scripts"
  storage_account_name = module.scripts_sa.name
}


# Create files content which will be saved on the localhost:
# - Dockerfile for creating an image for interacting with AKS
# - values.yaml files for Helm charts
locals {
  # Names of images we will be pushing to ACR and using in Helm charts
  mcp_server_image_name         = "mcp-server"
  prepare_milvus_db_image_name  = "prepare-milvus-db"
  ray_serve_app_image_name      = "ray-serve-app"
  semantic_search_image_name    = "semantic-search"

  # Dockerfile for interacting with AKS
  dockerfile_interacting_aks = templatefile("template_files/docker/template.interacting.aks.Dockerfile", {
    rg_name         = module.resource_group.name
    aks_name        = azurerm_kubernetes_cluster.aks.name

    acr_sp_id       = module.service_principal.client_id
    acr_sp_password = module.service_principal.client_password
    acr_name        = module.acr.name
    
    tenant_id       = data.azurerm_client_config.current.tenant_id
    subscription_id = data.azurerm_client_config.current.subscription_id

    mcp_server_image_name         = local.mcp_server_image_name
    prepare_milvus_db_image_name  = local.prepare_milvus_db_image_name
    ray_serve_app_image_name      = local.ray_serve_app_image_name
    semantic_search_image_name    = local.semantic_search_image_name
  })

  # Dockerfile for running MCP Server
  dockerfile_mcp = templatefile("template_files/docker/template.mcp.Dockerfile", {
    acr_url = module.acr.url
    semantic_search_image_name = local.semantic_search_image_name
  })

  # Dockerfile for running the script for preparing sample data in Milvus db
  dockerfile_prepare_milvus = templatefile("template_files/docker/template.prepare.milvus.Dockerfile", {
    acr_url = module.acr.url
    semantic_search_image_name = local.semantic_search_image_name
  })

  # values.yaml file for the common Helm chart
  values_common = templatefile("template_files/helm_charts/values-common.yaml", {
    acr_url               = module.acr.url
    acr_sp_id             = module.service_principal.client_id
    acr_sp_password       = module.service_principal.client_password

    mlflow_storage_account_name       = module.scripts_sa.name
    mlflow_storage_account_access_key = module.scripts_sa.primary_access_key
    sa_file_share_name                = module.scripts_sa_file_share.name
  })

  # values.yaml file for the mcp_server Helm chart
  values_mcp = templatefile("template_files/helm_charts/values-mcp.yaml", {
    acr_url                     = module.acr.url
    mcp_server_image_name       = local.mcp_server_image_name
    mlflow_storage_account_name = module.scripts_sa.name
  })

  # values.yaml file for the prepare_milvus_db Helm chart
  values_prepare_milvus = templatefile("template_files/helm_charts/values-prepare-milvus.yaml", {
    acr_url                       = module.acr.url
    prepare_milvus_db_image_name  = local.prepare_milvus_db_image_name
    mlflow_storage_account_name   = module.scripts_sa.name
  })

  # values.yaml file for the mcp_server Helm chart
  values_ray_service = templatefile("template_files/helm_charts/values-ray-service.yaml", {
    acr_url                     = module.acr.url
    ray_serve_app_image_name    = local.ray_serve_app_image_name
    mlflow_storage_account_name = module.scripts_sa.name
  })
}


# Save files on the localhost
resource "local_file" "local_files" {
  # each.key - content to save in a file
  # each.value - path where to save a file
  for_each = {
    0 = {content = local.dockerfile_interacting_aks, path = "../interacting.aks.Dockerfile"}
    1 = {content = local.dockerfile_mcp, path = "../apps/mcp_server/Dockerfile"}
    2 = {content = local.dockerfile_prepare_milvus, path = "../apps/prepare_milvus_db/Dockerfile"}
    3 = {content = local.values_common, path = "../helm_charts/common/values.yaml"}
    4 = {content = local.values_mcp, path = "../helm_charts/mcp_server/values.yaml"}
    5 = {content = local.values_prepare_milvus, path = "../helm_charts/prepare_milvus_db/values.yaml"}
    6 = {content = local.values_ray_service, path = "../helm_charts/ray_service/values.yaml"}
  }

  content = each.value.content
  filename = each.value.path
}


# Get info about the current client to get subscription ID
data "azurerm_client_config" "current" {}