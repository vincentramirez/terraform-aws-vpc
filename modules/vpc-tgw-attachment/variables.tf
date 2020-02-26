# variable "route_tables" {
#   type        = list(string)
#   description = "The list of route tables to add the TGW route to"
# }

variable "subnet_ids" {
  type        = list(string)
  description = "The list of subnets to associate with the TGW, max one per AZ allowed"
}

variable "vpc_id" {
  type        = string
  description = "Name of the VPC"
}

variable "tfe_core_network_workspace_name" {
  type        = string
  description = "Name of network workspace"

  default = "tlz-core_network"
}

variable "tfe_host_name" {
  description = "host_name for ptfe"
  default     = "prod.ptfe.dht.dev"
}

variable "tfe_org_name" {
  description = "ptfe organization name"
  default     = "example"
}

