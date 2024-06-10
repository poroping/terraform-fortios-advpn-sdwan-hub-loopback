variable "interfaces" {
  type = set(object({
    interface_id     = number
    interface_name   = string
    local_gw         = optional(string, null)
    nat_ip           = optional(string, null)
    sla_latency      = optional(number, 50)
    sla_priority_in  = optional(number, null)
    sla_priority_out = optional(number, null)
    }
  ))
  validation {
    condition = alltrue([
      for hub in var.interfaces : hub.interface_id >= 0 && hub.interface_id <= 99
    ], )
    error_message = "Value of interface_id must be between 0 and 99 inclusive."
  }
  description = "Set of interface objects.\ninterface_id is significant to hub.\ninterface_name is name of parent interface to bind tunnel to.\nlocal_gw is local gateway for phase1-interface.\nnat_ip is ext IP if hub behind NAT.\ntunnel_subnet is subnet used for dial-in tunnels. "
}

variable "networks" {
  type        = set(string)
  description = "Networks to add to BGP networks."
  default     = []
}

variable "bgp_as" {
  type        = number
  description = "BGP AS to use for ADVPN."
  default     = 65000
}

variable "vdom" {
  type        = string
  description = "VDOM to apply configuration."
  default     = "root"
}

variable "hub_id" {
  type = number
  validation {
    condition     = var.hub_id >= 0 && var.hub_id <= 99
    error_message = "Value must be between 0 and 99 inclusive."
  }
  description = "Hub ID - single digit int."
  default     = 1
}

variable "loopback_ip" {
  type        = string
  description = "Loopback address for SLA and BGP."
  default     = "10.255.255.254"
}

variable "ipsec" {
  type = object({
    proposal = optional(string, "aes256-sha256")
    dhgrp    = optional(string, "14")
    psk      = optional(string, null)
  }) #proposal = "aes256-sha-256", dhgrp = "14", psk = null

}

variable "vpn_name_prefix" {
  type        = string
  description = "Used to prefix advpn interface name."
  default     = "ADVPN-"
  validation {
    condition     = length(var.vpn_name_prefix) < 9
    error_message = "Length of string must be max 8 due to interface name length restrictions."
  }
}


variable "loopback_subnet" {
  type        = string
  description = "Loopback subnet"
  default     = "10.255.255.0/24"

}
