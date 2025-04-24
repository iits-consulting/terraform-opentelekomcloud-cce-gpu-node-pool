data "opentelekomcloud_cce_cluster_v3" "cluster" {
  id = var.cce_cluster_id
}

data "opentelekomcloud_cce_addon_templates_v3" "gpu" {
  cluster_version = data.opentelekomcloud_cce_cluster_v3.cluster.cluster_version
  cluster_type    = data.opentelekomcloud_cce_cluster_v3.cluster.cluster_type
  addon_name      = "gpu-beta"
}

resource "errorcheck_is_valid" "gpu_beta_version_availability" {
  name = "Check if version selected in var.gpu_beta_version is available on OTC."
  test = {
    assert        = var.gpu_beta_version == "latest" || contains(data.opentelekomcloud_cce_addon_templates_v3.gpu.addons[*].addon_version, var.gpu_beta_version)
    error_message = "Please check your gpu_beta_version. For CCE ${data.opentelekomcloud_cce_cluster_v3.cluster.cluster_version} the valid gpu-beta versions are: [${join(", ", data.opentelekomcloud_cce_addon_templates_v3.gpu.addons[*].addon_version)}]"
  }
}

# OTC API returns the addons in the order of release date, unfortunately this is not always guaranteed to be correctly ordered in terms of semver
# Here is the counter example for the interested reader:
# data "opentelekomcloud_cce_addon_templates_v3" "test" {
#   cluster_version = "v1.27"
#   addon_name      = "autoscaler"
# }
locals {
  gpu_beta_split_versions = [for version in data.opentelekomcloud_cce_addon_templates_v3.gpu.addons[*].addon_version : split(".", version)]
  gpu_beta_major          = max(local.gpu_beta_split_versions[*][0]...)
  gpu_beta_minor          = max([for version in local.gpu_beta_split_versions : version[1] if tonumber(version[0]) == local.gpu_beta_major]...)
  gpu_beta_patch          = max([for version in local.gpu_beta_split_versions : version[2] if tonumber(version[0]) == local.gpu_beta_major && tonumber(version[1]) == local.gpu_beta_minor]...)
  gpu_beta_version        = var.gpu_beta_version == "latest" ? "${local.gpu_beta_major}.${local.gpu_beta_minor}.${local.gpu_beta_patch}" : var.gpu_beta_version
  gpu_beta_template       = [for addon in data.opentelekomcloud_cce_addon_templates_v3.gpu.addons : addon if addon.addon_version == local.gpu_beta_version][0]
}

resource "opentelekomcloud_cce_addon_v3" "gpu" {
  count            = var.gpu_beta_enabled ? 1 : 0
  template_name    = data.opentelekomcloud_cce_addon_templates_v3.gpu.addon_name
  template_version = local.gpu_beta_template.addon_version
  cluster_id       = var.cce_cluster_id

  values {
    basic = {
      "swr_addr" = local.gpu_beta_template.swr_addr
      "swr_user" = local.gpu_beta_template.swr_user
    }
    custom = {
      is_driver_from_nvidia      = true
      nvidia_driver_download_url = var.gpu_driver_url
    }
  }
}
