provider "aws" {
  profile = "terraform"
  region  = var.region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.42.0"
    }
  }
}

# Declare the data source
data "aws_availability_zones" "available" {}

# Local variables
locals {
  name        = replace(basename(path.cwd), "-cluster", "")
  vpc_name    = "MyVPC1"
  vpc_cidr    = "10.0.0.0/16"
  bucket_name = "slvr-emr-bucket-443"
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
}

################################################################################
# EMR Module
################################################################################


// First spot usage => aws iam create-service-linked-role --aws-service-name spot.amazonaws.com

module "emr_instance_group" {
  source  = "terraform-aws-modules/emr/aws"
  version = "~>1.2.1"

  name = "${local.name}-instance-group"

  release_label_filters = {
    emr6 = {
      prefix = "emr-6"
    }
  }

  applications = ["spark", "hadoop"]
  auto_termination_policy = {
    idle_timeout = 3600
  }

  bootstrap_action = {
    example = {
      path = "file:/bin/echo",
      name = "Just an example",
      args = ["Hello World!"]
    }
  }

  configurations_json = jsonencode([
    {
      "Classification" : "spark-env",
      "Configurations" : [
        {
          "Classification" : "export",
          "Properties" : {
            "JAVA_HOME" : "/usr/lib/jvm/java-1.8.0"
          }
        }
      ],
      "Properties" : {}
    }
  ])

  master_instance_group = {
    name           = "master-group"
    instance_count = 1
    instance_type  = "m5.xlarge"
    # bid_price      = "0.25"
  }

  core_instance_group = {
    name           = "core-group"
    instance_count = 1
    instance_type  = "c4.2xlarge"
    # bid_price      = "0.25"
  }

  ebs_root_volume_size = 64
  ec2_attributes = {
    subnet_id = element(module.vpc.private_subnets, 0)
    key_name  = "Login-1"
  }
  vpc_id             = module.vpc.vpc_id
  is_private_cluster = true

  master_security_group_rules = {
    "rule1" = {
      description = "Allow ssh ingress traffic"
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
    "rule2" = {
      description = "Allow all egress traffic"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  keep_job_flow_alive_when_no_steps = true
  list_steps_states                 = ["PENDING", "RUNNING", "CANCEL_PENDING", "CANCELLED", "FAILED", "INTERRUPTED", "COMPLETED"]
  log_uri                           = "s3://${module.s3_bucket.s3_bucket_id}/"

  step_concurrency_level = 3
  termination_protection = false
  visible_to_all_users   = true

  tags       = var.tags
  depends_on = [module.vpc, module.s3_bucket]

}

########################
#     EC2 instance     #
########################

// Create an EC2 to allow ssh access to private EMR cluster
module "ec2_instance" {
  source = "terraform-aws-modules/ec2-instance/aws"

  name = "${local.name}-EMR-Login"

  instance_type               = "t2.micro"
  key_name                    = "Login-1"
  monitoring                  = true
  vpc_security_group_ids      = [module.ec2_instance_sg.security_group_id]
  subnet_id                   = element(module.vpc.public_subnets, 0)
  associate_public_ip_address = true

  tags = var.tags

  depends_on = [module.ec2_instance_sg]
}

module "ec2_instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.vpc_name}-ec2-sg"
  description = "Security group for EC2 access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "ssh-tcp"
      description = "VPC CIDR SSH"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all egress"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  tags = var.tags

  depends_on = [module.vpc]

}

################################################################################
# Supporting Resources
################################################################################


########################
#     VPC for EMR      #
########################

// First we create VPC for the EMR Cluster
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name            = local.vpc_name
  cidr            = local.vpc_cidr
  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 8)]


  enable_nat_gateway = true
  single_nat_gateway = true
  default_vpc_enable_dns_hostnames  = true
  default_vpc_enable_dns_support = true

  private_subnet_tags = { "for-use-with-amazon-emr-managed-policies" = true }
  tags                = var.tags

  vpc_tags = {
    Name = local.vpc_name
  }
}

// Endpoint for the VPC to allow EMR to access S3 over private network
module "vpc_endpoint" {
  source = "./.terraform/modules/vpc/modules/vpc-endpoints"

  vpc_id                     = module.vpc.vpc_id
  security_group_ids         = [module.vpc_endpoints_sg.security_group_id]

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      private_dns_enabled = true
      route_table_ids = flatten([module.vpc.private_route_table_ids])
      // policy          = data.aws_iam_policy_document.generic_s3_policy.json
      tags            = { Name = "${local.vpc_name}-s3" }
    }
    },
    {
      for service in toset(["elasticmapreduce", "sts"]) :
      service => {
        service             = service
        service_type        = "Interface"
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.vpc_name}-${service}" }
      }
  }
  )

  tags = var.tags

  depends_on = [module.vpc, module.vpc_endpoints_sg]

}

// Endpoint to connect to nodes
resource "aws_ec2_instance_connect_endpoint" "ec2connect" {
  subnet_id = element(module.vpc.private_subnets, 0)
  security_group_ids = [ module.ec2connect_endpoints_sg.security_group_id ]
  tags = var.tags
}

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoint access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      // rule        = "https-443-tcp"
      description = "VPC CIDR HTTPS"
      cidr_blocks = join(",", module.vpc.private_subnets_cidr_blocks)
      from_port = "0"
      to_port = "0"
      protocol = "-1"
    },
  ]

  egress_with_cidr_blocks = [ 
    {
      description = "All outbound ok"
      cidr_blocks = "0.0.0.0/0" // module.vpc.vpc_cidr_block
      from_port = "0"
      to_port = "0"
      protocol = "-1"
    }
   ]

  tags = var.tags
}

module "ec2connect_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-ec2connect-endpoints"
  description = "Security group for VPC endpoint access for EC2 instances"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      description = "All ingress"
      cidr_blocks = "0.0.0.0/0"
      from_port = "0"
      to_port = "0"
      protocol = "-1"
    },
  ]

  egress_with_cidr_blocks = [ 
    {
      description = "All outbound ok for testing"
      cidr_blocks = "0.0.0.0/0"
      from_port = "0"
      to_port = "0"
      protocol = "-1"
    }
   ]

  tags = var.tags
}



// Allow if request coming from VPC network
data "aws_iam_policy_document" "generic_s3_policy" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpc"
      values   = [module.vpc.vpc_id]
    }
  }
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = local.bucket_name

  # Allow deletion of non-empty bucket
  # Example usage only - not recommended for production
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = var.tags
}


