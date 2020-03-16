terraform {
  required_version = ">= 0.10.3" # introduction of Local Values configuration language feature
}

locals {
  common_tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags
  )
  max_subnet_length = max(
    length(var.private_subnets),
    length(var.elasticache_subnets),
    length(var.database_subnets),
    length(var.redshift_subnets),
  )
  nat_gateway_count = var.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(var.azs) : local.max_subnet_length

  # Use `local.vpc_id` to give a hint to Terraform that subnets should be deleted before secondary CIDR blocks can be free!
  vpc_id = element(
    concat(
      aws_vpc_ipv4_cidr_block_association.this.*.vpc_id,
      aws_vpc.this.*.id,
      [""],
    ),
    0,
  )
}

######
# VPC
######
module "aws_vpc_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.aws_vpc_tags.rt_vpc
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    local.common_tags,
    var.vpc_tags,
  )
}

resource "aws_vpc" "this" {
  count = var.create_vpc ? 1 : 0

  cidr_block                       = var.cidr
  instance_tenancy                 = var.instance_tenancy
  enable_dns_hostnames             = var.enable_dns_hostnames
  enable_dns_support               = var.enable_dns_support
  assign_generated_ipv6_cidr_block = var.assign_generated_ipv6_cidr_block

  tags = module.aws_vpc_tags.tags
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count      = var.create_vpc && length(var.secondary_cidr_blocks) > 0 ? length(var.secondary_cidr_blocks) : 0
  vpc_id     = aws_vpc.this[0].id
  cidr_block = element(var.secondary_cidr_blocks, count.index)
}

###################
# DHCP Options Set
###################
module "dhcp_options_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.dhcp_options_tags.rt_dhcp_options
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    local.common_tags,
    var.dhcp_options_tags,
  )
}

resource "aws_vpc_dhcp_options" "this" {
  count                = var.create_vpc && var.enable_dhcp_options ? 1 : 0
  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers
  ntp_servers          = var.dhcp_options_ntp_servers
  netbios_name_servers = var.dhcp_options_netbios_name_servers
  netbios_node_type    = var.dhcp_options_netbios_node_type
  tags                 = module.dhcp_options_tags.tags
}

###############################
# DHCP Options Set Association
###############################
resource "aws_vpc_dhcp_options_association" "this" {
  count = var.create_vpc && var.enable_dhcp_options ? 1 : 0

  vpc_id          = local.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

###################
# Internet Gateway
###################
module "internet_gateway_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.internet_gateway_tags.rt_igw
  function      = var.module_function
  description   = var.internet_gateway_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    local.common_tags,
    var.igw_tags,
  )
}

resource "aws_internet_gateway" "this" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = module.internet_gateway_tags.tags
}

################
# Publiс routes
################
module "public_route_table_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.public_route_table_tags.rt_route_table
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    {
      "Name" = format("%s-${var.public_subnet_suffix}", var.name)
    },
    var.tags,
    var.public_route_table_tags,
  )
}

resource "aws_route_table" "public" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = module.public_route_table_tags.tags
}

resource "aws_route" "public_internet_gateway" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

#################
# Private routes
# There are so many routing tables as the largest amount of subnets of each type (really?)
#################
module "private_route_table_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.private_route_table_tags.rt_route_table
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.private_route_table_tags,
  )
}

resource "aws_route_table" "private" {
  count = var.create_vpc && local.max_subnet_length > 0 ? local.nat_gateway_count : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = var.single_nat_gateway ? "${var.name}-${var.private_subnet_suffix}" : format(
        "%s-${var.private_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    module.private_route_table_tags.tags
  )

  lifecycle {
    # When attaching VPN gateways it is common to define aws_vpn_gateway_route_propagation
    # resources that manipulate the attributes of the routing table (typically for the private subnets)
    ignore_changes = [propagating_vgws]
  }
}

#################
# Database routes
#################
module "database_route_table_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.database_route_table_tags.rt_route_table
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.database_route_table_tags,
    {
      "Name" = "${var.name}-${var.database_subnet_suffix}"
    },
  )
}

resource "aws_route_table" "database" {
  count = var.create_vpc && var.create_database_subnet_route_table && length(var.database_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = module.database_route_table_tags.tags
}

#################
# Redshift routes
#################
module "redshift_route_table_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.redshift_route_table_tags.rt_route_table
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.redshift_route_table_tags,
    {
      "Name" = "${var.name}-${var.redshift_subnet_suffix}"
    },
  )
}

resource "aws_route_table" "redshift" {
  count = var.create_vpc && var.create_redshift_subnet_route_table && length(var.redshift_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = module.redshift_route_table_tags.tags
}

#################
# Elasticache routes
#################
module "elasticache_route_table_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.elasticache_route_table_tags.rt_route_table
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.elasticache_route_table_tags,
    {
      "Name" = "${var.name}-${var.elasticache_subnet_suffix}"
    },
  )
}

