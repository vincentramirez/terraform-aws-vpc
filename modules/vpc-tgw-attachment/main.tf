data "terraform_remote_state" "network" {
  backend = "remote"

  config = {
    organization = "${var.tfe_org_name}"
    hostname     = "${var.tfe_host_name}"
    workspaces = {
      name = "${var.tfe_core_network_workspace_name}"
    }
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attachment" {
  vpc_id             = "${var.vpc_id}"
  transit_gateway_id = "${data.terraform_remote_state.network.outputs.transitgw}"
  subnet_ids         = ["${var.subnet_ids}"]
  dns_support        = "disable"

  tags = {
    Name = "tlz-tgw-attachment"
  }
}

# resource "aws_route" "route" {
#   count = length(var.route_tables)

#   route_table_id = data.aws_route_table.rt.*.id[count.index]
#   destination_cidr_block = "0.0.0.0/0"
#   transit_gateway_id = data.aws_ec2_transit_gateway.tgw.id

#   depends_on = [aws_ec2_transit_gateway_vpc_attachment.tgw_attachment]
# }
