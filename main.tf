/**
 * # terraform-fortios-advpn-sdwan-hub-loopback
 * 
 * Uses forked version of fortios provider
 *
 * Requires FortiOS >= 7.2.7
 *
 * Uses sub-table resources in BGP and SDWAN parent tables. Do not mix and match here.
 * 
 */

terraform {
  required_providers {
    fortios = {
      source  = "poroping/fortios"
      version = ">= 3.2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
  }
}

locals {
  interfaces = { for i in var.interfaces : "${i.interface_name}-${i.interface_id}" => {
    interface_name   = i.interface_name
    interface_id     = i.interface_id
    interface_uid    = "${i.interface_name}-${i.interface_id}"
    local_gw         = i.local_gw
    nat_ip           = i.nat_ip
    advpn_name       = join("-", [tostring(var.hub_id), tostring(i.interface_id)])
    advpn_longname   = "HUB:${tostring(var.hub_id)}-INTERFACE:${tostring(i.interface_id)}"
    advpn_id         = join("", [tostring(var.hub_id), tostring(i.interface_id)])
    hub_id           = var.hub_id
    vpn_name_prefix  = var.vpn_name_prefix
    sla_latency      = i.sla_latency
    sla_priority_in  = i.sla_priority_in != null ? i.sla_priority_in : 10 + i.interface_id
    sla_priority_out = i.sla_priority_out != null ? i.sla_priority_out : 20 + i.interface_id
  } }
}

resource "random_id" "psk" {
  count = var.ipsec.psk == null ? 1 : 0

  byte_length = 32
}

resource "fortios_vpnipsec_phase1interface" "phase1" {
  for_each = { for i in local.interfaces : i.interface_uid => i }

  vdomparam = var.vdom

  name                  = "${each.value.vpn_name_prefix}${each.value.advpn_name}"
  local_gw              = each.value.local_gw
  type                  = "dynamic"
  interface             = each.value.interface_name
  ike_version           = 2
  exchange_interface_ip = "enable"
  exchange_ip_addr4     = split("/", fortios_system_interface.loopback.ip)[0]
  peertype              = "any"
  nattraversal          = each.value.nat_ip == null ? "disable" : "forced"
  network_overlay       = "enable"
  network_id            = tonumber(each.value.advpn_id)
  net_device            = "disable"
  proposal              = var.ipsec.proposal
  add_route             = "disable"
  dpd                   = "on-idle"
  auto_discovery_sender = "enable"
  psksecret             = var.ipsec.psk == null ? random_id.psk[0].b64_url : var.ipsec.psk

  lifecycle {
    ignore_changes = [exchange_interface_ip] # seems to be missing in some versions?
  }
}

resource "fortios_vpnipsec_phase2interface" "phase2" {
  for_each = { for i in local.interfaces : i.interface_uid => i }

  vdomparam = var.vdom

  name       = fortios_vpnipsec_phase1interface.phase1[each.key].name
  phase1name = fortios_vpnipsec_phase1interface.phase1[each.key].name
  proposal   = fortios_vpnipsec_phase1interface.phase1[each.key].proposal
  pfs        = "enable"
  dhgrp      = var.ipsec.dhgrp
}

resource "fortios_routerbgp_neighbor_group" "group" {
  vdomparam = var.vdom

  name                        = "${var.vpn_name_prefix}${var.hub_id}"
  update_source               = fortios_system_interface.loopback.name
  remote_as                   = var.bgp_as
  route_reflector_client      = "enable"
  link_down_failover          = "enable"
  additional_path             = "both"
  adv_additional_path         = length(local.interfaces)*2
  capability_graceful_restart = "enable"
  capability_route_refresh    = "enable"
  soft_reconfiguration        = "enable"
  keep_alive_timer            = 7
  holdtime_timer              = 21
  advertisement_interval      = 5

  lifecycle {
    create_before_destroy = true
  }
}

resource "fortios_routerbgp_neighbor_range" "range" {
  vdomparam = var.vdom

  neighbor_group = fortios_routerbgp_neighbor_group.group.name
  prefix         = var.loopback_subnet
}

resource "fortios_routerbgp_network" "networks" {
  for_each = var.networks

  vdomparam = var.vdom

  prefix = each.key
}

# advertise loopback subnet
resource "fortios_routerbgp_network" "loopback_subnet" {
  vdomparam = var.vdom

  prefix = var.loopback_subnet
}

resource "fortios_system_interface" "loopback" {
  allow_append = true

  type        = "loopback"
  name        = "${var.vpn_name_prefix}LOOP"
  ip          = var.loopback_ip
  allowaccess = "ping"
  vdom        = var.vdom

  lifecycle {
    create_before_destroy = true
    ignore_changes = [ allowaccess ]
  }
}

# advertise sla/bgp loopback
resource "fortios_routerbgp_network" "loopback" {
  vdomparam = var.vdom

  prefix = fortios_system_interface.loopback.ip
}

resource "fortios_system_sdwan_zone" "zone" {
  vdomparam = var.vdom

  name = "sdwan-hub${tostring(var.hub_id)}"
}

resource "fortios_system_sdwan_members" "hub" {
  for_each = { for i in local.interfaces : i.interface_uid => i }

  vdomparam = var.vdom

  seq_num   = tonumber(each.value.advpn_id)
  interface = fortios_vpnipsec_phase1interface.phase1[each.key].name
  zone      = fortios_system_sdwan_zone.zone.name
}

# resource "fortios_system_sdwan_service" "hub" {
#   for_each = { for i in local.interfaces : i.interface_uid => i }

#   vdomparam = var.vdom

#   name = "${each.value.advpn_longname}-all"

#   input_device {
#     name = fortios_vpnipsec_phase1interface.phase1[each.key].name
#   }

#   dst {
#     name = "all"
#   }

#   src {
#     name = "all"
#   }

#   priority_members {
#     seq_num = fortios_system_sdwan_members.hub[each.key].seq_num
#   }

#   dynamic "priority_members" {
#     for_each = setsubtract([for int in local.interfaces : int.advpn_id], [fortios_system_sdwan_members.hub[each.key].seq_num])

#     content {
#       seq_num = priority_members.value
#     }
#   }

# }

resource "fortios_firewall_policy" "sla_loop" {
  vdomparam = var.vdom

  action   = "accept"
  name     = "ADVPN to SLA LOOPBACK"
  schedule = "always"

  dstaddr {
    name = "all"
  }

  dstintf {
    name = fortios_system_interface.loopback.name
  }

  service {
    name = "PING"
  }

  srcaddr {
    name = "all"
  }

  srcintf {
    name = fortios_system_sdwan_zone.zone.name
  }
}

resource "fortios_firewall_policy" "bgp" {
  vdomparam = var.vdom

  action   = "accept"
  name     = "ADVPN to BGP LOOPBACK"
  schedule = "always"

  dstaddr {
    name = "all"
  }

  dstintf {
    name = fortios_system_interface.loopback.name
  }

  service {
    name = "BGP"
  }

  srcaddr {
    name = "all"
  }

  srcintf {
    name = fortios_system_sdwan_zone.zone.name
  }
}

resource "fortios_system_sdwan_health_check" "health" {
  for_each = { for i in local.interfaces : i.interface_uid => i }

  vdomparam = var.vdom

  name                = replace("${each.value.advpn_longname}-REMOTE", "-", "_")
  detect_mode         = "remote"
  sla_id_redistribute = 1
  sla_fail_log_period = 30
  sla_pass_log_period = 60

  members {
    seq_num = tonumber(each.value.advpn_id)
  }

  sla {
    id                = 1
    link_cost_factor  = "latency"
    latency_threshold = each.value.sla_latency
    priority_in_sla   = each.value.sla_priority_in
    priority_out_sla  = each.value.sla_priority_out
  }



}

data "fortios_router_bgp" "bgp" {
}

data "fortios_system_interface" "parent_interfaces" {
  for_each = { for i in local.interfaces : i.interface_uid => i }

  name = each.value.interface_name
}

locals {
  hub_links = [for i in local.interfaces : {
    advpn_id   = fortios_vpnipsec_phase1interface.phase1[i.interface_uid].network_id
    advpn_name = fortios_vpnipsec_phase1interface.phase1[i.interface_uid].name
    remote_gw  = i.nat_ip != null ? i.nat_ip : i.local_gw != null ? i.local_gw : try(split(" ", data.fortios_system_interface.parent_interfaces[i.interface_uid].ip)[0], null)
  }]
  hub_info = {
    bgp_as       = data.fortios_router_bgp.bgp.as
    hub_id       = var.hub_id
    hub_loopback = fortios_system_interface.loopback.ip
    links        = local.hub_links
  }

}

output "hub" {
  description = "Hub information."
  value       = local.hub_info
}

output "psk" {
  description = "Outputs PSK if auto generated. Null if provided."
  value       = var.ipsec.psk == null ? random_id.psk[0].b64_url : null
}
