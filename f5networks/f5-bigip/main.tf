
locals {
  _f5_urls = {
    as3  = "https://github.com/F5Networks/f5-appsvcs-extension/releases/download/v3.46.0/f5-appsvcs-3.46.0-5.noarch.rpm"
    cfe  = "https://github.com/F5Networks/f5-cloud-failover-extension/releases/download/v1.15.0/f5-cloud-failover-1.15.0-0.noarch.rpm"
    do   = "https://github.com/F5Networks/f5-declarative-onboarding/releases/download/v1.41.0/f5-declarative-onboarding-1.41.0-8.noarch.rpm"
    fast = "https://github.com/F5Networks/f5-appsvcs-templates/releases/download/v1.25.0/f5-appsvcs-templates-1.25.0-1.noarch.rpm"
    init = "https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v1.6.2/dist/f5-bigip-runtime-init-1.6.2-1.gz.run"
    ts   = "https://github.com/F5Networks/f5-telemetry-streaming/releases/download/v1.33.0/f5-telemetry-1.33.0-1.noarch.rpm"
  }
  _f5_urls_split = {
    for k, v in local._f5_urls
    : k => split("/", v)
  }
  _f5_vers = {
    as3  = split("-", local._f5_urls_split.as3[length(local._f5_urls_split.as3) - 1])[2]
    cfe  = split("-", local._f5_urls_split.cfe[length(local._f5_urls_split.cfe) - 1])[3]
    do   = split("-", local._f5_urls_split.do[length(local._f5_urls_split.do) - 1])[3]
    fast = format("v%s", split("-", local._f5_urls_split.fast[length(local._f5_urls_split.fast) - 1])[3])
    ts   = format("v%s", split("-", local._f5_urls_split.ts[length(local._f5_urls_split.ts) - 1])[2])
  }
  f5_config = merge(
    { NIC_COUNT = true },
    { for k, v in local._f5_urls : upper("${k}_url") => v },
    { for k, v in local._f5_vers : upper("${k}_ver") => v },
    # hostnames and management IPs addresses for the cluster configuration
    { for k, v in var.dedicated_instances_configs : "hostname_${k}" => "${var.prefix}-${k}.${var.shared_instances_configs.dns_suffix}" },
    {
      for k, v in var.dedicated_instances_configs :
      "mgmt_ip_${k}" =>
      v.network_addresses.management == null ?
      resource.google_compute_address.management[k].address :
      v.network_addresses.management_address
    }
  )
}

resource "google_compute_instance" "f5-bigip-vms" {
  for_each         = var.dedicated_instances_configs
  name             = "${var.prefix}-${each.key}"
  zone             = "${var.region}-${each.key}"
  project          = var.project_id
  min_cpu_platform = var.shared_instances_configs.min_cpu_platform
  machine_type     = var.shared_instances_configs.machine_type

  boot_disk {
    auto_delete = true
    initialize_params {
      image = var.shared_instances_configs.boot_disk.image
      size  = var.shared_instances_configs.boot_disk.size
      type  = var.shared_instances_configs.boot_disk.type
    }
  }

  service_account {
    email  = var.shared_instances_configs.service_account
    scopes = ["cloud-platform"]
  }

  can_ip_forward = true

  # External Nic
  network_interface {
    subnetwork = var.vpc_config.external.subnetwork
    network_ip = (each.value.network_addresses.external == null ?
      resource.google_compute_address.external[each.key].address :
      each.value.network_addresses.external
    )
  }

  # Management Nic
  network_interface {
    subnetwork = var.vpc_config.management.subnetwork
    network_ip = (each.value.network_addresses.management == null ?
      resource.google_compute_address.management[each.key].address :
      each.value.network_addresses.management
    )
  }

  # Internal NIC
  network_interface {
    subnetwork = var.vpc_config.internal.subnetwork
    network_ip = (each.value.network_addresses.internal == null ?
      resource.google_compute_address.internal[each.key].address :
      each.value.network_addresses.internal
    )
  }
  metadata_startup_script = replace(templatefile("${path.module}/data/f5_onboard.tmpl",
    merge(local.f5_config, {
      onboard_log                       = "/var/log/startup-script.log",
      libs_dir                          = "/config/cloud/gcp/node_modules",
      f5_username                       = var.shared_instances_configs.username
      f5_password                       = var.shared_instances_configs.password
      gcp_secret_manager_authentication = false
      gcp_secret_name                   = ""
      ssh_keypair                       = file(var.shared_instances_configs.ssh_public_key)
      license_key                       = each.value.license_key
      dns_suffix                        = var.shared_instances_configs.dns_suffix
      dns_server                        = var.shared_instances_configs.dns_server
      ntp_server                        = var.shared_instances_configs.ntp_server
      timezone                          = var.shared_instances_configs.timezone
      mgmt_ip = (each.value.network_addresses.management == null ?
        resource.google_compute_address.management[each.key].address :
        each.value.network_addresses.management_address
      )
      ilb_vip = var.shared_instances_configs.ilb_vip
      private_vip = (each.value.network_addresses.external == null ?
        resource.google_compute_address.external[each.key].address :
        each.value.network_addresses.external_address
      )
      internal_subnets = var.shared_instances_configs.route_to_configure
      # TODO:
      # change the variable to a list and modify the f5_onbaord.tmpl script accordingly to configure all routes in the list
      # [
        # {"name" : "web_servers" , "network" : "192.168.10.0/24" }
        # {"name" : "db_servers"  , "network" : "192.168.20.0/24" }
      # ]
      # internal_routes = var.shared_instances_configs.internal_routes
    })), "/\r/", "")

  labels = var.shared_instances_configs.labels
  tags   = var.shared_instances_configs.tags

}