resource "aws_route_table" "elasticache" {
  count = var.create_vpc && var.create_elasticache_subnet_route_table && length(var.elasticache_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = module.elasticache_route_table_tags.tags
}

#################
# Intra routes
#################
module "intra_route_table_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.intra_route_table_tags.rt_route_table
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    {
      "Name" = "${var.name}-intra"
    },
    var.tags,
    var.intra_route_table_tags,
  )
}

resource "aws_route_table" "intra" {
  count = var.create_vpc && length(var.intra_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = module.intra_route_table_tags.tags
}

################
# Public subnet
################
module "public_subnet_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.public_subnet_tags.rt_subnet
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.public_subnet_tags,
  )
}

resource "aws_subnet" "public" {
  count = var.create_vpc && length(var.public_subnets) > 0 && false == var.one_nat_gateway_per_az || length(var.public_subnets) >= length(var.azs) ? length(var.public_subnets) : 0

  vpc_id                  = local.vpc_id
  cidr_block              = element(concat(var.public_subnets, [""]), count.index)
  availability_zone       = element(var.azs, count.index)
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    {
      "Name" = format(
        "%s-${var.public_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    module.public_subnet_tags.tags,
  )
}

#################
# Private subnet
#################
module "private_subnet_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.private_subnet_tags.rt_subnet
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.private_subnet_tags,
  )
}

resource "aws_subnet" "private" {
  count = var.create_vpc && length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  vpc_id            = local.vpc_id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = element(var.azs, count.index)

  tags = merge(
    {
      "Name" = format(
        "%s-${var.private_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    module.private_subnet_tags.tags,
  )
}

##################
# Database subnet
##################
module "database_subnet_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.database_subnet_tags.rt_subnet
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.database_subnet_tags,
  )
}

resource "aws_subnet" "database" {
  count = var.create_vpc && length(var.database_subnets) > 0 ? length(var.database_subnets) : 0

  vpc_id            = local.vpc_id
  cidr_block        = var.database_subnets[count.index]
  availability_zone = element(var.azs, count.index)

  tags = merge(
    {
      "Name" = format(
        "%s-${var.database_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    module.database_subnet_tags.tags,
  )
}

module "db_subnet_group_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.db_subnet_group_tags.rt_subnet_group
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    local.common_tags,
    var.database_subnet_group_tags,
  )
}

resource "aws_db_subnet_group" "database" {
  count = var.create_vpc && length(var.database_subnets) > 0 && var.create_database_subnet_group ? 1 : 0

  name        = lower(var.name)
  description = "Database subnet group for ${var.name}"
  subnet_ids  = aws_subnet.database.*.id

  tags = module.db_subnet_group_tags.tags
}

##################
# Redshift subnet
##################
module "redshift_subnet_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.redshift_subnet_tags.rt_subnet
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.redshift_subnet_tags,
  )
}

resource "aws_subnet" "redshift" {
  count = var.create_vpc && length(var.redshift_subnets) > 0 ? length(var.redshift_subnets) : 0

  vpc_id            = local.vpc_id
  cidr_block        = var.redshift_subnets[count.index]
  availability_zone = element(var.azs, count.index)

  tags = merge(
    {
      "Name" = format(
        "%s-${var.redshift_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    module.redshift_subnet_tags.tags,
  )
}

module "redshift_subnet_group_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.redshift_subnet_group_tags.rt_subnet_group
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    local.common_tags,
    var.redshift_subnet_group_tags,
  )
}

resource "aws_redshift_subnet_group" "redshift" {
  count = var.create_vpc && length(var.redshift_subnets) > 0 ? 1 : 0

  name        = var.name
  description = "Redshift subnet group for ${var.name}"
  subnet_ids  = aws_subnet.redshift.*.id

  tags = module.redshift_subnet_group_tags.tags
}

#####################
# ElastiCache subnet
#####################
module "elasticache_subnet_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.elasticache_subnet_tags.rt_subnet
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.elasticache_subnet_tags,
  )
}

resource "aws_subnet" "elasticache" {
  count = var.create_vpc && length(var.elasticache_subnets) > 0 ? length(var.elasticache_subnets) : 0

  vpc_id            = local.vpc_id
  cidr_block        = var.elasticache_subnets[count.index]
  availability_zone = element(var.azs, count.index)

  tags = merge(
    {
      "Name" = format(
        "%s-${var.elasticache_subnet_suffix}-%s",
        var.name,
        element(var.azs, count.index),
      )
    },
    module.elasticache_subnet_tags.tags,
  )
}

resource "aws_elasticache_subnet_group" "elasticache" {
  count = var.create_vpc && length(var.elasticache_subnets) > 0 ? 1 : 0

  name        = var.name
  description = "ElastiCache subnet group for ${var.name}"
  subnet_ids  = aws_subnet.elasticache.*.id
}

