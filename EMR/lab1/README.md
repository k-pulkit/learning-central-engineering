## Introduction

In this comprehensive guide, we'll walk through the process of creating an Amazon EMR (Elastic MapReduce) cluster in a private subnet using Terraform. By deploying the EMR cluster in a private subnet, we ensure that the cluster's resources are not directly accessible from the internet, enhancing its security posture.

## Prerequisites

Before we begin, ensure you have the following:

- An AWS account with appropriate permissions to create resources.
- Terraform installed on your local machine.

## Step 1: Setting Up the Terraform Configuration

We start by creating a new Terraform configuration file (e.g., `emr_cluster.tf`) and define the AWS provider and required providers:

```hcl
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
```

Here, we configure the AWS provider to use the AWS profile "terraform" and specify the region from the `var.region` variable.

## Step 2: Declaring Data Sources

We declare data sources to fetch information needed for our configuration. For example, to get the list of available availability zones:

```hcl
data "aws_availability_zones" "available" {}
```

## Step 3: Defining Local Variables

Next, let's define some local variables for reuse in our configuration:

```hcl
locals {
  name        = replace(basename(path.cwd), "-cluster", "")
  vpc_name    = "MyVPC1"
  vpc_cidr    = "10.0.0.0/16"
  bucket_name = "slvr-emr-bucket-443"
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
}
```

Here, we set the name of the EMR cluster, the VPC name, VPC CIDR block, S3 bucket name, and the availability zones to use. The last local variable `azs` takes the first 3 zones of the available zone for configured aws-region.

## Step 4: Configuring the EMR Module

Now, let's configure the EMR module to create our EMR cluster. We specify the release label, applications, auto-termination policy, bootstrap action, configurations, instance groups, and other settings:

```hcl
module "emr_instance_group" {
  source  = "terraform-aws-modules/emr/aws"
  version = "~>1.2.1"

  name = "${local.name}-instance-group"

  #: Version of the EMR Big-data release
  release_label_filters = {
    emr6 = {
      prefix = "emr-6"
    }
  }

  #: List of applications to deploy on the EMR cluster
  applications = ["spark", "hadoop"]
  auto_termination_policy = {
    idle_timeout = 3600
  }

  #: Any script to run while bootstrapping the cluster
  bootstrap_action = {
    example = {
      path = "file:/bin/echo",
      name = "Just an example",
      args = ["Hello World!"]
    }
  }

  #: Alter any existing configuration, like spark-env, core-site, hdfs-site etc.
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

  #: What instances are needed for master and core nodes
  # Using bid price ensures that it will be a spot instance
  master_instance_group = {
    name           = "master-group"
    instance_count = 1
    instance_type  = "m5.xlarge"
    bid_price      = "0.25"
  }
  # core nodes
  core_instance_group = {
    name           = "core-group"
    instance_count = 1
    instance_type  = "c4.2xlarge"
    bid_price      = "0.25"
  }

  # What private subnet to launch the EMR into, and the key to login
  ebs_root_volume_size = 64
  ec2_attributes = {
    subnet_id = element(module.vpc.private_subnets, 0)
    key_name  = "Login-1"
  }
  vpc_id             = module.vpc.vpc_id
  is_private_cluster = true

  #: Allow ssh traffic to connect to it
  master_security_group_rules = {
    "rule1" = {
      description = "Allow ssh ingress traffic"
      type        = "ingress"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]     // Allow traffic coming from EC2 instance connect endpoint
    }
    #: Allow egress so EMR nodes can reach internet if needed (via NAT gateway)
    "rule2" = {
      description = "Allow all egress traffic"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]     // Outbound traffic is okay as internet access may be needed later
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
```

In this configuration, we define the EMR cluster's specifications, including the EMR release label, applications, auto-termination policy, bootstrap action, configurations, instance groups, and security group rules.

