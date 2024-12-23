## Introduction

In this comprehensive guide, we'll walk through the process of creating an Amazon EMR (Elastic MapReduce) cluster in a public subnet using Terraform.

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
  name     = replace(basename(path.cwd), "-cluster", "")
  vpc_name = "MyVPC2"
  vpc_cidr = "10.0.0.0/16"
  bucket_name = "slvr-emr-bucket-4433"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
}
```

Here, we set the name of the EMR cluster, the VPC name, VPC CIDR block, S3 bucket name, and the availability zones to use. The last local variable `azs` takes the first 3 zones of the available zone for configured aws-region.

## Step 4: Configuring the EMR Module

Now, let's configure the EMR module to create our EMR cluster. We specify the release label, applications, auto-termination policy, bootstrap action, configurations, instance groups, and other settings:

```hcl
module "emr_instance_group" {
  source = "terraform-aws-modules/emr/aws"
  version = "~>1.2.1"

  name = "${local.name}-instance-group"

  release_label_filters = {
    emr6 = {
      prefix = "emr-6"
    }
  }

  applications  = ["spark", "hadoop", "hive"]
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
    instance_type  = "c4.large"
    # bid_price      = "0.25"

  }

  # Configure public subnet for the cluster
  ebs_root_volume_size = 64
  ec2_attributes = {
    subnet_id = element(module.vpc.public_subnets, 1)
    key_name  = "Login-1"
  }
  vpc_id               = module.vpc.vpc_id
  is_private_cluster   = false

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
      description      = "Allow ssh ingress traffic"
      type             = "ingress"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  }

  keep_job_flow_alive_when_no_steps = true
  list_steps_states                 = ["PENDING", "RUNNING", "CANCEL_PENDING", "CANCELLED", "FAILED", "INTERRUPTED", "COMPLETED"]
  log_uri                           = "s3://${module.s3_bucket.s3_bucket_id}/"

  step_concurrency_level = 3
  termination_protection = false
  visible_to_all_users   = true

  tags = var.tags

  depends_on = [module.vpc, module.s3_bucket]

}
```

In this configuration, we define the EMR cluster's specifications, including the EMR release label, applications, auto-termination policy, bootstrap action, configurations, instance groups, and security group rules.

When launching EMR, you can create the cluster by selecting instance group of instance fleet. Instance group means that the master or say core nodes need to of same instance type. Instance fleet allows you to use a mix of instance types, and include spot instances in mix. This allows you to improve availability and cost effectiveness of cluster.
{: .notice--info}

## Step 5: Configuring the VPC

To create a VPC for our EMR cluster, we use the Terraform AWS VPC module:

```hcl
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name           = local.vpc_name
  cidr           = local.vpc_cidr
  azs            = local.azs
  public_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  enable_nat_gateway = false
  public_subnet_tags = { "for-use-with-amazon-emr-managed-policies" = true }
  tags               = var.tags

  vpc_tags = {
    Name = local.vpc_name
  }
}
```

Here, we define the VPC's specifications, including the VPC name, CIDR block, availability zones, and subnets.

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

In this guide, we've demonstrated how to create an Amazon EMR cluster in a public subnet using Terraform. By following these steps, you can securely provision an EMR cluster for your big data processing needs. Feel free to customize the configurations to fit your specific requirements and environments.

Checkout the official article for reference [Link](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-clusters-in-a-vpc.html){: .btn .btn--xsmall .btn--info}.