#####################################################
# intra subnets - private subnet without NAT gateway
#####################################################
module "intra_aws_subnet_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.intra_aws_subnet_tags.rt_subnet
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.intra_subnet_tags,
  )
}

resource "aws_subnet" "intra" {
  count = var.create_vpc && length(var.intra_subnets) > 0 ? length(var.intra_subnets) : 0

  vpc_id            = local.vpc_id
  cidr_block        = var.intra_subnets[count.index]
  availability_zone = element(var.azs, count.index)

  tags = merge(
    {
      "Name" = format("%s-intra-%s", var.name, element(var.azs, count.index))
    },
    module.intra_aws_subnet_tags.tags,
  )
}

##############
# NAT Gateway
##############
# Workaround for interpolation not being able to "short-circuit" the evaluation of the conditional branch that doesn't end up being used
# Source: https://github.com/hashicorp/terraform/issues/11566#issuecomment-289417805
#
# The logical expression would be
#
#    nat_gateway_ips = var.reuse_nat_ips ? var.external_nat_ip_ids : aws_eip.nat.*.id
#
# but then when count of aws_eip.nat.*.id is zero, this would throw a resource not found error on aws_eip.nat.*.id.
locals {
  nat_gateway_ips = split(
    ",",
    var.reuse_nat_ips ? join(",", var.external_nat_ip_ids) : join(",", aws_eip.nat.*.id),
  )
}

module "eip_nat_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.eip_nat_tags.rt_nat
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.nat_eip_tags,
  )
}

resource "aws_eip" "nat" {
  count = var.create_vpc && var.enable_nat_gateway && false == var.reuse_nat_ips ? local.nat_gateway_count : 0

  vpc = true

  tags = merge(
    {
      "Name" = format(
        "%s-%s",
        var.name,
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    module.eip_nat_tags.tags,
  )
}

module "eip_nat_gateway_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.eip_nat_gateway_tags.rt_nat_gw
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    var.tags,
    var.nat_gateway_tags,
  )
}

