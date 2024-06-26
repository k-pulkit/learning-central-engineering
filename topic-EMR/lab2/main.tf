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
  vpc_name    = "MyVPC2"
  vpc_cidr    = "10.0.0.0/16"
  bucket_name = "slvr-emr-bucket-4433"
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
}

################################################################################
# EMR Module
################################################################################

// First spot usage => aws iam create-service-linked-role --aws-service-name spot.amazonaws.com

# Turn on EMR managed auto-scaling to resize the cluster as per the load.
resource "aws_emr_managed_scaling_policy" "samplepolicy" {
  cluster_id = module.emr_instance_group.cluster_id
  compute_limits {
    unit_type                       = "Instances"
    minimum_capacity_units          = 2
    maximum_capacity_units          = 6
    maximum_ondemand_capacity_units = 2
    maximum_core_capacity_units     = 3
  }

  depends_on = [ module.emr_instance_group ]
}

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
    },
    #: Enable Glue Metastore for EMR
    {
      "Classification" : "spark-hive-site",
      "Properties" : {
        "hive.metastore.client.factory.class" : "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
      }
    }
  ])

  iam_instance_profile_policies = {
    "AmazonElasticMapReduceforEC2Role" : "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role",
    "Emr_glue_full_access": aws_iam_policy.glue_full_access.arn
  }

  master_instance_group = {
    name           = "master-group"
    instance_count = 1
    instance_type  = "m5.xlarge"
    bid_price      = "0.25"
  }

  core_instance_group = {
    name           = "core-group"
    instance_count = 2
    instance_type  = "m5.xlarge"
    bid_price      = "0.25"

  }

  task_instance_group = {
    name           = "task-group"
    instance_count = 0
    instance_type  = "m5.xlarge"
    bid_price      = "0.25"

  }

  ebs_root_volume_size = 64
  ec2_attributes = {
    subnet_id = element(module.vpc.public_subnets, 1)
    key_name  = "Login-1"
  }
  vpc_id             = module.vpc.vpc_id
  is_private_cluster = false

  master_security_group_rules = {
    "rule1" = {
      description      = "Allow all egress traffic"
      type             = "egress"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    },
    "rule2" = {
      description = "Allow ssh ingress traffic"
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  keep_job_flow_alive_when_no_steps = true
  list_steps_states                 = ["PENDING", "RUNNING", "CANCEL_PENDING", "CANCELLED", "FAILED", "INTERRUPTED", "COMPLETED"]
  log_uri                           = "s3://${module.s3_bucket.s3_bucket_id}/"

  step_concurrency_level = 3
  termination_protection = false
  visible_to_all_users   = true

  tags = var.tags

  depends_on = [module.vpc, module.s3_bucket, aws_iam_policy.glue_full_access]

}

################################################################################
# Supporting Resources
################################################################################

########################
#     VPC for EMR      #
########################

// First we create VPC for the EMR Cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name               = local.vpc_name
  cidr               = local.vpc_cidr
  azs                = local.azs
  public_subnets     = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  enable_nat_gateway = false
  public_subnet_tags = { "for-use-with-amazon-emr-managed-policies" = true }
  tags               = var.tags

  vpc_tags = {
    Name = local.vpc_name
  }
}

// Glue all permissions
data "aws_iam_policy_document" "glue_full_access" {
  statement {
    effect    = "Allow"
    actions   = ["glue:*"]
    resources = ["*"]
  }

  depends_on = [module.vpc]
}

resource "aws_iam_policy" "glue_full_access" {
  name        = "Emr_glue_full_access"
  description = "IAM policy to allow EMR instances to access glue data catalog"
  policy      = data.aws_iam_policy_document.glue_full_access.json
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

  depends_on = [module.vpc]
}


module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = local.bucket_name

  # Allow deletion of non-empty bucket
  # Example usage only - not recommended for production
  force_destroy                         = true
  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  policy                  = data.aws_iam_policy_document.generic_s3_policy.json

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = var.tags

  depends_on = [module.vpc]
}
