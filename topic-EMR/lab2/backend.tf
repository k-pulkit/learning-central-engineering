terraform {
  backend "s3" {
    bucket         = "slvr-terraform-state"
    key            = "learning-central-EMR-Lab2.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform_state"
  }
}