When launching EMR, you can create the cluster by selecting instance group of instance fleet. Instance group means that the master or say core nodes need to of same instance type. Instance fleet allows you to use a mix of instance types, and include spot instances in mix. This allows you to improve availability and cost effectiveness of cluster.
{: .notice--info}

Some important things to note are:

- Instance groups can only be launched in one private subnet, where as instance fleets can be launched in multiple.
- Security group rules need to modified so that ssh connection is allowed
- In case of instance fleets, you can use EMR Managed policies for automatic scaling up and down of cluster

## Step 5: Configuring the VPC

To create a VPC for our EMR cluster, we use the Terraform AWS VPC module:

```hcl
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name            = local.vpc_name
  cidr            = local.vpc_cidr
  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 8)]

  #: Nat gateway to allows private subnet to reach internet
  enable_nat_gateway = true
  single_nat_gateway = true

  #: Enable private DNS support
  default_vpc_enable_dns_hostnames  = true
  default_vpc_enable_dns_support = true

  #: Required for the subnet used by EMR cluster
  private_subnet_tags = { "for-use-with-amazon-emr-managed-policies" = true }
  tags                = var.tags

  vpc_tags = {
    Name = local.vpc_name
  }
}
```

Here, we define the VPC's specifications, including the VPC name, CIDR block, availability zones, and subnets.

## Step 6: Configuring the VPC Endpoints

While launching EMR cluster in private subnet, you need to

```hcl
// Endpoint for the VPC to allow EMR to access S3 over private network
module "vpc_endpoint" {
  source = "./.terraform/modules/vpc/modules/vpc-endpoints"
  vpc_id                     = module.vpc.vpc_id

  #: Security group used by Interface Gateway to allow/disallow traffic
  # Note - Security group allows ingress from private subnet
  security_group_ids         = [module.vpc_endpoints_sg.security_group_id]

  endpoints = merge({
    #: Gateway S3 endpoint
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      private_dns_enabled = true

      # Gateway endpoint required route table IDs of private route tables to create the entry
      route_table_ids = flatten([module.vpc.private_route_table_ids])

      # This policy allows all actions if traffic is coming from the VPC
      policy          = data.aws_iam_policy_document.generic_s3_policy.json
      tags            = { Name = "${local.vpc_name}-s3" }
    }
    },

    #: Interface endpoint for EMR and STS service
    {
      for service in toset(["elasticmapreduce", "sts"]) :
      service => {
        service             = service
        service_type        = "Interface"

        # List of private subnets where the ENI will be attached
        subnet_ids          = module.vpc.private_subnets
        private_dns_enabled = true
        tags                = { Name = "${local.vpc_name}-${service}" }
      }
  }
  )

  tags = var.tags
  depends_on = [module.vpc, module.vpc_endpoints_sg]

}

```

To allow the EMR cluster to access S3 over a private network, we configure VPC endpoints. This configuration creates VPC endpoints for services like S3, EMR, and STS, allowing the EMR cluster to access these services over a private network.

## Step 7: Configuring the S3 Bucket

Finally, we configure an S3 bucket for the EMR cluster to use:

```hcl
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = local.bucket_name

  // Other configurations...
}
```

This configuration creates an S3 bucket with secure settings and server-side encryption enabled.

## Step 8: Deploying the Configuration

To deploy the Terraform configuration and create the EMR cluster, follow these steps:

1. Initialize the Terraform configuration `terraform init`
2. Review the planned changes `terraform plan`
3. Apply the Terraform configuration to create the EMR cluster `terraform apply`
4. Confirm the changes by entering `yes` when prompted.

## Conclusion

In this guide, we've demonstrated how to create an Amazon EMR cluster in a private subnet using Terraform. By following these steps, you can securely provision an EMR cluster for your big data processing needs. Feel free to customize the configurations to fit your specific requirements and environments.

Checkout the official article for reference [Link](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-clusters-in-a-vpc.html){: .btn .btn--xsmall .btn--info}.