resource "aws_nat_gateway" "this" {
  count = var.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = element(
    local.nat_gateway_ips,
    var.single_nat_gateway ? 0 : count.index,
  )
  subnet_id = element(
    aws_subnet.public.*.id,
    var.single_nat_gateway ? 0 : count.index,
  )

  tags = merge(
    {
      "Name" = format(
        "%s-%s",
        var.name,
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    module.eip_nat_gateway_tags.tags,
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat_gateway" {
  count = var.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.this.*.id, count.index)

  timeouts {
    create = "5m"
  }
}

######################
# VPC Endpoint for S3
######################
data "aws_vpc_endpoint_service" "s3" {
  count = var.create_vpc && var.enable_s3_endpoint ? 1 : 0

  service = "s3"
}

module "s3_vpc_endpoint_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.s3_vpc_endpoint_tags.rt_vpc_endpoint
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags          = local.common_tags
}

resource "aws_vpc_endpoint" "s3" {
  count = var.create_vpc && var.enable_s3_endpoint ? 1 : 0

  vpc_id       = local.vpc_id
  service_name = data.aws_vpc_endpoint_service.s3[0].service_name

  tags = module.s3_vpc_endpoint_tags.tags
}

resource "aws_vpc_endpoint_route_table_association" "private_s3" {
  count = var.create_vpc && var.enable_s3_endpoint ? local.nat_gateway_count : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id  = element(aws_route_table.private.*.id, count.index)
}

resource "aws_vpc_endpoint_route_table_association" "intra_s3" {
  count = var.create_vpc && var.enable_s3_endpoint && length(var.intra_subnets) > 0 ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id  = element(aws_route_table.intra.*.id, 0)
}

resource "aws_vpc_endpoint_route_table_association" "public_s3" {
  count = var.create_vpc && var.enable_s3_endpoint && length(var.public_subnets) > 0 ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id  = aws_route_table.public[0].id
}

############################
# VPC Endpoint for DynamoDB
############################
data "aws_vpc_endpoint_service" "dynamodb" {
  count = var.create_vpc && var.enable_dynamodb_endpoint ? 1 : 0

  service = "dynamodb"
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = var.create_vpc && var.enable_dynamodb_endpoint ? 1 : 0

  vpc_id       = local.vpc_id
  service_name = data.aws_vpc_endpoint_service.dynamodb[0].service_name

  tags = module.vpc_endpoint_tags.tags
}

resource "aws_vpc_endpoint_route_table_association" "private_dynamodb" {
  count = var.create_vpc && var.enable_dynamodb_endpoint ? local.nat_gateway_count : 0

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb[0].id
  route_table_id  = element(aws_route_table.private.*.id, count.index)
}

resource "aws_vpc_endpoint_route_table_association" "intra_dynamodb" {
  count = var.create_vpc && var.enable_dynamodb_endpoint && length(var.intra_subnets) > 0 ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb[0].id
  route_table_id  = element(aws_route_table.intra.*.id, 0)
}

resource "aws_vpc_endpoint_route_table_association" "public_dynamodb" {
  count = var.create_vpc && var.enable_dynamodb_endpoint && length(var.public_subnets) > 0 ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.dynamodb[0].id
  route_table_id  = aws_route_table.public[0].id
}

##########################
# Route table association
##########################
resource "aws_route_table_association" "private" {
  count = var.create_vpc && length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  subnet_id = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(
    aws_route_table.private.*.id,
    var.single_nat_gateway ? 0 : count.index,
  )
}

resource "aws_route_table_association" "database" {
  count = var.create_vpc && length(var.database_subnets) > 0 ? length(var.database_subnets) : 0

  subnet_id = element(aws_subnet.database.*.id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.database.*.id, aws_route_table.private.*.id),
    var.single_nat_gateway || var.create_database_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "redshift" {
  count = var.create_vpc && length(var.redshift_subnets) > 0 ? length(var.redshift_subnets) : 0

  subnet_id = element(aws_subnet.redshift.*.id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.redshift.*.id, aws_route_table.private.*.id),
    var.single_nat_gateway || var.create_redshift_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "elasticache" {
  count = var.create_vpc && length(var.elasticache_subnets) > 0 ? length(var.elasticache_subnets) : 0

  subnet_id = element(aws_subnet.elasticache.*.id, count.index)
  route_table_id = element(
    coalescelist(
      aws_route_table.elasticache.*.id,
      aws_route_table.private.*.id,
    ),
    var.single_nat_gateway || var.create_elasticache_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "intra" {
  count = var.create_vpc && length(var.intra_subnets) > 0 ? length(var.intra_subnets) : 0

  subnet_id      = element(aws_subnet.intra.*.id, count.index)
  route_table_id = element(aws_route_table.intra.*.id, 0)
}

resource "aws_route_table_association" "public" {
  count = var.create_vpc && length(var.public_subnets) > 0 ? length(var.public_subnets) : 0

  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public[0].id
}

##############
# VPN Gateway
##############
module "vpc_endpoint_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.vpc_endpoint_tags.rt_vpc_endpoint
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    local.common_tags,
    var.vpn_gateway_tags,
  )
}

resource "aws_vpn_gateway" "this" {
  count = var.create_vpc && var.enable_vpn_gateway ? 1 : 0

  vpc_id          = local.vpc_id
  amazon_side_asn = var.amazon_side_asn

  tags = module.vpc_endpoint_tags.tags
}

resource "aws_vpn_gateway_attachment" "this" {
  count = var.vpn_gateway_id != "" ? 1 : 0

  vpc_id         = local.vpc_id
  vpn_gateway_id = var.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "public" {
  count = var.create_vpc && var.propagate_public_route_tables_vgw && var.enable_vpn_gateway || var.vpn_gateway_id != "" ? 1 : 0

  route_table_id = element(aws_route_table.public.*.id, count.index)
  vpn_gateway_id = element(
    concat(
      aws_vpn_gateway.this.*.id,
      aws_vpn_gateway_attachment.this.*.vpn_gateway_id,
    ),
    count.index,
  )
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count = var.create_vpc && var.propagate_private_route_tables_vgw && var.enable_vpn_gateway || var.vpn_gateway_id != "" ? length(var.private_subnets) : 0

  route_table_id = element(aws_route_table.private.*.id, count.index)
  vpn_gateway_id = element(
    concat(
      aws_vpn_gateway.this.*.id,
      aws_vpn_gateway_attachment.this.*.vpn_gateway_id,
    ),
    count.index,
  )
}

###########
# Defaults
###########resource_type
module "default_vpc_endpoint_tags" {
  source        = "tfe.tlzproject.com/san-uk-poc/tagging/aws"
  version       = "~> 0.1.93"
  environment   = var.environment
  region        = var.region
  resource_type = module.default_vpc_endpoint_tags.rt_vpc
  function      = var.module_function
  description   = var.module_description
  tracking_code = var.tracking_code
  channel       = var.channel
  tags = merge(
    {
      "Name" = format("%s", var.default_vpc_name)
    },
    var.tags,
    var.default_vpc_tags,
  )
}

resource "aws_default_vpc" "this" {
  count = var.manage_default_vpc ? 1 : 0

  enable_dns_support   = var.default_vpc_enable_dns_support
  enable_dns_hostnames = var.default_vpc_enable_dns_hostnames
  enable_classiclink   = var.default_vpc_enable_classiclink

  tags = module.default_vpc_endpoint_tags.tags
}
