<!-- BEGIN_TF_DOCS -->
# terraform-fortios-advpn-sdwan-hub

Uses forked version of fortios provider

Requires FortiOS >= 7.2.9

Uses sub-table resources in BGP and SDWAN parent tables. Do not mix and match here.

### Example Usage:
```hcl
terraform {
  required_version = ">= 1.0.1"
  backend "local" {}
  required_providers {
    fortios = {
      source  = "poroping/fortios"
      version = ">= 3.1.4"
    }
  }
}

provider "fortios" {
  alias    = "hub1"
  hostname = "192.168.1.99"
  token    = "supertokens"
  vdom     = "root"
  insecure = "true"
}

## Hub Info

data "fortios_system_interface" "hub1_1" {
  provider = fortios.hub1

  name = "port1"
}

data "fortios_system_interface" "hub1_2" {
  provider = fortios.hub1

  name = "port1"
}

locals {
  hub1_interfaces = [
    {
      interface_name = data.fortios_system_interface.hub1_1.name
      interface_id   = 1
      local_gw       = null
      cost           = null
      nat_ip         = null
      tunnel_subnet  = "169.254.101.0/24"
    },
    {
      interface_name = data.fortios_system_interface.hub1_2.name
      interface_id   = 2
      local_gw       = null
      cost           = null
      nat_ip         = null
      tunnel_subnet  = "169.254.102.0/24"
    }
  ]
  hub1_bgp_as = 64420
}

# BGP pre-reqs

resource "fortios_router_bgp" "hub1" {
  provider = fortios.hub1

  vdomparam = "root"

  as                     = local.hub1_bgp_as
  router_id              = "1.1.1.1"
  ibgp_multipath         = "enable"
  additional_path        = "enable"
  additional_path_select = 4

  # ignore subtables
  lifecycle {
    ignore_changes = [
      aggregate_address,
      aggregate_address6,
      network,
      network6,
      neighbor,
      neighbor_group,
      neighbor_range,
      neighbor_range6,
      admin_distance
    ]
  }
}

module "advpnhub1" {
  providers = {
    fortios = fortios.hub1
  }
  source  = "poroping/advpn-sdwan-hub/fortios"
  version = "~> 0.0.15"

  bgp_as          = local.hub1_bgp_as
  interfaces      = local.hub1_interfaces
  hub_id          = 1
  vdom            = "root"
  sla_loopback_ip = "169.254.255.1/32"
}

# Make sure hub networks are advertised towards spokes example:

resource "fortios_routerbgp_network" "hub1_nets" {
  provider = fortios.hub1
  for_each = toset(["192.168.1.0/24"])

  vdomparam = "root"

  prefix = each.key

  depends_on = [
    fortios_router_bgp.hub1
  ]
}

# Basic any-any policies to bring up tunnel

resource "fortios_firewall_policy" "in1" {
  provider = fortios.hub1

  action   = "accept"
  schedule = "always"

  dstaddr {
    name = "all"
  }

  dstintf {
    name = "port2"
  }

  service {
    name = "ALL"
  }

  srcaddr {
    name = "all"
  }

  srcintf {
    name = "sdwan-hub1"
  }

  depends_on = [
    module.advpnhub1
  ]
}

resource "fortios_firewall_policy" "out1" {
  provider = fortios.hub1

  action   = "accept"
  schedule = "always"

  dstaddr {
    name = "all"
  }

  dstintf {
    name = "sdwan-hub1"
  }

  service {
    name = "ALL"
  }

  srcaddr {
    name = "all"
  }

  srcintf {
    name = "port2"
  }

  depends_on = [
    module.advpnhub1
  ]
}
```

## Providers

| Name | Version |
|------|---------|
| <a name="provider_fortios"></a> [fortios](#provider\_fortios) | >= 3.1.4 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.1.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_interfaces"></a> [interfaces](#input\_interfaces) | Set of interface objects.<br>interface\_id is significant to hub.<br>interface\_name is name of parent interface to bind tunnel to.<br>local\_gw is local gateway for phase1-interface.<br>nat\_ip is ext IP if hub behind NAT.<br>tunnel\_subnet is subnet used for dial-in tunnels. | <pre>set(object({<br>    interface_id   = number<br>    interface_name = string<br>    local_gw       = string<br>    nat_ip         = string<br>    tunnel_subnet  = string<br>    }<br>  ))</pre> | n/a | yes |
| <a name="input_bgp_as"></a> [bgp\_as](#input\_bgp\_as) | BGP AS to use for ADVPN. | `number` | `65000` | no |
| <a name="input_hub_id"></a> [hub\_id](#input\_hub\_id) | Hub ID - single digit int. | `number` | `1` | no |
| <a name="input_ipsec_dhgrp"></a> [ipsec\_dhgrp](#input\_ipsec\_dhgrp) | List of dhgrp separated by whitespace. | `string` | `"14"` | no |
| <a name="input_ipsec_proposal"></a> [ipsec\_proposal](#input\_ipsec\_proposal) | List of proposals separated by whitespace. | `string` | `"aes256-sha256"` | no |
| <a name="input_ipsec_psk"></a> [ipsec\_psk](#input\_ipsec\_psk) | Pre-shared key for IPSEC tunnels. | `string` | `null` | no |
| <a name="input_networks"></a> [networks](#input\_networks) | Networks to add to BGP networks. | `set(string)` | `[]` | no |
| <a name="input_sla_loopback_ip"></a> [sla\_loopback\_ip](#input\_sla\_loopback\_ip) | Loopback address for SLA and VPN tunnel monitoring. | `string` | `"169.254.255.255/32"` | no |
| <a name="input_vdom"></a> [vdom](#input\_vdom) | VDOM to apply configuration. | `string` | `"root"` | no |
| <a name="input_vpn_name_prefix"></a> [vpn\_name\_prefix](#input\_vpn\_name\_prefix) | Used to prefix advpn interface name. | `string` | `"advpn-"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_hub"></a> [hub](#output\_hub) | Hub information. |
| <a name="output_psk"></a> [psk](#output\_psk) | Outputs PSK if auto generated. Null if provided. |
<!-- END_TF_DOCS -->    