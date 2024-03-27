provider "aws" {
  profile = "terraform"
  region  = var.region
}

# Declare the data source
data "aws_availability_zones" "available" {
  state = "available"
}

# Local variables
locals {
  vpc_name = "MyVPC1"
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  network_acls = {
    default_inbound = [
      {
        rule_number = 900
        rule_action = "allow"
        from_port   = 1024
        to_port     = 65535
        protocol    = "tcp"
        cidr_block  = "0.0.0.0/0"
      }
    ]
    default_outbound = [
      {
        rule_number = 900
        rule_action = "allow"
        from_port   = 32768
        to_port     = 65535
        protocol    = "tcp"
        cidr_block  = "0.0.0.0/0"
      }
    ]
    public_inbound  = []
    public_outbound = []
  }
}

########################
#     VPC for EMR      #
########################

// First we create VPC for the EMR Cluster
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name           = local.vpc_name
  cidr           = local.vpc_cidr
  public_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]

  azs                          = local.azs
  public_dedicated_network_acl = true
  public_inbound_acl_rules     = concat(local.network_acls["default_inbound"], local.network_acls["public_inbound"])
  public_outbound_acl_rules    = concat(local.network_acls["default_outbound"], local.network_acls["public_outbound"])

  manage_default_network_acl = true

  tags = var.tags

  vpc_tags = {
    Name = local.vpc_name
  }
}

// Endpoint for the VPC to allow EMR to access S3 over private network
module "vpc_endpoint" {
  source = "./.terraform/modules/vpc/modules/vpc-endpoints"

  vpc_id = module.vpc.vpc_id
  create_security_group      = true
  security_group_name_prefix = "${local.vpc_name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = flatten([module.vpc.intra_route_table_ids, module.vpc.private_route_table_ids, module.vpc.public_route_table_ids])
      policy          = data.aws_iam_policy_document.generic_s3_policy.json
    }
  }

  tags = var.tags

}

########################
#     EMR Cluster      #
########################







########################
#     Supporting       #
########################

// Deny if request not coming from VPC network
data "aws_iam_policy_document" "generic_s3_policy" {
  statement {
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpc"
      values   = [module.vpc.vpc_id]
    }
  }
}

