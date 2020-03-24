data "terraform_remote_state" "network" {
  backend = "remote"

  config = {
    organization = var.tfe_org_name
    hostname     = var.tfe_host_name
    workspaces = {
      name = var.tfe_core_network_workspace_name
    }
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attachment" {
  vpc_id             = var.vpc_id
  transit_gateway_id = data.terraform_remote_state.network.outputs.transitgw
  subnet_ids         = var.subnet_ids
  dns_support        = "disable"

  tags = module.tgw_tags.tags
}

module "tgw_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.105"
  description   = var.module_description
  function      = var.module_function
  region        = var.region
  resource_type = module.tgw_tags.rt_transit_gateway
  tags          = var.tags
  environment   = var.environment
  tracking_code = var.tracking_code
  channel       = var.channel
}
